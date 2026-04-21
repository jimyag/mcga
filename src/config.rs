use std::time::Duration;

use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Config {
    /// 剪切板轮询间隔（毫秒）
    pub poll_interval_ms: u64,
    /// 通知超时时间（毫秒），0 表示不自动消失
    pub notification_timeout_ms: i32,
    /// 应用名称
    pub app_name: String,
    /// 通知图标
    pub icon: String,
}

impl Default for Config {
    fn default() -> Self {
        Self {
            poll_interval_ms: 500,
            notification_timeout_ms: 5000,
            app_name: "MCGA".to_string(),
            icon: "dialog-information".to_string(),
        }
    }
}

impl Config {
    pub fn poll_interval(&self) -> Duration {
        Duration::from_millis(self.poll_interval_ms)
    }
}
