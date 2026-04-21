use std::net::{Ipv4Addr, Ipv6Addr};
use std::time::Duration;

use serde::Deserialize;

use super::{ParseResult, Parser};

/// IP 地址解析器
pub struct IpParser {
    client: reqwest::blocking::Client,
}

/// ip-api.com 响应数据
#[derive(Debug, Deserialize)]
#[allow(dead_code)]
struct IpApiResponse {
    status: String,
    message: Option<String>,
    country: Option<String>,
    city: Option<String>,
    isp: Option<String>,
    reverse: Option<String>,
    query: Option<String>,
}

impl IpParser {
    pub fn new() -> Self {
        let client = reqwest::blocking::Client::builder()
            .timeout(Duration::from_secs(3))
            .build()
            .unwrap_or_default();
        Self { client }
    }

    fn is_private_ipv4(addr: &Ipv4Addr) -> bool {
        addr.is_private()
            || addr.is_loopback()
            || addr.is_link_local()
            || addr.is_broadcast()
            || addr.is_unspecified()
            || addr.is_multicast()
    }

    fn is_private_ipv6(addr: &Ipv6Addr) -> bool {
        if addr.is_loopback() || addr.is_unspecified() || addr.is_multicast() {
            return true;
        }
        let seg0 = addr.segments()[0];
        // ULA: fc00::/7 (fc__ 和 fd__)
        if (seg0 & 0xfe00) == 0xfc00 {
            return true;
        }
        // Link-local: fe80::/10
        if (seg0 & 0xffc0) == 0xfe80 {
            return true;
        }
        false
    }

    fn query_ip_info(&self, ip: &str) -> Option<IpApiResponse> {
        let url = format!(
            "http://ip-api.com/json/{}?fields=status,message,country,city,isp,reverse,query&lang=zh-CN",
            ip
        );

        let response = self.client.get(&url).send().ok()?;
        let data: IpApiResponse = response.json().ok()?;

        if data.status == "success" {
            Some(data)
        } else {
            None
        }
    }

    fn parse_ipv4(&self, content: &str) -> Option<ParseResult> {
        let addr: Ipv4Addr = content.parse().ok()?;

        if Self::is_private_ipv4(&addr) {
            return None;
        }

        let octets = addr.octets();
        let mut details = format!(
            "八位组：{:?}\n二进制：{:08b}.{:08b}.{:08b}.{:08b}",
            octets, octets[0], octets[1], octets[2], octets[3]
        );

        // 公网 IP 查询地理位置
        let mut parsed = String::new();
        if let Some(info) = self.query_ip_info(content) {
            if let Some(country) = &info.country {
                if !country.is_empty() {
                    parsed.push_str(&format!("国家：{}", country));
                }
            }
            if let Some(city) = &info.city {
                if !city.is_empty() {
                    if !parsed.is_empty() {
                        parsed.push('\n');
                    }
                    parsed.push_str(&format!("城市：{}", city));
                }
            }
            if let Some(isp) = &info.isp {
                if !isp.is_empty() {
                    if !parsed.is_empty() {
                        parsed.push('\n');
                    }
                    parsed.push_str(&format!("ISP：{}", isp));
                }
            }
            if let Some(reverse) = &info.reverse {
                if !reverse.is_empty() {
                    if !parsed.is_empty() {
                        parsed.push('\n');
                    }
                    parsed.push_str(&format!("反向 DNS：{}", reverse));
                }
            }

            if !parsed.is_empty() {
                details.push_str(&format!("\n\n地理位置信息：\n{}", parsed));
            }
        }

        if parsed.is_empty() {
            parsed = "公网 IP".to_string();
        }

        Some(ParseResult::new("IPv4", content, parsed).with_details(details))
    }

    fn parse_ipv6(&self, content: &str) -> Option<ParseResult> {
        let addr: Ipv6Addr = content.parse().ok()?;

        let ip_type = if addr.is_loopback() {
            "Loopback"
        } else if addr.is_multicast() {
            "Multicast"
        } else if addr.is_unspecified() {
            "Unspecified"
        } else {
            "Unicast"
        };

        let segments = addr.segments();
        let mut details =
            format!(
            "类型：{}\n段：{:?}\n完整格式：{:04x}:{:04x}:{:04x}:{:04x}:{:04x}:{:04x}:{:04x}:{:04x}",
            ip_type,
            segments,
            segments[0], segments[1], segments[2], segments[3],
            segments[4], segments[5], segments[6], segments[7]
        );

        let mut parsed = format!("类型：{}", ip_type);

        if !Self::is_private_ipv6(&addr) {
            if let Some(info) = self.query_ip_info(content) {
                let mut geo = String::new();
                if let Some(country) = &info.country {
                    if !country.is_empty() {
                        geo.push_str(&format!("国家：{}", country));
                    }
                }
                if let Some(city) = &info.city {
                    if !city.is_empty() {
                        if !geo.is_empty() {
                            geo.push('\n');
                        }
                        geo.push_str(&format!("城市：{}", city));
                    }
                }
                if let Some(isp) = &info.isp {
                    if !isp.is_empty() {
                        if !geo.is_empty() {
                            geo.push('\n');
                        }
                        geo.push_str(&format!("ISP：{}", isp));
                    }
                }
                if let Some(reverse) = &info.reverse {
                    if !reverse.is_empty() {
                        if !geo.is_empty() {
                            geo.push('\n');
                        }
                        geo.push_str(&format!("反向 DNS：{}", reverse));
                    }
                }
                if !geo.is_empty() {
                    parsed.push('\n');
                    parsed.push_str(&geo);
                    details.push_str(&format!("\n\n地理位置信息：\n{}", geo));
                }
            }
        }

        Some(ParseResult::new("IPv6", content, parsed).with_details(details))
    }
}

impl Default for IpParser {
    fn default() -> Self {
        Self::new()
    }
}

impl Parser for IpParser {
    fn name(&self) -> &'static str {
        "IP"
    }

    fn parse(&self, content: &str) -> Vec<ParseResult> {
        if let Some(r) = self.parse_ipv4(content) {
            return vec![r];
        }
        if let Some(r) = self.parse_ipv6(content) {
            return vec![r];
        }
        vec![]
    }
}
