use chrono::{DateTime, TimeZone, Utc};

use super::{ParseResult, Parser};

/// 时间戳解析器
pub struct TimestampParser;

impl TimestampParser {
    pub fn new() -> Self {
        Self
    }

    fn parse_unix_seconds(&self, ts: i64) -> Option<DateTime<Utc>> {
        // 合理的时间范围：1970-2100
        if ts < 0 || ts > 4102444800 {
            return None;
        }
        Utc.timestamp_opt(ts, 0).single()
    }

    fn parse_unix_millis(&self, ts: i64) -> Option<DateTime<Utc>> {
        // 毫秒时间戳 (13 位数字)
        let secs = ts / 1000;
        let nanos = ((ts % 1000) * 1_000_000) as u32;
        if secs < 0 || secs > 4102444800 {
            return None;
        }
        Utc.timestamp_opt(secs, nanos).single()
    }

    fn parse_unix_micros(&self, ts: i64) -> Option<DateTime<Utc>> {
        // 微秒时间戳 (16 位数字)
        let secs = ts / 1_000_000;
        let nanos = ((ts % 1_000_000) * 1000) as u32;
        if secs < 0 || secs > 4102444800 {
            return None;
        }
        Utc.timestamp_opt(secs, nanos).single()
    }

    fn parse_unix_100nanos(&self, ts: i64) -> Option<DateTime<Utc>> {
        // 百纳秒时间戳 (17 位数字)
        let nanos_total = ts * 100;
        let secs = nanos_total / 1_000_000_000;
        let nanos = (nanos_total % 1_000_000_000) as u32;
        if secs < 0 || secs > 4102444800 {
            return None;
        }
        Utc.timestamp_opt(secs, nanos).single()
    }

    fn parse_unix_nanos(&self, ts: i64) -> Option<DateTime<Utc>> {
        // 纳秒时间戳 (19 位数字)
        let secs = ts / 1_000_000_000;
        let nanos = (ts % 1_000_000_000) as u32;
        if secs < 0 || secs > 4102444800 {
            return None;
        }
        Utc.timestamp_opt(secs, nanos).single()
    }
}

impl Default for TimestampParser {
    fn default() -> Self {
        Self::new()
    }
}

impl Parser for TimestampParser {
    fn name(&self) -> &'static str {
        "Timestamp"
    }

    fn parse(&self, content: &str) -> Vec<ParseResult> {
        // 只解析纯数字
        let ts: i64 = match content.parse() {
            Ok(v) => v,
            Err(_) => return vec![],
        };
        let len = content.len();

        let (datetime, unit) = match len {
            10 => match self.parse_unix_seconds(ts) {
                Some(d) => (d, "秒"),
                None => return vec![],
            },
            13 => match self.parse_unix_millis(ts) {
                Some(d) => (d, "毫秒"),
                None => return vec![],
            },
            16 => match self.parse_unix_micros(ts) {
                Some(d) => (d, "微秒"),
                None => return vec![],
            },
            17 => match self.parse_unix_100nanos(ts) {
                Some(d) => (d, "百纳秒"),
                None => return vec![],
            },
            19 => match self.parse_unix_nanos(ts) {
                Some(d) => (d, "纳秒"),
                None => return vec![],
            },
            _ => return vec![],
        };

        let local_time = datetime.format("%Y-%m-%d %H:%M:%S%.3f UTC");

        let details = format!(
            "原始值：{}\n精度：{}\nUTC: {}\nISO 8601: {}",
            ts,
            unit,
            local_time,
            datetime.to_rfc3339()
        );

        vec![ParseResult::new(
            "Timestamp",
            content,
            format!("精度：{}\n时间：{}", unit, local_time),
        )
        .with_details(details)]
    }
}
