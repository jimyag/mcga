use chrono::{DateTime, TimeZone, Utc};
use uuid::Uuid;

use super::{ParseResult, Parser};

/// UUID 解析器
pub struct UuidParser;

impl UuidParser {
    pub fn new() -> Self {
        Self
    }

    fn get_version_info(uuid: &Uuid) -> &'static str {
        match uuid.get_version_num() {
            1 => "v1 (基于时间和 MAC 地址)",
            2 => "v2 (DCE Security)",
            3 => "v3 (基于 MD5 哈希)",
            4 => "v4 (随机生成)",
            5 => "v5 (基于 SHA-1 哈希)",
            6 => "v6 (有序时间戳)",
            7 => "v7 (Unix 时间戳)",
            8 => "v8 (自定义)",
            _ => "未知版本",
        }
    }

    fn get_variant_info(uuid: &Uuid) -> &'static str {
        match uuid.get_variant() {
            uuid::Variant::NCS => "NCS 向后兼容",
            uuid::Variant::RFC4122 => "RFC 4122",
            uuid::Variant::Microsoft => "Microsoft 向后兼容",
            uuid::Variant::Future => "保留给未来定义",
            _ => "未知变体",
        }
    }

    /// 提取 UUID v1 的时间戳和 MAC 地址
    fn extract_v1_info(uuid: &Uuid) -> Option<(DateTime<Utc>, String)> {
        let bytes = uuid.as_bytes();

        // UUID v1 时间戳结构：
        // time_low (bytes 0-3), time_mid (bytes 4-5), time_hi_and_version (bytes 6-7)
        let time_low = u32::from_be_bytes([bytes[0], bytes[1], bytes[2], bytes[3]]) as u64;
        let time_mid = u16::from_be_bytes([bytes[4], bytes[5]]) as u64;
        let time_hi = (u16::from_be_bytes([bytes[6], bytes[7]]) & 0x0FFF) as u64;

        // 组合成 60-bit 时间戳 (100 纳秒间隔，从 1582-10-15 开始)
        let timestamp = time_low | (time_mid << 32) | (time_hi << 48);

        // 转换为 Unix 时间戳
        // UUID epoch: 1582-10-15 00:00:00
        // Unix epoch: 1970-01-01 00:00:00
        // 差值：122192928000000000 (100 纳秒)
        const UUID_EPOCH_DIFF: u64 = 122192928000000000;
        if timestamp < UUID_EPOCH_DIFF {
            return None;
        }

        let unix_100ns = timestamp - UUID_EPOCH_DIFF;
        let unix_secs = (unix_100ns / 10_000_000) as i64;
        let unix_nanos = ((unix_100ns % 10_000_000) * 100) as u32;

        let datetime = Utc.timestamp_opt(unix_secs, unix_nanos).single()?;

        // 提取 MAC 地址 (bytes 10-15)
        let mac = format!(
            "{:02x}:{:02x}:{:02x}:{:02x}:{:02x}:{:02x}",
            bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]
        );

        Some((datetime, mac))
    }

    /// 提取 UUID v6 的时间戳
    fn extract_v6_info(uuid: &Uuid) -> Option<DateTime<Utc>> {
        let bytes = uuid.as_bytes();

        // UUID v6 时间戳结构 (重新排序的 v1):
        // time_high (bytes 0-3), time_mid (bytes 4-5), time_low_and_version (bytes 6-7)
        let time_high = u32::from_be_bytes([bytes[0], bytes[1], bytes[2], bytes[3]]) as u64;
        let time_mid = u16::from_be_bytes([bytes[4], bytes[5]]) as u64;
        let time_low = (u16::from_be_bytes([bytes[6], bytes[7]]) & 0x0FFF) as u64;

        let timestamp = (time_high << 28) | (time_mid << 12) | time_low;

        const UUID_EPOCH_DIFF: u64 = 122192928000000000;
        if timestamp < UUID_EPOCH_DIFF {
            return None;
        }

        let unix_100ns = timestamp - UUID_EPOCH_DIFF;
        let unix_secs = (unix_100ns / 10_000_000) as i64;
        let unix_nanos = ((unix_100ns % 10_000_000) * 100) as u32;

        Utc.timestamp_opt(unix_secs, unix_nanos).single()
    }

    /// 提取 UUID v7 的时间戳
    fn extract_v7_info(uuid: &Uuid) -> Option<DateTime<Utc>> {
        let bytes = uuid.as_bytes();

        // UUID v7: 前 48 位是 Unix 毫秒时间戳
        let unix_ms = u64::from_be_bytes([
            0, 0, bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5],
        ]);

        let unix_secs = (unix_ms / 1000) as i64;
        let unix_nanos = ((unix_ms % 1000) * 1_000_000) as u32;

        Utc.timestamp_opt(unix_secs, unix_nanos).single()
    }
}

impl Default for UuidParser {
    fn default() -> Self {
        Self::new()
    }
}

impl Parser for UuidParser {
    fn name(&self) -> &'static str {
        "UUID"
    }

    fn parse(&self, content: &str) -> Vec<ParseResult> {
        let trimmed = content.trim();
        // 要求标准带横线格式（36 字符），避免与 MD5 等 32 位 hex hash 冲突
        if !trimmed.contains('-') {
            return vec![];
        }
        let uuid = match Uuid::parse_str(trimmed) {
            Ok(u) => u,
            Err(_) => return vec![],
        };

        let version_num = uuid.get_version_num();
        let version_info = Self::get_version_info(&uuid);
        let variant_info = Self::get_variant_info(&uuid);

        let (hi, lo) = uuid.as_u64_pair();

        // 基础信息
        let mut details = format!(
            "版本：{}\n变体：{}\n大写：{}\nURN: {}\n高 64 位：{:#018x}\n低 64 位：{:#018x}",
            version_info,
            variant_info,
            uuid.as_hyphenated().to_string().to_uppercase(),
            uuid.urn(),
            hi,
            lo
        );

        // 根据版本提取额外信息
        let mut time_info = String::new();

        match version_num {
            1 => {
                if let Some((datetime, mac)) = Self::extract_v1_info(&uuid) {
                    time_info = format!(
                        "\n创建时间：{}",
                        datetime.format("%Y-%m-%d %H:%M:%S%.3f UTC")
                    );
                    details.push_str(&format!(
                        "\n\n时间信息:\n  创建时间：{}\n  ISO 8601: {}",
                        datetime.format("%Y-%m-%d %H:%M:%S%.3f UTC"),
                        datetime.to_rfc3339()
                    ));
                    details.push_str(&format!("\n\n节点信息:\n  MAC 地址：{}", mac));

                    // 检查是否是随机生成的 MAC（第一个字节的最低位为 1）
                    let first_byte = uuid.as_bytes()[10];
                    if first_byte & 0x01 == 0x01 {
                        details.push_str(" (随机生成)");
                    }
                }
            }
            6 => {
                if let Some(datetime) = Self::extract_v6_info(&uuid) {
                    time_info = format!(
                        "\n创建时间：{}",
                        datetime.format("%Y-%m-%d %H:%M:%S%.3f UTC")
                    );
                    details.push_str(&format!(
                        "\n\n时间信息:\n  创建时间：{}\n  ISO 8601: {}",
                        datetime.format("%Y-%m-%d %H:%M:%S%.3f UTC"),
                        datetime.to_rfc3339()
                    ));
                }
            }
            7 => {
                if let Some(datetime) = Self::extract_v7_info(&uuid) {
                    time_info = format!(
                        "\n创建时间：{}",
                        datetime.format("%Y-%m-%d %H:%M:%S%.3f UTC")
                    );
                    details.push_str(&format!(
                        "\n\n时间信息:\n  创建时间：{}\n  ISO 8601: {}\n  精度：毫秒",
                        datetime.format("%Y-%m-%d %H:%M:%S%.3f UTC"),
                        datetime.to_rfc3339()
                    ));
                }
            }
            2 | 3 | 4 | 5 | 8 => {
                // 这些版本不包含时间信息
                time_info = "\n时间信息：无 (该版本不包含时间戳)".to_string();
                details.push_str("\n\n时间信息：该版本不包含时间戳");
            }
            _ => {
                time_info = "\n时间信息：无法解析".to_string();
            }
        }

        vec![
            ParseResult::new("UUID", content, format!("{}{}", version_info, time_info))
                .with_details(details),
        ]
    }
}
