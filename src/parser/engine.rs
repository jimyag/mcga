use super::{
    CidrParser, DnsParser, IpParser, Json5Parser, JsonParser, ObjectIdParser, ParseResult, Parser,
};

/// 解析引擎，管理所有解析器
pub struct ParserEngine {
    parsers: Vec<Box<dyn Parser>>,
}

impl ParserEngine {
    pub fn new() -> Self {
        // 解析器顺序很重要：更具体的解析器应该放在前面
        let parsers: Vec<Box<dyn Parser>> = vec![
            Box::new(CidrParser::new()),      // CIDR 网段（含 /xx 后缀）
            Box::new(UuidParser::new()),      // 精确格式
            Box::new(ObjectIdParser::new()),  // 精确格式 (24 位 hex)
            Box::new(IpParser::new()),        // 精确格式（仅公网 IP）
            Box::new(TimestampParser::new()), // 纯数字，长度限定
            Box::new(JsonParser::new()),      // 以 { 或 [ 开头（严格 JSON）
            Box::new(Json5Parser::new()),     // JSON5 / JSONC（含注释或 trailing comma）
            Box::new(YamlParser::new()),      // YAML map / sequence
            Box::new(DnsParser::new()),       // 域名 DoH 查询（Cloudflare / AliDNS）
        ];

        Self { parsers }
    }

    /// 获取所有解析器名称
    pub fn parser_names(&self) -> Vec<&'static str> {
        self.parsers.iter().map(|p| p.name()).collect()
    }

    /// 尝试用所有解析器解析，返回第一个成功的结果
    pub fn parse(&self, content: &str) -> Option<ParseResult> {
        let trimmed = content.trim();
        if trimmed.is_empty() {
            return None;
        }

        for parser in &self.parsers {
            let results = parser.parse(trimmed);
            if !results.is_empty() {
                return results.into_iter().next();
            }
        }
        None
    }

    /// 尝试用所有解析器解析内容，返回所有成功的结果
    pub fn parse_all(&self, content: &str) -> Vec<ParseResult> {
        let trimmed = content.trim();
        if trimmed.is_empty() {
            return Vec::new();
        }

        self.parsers
            .iter()
            .flat_map(|parser| parser.parse(trimmed))
            .collect()
    }
}

impl Default for ParserEngine {
    fn default() -> Self {
        Self::new()
    }
}
