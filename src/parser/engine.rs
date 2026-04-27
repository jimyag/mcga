use super::{
    B64Generator, Base64Parser, CidrParser, CronParser, DB64Generator, DnsParser, HashParser,
    IpParser, Ipv6Parser, Json5Parser, JsonParser, ObjectIdGenerator, ObjectIdParser, ParseResult,
    TimestampParser, UuidGenerator, UuidParser, YamlParser,
};

/// 解析引擎，管理所有解析器
pub struct ParserEngine {
    parsers: Vec<Box<dyn Parser>>,
}

impl ParserEngine {
    pub fn new() -> Self {
        // 解析器顺序很重要：更具体的解析器应该放在前面
        let parsers: Vec<Box<dyn Parser>> = vec![
            // 关键词触发生成器（最高优先级，精确匹配单词）
            Box::new(UuidGenerator::new()),       // "uuid"           → UUID v7
            Box::new(TimestampGenerator::new()),  // "ts"/"timestamp" → 秒时间戳
            Box::new(TimeGenerator::new()),       // "time"           → RFC 3339
            Box::new(ObjectIdGenerator::new()),   // "objectid"/"oid" → MongoDB ObjectId
            Box::new(B64Generator::new()),        // "b64"  → 对上一条剪贴板内容做 Base64 编码
            Box::new(DB64Generator::new()),       // "db64" → 对上一条剪贴板内容做 Base64 解码
            Box::new(PswdGenerator::new()),       // "pswd"/"pswd N"  → 随机密码
            Box::new(CidrParser::new()),      // CIDR 网段（含 /xx 后缀）
            Box::new(UuidParser::new()),      // 精确格式
            Box::new(ObjectIdParser::new()),  // 精确格式 (24 位 hex)
            Box::new(HashParser::new()),      // MD5/SHA-1/SHA-256 等（按 hex 长度识别）
            Box::new(Ipv6Parser::new()),      // IPv6 地址
            Box::new(IpParser::new()),        // 精确格式（仅公网 IPv4）
            Box::new(TimestampParser::new()), // 纯数字，长度限定
            Box::new(CronParser::new()),      // Cron 表达式（5 或 6 字段）
            Box::new(JsonParser::new()),      // 以 { 或 [ 开头（严格 JSON）
            Box::new(Json5Parser::new()),     // JSON5 / JSONC（含注释或 trailing comma）
            Box::new(YamlParser::new()),      // YAML map / sequence
            Box::new(Base64Parser::new()),    // Base64 解码（解码结果须为可打印文本）
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
        self.parse_all_with_prev(content, "")
    }

    /// 带上一条剪贴板内容的完整解析（供需要上下文的生成器使用）
    pub fn parse_all_with_prev(&self, content: &str, prev: &str) -> Vec<ParseResult> {
        let trimmed = content.trim();
        if trimmed.is_empty() {
            return Vec::new();
        }

        self.parsers
            .iter()
            .flat_map(|parser| parser.parse_with_prev(trimmed, prev))
            .collect()
    }
}

impl Default for ParserEngine {
    fn default() -> Self {
        Self::new()
    }
}
