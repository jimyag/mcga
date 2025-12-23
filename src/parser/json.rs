use serde_json::Value;

use super::{ParseResult, Parser};

/// JSON 解析器
pub struct JsonParser;

impl JsonParser {
    pub fn new() -> Self {
        Self
    }

    fn get_json_info(value: &Value) -> String {
        match value {
            Value::Null => "null".to_string(),
            Value::Bool(_) => "boolean".to_string(),
            Value::Number(_) => "number".to_string(),
            Value::String(_) => "string".to_string(),
            Value::Array(arr) => format!("array[{}]", arr.len()),
            Value::Object(obj) => format!("object{{{}}}", obj.len()),
        }
    }

    fn count_elements(value: &Value) -> usize {
        match value {
            Value::Array(arr) => arr.iter().map(Self::count_elements).sum::<usize>() + arr.len(),
            Value::Object(obj) => {
                obj.values().map(Self::count_elements).sum::<usize>() + obj.len()
            }
            _ => 1,
        }
    }

    fn get_depth(value: &Value) -> usize {
        match value {
            Value::Array(arr) => {
                1 + arr.iter().map(Self::get_depth).max().unwrap_or(0)
            }
            Value::Object(obj) => {
                1 + obj.values().map(Self::get_depth).max().unwrap_or(0)
            }
            _ => 0,
        }
    }
}

impl Default for JsonParser {
    fn default() -> Self {
        Self::new()
    }
}

impl Parser for JsonParser {
    fn name(&self) -> &'static str {
        "JSON"
    }

    fn parse(&self, content: &str) -> Option<ParseResult> {
        // 快速检查：必须以 { 或 [ 开头
        let trimmed = content.trim();
        if !trimmed.starts_with('{') && !trimmed.starts_with('[') {
            return None;
        }

        let value: Value = serde_json::from_str(content).ok()?;
        
        let type_info = Self::get_json_info(&value);
        let element_count = Self::count_elements(&value);
        let depth = Self::get_depth(&value);

        // 格式化 JSON（限制长度）
        let formatted = serde_json::to_string_pretty(&value).ok()?;
        let preview = if formatted.len() > 500 {
            format!("{}...", &formatted[..500])
        } else {
            formatted
        };

        let details = format!(
            "类型：{}\n元素数：{}\n嵌套深度：{}\n原始大小：{} 字节\n\n预览:\n{}",
            type_info,
            element_count,
            depth,
            content.len(),
            preview
        );

        Some(
            ParseResult::new("JSON", content, format!("类型：{}\n元素数：{}\n嵌套深度：{}", type_info, element_count, depth))
                .with_details(details),
        )
    }
}

