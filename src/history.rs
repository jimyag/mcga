use std::fs;
use std::path::PathBuf;

use anyhow::Result;
use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};

use crate::parser::ParseResult;

const MAX_ENTRIES: usize = 500;
/// 原始内容预览最多保留的字符数
const ORIGINAL_PREVIEW_LEN: usize = 200;

#[derive(Debug, Serialize, Deserialize)]
pub struct HistoryEntry {
    pub id: u64,
    pub timestamp: DateTime<Utc>,
    /// 原始剪贴板内容（超长时截断）
    pub original_preview: String,
    /// 各解析器的结果摘要
    pub results: Vec<HistoryResult>,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct HistoryResult {
    pub parser_name: String,
    pub parsed: String,
}

fn history_path() -> Option<PathBuf> {
    // 强制使用 ~/.local/share/mcga/history.json，跨平台一致
    dirs::home_dir().map(|h| h.join(".local").join("share").join("mcga").join("history.json"))
}

/// 追加一批解析结果到历史文件
pub fn append(original: &str, results: &[ParseResult]) -> Result<()> {
    if results.is_empty() {
        return Ok(());
    }

    let path = history_path().ok_or_else(|| anyhow::anyhow!("无法确定数据目录"))?;
    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent)?;
    }

    let mut entries = load_all().unwrap_or_default();

    let id = entries.last().map(|e| e.id + 1).unwrap_or(1);
    let preview = if original.len() > ORIGINAL_PREVIEW_LEN {
        format!("{}…", &original[..ORIGINAL_PREVIEW_LEN])
    } else {
        original.to_string()
    };

    entries.push(HistoryEntry {
        id,
        timestamp: Utc::now(),
        original_preview: preview,
        results: results
            .iter()
            .map(|r| HistoryResult {
                parser_name: r.parser_name.clone(),
                parsed: r.parsed.clone(),
            })
            .collect(),
    });

    // 保留最近 MAX_ENTRIES 条
    if entries.len() > MAX_ENTRIES {
        let drain_count = entries.len() - MAX_ENTRIES;
        entries.drain(..drain_count);
    }

    let text = serde_json::to_string_pretty(&entries)?;
    fs::write(&path, text)?;
    Ok(())
}

/// 读取所有历史记录
pub fn load_all() -> Result<Vec<HistoryEntry>> {
    let path = history_path().ok_or_else(|| anyhow::anyhow!("无法确定数据目录"))?;
    let text = fs::read_to_string(&path)?;
    Ok(serde_json::from_str(&text)?)
}

/// 展示最近 n 条历史记录
pub fn print_recent(n: usize) {
    let entries = match load_all() {
        Ok(e) => e,
        Err(_) => {
            println!("暂无历史记录");
            return;
        }
    };

    if entries.is_empty() {
        println!("暂无历史记录");
        return;
    }

    let recent: Vec<_> = entries.iter().rev().take(n).collect();
    println!("最近 {} 条解析记录（共 {} 条）", recent.len(), entries.len());
    println!("{}", "=".repeat(60));

    for entry in recent {
        let time = entry.timestamp.format("%Y-%m-%d %H:%M:%S");
        let parsers: Vec<_> = entry.results.iter().map(|r| r.parser_name.as_str()).collect();
        println!("[{}] #{}", time, entry.id);
        println!("  内容：{}", entry.original_preview.lines().next().unwrap_or(""));
        println!("  解析：{}", parsers.join(", "));
        println!();
    }
}

/// 将最近 n 条历史记录格式化为适合浮层展示的文本
pub fn format_for_overlay(entries: &[HistoryEntry], n: usize) -> String {
    if entries.is_empty() {
        return "暂无历史记录".to_string();
    }

    let recent: Vec<_> = entries.iter().rev().take(n).collect();
    let mut out = format!("最近 {} 条 / 共 {} 条\n\n", recent.len(), entries.len());

    for entry in &recent {
        let time = entry.timestamp.format("%m-%d %H:%M:%S");
        let parsers: Vec<_> = entry.results.iter().map(|r| r.parser_name.as_str()).collect();
        out.push_str(&format!(
            "[{}] #{} — {}\n{}\n\n",
            time,
            entry.id,
            parsers.join(", "),
            entry.original_preview.lines().take(3).collect::<Vec<_>>().join(" ↵ ")
        ));
    }

    out.trim_end().to_string()
}

/// 清空历史记录
pub fn clear() -> Result<()> {
    let path = history_path().ok_or_else(|| anyhow::anyhow!("无法确定数据目录"))?;
    fs::write(&path, "[]")?;
    Ok(())
}
