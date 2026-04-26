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
    /// macOS 浮层：自动消失时间（秒）
    pub overlay_dismiss_secs: u64,
    /// macOS 浮层：宽度占屏幕宽度的比例（0.0–1.0）
    pub overlay_width_pct: f64,
    /// macOS 浮层：高度占屏幕高度的比例（0.0–1.0）
    pub overlay_height_pct: f64,
    /// macOS 浮层：距屏幕右边缘占屏幕宽度的比例
    pub overlay_margin_right_pct: f64,
    /// macOS 浮层：距屏幕底边缘占屏幕高度的比例
    pub overlay_margin_bottom_pct: f64,
    /// macOS 浮层：相邻浮层间距占屏幕高度的比例
    pub overlay_gap_pct: f64,
}

impl Default for Config {
    fn default() -> Self {
        Self {
            poll_interval_ms: 500,
            notification_timeout_ms: 5000,
            app_name: "MCGA".to_string(),
            icon: "dialog-information".to_string(),
            overlay_dismiss_secs: 5,
            overlay_width_pct: 0.28,
            overlay_height_pct: 0.38,
            overlay_margin_right_pct: 0.012,
            overlay_margin_bottom_pct: 0.07,
            overlay_gap_pct: 0.012,
        }
    }
}

impl Config {
    pub fn poll_interval(&self) -> Duration {
        Duration::from_millis(self.poll_interval_ms)
    }
}
