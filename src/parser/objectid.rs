use chrono::{DateTime, TimeZone, Utc};
use regex::Regex;

use super::{ParseResult, Parser};

/// MongoDB ObjectID 解析器
pub struct ObjectIdParser {
    regex: Regex,
}

impl ObjectIdParser {
    pub fn new() -> Self {
        // ObjectID 是 24 位十六进制字符串
        Self {
            regex: Regex::new(r"^[0-9a-fA-F]{24}$").unwrap(),
        }
    }

    fn parse_objectid(&self, hex: &str) -> Option<ObjectIdInfo> {
        if !self.regex.is_match(hex) {
            return None;
        }

        let bytes = hex::decode(hex).ok()?;
        if bytes.len() != 12 {
            return None;
        }

        // ObjectID 结构:
        // - 4 字节: Unix 时间戳（秒）
        // - 5 字节: 随机值（包含机器标识和进程 ID）
        // - 3 字节: 计数器
        let timestamp = u32::from_be_bytes([bytes[0], bytes[1], bytes[2], bytes[3]]);
        let random = &bytes[4..9];
        let counter = u32::from_be_bytes([0, bytes[9], bytes[10], bytes[11]]);

        let datetime: DateTime<Utc> = Utc.timestamp_opt(timestamp as i64, 0).single()?;

        Some(ObjectIdInfo {
            timestamp,
            datetime,
            random: random.to_vec(),
            counter,
        })
    }
}

struct ObjectIdInfo {
    timestamp: u32,
    datetime: DateTime<Utc>,
    random: Vec<u8>,
    counter: u32,
}

impl Default for ObjectIdParser {
    fn default() -> Self {
        Self::new()
    }
}

impl Parser for ObjectIdParser {
    fn name(&self) -> &'static str {
        "ObjectID"
    }

    fn parse(&self, content: &str) -> Option<ParseResult> {
        let info = self.parse_objectid(content)?;
        
        let parsed = format!(
            "创建时间: {}\n随机值: {}\n计数器: {}",
            info.datetime.format("%Y-%m-%d %H:%M:%S UTC"),
            hex::encode(&info.random),
            info.counter
        );

        let details = format!(
            "时间戳: {}\nISO 8601: {}",
            info.timestamp,
            info.datetime.to_rfc3339()
        );

        Some(ParseResult::new("ObjectID", content, parsed).with_details(details))
    }
}

