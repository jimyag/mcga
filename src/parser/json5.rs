use serde_json::Value;

use super::{ParseResult, Parser};

/// JSON5 / JSONC 解析器
/// 仅在严格 JSON 解析失败时触发，处理带注释、trailing comma、单引号等 JSON5 扩展语法。
pub struct Json5Parser;

impl Json5Parser {
    pub fn new() -> Self {
        Self
    }
}

impl Default for Json5Parser {
    fn default() -> Self {
        Self::new()
    }
}

impl Parser for Json5Parser {
    fn name(&self) -> &'static str {
        "JSON5"
    }

    fn parse(&self, content: &str) -> Vec<ParseResult> {
        let trimmed = content.trim();
        // 必须以 { 或 [ 开头（JSON5 对象/数组）
        if !trimmed.starts_with('{') && !trimmed.starts_with('[') {
            return vec![];
        }
        // 已能被严格 JSON 解析的交给 JsonParser 处理
        if serde_json::from_str::<Value>(trimmed).is_ok() {
            return vec![];
        }
        // 尝试 JSON5 解析
        let value: Value = match json5::from_str(trimmed) {
            Ok(v) => v,
            Err(_) => return vec![],
        };

        let formatted = match serde_json::to_string_pretty(&value) {
            Ok(s) => s,
            Err(_) => return vec![],
        };

        let variant = if trimmed.contains("//") || trimmed.contains("/*") {
            "JSONC"
        } else {
            "JSON5"
        };

        vec![ParseResult::new(
            "JSON5",
            content,
            format!(
                "{} → 转换为标准 JSON，大小：{} 字节",
                variant,
                content.len()
            ),
        )
        .with_details(format!(
            "{}\n\n来源格式：{}  大小：{} 字节",
            formatted,
            variant,
            content.len()
        ))]
    }
}
