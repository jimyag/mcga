use std::time::Duration;

use hickory_resolver::{
    config::{ResolverConfig, ResolverOpts, ServerGroup},
    net::runtime::TokioRuntimeProvider,
    proto::rr::RecordType,
    Resolver,
};
use regex::Regex;
use serde::Deserialize;

use super::{ParseResult, Parser};

/// DNS over HTTPS 解析器
/// 支持 DoH 和传统 DNS 公共解析器
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

enum Provider {
    JsonDoh {
        name: &'static str,
        url: &'static str,
    },
    PlainDns {
        name: &'static str,
        servers: &'static [&'static str],
    },
}

const PROVIDERS: &[Provider] = &[
    Provider::JsonDoh {
        name: "Cloudflare DoH",
        url: "https://cloudflare-dns.com/dns-query",
    },
    Provider::JsonDoh {
        name: "Google DoH",
        url: "https://dns.google/resolve",
    },
    Provider::JsonDoh {
        name: "AliDNS DoH",
        url: "https://dns.alidns.com/dns-query",
    },
    Provider::PlainDns {
        name: "AliDNS 223.5.5.5",
        servers: &["223.5.5.5"],
    },
    Provider::PlainDns {
        name: "Google DNS 8.8.8.8",
        servers: &["8.8.8.8", "8.8.4.4"],
    },
    Provider::PlainDns {
        name: "Cloudflare DNS 1.1.1.1",
        servers: &["1.1.1.1", "1.0.0.1"],
    },
    Provider::PlainDns {
        name: "114DNS 114.114.114.114",
        servers: &["114.114.114.114"],
    },
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

    fn query_json_doh_provider(
        &self,
        domain: &str,
        name: &'static str,
        url: &str,
    ) -> Option<DnsResult> {
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

    fn query_plain_dns_provider(
        &self,
        domain: &str,
        name: &'static str,
        servers: &[&str],
    ) -> Option<DnsResult> {
        let mut ips = Vec::new();
        for server in servers {
            if let Ok(ip) = server.parse() {
                ips.push(ip);
            }
        }
        if ips.is_empty() {
            return None;
        }

        let group = ServerGroup {
            ips: &ips,
            server_name: "",
            path: "/dns-query",
        };
        let config = ResolverConfig::udp_and_tcp(&group);
        let mut opts = ResolverOpts::default();
        opts.timeout = Duration::from_secs(3);
        opts.attempts = 1;

        let runtime = tokio::runtime::Runtime::new().ok()?;
        let resolver = Resolver::builder_with_config(config, TokioRuntimeProvider::default())
            .with_options(opts)
            .build()
            .ok()?;

        let by_type: Vec<(String, u32, Vec<String>)> = QUERY_TYPES
            .iter()
            .filter_map(|(type_num, type_name)| {
                let record_type = match *type_num {
                    1 => RecordType::A,
                    28 => RecordType::AAAA,
                    5 => RecordType::CNAME,
                    _ => return None,
                };

                let lookup = runtime
                    .block_on(resolver.lookup(format!("{domain}."), record_type))
                    .ok()?;
                let answers = lookup.answers();
                if answers.is_empty() {
                    return None;
                }

                let ttl = answers[0].ttl;
                let values: Vec<String> = answers
                    .iter()
                    .map(|answer| answer.data.to_string())
                    .collect();

                if values.is_empty() {
                    None
                } else {
                    Some((type_name.to_string(), ttl, values))
                }
            })
            .collect();

        if by_type.is_empty() {
            None
        } else {
            Some(DnsResult {
                provider: name,
                by_type,
            })
        }
    }

    fn query_provider(&self, domain: &str, provider: &Provider) -> Option<DnsResult> {
        match provider {
            Provider::JsonDoh { name, url } => self.query_json_doh_provider(domain, name, url),
            Provider::PlainDns { name, servers } => {
                self.query_plain_dns_provider(domain, name, servers)
            }
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

        // 并发查询多家 DNS，各自返回结果，互不兜底
        let results: Vec<DnsResult> = std::thread::scope(|s| {
            let handles: Vec<_> = PROVIDERS
                .iter()
                .map(|provider| s.spawn(|| self.query_provider(content, provider)))
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
