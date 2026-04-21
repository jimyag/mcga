use anyhow::{bail, Context, Result};
#[cfg(not(target_os = "macos"))]
use notify_rust::Notification;
#[cfg(not(target_os = "macos"))]
use notify_rust::Timeout;
#[cfg(target_os = "macos")]
use std::process::Command;

use crate::config::Config;
use crate::parser::ParseResult;

/// 桌面通知发送器
pub struct Notifier {
    #[cfg(not(target_os = "macos"))]
    app_name: String,
    #[cfg(not(target_os = "macos"))]
    icon: String,
    #[cfg(not(target_os = "macos"))]
    timeout: Timeout,
}

impl Notifier {
    pub fn new(config: &Config) -> Self {
        #[cfg(target_os = "macos")]
        let _ = config;

        #[cfg(not(target_os = "macos"))]
        let timeout = if config.notification_timeout_ms == 0 {
            Timeout::Never
        } else {
            Timeout::Milliseconds(config.notification_timeout_ms as u32)
        };

        Self {
            #[cfg(not(target_os = "macos"))]
            app_name: config.app_name.clone(),
            #[cfg(not(target_os = "macos"))]
            icon: config.icon.clone(),
            #[cfg(not(target_os = "macos"))]
            timeout,
        }
    }

    /// 发送解析结果通知
    pub fn send(&self, result: &ParseResult) -> Result<()> {
        let notification = parse_result_notification(result);
        self.send_notification(
            &notification.title,
            &notification.body,
            notification.subtitle.as_deref(),
        )
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

        self.send_notification(&summary, body.trim_end(), None)
    }

    /// 发送简单通知
    pub fn send_simple(&self, summary: &str, body: &str) -> Result<()> {
        self.send_notification(summary, body, None)
    }

    fn send_notification(&self, title: &str, body: &str, subtitle: Option<&str>) -> Result<()> {
        #[cfg(target_os = "macos")]
        {
            let args = macos_osascript_args(body, title, subtitle);
            let status = Command::new("osascript")
                .args(args.iter().map(String::as_str))
                .status()
                .context("调用 osascript 发送通知失败")?;

            if !status.success() {
                bail!("osascript 发送通知失败：退出状态 {status}");
            }

            Ok(())
        }

        #[cfg(not(target_os = "macos"))]
        {
            let summary = match subtitle {
                Some(subtitle) => format!("[{subtitle}] {title}"),
                None => title.to_string(),
            };

            Notification::new()
                .appname(&self.app_name)
                .summary(&summary)
                .body(body)
                .icon(&self.icon)
                .timeout(self.timeout)
                .show()?;

            Ok(())
        }
    }
}

struct NotificationContent {
    title: String,
    subtitle: Option<String>,
    body: String,
}

fn parse_result_notification(result: &ParseResult) -> NotificationContent {
    let title = format!(
        "[{}] {}",
        result.parser_name,
        &result.original[..result.original.len().min(30)]
    );

    let mut body = result.parsed.clone();
    if let Some(details) = &result.details {
        if !body.is_empty() && !details.is_empty() {
            body.push('\n');
        }
        body.push_str(details);
    }

    NotificationContent {
        title,
        subtitle: None,
        body,
    }
}

#[cfg(target_os = "macos")]
fn macos_osascript_args<'a>(
    body: &'a str,
    title: &'a str,
    subtitle: Option<&'a str>,
) -> Vec<String> {
    let body = apple_script_string_literal(body);
    let title = apple_script_string_literal(title);

    let script = match subtitle {
        Some(subtitle) => format!(
            "display notification {body} with title {title} subtitle {}",
            apple_script_string_literal(subtitle)
        ),
        None => format!("display notification {body} with title {title}"),
    };

    vec!["-e".to_string(), script]
}

#[cfg(target_os = "macos")]
fn apple_script_string_literal(value: &str) -> String {
    let mut parts = value
        .split('\n')
        .map(|part| format!("\"{}\"", part.replace('\\', "\\\\").replace('"', "\\\"")))
        .collect::<Vec<_>>();

    if parts.is_empty() {
        return "\"\"".to_string();
    }

    if parts.len() == 1 {
        return parts.pop().unwrap();
    }

    parts.join(" & linefeed & ")
}

#[cfg(test)]
mod tests {
    use crate::parser::ParseResult;

    #[cfg(target_os = "macos")]
    use super::macos_osascript_args;
    use super::parse_result_notification;

    #[test]
    fn parse_result_notification_keeps_parser_in_title_and_puts_details_in_body() {
            .with_details("机房：nb\n环境：prod");

        let notification = parse_result_notification(&result);

        assert_eq!(notification.subtitle, None);
        assert_eq!(notification.body, "节点：zz1434\n机房：nb\n环境：prod");
    }

    #[cfg(target_os = "macos")]
    #[test]
    fn macos_notification_args_include_title_and_body() {
        let args = macos_osascript_args("parsed body", "summary title", None);

        assert_eq!(
            args,
            vec![
                "-e".to_string(),
                "display notification \"parsed body\" with title \"summary title\"".to_string(),
            ]
        );
    }

    #[cfg(target_os = "macos")]
    #[test]
    fn macos_notification_args_include_subtitle_when_present() {

        assert_eq!(
            args,
            vec![
                "-e".to_string(),
                    .to_string(),
            ]
        );
    }
}
