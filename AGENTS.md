# AGENTS.md

This file provides guidance to Codex (Codex.ai/code) when working with code in this repository.

## 项目简介

mcga（My Clipboard Guard Assistant）是剪切板智能解析工具，监控剪切板变化并展示解析结果。

当前仓库有两套实现：

- Swift macOS App：macOS 15+ 状态栏应用，入口在 `Sources/MCGA`，核心解析器在 `Sources/MCGACore`。
- Rust CLI/daemon：原有实现，入口在 `src/main.rs`，解析器在 `src/parser`。

## 常用命令

```bash
# Swift macOS App
swift run MCGASmokeTests          # 验证 Swift 核心解析器
swift build --product MCGA        # 构建 macOS 状态栏 App 可执行文件
bash scripts/build-macos-app.sh   # 打包 .build/MCGA.app
open .build/MCGA.app              # 打开状态栏 App
pkill MCGA                        # 关闭正在运行的 Swift App

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

Swift macOS App：

```
Package.swift                   SwiftPM 工程，最低 macOS 15
Sources/MCGA/MCGAApp.swift      状态栏 App、剪切板轮询、Popover、自动浮层
Sources/MCGACore/ParserEngine.swift
Sources/MCGACore/*Parsers.swift 解析器实现
Sources/MCGACore/HistoryStore.swift
Sources/MCGASmokeTests/main.swift 无 XCTest 依赖的 smoke test
Packaging/Info.plist            .app bundle 元数据，LSUIElement=true
scripts/build-macos-app.sh      打包 .build/MCGA.app
```

Rust CLI/daemon：

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

Rust `src/parser/engine.rs` 和 Swift `Sources/MCGACore/ParserEngine.swift` 中解析器顺序决定 `parse()` 的优先级，越具体的解析器越靠前。两边新增解析器时要同步评估顺序和 smoke test 覆盖。


### 添加新解析器

1. 在 `src/parser/` 下新建 `foo.rs`，实现 `Parser` trait（`name()` 和 `parse()`）
2. 在 `src/parser/mod.rs` 中 `mod foo;` 并 `pub use foo::FooParser;`
3. 在 `src/parser/engine.rs` 的 `ParserEngine::new()` 中按优先级插入 `Box::new(FooParser::new())`



## 运行时行为

Swift App 打开后常驻菜单栏，不出现在 Dock。复制可解析内容时会自动弹出右下角浮层，同时状态栏 Popover 可查看当前结果和历史。设置通过齿轮按钮打开独立 sheet，并用 `UserDefaults` 持久化，支持中文/英文、浅色/深色主题、按解析器启用/关闭；每个解析器都要维护说明和示例。浮层内复制解析结果时要避免再次触发自解析，并显示非阻塞复制反馈。

Rust 守护进程模式下，每次剪切板变化会对所有匹配的解析器各发送一个独立的桌面通知（`notifier.send_all` 方法存在但当前未使用）。
