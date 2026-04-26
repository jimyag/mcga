use super::{ParseResult, Parser};

/// 哈希值识别器：按十六进制长度识别常见算法
pub struct HashParser;

impl HashParser {
    pub fn new() -> Self {
        Self
    }

    fn identify(len: usize) -> Option<&'static str> {
        match len {
            32 => Some("MD5"),
            40 => Some("SHA-1"),
            56 => Some("SHA-224"),
            64 => Some("SHA-256"),
            96 => Some("SHA-384"),
            128 => Some("SHA-512"),
            _ => None,
        }
    }
}

impl Default for HashParser {
    fn default() -> Self {
        Self::new()
    }
}

impl Parser for HashParser {
    fn name(&self) -> &'static str {
        "Hash"
    }

    fn parse(&self, content: &str) -> Vec<ParseResult> {
        let trimmed = content.trim();

        // 全部是十六进制字符
        if !trimmed.chars().all(|c| c.is_ascii_hexdigit()) {
            return vec![];
        }

        let algo = match Self::identify(trimmed.len()) {
            Some(a) => a,
            None => return vec![],
        };

        // 格式化：每 8 字符加空格，提高可读性
        let grouped = trimmed
            .as_bytes()
            .chunks(8)
            .map(|c| std::str::from_utf8(c).unwrap())
            .collect::<Vec<_>>()
            .join(" ");

        vec![
            ParseResult::new("Hash", content, format!("算法：{}  长度：{} 位", algo, trimmed.len() * 4))
                .with_details(format!(
                    "{}\n\n算法：{}  摘要长度：{} bits ({} 字节)",
                    grouped,
                    algo,
                    trimmed.len() * 4,
                    trimmed.len() / 2,
                )),
        ]
    }
}
