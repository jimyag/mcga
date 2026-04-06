# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## 项目简介

mcga（My Clipboard Guard Assistant）是一个 Rust 编写的剪切板智能解析工具，监控剪切板变化并通过桌面通知展示解析结果。

## 常用命令

```bash
# 构建
cargo build
cargo build --release

# 运行（默认启动守护进程）
cargo run

# 运行子命令
cargo run -- daemon --interval 500    # 启动守护进程，500ms 轮询
cargo run -- parse "内容"             # 解析指定内容
cargo run -- parse --all "内容"       # 显示所有匹配结果
cargo run -- clip                     # 解析当前剪切板
cargo run -- parsers                  # 列出所有解析器

# 测试
cargo test
cargo test <test_name>               # 运行单个测试

# 检查代码
cargo clippy
cargo fmt
```

## 架构概览

程序由四个核心模块组成：

```
main.rs          CLI 入口，处理子命令分发
config.rs        配置结构（轮询间隔、通知超时、应用名等），无文件持久化，全部硬编码默认值
monitor.rs       ClipboardMonitor，基于 arboard 轮询剪切板，记录上次内容以检测变化
notifier.rs      Notifier，基于 notify-rust 发送桌面通知
parser/          解析器子系统
  mod.rs         Parser trait 和 ParseResult 结构定义
  engine.rs      ParserEngine，管理所有解析器，提供 parse()（返回第一个）和 parse_all()（返回全部）
  *.rs           各具体解析器实现
```

### 解析器注册顺序

`ParserEngine::new()` 中解析器顺序决定 `parse()` 的优先级，越具体的解析器越靠前：

2. Cidr — CIDR 网段（含 /xx 后缀）
3. Uuid — UUID 格式
4. ObjectId — MongoDB ObjectId（24 位 hex）
5. Ip — 公网 IPv4
6. Timestamp — 纯数字时间戳（10/13/16/17/19 位）
7. Json — JSON 对象或数组

### 添加新解析器

1. 在 `src/parser/` 下新建 `foo.rs`，实现 `Parser` trait（`name()` 和 `parse()`）
2. 在 `src/parser/mod.rs` 中 `mod foo;` 并 `pub use foo::FooParser;`
3. 在 `src/parser/engine.rs` 的 `ParserEngine::new()` 中按优先级插入 `Box::new(FooParser::new())`



## 运行时行为

守护进程模式下，每次剪切板变化会对所有匹配的解析器各发送一个独立的桌面通知（`notifier.send_all` 方法存在但当前未使用）。
