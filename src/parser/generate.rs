use std::sync::OnceLock;
use std::sync::atomic::{AtomicU32, Ordering};
use std::time::{SystemTime, UNIX_EPOCH};

use base64::{engine::general_purpose, Engine as _};
use chrono::Utc;
use uuid::Uuid;

use super::{ParseResult, Parser};

// ── 安全随机 ─────────────────────────────────────────────────────────────────

fn random_bytes(n: usize) -> Vec<u8> {
    let mut buf = vec![0u8; n];
    getrandom::getrandom(&mut buf).expect("getrandom failed");
    buf
}

// ── 通用构造 ─────────────────────────────────────────────────────────────────

fn gen_result(
    parser_name: &'static str,
    original: &str,
    generated: &str,
    details: String,
) -> Vec<ParseResult> {
    vec![ParseResult::new(parser_name, original, generated).with_details(details)]
}

fn now_secs() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_secs()
}

// ── UUID v7 生成器 ────────────────────────────────────────────────────────────

pub struct UuidGenerator;

impl UuidGenerator {
    pub fn new() -> Self { Self }
}
impl Default for UuidGenerator { fn default() -> Self { Self::new() } }

impl Parser for UuidGenerator {
    fn name(&self) -> &'static str { "UUID生成" }

    fn parse(&self, content: &str) -> Vec<ParseResult> {
        if content.trim().to_lowercase() != "uuid" {
            return vec![];
        }
        let generated = Uuid::now_v7().to_string();
        gen_result("UUID生成", content, &generated, format!("UUID v7：{}", generated))
    }
}

// ── 秒时间戳生成器 ────────────────────────────────────────────────────────────

pub struct TimestampGenerator;

impl TimestampGenerator {
    pub fn new() -> Self { Self }
}
impl Default for TimestampGenerator { fn default() -> Self { Self::new() } }

impl Parser for TimestampGenerator {
    fn name(&self) -> &'static str { "时间戳生成" }

    fn parse(&self, content: &str) -> Vec<ParseResult> {
        let kw = content.trim().to_lowercase();
        if kw != "ts" && kw != "timestamp" {
            return vec![];
        }
        let ts = now_secs().to_string();
        let dt = chrono::DateTime::from_timestamp(ts.parse::<i64>().unwrap_or(0), 0)
            .unwrap_or_default()
            .with_timezone(&Utc);
        gen_result(
            "时间戳生成",
            content,
            &ts,
            format!("Unix 时间戳（秒）：{}\n对应时间：{}", ts, dt.format("%Y-%m-%d %H:%M:%S UTC")),
        )
    }
}

// ── RFC 3339 时间字符串生成器 ─────────────────────────────────────────────────

pub struct TimeGenerator;

impl TimeGenerator {
    pub fn new() -> Self { Self }
}
impl Default for TimeGenerator { fn default() -> Self { Self::new() } }

impl Parser for TimeGenerator {
    fn name(&self) -> &'static str { "时间生成" }

    fn parse(&self, content: &str) -> Vec<ParseResult> {
        if content.trim().to_lowercase() != "time" {
            return vec![];
        }
        let rfc = Utc::now().to_rfc3339();
        gen_result("时间生成", content, &rfc, format!("RFC 3339：{}", rfc))
    }
}

// ── MongoDB ObjectId 生成器 ───────────────────────────────────────────────────

static OID_MACHINE_PROC: OnceLock<[u8; 5]> = OnceLock::new();
static OID_COUNTER: OnceLock<AtomicU32> = OnceLock::new();

fn machine_proc_bytes() -> [u8; 5] {
    *OID_MACHINE_PROC.get_or_init(|| {
        let mut buf = [0u8; 5];
        getrandom::getrandom(&mut buf).unwrap_or(());
        buf
    })
}

fn oid_counter() -> &'static AtomicU32 {
    OID_COUNTER.get_or_init(|| {
        // 初始值随机，与 MongoDB 驱动规范一致
        let mut buf = [0u8; 4];
        getrandom::getrandom(&mut buf).unwrap_or(());
        let init = u32::from_be_bytes(buf) & 0x00FF_FFFF; // 只用低 3 字节
        AtomicU32::new(init)
    })
}

fn generate_object_id() -> String {
    let ts = now_secs() as u32;
    let mp = machine_proc_bytes();
    let cnt = oid_counter().fetch_add(1, Ordering::Relaxed) & 0x00FF_FFFF;

    let mut bytes = [0u8; 12];
    bytes[..4].copy_from_slice(&ts.to_be_bytes());
    bytes[4..9].copy_from_slice(&mp);
    bytes[9] = (cnt >> 16) as u8;
    bytes[10] = (cnt >> 8) as u8;
    bytes[11] = cnt as u8;
    hex::encode(bytes)
}

pub struct ObjectIdGenerator;

impl ObjectIdGenerator {
    pub fn new() -> Self { Self }
}
impl Default for ObjectIdGenerator { fn default() -> Self { Self::new() } }

impl Parser for ObjectIdGenerator {
    fn name(&self) -> &'static str { "ObjectId生成" }

    fn parse(&self, content: &str) -> Vec<ParseResult> {
        let kw = content.trim().to_lowercase();
        if kw != "objectid" && kw != "oid" {
            return vec![];
        }
        let oid = generate_object_id();
        let ts_bytes: [u8; 4] = hex::decode(&oid[..8]).unwrap().try_into().unwrap();
        let dt = chrono::DateTime::from_timestamp(u32::from_be_bytes(ts_bytes) as i64, 0)
            .unwrap_or_default()
            .with_timezone(&Utc);
        gen_result(
            "ObjectId生成",
            content,
            &oid,
            format!("MongoDB ObjectId：{}\n嵌入时间：{}", oid, dt.format("%Y-%m-%d %H:%M:%S UTC")),
        )
    }
}

// ── Base64 编码生成器 ─────────────────────────────────────────────────────────

pub struct B64Generator;

impl B64Generator {
    pub fn new() -> Self { Self }
}
impl Default for B64Generator { fn default() -> Self { Self::new() } }

impl Parser for B64Generator {
    fn name(&self) -> &'static str { "Base64编码" }

    fn parse(&self, content: &str) -> Vec<ParseResult> {
        let trimmed = content.trim();
        let lower = trimmed.to_lowercase();

        if lower == "b64" {
            // 无参数：生成 32 字节随机密钥
            let bytes = random_bytes(32);
            let encoded = general_purpose::STANDARD.encode(&bytes);
            return gen_result(
                "Base64编码",
                content,
                &encoded,
                format!("随机 256-bit 密钥（Base64）：{}", encoded),
            );
        }

        // "b64 <text>" → 编码文本
        if let Some(rest) = trimmed.strip_prefix("b64 ").or_else(|| trimmed.strip_prefix("B64 ")) {
            let encoded = general_purpose::STANDARD.encode(rest.as_bytes());
            return gen_result(
                "Base64编码",
                content,
                &encoded,
                format!(
                    "原文（{} 字节）：{}\nBase64：{}",
                    rest.len(),
                    rest,
                    encoded
                ),
            );
        }

        vec![]
    }
}

// ── 随机密码生成器 ────────────────────────────────────────────────────────────

const PSWD_CHARSET: &[u8] =
    b"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789!@#$%^&*-_=+";

pub struct PswdGenerator;

impl PswdGenerator {
    pub fn new() -> Self { Self }
}
impl Default for PswdGenerator { fn default() -> Self { Self::new() } }

impl Parser for PswdGenerator {
    fn name(&self) -> &'static str { "密码生成" }

    fn parse(&self, content: &str) -> Vec<ParseResult> {
        let trimmed = content.trim().to_lowercase();

        // 接受 "pswd" / "pswd N" / "pwd" / "pwd N"
        let (prefix, rest) = if let Some(r) = trimmed.strip_prefix("pswd") {
            ("pswd", r.trim())
        } else if let Some(r) = trimmed.strip_prefix("pwd") {
            ("pwd", r.trim())
        } else {
            return vec![];
        };

        // 必须是结尾或紧跟数字，避免误匹配 "pwd123456..." 之类的内容
        let len: usize = if rest.is_empty() {
            16 // 默认 16 位
        } else if let Ok(n) = rest.parse::<usize>() {
            n.clamp(4, 128)
        } else {
            return vec![];
        };
        let _ = prefix;

        // 使用拒绝采样消除模偏
        let charset_len = PSWD_CHARSET.len(); // 74
        let limit = (256 / charset_len) * charset_len; // 最大无偏范围
        let mut pwd = String::with_capacity(len);
        let mut buf = vec![0u8; len * 4];
        getrandom::getrandom(&mut buf).expect("getrandom failed");

        let mut used = 0;
        for &b in buf.iter() {
            if (b as usize) < limit {
                pwd.push(PSWD_CHARSET[b as usize % charset_len] as char);
                used += 1;
                if used == len {
                    break;
                }
            }
        }
        // buf 不够时补充（极少发生）
        while pwd.len() < len {
            let mut extra = [0u8; 8];
            getrandom::getrandom(&mut extra).ok();
            for &b in extra.iter() {
                if (b as usize) < limit && pwd.len() < len {
                    pwd.push(PSWD_CHARSET[b as usize % charset_len] as char);
                }
            }
        }

        gen_result(
            "密码生成",
            content,
            &pwd,
            format!("随机密码（{} 位）：{}", len, pwd),
        )
    }
}
