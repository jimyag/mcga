use std::fs;
use std::path::PathBuf;

use anyhow::Result;

use crate::config::Config;

pub fn config_path() -> Option<PathBuf> {
    dirs::config_dir().map(|d| d.join("mcga").join("config.toml"))
}

/// 加载配置文件，文件不存在时返回默认值
pub fn load() -> Config {
    let path = match config_path() {
        Some(p) => p,
        None => return Config::default(),
    };

    let text = match fs::read_to_string(&path) {
        Ok(t) => t,
        Err(_) => return Config::default(),
    };

    match toml::from_str::<Config>(&text) {
        Ok(c) => c,
        Err(e) => {
            eprintln!("配置文件解析失败（{}），使用默认值：{}", path.display(), e);
            Config::default()
        }
    }
}

/// 将当前配置写入配置文件（首次运行可用于生成模板）
pub fn save(config: &Config) -> Result<()> {
    let path = config_path().ok_or_else(|| anyhow::anyhow!("无法确定配置目录"))?;
    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent)?;
    }
    let text = toml::to_string_pretty(config)?;
    fs::write(&path, text)?;
    Ok(())
}
