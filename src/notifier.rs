use anyhow::Result;
use notify_rust::{Notification, Timeout};

use crate::config::Config;
use crate::parser::ParseResult;

/// 桌面通知发送器
pub struct Notifier {
    app_name: String,
    icon: String,
    timeout: Timeout,
}

impl Notifier {
    pub fn new(config: &Config) -> Self {
        let timeout = if config.notification_timeout_ms == 0 {
            Timeout::Never
        } else {
            Timeout::Milliseconds(config.notification_timeout_ms as u32)
        };

        Self {
            app_name: config.app_name.clone(),
            icon: config.icon.clone(),
            timeout,
        }
    }

    /// 发送解析结果通知
    pub fn send(&self, result: &ParseResult) -> Result<()> {
        let summary = format!("[{}] {}", result.parser_name, &result.original[..result.original.len().min(30)]);
        
        let body = result.parsed.clone();

        Notification::new()
            .appname(&self.app_name)
            .summary(&summary)
            .body(&body)
            .icon(&self.icon)
            .timeout(self.timeout)
            .show()?;

        Ok(())
    }

    /// 发送多个解析结果的合并通知
    pub fn send_all(&self, results: &[ParseResult]) -> Result<()> {
        if results.is_empty() {
            return Ok(());
        }

        // 原始内容作为标题
        let original = &results[0].original;
        let summary = original[..original.len().min(40)].to_string();

        // 合并所有结果
        let mut body = String::new();
        for (i, result) in results.iter().enumerate() {
            if i > 0 {
                body.push('\n');
            }
            body.push_str(&format!("{}：\n", result.parser_name));
            
            // 解析 parsed 字段，添加缩进
            for line in result.parsed.lines() {
                body.push_str(&format!("   {}\n", line));
            }
            
            // 解析 details 字段，添加缩进
            if let Some(ref details) = result.details {
                for line in details.lines() {
                    body.push_str(&format!("   {}\n", line));
                }
            }
        }

        Notification::new()
            .appname(&self.app_name)
            .summary(&summary)
            .body(&body.trim_end())
            .icon(&self.icon)
            .timeout(self.timeout)
            .show()?;

        Ok(())
    }

    /// 发送简单通知
    pub fn send_simple(&self, summary: &str, body: &str) -> Result<()> {
        Notification::new()
            .appname(&self.app_name)
            .summary(summary)
            .body(body)
            .icon(&self.icon)
            .timeout(self.timeout)
            .show()?;

        Ok(())
    }
}

