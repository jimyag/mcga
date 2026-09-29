# AGENTS.md

This file provides guidance to Codex when working with this repository.

## 项目简介

mcga（My Clipboard Guard Assistant）是剪切板智能解析工具。macOS 版在 `macos/`，本文件主要描述它；Windows 版在 `windows/`。App 常驻菜单栏，监控剪切板变化，统一执行解析器并展示当前结果和历史结果。

## 常用命令

所有 shell 命令先加载用户 zsh 环境，并在 `macos/` 目录下执行：

```bash
source ~/.zshrc && <command>
```

```bash
source ~/.zshrc && swift run MCGASmokeTests
source ~/.zshrc && swift build --product MCGA
source ~/.zshrc && bash scripts/build-macos-app.sh
source ~/.zshrc && open .build/MCGA.app
source ~/.zshrc && pkill MCGA
```

## 重新安装

修改后重新安装 MCGA 时，必须完整执行构建、替换 App 和重启流程，不要只打开 `.build/MCGA.app`：

```bash
source ~/.zshrc
cd macos
bash scripts/build-macos-app.sh
pkill MCGA || true
if [[ -d /Applications/MCGA.app ]]; then
  mv /Applications/MCGA.app "/Users/jimyag/.Trash/MCGA-previous-$(date +%Y%m%d-%H%M%S).app"
fi
ditto .build/MCGA.app /Applications/MCGA.app
codesign --verify --strict --verbose=2 /Applications/MCGA.app
open /Applications/MCGA.app
```

`build-macos-app.sh` 使用钥匙串中的 `MCGA Self Signed` 证书签名，签名身份不变时辅助功能授权会保留，不要再重置。只有构建输出 ad-hoc 签名警告，或签名身份刚发生变化（例如首次从 ad-hoc 切换到该证书）时，才执行一次：

```bash
tccutil reset Accessibility com.jimyag.mcga
open "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
```

然后在“系统设置 > 隐私与安全性 > 辅助功能”中重新启用 `MCGA.app`。

## 架构概览

```
macos/Package.swift
macos/Sources/MCGA/MCGAApp.swift                  App 入口
macos/Sources/MCGA/AppDelegate.swift              状态栏图标、历史/设置/看图窗口、全局快捷键、粘贴回原 App、Sparkle
macos/Sources/MCGA/ClipboardModel.swift           剪切板轮询、解析结果流、历史读写
macos/Sources/MCGA/AppPreferences.swift           偏好设置、快捷键录制、界面文案
macos/Sources/MCGA/Views/                         历史窗口、自动浮层、设置窗口、看图窗口
macos/Sources/MCGACore/ParserEngine.swift         解析器注册顺序和结果流
macos/Sources/MCGACore/*Parsers.swift             内置解析器
macos/Sources/MCGACore/CustomCommandParser.swift  自定义 command 解析器
macos/Sources/MCGACore/HistoryStore.swift         历史记录和图片文件
macos/Sources/MCGASmokeTests/main.swift           无 XCTest 依赖的 smoke test，不联网，不读本机自定义解析器配置
macos/Packaging/Info.plist                        .app bundle 元数据，LSUIElement=true
macos/scripts/build-macos-app.sh                  打包 .build/MCGA.app
```

## 解析器注册顺序

`macos/Sources/MCGACore/ParserEngine.swift` 中解析器顺序决定结果顺序，第一个结果是浮层主结果，越具体的解析器越靠前。自定义命令和网络解析器（IP、DNS）标记为慢解析器：其他解析器先出结果，慢解析器随后并发运行，结果按注册顺序陆续并入浮层和历史。

解析结果跟随界面语言，解析器里的文案用 `tr("中文", "English")` 或 `labeled(...)` 写两种语言。

当前 Swift 版覆盖：关键词生成器、自定义 command 解析器、CIDR、UUID、ObjectID、Hash、IPv6、公网 IPv4、Timestamp、HTTP Status、Number Base、Cron、URL、JSON、JSON5、XML、TOML、YAML、HTML Entity、Unicode Escape、Base64、DNS。

## 自定义 Command 解析器

自定义解析器配置文件：

```text
~/.config/mcga/custom_parsers.json
```

只支持 `kind: "command"`。App 会把剪切板内容写入命令 stdin，并读取 stdout：

- exit code 为 `0` 且 stdout 非空时才产生解析结果
- stdout 第一行作为结果正文
- stdout 多行时完整 stdout 作为详情
- stderr 忽略
- `command` 支持绝对路径、`~`、`$HOME`、`${HOME}`
- 命令必须是可执行文件
- `timeoutMs` 范围 50-10000 ms，默认 500 ms（Windows 版上限 3000 ms）
- 可选 `match` 正则用于运行命令前过滤剪切板内容
- stdin 和 stdout 走临时文件而不是管道，命令不读完 stdin 也不会让 App 收到 SIGPIPE
- 配置修改后在下次复制或打开设置时自动重新加载；JSON 无效、`match` 正则无效、命令不存在或不可执行会显示在设置的解析器页

## 运行时行为

Swift App 打开后常驻菜单栏，不出现在 Dock。复制可解析内容时会自动弹出浮层，点击状态栏图标打开历史窗口查看结果和历史。浮层可以在设置里关闭、调整停留时间，也可以按解析器设为只记历史不弹浮层。

历史记录按操作时间排序，置顶条目固定在最前：新复制内容、从历史复制、从历史粘贴都会把对应记录移动到第一位，再次复制同一段文本会移动已有记录而不是新增一条，单纯选中和键盘移动不改变顺序。历史窗口支持置顶、`⌘⌫` 删除当前条目、`⌘1`–`⌘9` 粘贴前九条；清空历史需要确认，置顶条目保留。复制的图片保存原图，从历史复制回剪切板不降质；图片解码和缩略图生成在后台线程。

浮层或历史里复制的内容不会再次触发解析，但会作为当前剪切板内容：之后再复制关键词（如 `uuid`）会重新生成，`b64`、`db64` 作用于这次复制的值。同时带文本和图片的剪切板内容（Office、iWork 复制单元格或文本）按文本处理；只有文本是单个链接且图片排在前面时（浏览器复制图片）按图片处理。
