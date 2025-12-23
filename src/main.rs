use std::thread;
use std::time::Duration;

use anyhow::Result;
use clap::{Parser, Subcommand};
use tracing::{debug, error, info, warn};
use tracing_subscriber::EnvFilter;

use mcga::config::Config;
use mcga::monitor::ClipboardMonitor;
use mcga::notifier::Notifier;
use mcga::parser::ParserEngine;

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
}

fn main() -> Result<()> {
    // 初始化日志
    tracing_subscriber::fmt()
        .with_env_filter(EnvFilter::from_default_env().add_directive("mcga=info".parse()?))
        .init();

    let cli = Cli::parse();

    match cli.command {
        Some(Commands::Daemon { interval }) => run_daemon(interval),
        Some(Commands::Parse { content, all }) => run_parse(&content, all),
        Some(Commands::Parsers) => list_parsers(),
        Some(Commands::Clip { all }) => run_clip(all),
        None => {
            // 默认行为：启动守护进程
            run_daemon(500)
        }
    }
}

/// 运行守护进程模式
fn run_daemon(interval_ms: u64) -> Result<()> {
    info!("MCGA 守护进程启动，轮询间隔：{}ms", interval_ms);

    let config = Config {
        poll_interval_ms: interval_ms,
        ..Default::default()
    };

    let mut monitor = ClipboardMonitor::new(config.poll_interval())?;
    let engine = ParserEngine::new();
    let notifier = Notifier::new(&config);

    info!("已加载 {} 个解析器：{:?}", engine.parser_names().len(), engine.parser_names());

    loop {
        match monitor.check_for_changes() {
            Ok(Some(content)) => {
                debug!("检测到剪切板变化：{} 字符", content.len());
                
                let results = engine.parse_all(&content);
                if results.is_empty() {
                    debug!("无法解析的内容");
                } else {
                    info!("解析成功：{} 个结果", results.len());
                    
                    // 每个解析结果单独发送一个通知
                    for result in &results {
                        info!("  [{}] {}", result.parser_name, &result.parsed);
                        if let Err(e) = notifier.send(result) {
                            error!("发送通知失败：{}", e);
                        }
                    }
                }
            }
            Ok(None) => {
                // 没有变化
            }
            Err(e) => {
                warn!("读取剪切板失败：{}", e);
            }
        }

        thread::sleep(Duration::from_millis(interval_ms));
    }
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
            println!("剪切板内容：{}\n", if content.len() > 50 {
                format!("{}...", &content[..50])
            } else {
                content.clone()
            });
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

