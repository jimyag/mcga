# MCGA - My Clipboard Guard Assistant

剪切板监控与解析工具，自动识别剪切板内容并发送桌面通知。

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
| Base64    | 解码预览                                |

## 编译

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
