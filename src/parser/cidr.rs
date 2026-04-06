use std::net::Ipv4Addr;

use regex::Regex;

use super::{ParseResult, Parser};

/// CIDR 网段解析器
pub struct CidrParser {
    pattern: Regex,
}

impl CidrParser {
    pub fn new() -> Self {
        Self {
            pattern: Regex::new(r"^(\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3})/(\d{1,2})$").unwrap(),
        }
    }

    fn parse_cidr(&self, content: &str) -> Option<CidrInfo> {
        let caps = self.pattern.captures(content)?;
        let ip_str = caps.get(1)?.as_str();
        let prefix_len: u8 = caps.get(2)?.as_str().parse().ok()?;

        // 验证前缀长度
        if prefix_len > 32 {
            return None;
        }

        // 解析 IP 地址
        let ip: Ipv4Addr = ip_str.parse().ok()?;
        let ip_u32 = u32::from(ip);

        // 计算子网掩码和网络地址
        let mask = if prefix_len == 0 {
            0u32
        } else {
            !0u32 << (32 - prefix_len)
        };
        let network_u32 = ip_u32 & mask;
        let broadcast_u32 = network_u32 | !mask;

        let network_addr = Ipv4Addr::from(network_u32);
        let broadcast_addr = Ipv4Addr::from(broadcast_u32);

        // 判断输入是否为标准网络地址
        let is_normalized = ip_u32 == network_u32;

        // 计算可用主机数和范围
        let total_ips = 1u64 << (32 - prefix_len);
        let (usable_count, first_usable, last_usable) = match prefix_len {
            32 => {
                // /32 单主机
                (1u64, network_addr, network_addr)
            }
            31 => {
                // /31 点对点链路，两个 IP 都可用
                (2u64, network_addr, broadcast_addr)
            }
            _ => {
                // 正常网段，排除网络地址和广播地址
                let first = Ipv4Addr::from(network_u32 + 1);
                let last = Ipv4Addr::from(broadcast_u32 - 1);
                (total_ips.saturating_sub(2), first, last)
            }
        };

        Some(CidrInfo {
            input_ip: ip,
            prefix_len,
            network_addr,
            broadcast_addr,
            first_usable,
            last_usable,
            usable_count,
            is_normalized,
        })
    }
}

impl Default for CidrParser {
    fn default() -> Self {
        Self::new()
    }
}

struct CidrInfo {
    input_ip: Ipv4Addr,
    prefix_len: u8,
    network_addr: Ipv4Addr,
    broadcast_addr: Ipv4Addr,
    first_usable: Ipv4Addr,
    last_usable: Ipv4Addr,
    usable_count: u64,
    is_normalized: bool,
}

impl Parser for CidrParser {
    fn name(&self) -> &'static str {
        "CIDR"
    }

    fn parse(&self, content: &str) -> Vec<ParseResult> {
        let info = match self.parse_cidr(content) {
            Some(i) => i,
            None => return vec![],
        };

        let mut parsed = String::new();

        // /0 默认路由特殊处理
        if info.prefix_len == 0 {
            parsed.push_str("默认路由（所有地址）");
            return vec![ParseResult::new("CIDR", content, parsed)];
        }

        // 如果输入不是标准网络地址，提示
        if !info.is_normalized {
            parsed.push_str(&format!(
                "输入：{}/{} → 网络：{}/{}\n",
                info.input_ip, info.prefix_len, info.network_addr, info.prefix_len
            ));
        }

        match info.prefix_len {
            32 => {
                parsed.push_str(&format!("单主机地址：{}", info.network_addr));
            }
            31 => {
                parsed.push_str(&format!(
                    "点对点链路（RFC 3021）\n可用范围：{} - {} ({})",
                    info.first_usable, info.last_usable, info.usable_count
                ));
            }
            _ => {
                parsed.push_str(&format!(
                    "网络地址：{}\n广播地址：{}\n可用范围：{} - {} ({})",
                    info.network_addr,
                    info.broadcast_addr,
                    info.first_usable,
                    info.last_usable,
                    info.usable_count
                ));
            }
        }

        vec![ParseResult::new("CIDR", content, parsed)]
    }
}

