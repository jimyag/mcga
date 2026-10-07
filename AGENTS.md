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

当前 Swift 版覆盖：关键词生成器、自定义 command 解析器、JWT、PEM Certificate、SSH Public Key、MAC Address、Data Size、Data Rate、CIDR、UUID、ObjectID、Hash、IPv6、公网 IPv4、Timestamp、HTTP Status、Number Base、Cron、URL、JSON、JSON5、XML、TOML、YAML、HTML Entity、Unicode Escape、Base64、DNS。Data Size 换算数据大小，区分 bit/Byte、十进制/二进制前缀，支持 `Mi`、`Gi` 等容量写法，无单位的非负数字按字节换算并标注。Data Rate 换算 `Mbps`、`MB/s`、`MiB/s` 等带宽和传输速率，不把纯数字猜成速率。换算结果最多保留 12 位有效数字。JWT 仅解码、不验证签名，PEM 证书仅解析、不验证信任链，均在本地处理。

## 视频下载

`Video Download` 识别 X/Twitter、哔哩哔哩、抖音、TikTok、YouTube、Vimeo 链接、分享文本及视频直链。浮层或历史显示视频结果时，先用本机 `yt-dlp --skip-download --dump-single-json` 解析视频信息；确认有视频后才显示下载按钮，同时展示标题、封面、时长和内嵌预览入口。仅图片或解析失败不显示下载按钮。点击下载后使用 `bestvideo+bestaudio/best` 下载到 `~/Downloads`，并由 `ffmpeg` 合并音视频；缺少任一工具时明确提示下载不可用。不下载图片。一次只运行一个下载任务，关闭普通浮层或历史窗口不取消下载；下载和合并状态显示在右上角常驻下载浮层中，提供进度、速度、剩余时间、取消、重试和文件入口。下载不自动打开主窗口，主窗口不显示下载进度条。普通剪切板浮层排在下载浮层下方；完成后可按叉关闭下载浮层。登录失败时，用户可主动选择浏览器 Cookie 后重新解析或重试，不自动读取登录状态；成功解析所选浏览器只用于同一链接的后续下载。

`VideoDownloadModel.swift` 在后台读取 `--progress-template` 和 `--print after_move` 的结构化输出，不解析普通进度行；忽略 yt-dlp 配置，URL 使用独立进程参数传入。工具搜索路径包括 `~/.local/bin`、Homebrew 和 PATH。原生离线下载检查见 `scripts/check-video-download.swift`，真实工具检查可传入本地 HTTP 视频地址。

## 自定义 Command 解析器

自定义解析器配置文件：

```text
~/.config/mcga/custom_parsers.json
```

只支持 `kind: "command"`。App 会把剪切板内容写入命令 stdin，并读取 stdout：

- exit code 为 `0` 且 stdout 非空时才产生解析结果
- stdout 第一行作为结果正文
- stdout 多行时完整 stdout 作为详情；macOS 浮层显示完整 stdout，从浮层或历史复制、粘贴结果时取完整 stdout
- stderr 忽略
- `command` 支持绝对路径、`~`、`$HOME`、`${HOME}`
- 命令必须是可执行文件
- `timeoutMs` 范围 50-10000 ms，默认 500 ms（Windows 版上限 3000 ms）
- 可选 `match` 正则用于运行命令前过滤剪切板内容
- stdin 和 stdout 走临时文件而不是管道，命令不读完 stdin 也不会让 App 收到 SIGPIPE
- 配置修改后在下次复制或打开设置时自动重新加载；JSON 无效、`match` 正则无效、命令不存在或不可执行会显示在设置的解析器页

## 运行时行为

Swift App 打开后常驻菜单栏，不出现在 Dock。复制可解析内容时会自动弹出浮层，点击状态栏图标打开历史窗口查看结果和历史。浮层位于屏幕右上角通知区域附近，距离屏幕可用区域上侧和右侧各 8 点，最新一条在最上面，较早的浮层向下排列。浮层直接展示所有匹配结果，不折叠其他结果；高度最多占屏幕可用高度的一半，超出时滚动查看。顶部按钮在滚动时保持可见，关闭按钮立即关闭当前浮层，其晚到的解析结果仍记入历史但不重新弹出。浮层可以在设置里关闭、调整停留时间，也可以按解析器设为只记历史不弹浮层。在浮层里选中文字会立即复制选中部分。浮层的复制按钮和历史里的复制、粘贴都取整条结果：自定义命令取完整 stdout，格式化数据只取正文、不带摘要行。

历史记录按操作时间排序，置顶条目固定在最前：新复制内容、从历史复制、从历史粘贴都会把对应记录移动到第一位，再次复制同一段文本会移动已有记录而不是新增一条，单纯选中和键盘移动不改变顺序。历史窗口支持置顶、`⌘⌫` 删除当前条目、`⌘1`–`⌘9` 粘贴前九条；清空历史需要确认，置顶条目保留。复制的图片保存原图，从历史复制回剪切板不降质；图片解码和缩略图生成在后台线程。

从历史复制的内容不会再次触发解析；从浮层复制的新文本（选中或复制按钮）会重新解析、记入历史，并在匹配到结果时弹出新浮层，支持连续解析。复制与当前剪切板相同的文本或暂停监听时不触发解析。两者都会作为当前剪切板内容：之后再复制关键词（如 `uuid`）会重新生成，`b64`、`db64` 作用于这次复制的值。同时带文本和图片的剪切板内容（Office、iWork 复制单元格或文本）按文本处理；只有文本是单个链接且图片排在前面时（浏览器复制图片）按图片处理。
