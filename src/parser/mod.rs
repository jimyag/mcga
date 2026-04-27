mod base64_decode;
mod cidr;
mod cron;
mod generate;
mod dns;
mod engine;
mod hash;
mod ip;
mod ipv6;
mod json;
mod json5;
mod objectid;
mod timestamp;
mod uuid;
mod yaml;

pub use base64_decode::Base64Parser;
pub use generate::{
    B64Generator, DB64Generator, ObjectIdGenerator, PswdGenerator, TimeGenerator,
    TimestampGenerator, UuidGenerator,
};
pub use cidr::CidrParser;
pub use cron::CronParser;
pub use dns::DnsParser;
pub use engine::ParserEngine;
pub use hash::HashParser;
pub use ip::IpParser;
pub use ipv6::Ipv6Parser;
pub use json::JsonParser;
pub use json5::Json5Parser;
pub use objectid::ObjectIdParser;
pub use timestamp::TimestampParser;
pub use uuid::UuidParser;
pub use yaml::YamlParser;

/// 解析结果
#[derive(Debug, Clone)]
pub struct ParseResult {
    /// 解析器名称
    pub parser_name: String,
    /// 原始内容
    pub original: String,
    /// 解析后的展示内容
    pub parsed: String,
    /// 额外详情（可选）
    pub details: Option<String>,
}

impl ParseResult {
    pub fn new(
        parser_name: impl Into<String>,
        original: impl Into<String>,
        parsed: impl Into<String>,
    ) -> Self {
        Self {
            parser_name: parser_name.into(),
            original: original.into(),
            parsed: parsed.into(),
            details: None,
        }
    }

    pub fn with_details(mut self, details: impl Into<String>) -> Self {
        self.details = Some(details.into());
        self
    }
}

/// 解析器 trait
pub trait Parser: Send + Sync {
    /// 解析器名称
    fn name(&self) -> &'static str;

    /// 尝试解析内容，返回零个或多个结果
    fn parse(&self, content: &str) -> Vec<ParseResult>;

    /// 带上一条剪贴板内容的解析（默认忽略 prev，只有需要它的解析器重写此方法）
    fn parse_with_prev(&self, content: &str, _prev: &str) -> Vec<ParseResult> {
        self.parse(content)
    }
}
