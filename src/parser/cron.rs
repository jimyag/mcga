use super::{ParseResult, Parser};

/// Cron 表达式解析器，支持 5 字段（标准）和 6 字段（含秒）格式
pub struct CronParser;

impl CronParser {
    pub fn new() -> Self {
        Self
    }
}

impl Default for CronParser {
    fn default() -> Self {
        Self::new()
    }
}

/// 判断一个字段是否合法（数字、*、/、-、,、? 的组合）
fn is_valid_field(s: &str) -> bool {
    !s.is_empty()
        && s.chars().all(|c| {
            c.is_ascii_digit() || matches!(c, '*' | '/' | '-' | ',' | '?' | 'L' | 'W' | '#')
        })
}

/// 将单个字段解释为自然语言
fn explain_field(field: &str, unit: &str, names: Option<&[&str]>) -> String {
    if field == "*" || field == "?" {
        return format!("每{}", unit);
    }
    // 步进：*/5
    if let Some(rest) = field.strip_prefix("*/") {
        return format!("每 {} {}", rest, unit);
    }
    // 范围：1-5
    if field.contains('-') && !field.contains('/') {
        let parts: Vec<&str> = field.splitn(2, '-').collect();
        let start = label(parts[0], names);
        let end = label(parts[1], names);
        return format!("{} 到 {}", start, end);
    }
    // 范围+步进：1-5/2
    if field.contains('-') && field.contains('/') {
        if let Some((range, step)) = field.split_once('/') {
            let (s, e) = range.split_once('-').unwrap_or((range, range));
            return format!("{} 到 {} 每隔 {}", label(s, names), label(e, names), step);
        }
    }
    // 列表：1,3,5
    if field.contains(',') {
        let items: Vec<String> = field.split(',').map(|v| label(v, names)).collect();
        return items.join("、");
    }
    // 单值
    label(field, names)
}

fn label(v: &str, names: Option<&[&str]>) -> String {
    if let (Ok(n), Some(ns)) = (v.parse::<usize>(), names) {
        if n < ns.len() {
            return ns[n].to_string();
        }
    }
    v.to_string()
}

const WEEKDAY_NAMES: &[&str] = &["周日", "周一", "周二", "周三", "周四", "周五", "周六"];
const MONTH_NAMES: &[&str] = &[
    "", "1月", "2月", "3月", "4月", "5月", "6月", "7月", "8月", "9月", "10月", "11月", "12月",
];

impl Parser for CronParser {
    fn name(&self) -> &'static str {
        "Cron"
    }

    fn parse(&self, content: &str) -> Vec<ParseResult> {
        let trimmed = content.trim();

        // 特殊宏
        let macro_desc = match trimmed {
            "@yearly" | "@annually" => Some("每年 1 月 1 日 00:00 执行"),
            "@monthly" => Some("每月 1 日 00:00 执行"),
            "@weekly" => Some("每周日 00:00 执行"),
            "@daily" | "@midnight" => Some("每天 00:00 执行"),
            "@hourly" => Some("每小时整点执行"),
            "@reboot" => Some("系统重启后执行一次"),
            _ => None,
        };
        if let Some(desc) = macro_desc {
            return vec![ParseResult::new("Cron", content, desc.to_string())];
        }

        let fields: Vec<&str> = trimmed.split_whitespace().collect();
        if fields.len() != 5 && fields.len() != 6 {
            return vec![];
        }
        if !fields.iter().all(|f| is_valid_field(f)) {
            return vec![];
        }

        let (sec_part, min, hour, dom, month, dow) = if fields.len() == 6 {
            (
                Some(explain_field(fields[0], "秒", None)),
                fields[1],
                fields[2],
                fields[3],
                fields[4],
                fields[5],
            )
        } else {
            (None, fields[0], fields[1], fields[2], fields[3], fields[4])
        };

        let min_desc = explain_field(min, "分钟", None);
        let hour_desc = explain_field(hour, "小时", None);
        let dom_desc = explain_field(dom, "天", None);
        let month_desc = explain_field(month, "月", Some(MONTH_NAMES));
        let dow_desc = explain_field(dow, "周", Some(WEEKDAY_NAMES));

        let mut lines = vec![
            format!("分钟：{}", min_desc),
            format!("小时：{}", hour_desc),
            format!("日期：{}", dom_desc),
            format!("月份：{}", month_desc),
            format!("星期：{}", dow_desc),
        ];
        if let Some(sec) = &sec_part {
            lines.insert(0, format!("秒：{}", sec));
        }

        let summary = format!("{}，{}，{}", month_desc, dom_desc, hour_desc);

        vec![ParseResult::new("Cron", content, summary).with_details(lines.join("\n"))]
    }
}
