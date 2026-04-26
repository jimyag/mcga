use std::net::Ipv6Addr;
use std::str::FromStr;

use super::{ParseResult, Parser};

/// IPv6 地址解析器
pub struct Ipv6Parser;

impl Ipv6Parser {
    pub fn new() -> Self {
        Self
    }

    fn addr_type(addr: &Ipv6Addr) -> &'static str {
        if addr.is_loopback() {
            "回环地址 (::1)"
        } else if addr.is_unspecified() {
            "未指定地址 (::)"
        } else if is_link_local(addr) {
            "链路本地地址 (fe80::/10)"
        } else if is_unique_local(addr) {
            "唯一本地地址 (fc00::/7)"
        } else if addr.is_multicast() {
            "多播地址 (ff00::/8)"
        } else if is_mapped_ipv4(addr) {
            "IPv4 映射地址 (::ffff:0:0/96)"
        } else {
            "全局单播地址"
        }
    }
}

fn is_link_local(addr: &Ipv6Addr) -> bool {
    let segs = addr.segments();
    (segs[0] & 0xffc0) == 0xfe80
}

fn is_unique_local(addr: &Ipv6Addr) -> bool {
    let segs = addr.segments();
    (segs[0] & 0xfe00) == 0xfc00
}

fn is_mapped_ipv4(addr: &Ipv6Addr) -> bool {
    matches!(addr.segments(), [0, 0, 0, 0, 0, 0xffff, _, _])
}

/// 展开 IPv6 为完整 8 组格式
fn expand(addr: &Ipv6Addr) -> String {
    addr.segments()
        .iter()
        .map(|s| format!("{:04x}", s))
        .collect::<Vec<_>>()
        .join(":")
}

impl Default for Ipv6Parser {
    fn default() -> Self {
        Self::new()
    }
}

impl Parser for Ipv6Parser {
    fn name(&self) -> &'static str {
        "IPv6"
    }

    fn parse(&self, content: &str) -> Vec<ParseResult> {
        let trimmed = content.trim();

        // 快速过滤：必须含 ":" 且不含空格（避免匹配普通文本）
        if !trimmed.contains(':') || trimmed.contains(' ') {
            return vec![];
        }
        // 去掉可能的方括号（URL 中的 IPv6 写法 [::1]）
        let cleaned = trimmed.trim_matches(|c| c == '[' || c == ']');

        let addr = match Ipv6Addr::from_str(cleaned) {
            Ok(a) => a,
            Err(_) => return vec![],
        };

        let compressed = addr.to_string(); // Rust 标准库输出压缩形式
        let expanded = expand(&addr);
        let addr_type = Self::addr_type(&addr);

        let details = format!(
            "压缩：{}\n展开：{}\n类型：{}",
            compressed, expanded, addr_type,
        );

        vec![
            ParseResult::new("IPv6", content, format!("类型：{}", addr_type))
                .with_details(details),
        ]
    }
}
