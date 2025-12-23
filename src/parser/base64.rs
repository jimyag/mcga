use base64::{engine::general_purpose, Engine};

use super::{ParseResult, Parser};

/// Base64 解析器
pub struct Base64Parser;

impl Base64Parser {
    pub fn new() -> Self {
        Self
    }

    fn is_likely_base64(content: &str) -> bool {
        // 至少 4 个字符
        if content.len() < 4 {
            return false;
        }

        // 检查是否只包含 Base64 字符
        let valid_chars = content
            .chars()
            .all(|c| c.is_ascii_alphanumeric() || c == '+' || c == '/' || c == '=');

        if !valid_chars {
            return false;
        }

        // 检查填充是否正确
        let padding_count = content.chars().rev().take_while(|&c| c == '=').count();
        if padding_count > 2 {
            return false;
        }

        // 长度检查（Base64 编码后长度应该是 4 的倍数）
        content.len() % 4 == 0
    }

    fn is_printable_text(bytes: &[u8]) -> bool {
        // 检查是否为可打印文本（允许 UTF-8）
        if let Ok(text) = std::str::from_utf8(bytes) {
            text.chars().all(|c| !c.is_control() || c == '\n' || c == '\r' || c == '\t')
        } else {
            false
        }
    }
}

impl Default for Base64Parser {
    fn default() -> Self {
        Self::new()
    }
}

impl Parser for Base64Parser {
    fn name(&self) -> &'static str {
        "Base64"
    }

    fn parse(&self, content: &str) -> Option<ParseResult> {
        if !Self::is_likely_base64(content) {
            return None;
        }

        let decoded = general_purpose::STANDARD.decode(content).ok()?;
        
        let decoded_preview = if Self::is_printable_text(&decoded) {
            let text = String::from_utf8_lossy(&decoded);
            if text.len() > 200 {
                format!("{}...", &text[..200])
            } else {
                text.to_string()
            }
        } else {
            // 显示十六进制预览
            let hex: String = decoded.iter().take(50).map(|b| format!("{:02x} ", b)).collect();
            if decoded.len() > 50 {
                format!("(二进制数据) {}...", hex)
            } else {
                format!("(二进制数据) {}", hex)
            }
        };

        let details = format!(
            "编码长度：{} 字节\n解码长度：{} 字节\n内容类型：{}\n\n解码结果:\n{}",
            content.len(),
            decoded.len(),
            if Self::is_printable_text(&decoded) { "文本" } else { "二进制" },
            decoded_preview
        );

        Some(
            ParseResult::new(
                "Base64",
                content,
                format!("编码长度：{} 字节\n解码长度：{} 字节\n内容类型：{}", 
                    content.len(), 
                    decoded.len(),
                    if Self::is_printable_text(&decoded) { "文本" } else { "二进制" }
                ),
            )
            .with_details(details),
        )
    }
}

