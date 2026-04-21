mod cidr;
mod dns;
mod engine;
mod ip;
mod json;
mod objectid;
mod timestamp;
mod uuid;

pub use cidr::CidrParser;
pub use dns::DnsParser;
pub use engine::ParserEngine;
pub use ip::IpParser;
pub use json::JsonParser;
pub use objectid::ObjectIdParser;
pub use timestamp::TimestampParser;
pub use uuid::UuidParser;

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
}
