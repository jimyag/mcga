use super::{ParseResult, Parser};

const MAX_YAML_INPUT_BYTES: usize = 64 * 1024;

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
        if trimmed.len() > MAX_YAML_INPUT_BYTES {
            return vec![];
        }

        // 快速过滤：必须包含 ": " / ": \n" 或以 "---" 开头，排除 JSON。
        // 单行 "- xxx" 常见于 Markdown bullet/path，不作为 YAML 触发条件。
        if trimmed.starts_with('{') || trimmed.starts_with('[') {
            return vec![];
        }
        let looks_like_yaml = trimmed.starts_with("---")
            || trimmed.contains(": ")
            || trimmed.contains(":\n")
            || looks_like_sequence(trimmed);
        if !looks_like_yaml {
            return vec![];
        }

        // 解析：用 catch_unwind 防止 libyml 对特定输入直接 panic（已知 libyml bug）
        let owned = trimmed.to_owned();
        let parse_result =
            std::panic::catch_unwind(|| serde_yml::from_str::<serde_yml::Value>(&owned));
        let value = match parse_result {
            Ok(Ok(v)) => v,
            _ => return vec![],
        };

        // 只对 map / sequence 触发，跳过标量（避免误报纯文本）
        if !value.is_mapping() && !value.is_sequence() {
            return vec![];
        }

        // 格式化输出
        let formatted_result = std::panic::catch_unwind(|| serde_yml::to_string(&value));
        let formatted = match formatted_result {
            Ok(Ok(s)) => s,
            _ => return vec![],
        };

        let kind = if value.is_mapping() {
            "map"
        } else {
            "sequence"
        };

        vec![ParseResult::new(
            "YAML",
            content,
            format!("类型：{}  大小：{} 字节", kind, content.len()),
        )
        .with_details(format!(
            "{}\n类型：{}  大小：{} 字节",
            formatted.trim_end(),
            kind,
            content.len()
        ))]
    }
}

fn looks_like_sequence(trimmed: &str) -> bool {
    trimmed
        .lines()
        .filter(|line| line.trim_start().starts_with("- "))
        .take(2)
        .count()
        >= 2
}
