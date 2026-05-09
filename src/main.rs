use std::sync::mpsc;
use std::sync::{Arc, Mutex};
use std::thread;
use std::time::Duration;

use anyhow::Result;
use clap::{Parser, Subcommand};
use tracing::{debug, error, info, warn};
use tracing_subscriber::EnvFilter;

use mcga::config::Config;
use mcga::monitor::ClipboardMonitor;
use mcga::parser::{ParseResult, ParserEngine};

#[derive(Parser)]
#[command(name = "mcga")]
#[command(author = "jimyag")]
#[command(version = "0.1.0")]
#[command(about = "My Clipboard Guard Assistant - 剪切板智能解析工具", long_about = None)]
struct Cli {
    #[command(subcommand)]
    command: Option<Commands>,
}

#[derive(Subcommand)]
enum Commands {
    /// 启动守护进程，监控剪切板
    Daemon {
        /// 轮询间隔（毫秒）
        #[arg(short, long, default_value = "500")]
        interval: u64,
    },
    /// 解析指定内容
    Parse {
        /// 要解析的内容
        content: String,
        /// 显示所有匹配的解析结果
        #[arg(short, long)]
        all: bool,
    },
    /// 列出所有支持的解析器
    Parsers,
    /// 解析当前剪切板内容
    Clip {
        /// 显示所有匹配的解析结果
        #[arg(short, long)]
        all: bool,
    },
    /// 查看解析历史
    History {
        /// 显示最近 N 条记录
        #[arg(short, long, default_value = "20")]
        count: usize,
        /// 清空历史记录
        #[arg(long)]
        clear: bool,
        /// 在浮层中展示（仅 macOS）
        #[arg(short, long)]
        overlay: bool,
    },
    /// 将当前配置写入配置文件（生成模板）
    InitConfig,
}

fn main() -> Result<()> {
    tracing_subscriber::fmt()
        .with_env_filter(EnvFilter::from_default_env().add_directive("mcga=info".parse()?))
        .init();

    let cli = Cli::parse();

    match cli.command {
        Some(Commands::Daemon { interval }) => run_daemon(interval),
        Some(Commands::Parse { content, all }) => run_parse(&content, all),
        Some(Commands::Parsers) => list_parsers(),
        Some(Commands::Clip { all }) => run_clip(all),
        Some(Commands::History {
            count,
            clear,
            overlay,
        }) => {
            if clear {
                mcga::history::clear()?;
                println!("历史记录已清空");
                Ok(())
            } else if overlay {
                #[cfg(target_os = "macos")]
                return run_history_overlay(count);
                #[cfg(not(target_os = "macos"))]
                {
                    mcga::history::print_recent(count);
                    Ok(())
                }
            } else {
                mcga::history::print_recent(count);
                Ok(())
            }
        }
        Some(Commands::InitConfig) => {
            let config = mcga::config_file::load();
            mcga::config_file::save(&config)?;
            println!(
                "配置文件已写入：{}",
                mcga::config_file::config_path().unwrap().display()
            );
            Ok(())
        }
        None => run_daemon(500),
    }
}

/// 运行守护进程模式
fn run_daemon(interval_ms: u64) -> Result<()> {
    #[cfg(target_os = "macos")]
    return run_daemon_macos(interval_ms);

    #[cfg(not(target_os = "macos"))]
    return run_daemon_generic(interval_ms);
}

/// 守护进程 — 非 macOS 平台（保留原有 notify-rust 逻辑）
#[cfg(not(target_os = "macos"))]
fn run_daemon_generic(interval_ms: u64) -> Result<()> {
    info!("MCGA 守护进程启动，轮询间隔：{}ms", interval_ms);

    let mut config = mcga::config_file::load();
    config.poll_interval_ms = interval_ms;

    let mut monitor = ClipboardMonitor::new(config.poll_interval())?;
    let engine = ParserEngine::new();
    let notifier = Notifier::new(&config);

    info!(
        "已加载 {} 个解析器：{:?}",
        engine.parser_names().len(),
        engine.parser_names()
    );

    let mut prev_content = String::new();
    loop {
        match monitor.check_for_changes() {
            Ok(Some(content)) => {
                debug!("检测到剪切板变化：{} 字符", content.len());
                let results = engine.parse_all_with_prev(&content, &prev_content);
                prev_content = content.clone();
                if results.is_empty() {
                    debug!("无法解析的内容");
                } else {
                    info!("解析成功：{} 个结果", results.len());
                    for result in &results {
                        info!("  [{}] {}", result.parser_name, &result.parsed);
                        if let Err(e) = notifier.send(result) {
                            error!("发送通知失败：{}", e);
                        }
                    }
                    if let Err(e) = mcga::history::append(&content, &results) {
                        debug!("历史记录写入失败：{}", e);
                    }
                }
            }
            Ok(None) => {}
            Err(e) => warn!("读取剪切板失败：{}", e),
        }
        thread::sleep(Duration::from_millis(interval_ms));
    }
}

/// 守护进程 — macOS：NSApplication 跑在主线程，剪切板轮询在后台线程
#[cfg(target_os = "macos")]
fn run_daemon_macos(interval_ms: u64) -> Result<()> {
    use objc2_app_kit::{NSApplication, NSApplicationActivationPolicy};

    info!(
        "MCGA 守护进程启动（macOS overlay 模式），轮询间隔：{}ms",
        interval_ms
    );

    let mut config = mcga::config_file::load();
    config.poll_interval_ms = interval_ms;
    let engine = Arc::new(ParserEngine::new());

    info!(
        "已加载 {} 个解析器：{:?}",
        engine.parser_names().len(),
        engine.parser_names()
    );

    let (tx, rx) = mpsc::channel::<Vec<ParseResult>>();
    let rx = Arc::new(Mutex::new(rx));

    // 后台线程：轮询剪切板
    let engine_bg = Arc::clone(&engine);
    let interval = config.poll_interval();
    thread::spawn(move || {
        let mut monitor = match ClipboardMonitor::new(interval) {
            Ok(m) => m,
            Err(e) => {
                error!("剪切板初始化失败：{}", e);
                return;
            }
        };
        let mut prev_content = String::new();
        loop {
            match monitor.check_for_changes() {
                Ok(Some(content)) => {
                    debug!("检测到剪切板变化：{} 字符", content.len());
                    let results = engine_bg.parse_all_with_prev(&content, &prev_content);
                    prev_content = content.clone();
                    if !results.is_empty() {
                        info!("解析成功：{} 个结果", results.len());
                        for r in &results {
                            info!("  [{}] {}", r.parser_name, &r.parsed);
                        }
                        if let Err(e) = mcga::history::append(&content, &results) {
                            debug!("历史记录写入失败：{}", e);
                        }
                        tx.send(results).ok();
                    }
                }
                Ok(None) => {}
                Err(e) => warn!("读取剪切板失败：{}", e),
            }
            thread::sleep(interval);
        }
    });

    // 主线程：NSApplication 事件循环
    unsafe {
        use objc2_foundation::MainThreadMarker;
        let mtm = MainThreadMarker::new_unchecked();
        let app = NSApplication::sharedApplication(mtm);
        app.setActivationPolicy(NSApplicationActivationPolicy::Accessory);
        app.finishLaunching();

        // 在 run loop 启动后开始轮询 channel
        let rx2 = Arc::clone(&rx);
        let config2 = Arc::new(config.clone());
        mcga::gcd::exec_async(move || {
            poll_and_reschedule(rx2, config2);
        });

        app.run();
    }

    Ok(())
}

/// 从 channel 取出解析结果并展示，然后重新调度自身（每 100ms）
#[cfg(target_os = "macos")]
fn poll_and_reschedule(rx: Arc<Mutex<mpsc::Receiver<Vec<ParseResult>>>>, config: Arc<Config>) {
    if let Ok(guard) = rx.lock() {
        while let Ok(results) = guard.try_recv() {
            mcga::overlay::show_results(&results, &config);
        }
    }

    let rx2 = Arc::clone(&rx);
    let config2 = Arc::clone(&config);
    mcga::gcd::exec_after(Duration::from_millis(100), move || {
        poll_and_reschedule(rx2, config2);
    });
}

/// 解析指定内容
fn run_parse(content: &str, all: bool) -> Result<()> {
    let engine = ParserEngine::new();

    if all {
        let results = engine.parse_all(content);
        if results.is_empty() {
            println!("无法解析该内容");
        } else {
            for result in results {
                print_result(&result);
                println!("---");
            }
        }
    } else {
        match engine.parse(content) {
            Some(result) => print_result(&result),
            None => println!("无法解析该内容"),
        }
    }

    Ok(())
}

/// 解析当前剪切板内容
fn run_clip(all: bool) -> Result<()> {
    let mut monitor = ClipboardMonitor::new(Duration::from_millis(100))?;

    match monitor.get_current()? {
        Some(content) => {
            println!(
                "剪切板内容：{}\n",
                if content.len() > 50 {
                    format!("{}...", &content[..50])
                } else {
                    content.clone()
                }
            );
            run_parse(&content, all)
        }
        None => {
            println!("剪切板为空");
            Ok(())
        }
    }
}

/// 列出所有解析器
fn list_parsers() -> Result<()> {
    let engine = ParserEngine::new();

    println!("支持的解析器：");
    println!("==============");
    for name in engine.parser_names() {
        println!("  • {}", name);
    }

    Ok(())
}

/// 以独立 NSApplication 在浮层中展示历史记录（macOS）
#[cfg(target_os = "macos")]
fn run_history_overlay(count: usize) -> Result<()> {
    use objc2_app_kit::{NSApplication, NSApplicationActivationPolicy};
    use objc2_foundation::MainThreadMarker;

    let entries = mcga::history::load_all().unwrap_or_default();
    if entries.is_empty() {
        println!("暂无历史记录");
        return Ok(());
    }

    let text = mcga::history::format_for_overlay(&entries, count);
    let config = mcga::config_file::load();

    mcga::overlay::set_quit_on_empty(true);

    unsafe {
        let mtm = MainThreadMarker::new_unchecked();
        let app = NSApplication::sharedApplication(mtm);
        app.setActivationPolicy(NSApplicationActivationPolicy::Accessory);
        app.finishLaunching();

        mcga::gcd::exec_async(move || {
            let result = mcga::parser::ParseResult::new("历史记录", &text, "").with_details(text);
            mcga::overlay::show_results(&[result], &config);
        });

        app.run();
    }
    Ok(())
}

fn print_result(result: &mcga::parser::ParseResult) {
    println!("解析器：{}", result.parser_name);
    println!("结果：{}", result.parsed);
    if let Some(ref details) = result.details {
        println!("\n详情：");
        for line in details.lines() {
            println!("   {}", line);
        }
    }
}
