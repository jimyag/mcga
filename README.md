# MCGA - My Clipboard Guard Assistant

剪切板监控与解析工具，自动识别剪切板内容并展示解析结果。

当前仓库包含两套实现：

- Swift macOS App：macOS 15+ 状态栏应用，监听剪切板变化后自动弹出浮层，支持一键复制结果。
- Rust CLI/daemon：原有命令行和守护进程实现。

## 功能

支持以下内容解析：

| 解析器    | 说明                                    |
| --------- | --------------------------------------- |
| CIDR      | 网段解析（可用 IP 范围、网络/广播地址） |
| UUID      | v1/v4/v6/v7 版本，提取时间戳            |
| ObjectID  | MongoDB ObjectID，提取创建时间          |
| IPv4/IPv6 | 公网 IP 地理位置查询                    |
| Timestamp | Unix 时间戳（秒/毫秒/微秒/纳秒）        |
| JSON      | 结构分析                                |

## 编译

### Swift macOS App

依赖：

- macOS 15+
- Swift 6 / Xcode Command Line Tools

验证核心解析器：

```bash
source ~/.zshrc && swift run MCGASmokeTests
```

编译状态栏 App：

```bash
source ~/.zshrc && swift build --product MCGA
```

打包为 `.app`：

```bash
source ~/.zshrc && bash scripts/build-macos-app.sh
```

输出：

```text
.build/MCGA.app
```

打开 App：

```bash
source ~/.zshrc && open .build/MCGA.app
```

如果已经运行旧版本，先退出或执行：

```bash
source ~/.zshrc && pkill MCGA
source ~/.zshrc && open .build/MCGA.app
```

打开后不会出现在 Dock 中，请在 macOS 菜单栏点击 `MCGA` 图标查看当前结果和历史。复制可解析内容后，App 会自动弹出浮层。

### Rust CLI/daemon

### 依赖

- Rust 1.70+
- Windows 交叉编译需要 `mingw-w64`

### Linux 原生编译

```bash
cargo build --release
```

输出：`target/release/mcga`

### Windows 交叉编译（WSL/Linux）

```bash
# 安装 Windows target
rustup target add x86_64-pc-windows-gnu

# 安装 mingw-w64（Ubuntu/Debian）
sudo apt install mingw-w64

# 编译
cargo build --target x86_64-pc-windows-gnu --release
```

输出：`target/x86_64-pc-windows-gnu/release/mcga.exe`

## 使用

### macOS 状态栏 App


浮层和状态栏面板都支持复制解析结果。状态栏面板还提供暂停监听、刷新历史、清空历史和退出。

### Rust CLI/daemon

> macOS 下通知通过系统自带的 `osascript` 发送，需确保“终端”或你使用的终端应用已在系统通知设置中允许通知。

### 守护进程模式

```bash
# 启动监控（默认 500ms 轮询）
mcga daemon

# 自定义轮询间隔
mcga daemon --interval 1000
```

### 手动解析

```bash
# 解析指定内容
mcga parse "192.168.1.0/24"

# 解析剪切板内容
mcga clip

# 显示所有匹配结果
mcga parse --all "507f1f77bcf86cd799439011"
```

### 查看解析器列表

```bash
mcga parsers
```

## 配置



```csv
node,ip
node1,10.0.0.1
node2,10.0.0.2
```


## License

MIT
