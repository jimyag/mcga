use base64::{engine::general_purpose, Engine as _};

use super::{ParseResult, Parser};

/// Base64 解码器
/// 同时尝试标准 base64 和 URL-safe base64，解码结果须为可打印 UTF-8 文本。
pub struct Base64Parser;

impl Base64Parser {
    pub fn new() -> Self {
        Self
    }

    fn try_decode(content: &str) -> Option<(String, &'static str)> {
        // 去掉空白后再尝试
        let s = content.trim();

        // 标准 base64（含 padding）
        if let Ok(bytes) = general_purpose::STANDARD.decode(s) {
            if let Ok(text) = std::str::from_utf8(&bytes) {
                if is_printable(text) {
                    return Some((text.to_string(), "standard"));
                }
            }
        }
        // URL-safe base64（含 padding）
        if let Ok(bytes) = general_purpose::URL_SAFE.decode(s) {
            if let Ok(text) = std::str::from_utf8(&bytes) {
                if is_printable(text) {
                    return Some((text.to_string(), "url-safe"));
                }
            }
        }
        // URL-safe 无 padding
        if let Ok(bytes) = general_purpose::URL_SAFE_NO_PAD.decode(s) {
            if let Ok(text) = std::str::from_utf8(&bytes) {
                if is_printable(text) {
                    return Some((text.to_string(), "url-safe-no-pad"));
                }
            }
        }
        None
    }
}

/// 可打印文本：允许普通 ASCII 可打印字符及常见空白，不允许控制字符（\x00-\x08 等）
fn is_printable(s: &str) -> bool {
    if s.is_empty() {
        return false;
    }
    s.chars()
        .all(|c| c >= ' ' || c == '\n' || c == '\r' || c == '\t')
}

/// 检查字符串是否全部由 base64 字符集组成
fn is_base64_charset(s: &str) -> bool {
    s.chars()
        .all(|c| c.is_ascii_alphanumeric() || matches!(c, '+' | '/' | '-' | '_' | '='))
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

    fn parse(&self, content: &str) -> Vec<ParseResult> {
        let trimmed = content.trim();

        // 长度限制：至少 8 字符，避免误报短字符串
        if trimmed.len() < 8 {
            return vec![];
        }
        // 必须全部为 base64 字符集
        if !is_base64_charset(trimmed) {
            return vec![];
        }
        // 解码后必须是可打印 UTF-8
        let (decoded, variant) = match Self::try_decode(trimmed) {
            Some(pair) => pair,
            None => return vec![],
        };

        vec![ParseResult::new(
            "Base64",
            content,
            format!(
                "格式：{}  编码长度：{}  解码长度：{}",
                variant,
                trimmed.len(),
                decoded.len()
            ),
        )
        .with_details(format!(
            "{}\n\n格式：{}  编码长度：{}  解码长度：{} 字节",
            decoded,
            variant,
            trimmed.len(),
            decoded.len()
        ))]
    }
}
