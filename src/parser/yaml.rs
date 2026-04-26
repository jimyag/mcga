use super::{ParseResult, Parser};

/// YAML 解析器
/// 仅对解析结果为 map 或 sequence 的内容触发，避免对普通文本误报。
pub struct YamlParser;

impl YamlParser {
    pub fn new() -> Self {
        Self
    }
}

impl Default for YamlParser {
    fn default() -> Self {
        Self::new()
    }
}

impl Parser for YamlParser {
    fn name(&self) -> &'static str {
        "YAML"
    }

    fn parse(&self, content: &str) -> Vec<ParseResult> {
        let trimmed = content.trim();

        // 快速过滤：必须包含 ": " / ": \n" 或以 "---" / "- " 开头，排除 JSON
        if trimmed.starts_with('{') || trimmed.starts_with('[') {
            return vec![];
        }
        let looks_like_yaml = trimmed.starts_with("---")
            || trimmed.starts_with("- ")
            || trimmed.contains(": ");
        if !looks_like_yaml {
            return vec![];
        }

        // 解析
        let value: serde_yml::Value = match serde_yml::from_str(trimmed) {
            Ok(v) => v,
            Err(_) => return vec![],
        };

        // 只对 map / sequence 触发，跳过标量（避免误报纯文本）
        if !value.is_mapping() && !value.is_sequence() {
            return vec![];
        }

        // 格式化输出
        let formatted = match serde_yml::to_string(&value) {
            Ok(s) => s,
            Err(_) => return vec![],
        };

        let kind = if value.is_mapping() { "map" } else { "sequence" };

        vec![
            ParseResult::new(
                "YAML",
                content,
                format!("类型：{}  大小：{} 字节", kind, content.len()),
            )
            .with_details(format!(
                "{}\n类型：{}  大小：{} 字节",
                formatted.trim_end(),
                kind,
                content.len()
            )),
        ]
    }
}
