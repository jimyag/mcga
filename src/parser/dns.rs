use std::time::Duration;

use regex::Regex;
use serde::Deserialize;

use super::{ParseResult, Parser};

/// DNS over HTTPS 解析器
/// 支持 Cloudflare（主）和 AliDNS（备）
pub struct DnsParser {
    client: reqwest::blocking::Client,
    domain_pattern: Regex,
}

#[derive(Debug, Deserialize)]
struct DohResponse {
    #[serde(rename = "Status")]
    status: i32,
    #[serde(rename = "Answer")]
    answer: Option<Vec<DnsAnswer>>,
}

#[derive(Debug, Deserialize)]
struct DnsAnswer {
    #[serde(rename = "type")]
    record_type: u16,
    #[serde(rename = "TTL")]
    ttl: u32,
    data: String,
}

// 查询的记录类型：编号、名称
const QUERY_TYPES: &[(u16, &str)] = &[(1, "A"), (28, "AAAA"), (5, "CNAME")];

const PROVIDERS: &[(&str, &str)] = &[
    ("Cloudflare", "https://cloudflare-dns.com/dns-query"),
    ("AliDNS", "https://dns.alidns.com/dns-query"),
];

struct DnsResult {
    provider: &'static str,
    // (type_name, ttl, data[])
    by_type: Vec<(String, u32, Vec<String>)>,
}

impl DnsParser {
    pub fn new() -> Self {
        let client = reqwest::blocking::Client::builder()
            .timeout(Duration::from_secs(3))
            .build()
            .unwrap_or_default();

        // 至少一个点，每段字母数字加连字符，TLD 至少 2 个字母
        // 不匹配纯 IP（各段含非数字字符或 TLD 非纯数字）
        let domain_pattern =
            Regex::new(r"(?i)^([a-z0-9]([a-z0-9\-]{0,61}[a-z0-9])?\.)+[a-z]{2,63}$").unwrap();

        Self {
            client,
            domain_pattern,
        }
    }

    fn query_type(&self, domain: &str, qtype_num: u16, provider_url: &str) -> Vec<DnsAnswer> {
        let url = format!("{}?name={}&type={}", provider_url, domain, qtype_num);
        let resp = self
            .client
            .get(&url)
            .header("Accept", "application/dns-json")
            .send();

        match resp {
            Ok(r) => match r.json::<DohResponse>() {
                Ok(data) if data.status == 0 => data.answer.unwrap_or_default(),
                _ => vec![],
            },
            Err(_) => vec![],
        }
    }

    fn query_all_types(&self, domain: &str, provider_url: &str) -> Vec<(String, u32, Vec<String>)> {
        let mut by_type: Vec<(String, u32, Vec<String>)> = Vec::new();
        for (type_num, type_name) in QUERY_TYPES {
            let answers: Vec<_> = self
                .query_type(domain, *type_num, provider_url)
                .into_iter()
                // 跳过类型不匹配的应答（resolver 跟随 CNAME 时会混入 A 记录）
                .filter(|a| a.record_type == *type_num)
                .collect();
            if !answers.is_empty() {
                let ttl = answers[0].ttl;
                let values = answers.into_iter().map(|a| a.data).collect();
                by_type.push((type_name.to_string(), ttl, values));
            }
        }
        by_type
    }

    fn query_provider(&self, domain: &str, name: &'static str, url: &str) -> Option<DnsResult> {
        let by_type = self.query_all_types(domain, url);
        if by_type.is_empty() {
            None
        } else {
            Some(DnsResult {
                provider: name,
                by_type,
            })
        }
    }
}

impl Default for DnsParser {
    fn default() -> Self {
        Self::new()
    }
}

impl Parser for DnsParser {
    fn name(&self) -> &'static str {
        "DNS"
    }

    fn parse(&self, content: &str) -> Vec<ParseResult> {
        if !self.domain_pattern.is_match(content) {
            return vec![];
        }

        // 并发查询两家 DNS，各自返回结果，互不兜底
        let results: Vec<DnsResult> = std::thread::scope(|s| {
            let handles: Vec<_> = PROVIDERS
                .iter()
                .map(|(name, url)| s.spawn(|| self.query_provider(content, name, url)))
                .collect();
            handles
                .into_iter()
                .filter_map(|h| h.join().ok().flatten())
                .collect()
        });

        // 每个 provider 的每种记录类型单独一条 ParseResult，对应一条通知
        results
            .into_iter()
            .flat_map(|result| {
                result
                    .by_type
                    .into_iter()
                    .map(move |(type_name, _ttl, values)| {
                        let parsed = format!(
                            "DNS/{} via {}\n{}",
                            type_name,
                            result.provider,
                            values.join("\n")
                        );
                        ParseResult::new("DNS", content, parsed)
                    })
            })
            .collect()
    }
}
