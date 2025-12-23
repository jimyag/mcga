use std::time::Duration;

use anyhow::Result;
use arboard::Clipboard;

/// 剪切板监控器
pub struct ClipboardMonitor {
    clipboard: Clipboard,
    last_content: Option<String>,
    poll_interval: Duration,
}

impl ClipboardMonitor {
    pub fn new(poll_interval: Duration) -> Result<Self> {
        let clipboard = Clipboard::new()?;
        Ok(Self {
            clipboard,
            last_content: None,
            poll_interval,
        })
    }

    /// 获取轮询间隔
    pub fn poll_interval(&self) -> Duration {
        self.poll_interval
    }

    /// 检查剪切板内容是否发生变化，如果变化则返回新内容
    pub fn check_for_changes(&mut self) -> Result<Option<String>> {
        let current = self.clipboard.get_text().ok();

        match (&self.last_content, &current) {
            (Some(last), Some(curr)) if last == curr => Ok(None),
            (None, None) => Ok(None),
            (_, Some(curr)) => {
                let content = curr.clone();
                self.last_content = Some(content.clone());
                Ok(Some(content))
            }
            (Some(_), None) => {
                self.last_content = None;
                Ok(None)
            }
        }
    }

    /// 获取当前剪切板内容（不检查变化）
    pub fn get_current(&mut self) -> Result<Option<String>> {
        Ok(self.clipboard.get_text().ok())
    }
}

