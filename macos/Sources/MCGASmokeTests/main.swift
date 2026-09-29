import CoreGraphics
import Foundation
import ImageIO
import MCGACore
import UniformTypeIdentifiers

func expect(_ condition: Bool, _ message: String) {
    guard condition else {
        fputs("FAILED: \(message)\n", stderr)
        exit(1)
    }
}

// Offline stand-ins for DoH and ip-api: every provider answers A queries only.
let fetch: HTTPFetch = { request in
    let url = request.url?.absoluteString ?? ""
    if url.contains("ip-api.com") {
        return Data(#"{"status":"success","country":"United States","city":"Mountain View","isp":"Google LLC"}"#.utf8)
    }
    if url.contains("type=1&") || url.hasSuffix("type=1") {
        return Data(#"{"Status":0,"Answer":[{"type":1,"TTL":60,"data":"93.184.216.34"}]}"#.utf8)
    }
    return Data(#"{"Status":0}"#.utf8)
}

let scratch = FileManager.default.temporaryDirectory.appendingPathComponent("mcga-smoke-\(UUID().uuidString)")
try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)

// The user's own custom parsers stay out of the built-in checks.
let engine = ParserEngine(customParserConfig: nil, fetch: fetch)
let names = engine.parserNames
for name in [
    "CIDR", "UUID", "ObjectID", "Hash", "IPv6", "IP", "Timestamp",
    "HTTP Status", "Number Base", "Cron", "URL", "JSON", "JSON5", "XML", "TOML",
    "YAML", "HTML Entity", "Unicode Escape", "Base64", "DNS",
] {
    expect(names.contains(name), "missing parser \(name)")
}

/// Builds Unicode escape sequences for the Unicode Escape parser; literal ones get lost in editing tools.
let backslash = #"\"#

func firstParser(_ input: String, previousContent: String = "", using engine: ParserEngine = engine) async -> String? {
    await engine.parseAll(input, previousContent: previousContent).first?.parserName
}

for (input, parserName) in [
    ("192.168.1.20/24", "CIDR"),
    ("550e8400-e29b-41d4-a716-446655440000", "UUID"),
    ("507f1f77bcf86cd799439011", "ObjectID"),
    ("d41d8cd98f00b204e9800998ecf8427e", "Hash"),
    ("2001:db8::1", "IPv6"),
    ("8.8.8.8", "IP"),
    ("1700000000", "Timestamp"),
    ("404", "HTTP Status"),
    ("0xff", "Number Base"),
    ("*/5 * * * *", "Cron"),
    ("https://example.com/a/b?x=1&name=mcga", "URL"),
    (#"{"hello":"world"}"#, "JSON"),
    (#"{hello: "world",}"#, "JSON5"),
    ("<root><item>1</item></root>", "XML"),
    ("name = \"mcga\"\ncount = 1", "TOML"),
    ("hello: world\ncount: 1", "YAML"),
    ("hello &amp; world", "HTML Entity"),
    ("\(backslash)u4F60\(backslash)u597D", "Unicode Escape"),
    ("aGVsbG8gd29ybGQ=", "Base64"),
    ("example.com", "DNS"),
] {
    let actual = await firstParser(input)
    expect(actual == parserName, "\(parserName) for \(input), got \(actual ?? "nil")")
}
expect(await engine.parseAll("404", enabledParserNames: []).isEmpty, "disabled all parsers")
expect(await engine.parseAll("404", enabledParserNames: ["HTTP Status"]).map(\.parserName) == ["HTTP Status"], "enabled parser filter")

let encoded = await engine.parseAll("b64", previousContent: "hello world").first
expect(encoded?.parserName == "Base64 Encode" && encoded?.parsed == "aGVsbG8gd29ybGQ=", "b64 output")
let decoded = await engine.parseAll("db64", previousContent: "aGVsbG8gd29ybGQ=").first
expect(decoded?.parserName == "Base64 Decode" && decoded?.parsed == "hello world", "db64 output")

let unicodeEscape = await engine.parseAll("hello \(backslash)u4F60\(backslash)u597D \(backslash)u{1F600} \(backslash)uD83D\(backslash)uDE00")
    .first { $0.parserName == "Unicode Escape" }
expect(unicodeEscape?.parsed == "hello 你好 😀 😀", "unicode escape output")

// Network parsers: all DoH queries answered by the stub, in provider order.
let dns = await engine.parseAll("example.com").filter { $0.parserName == "DNS" }.map(\.parsed)
expect(dns == ["Cloudflare DoH", "Google DoH", "AliDNS DoH"].map { "DNS/A via \($0)\n93.184.216.34" }, "DNS results in provider order, got \(dns)")
let ip = await engine.parseAll("8.8.8.8").first
expect(ip?.parsed == "国家：United States\n城市：Mountain View\nISP：Google LLC", "IP geolocation, got \(ip?.parsed ?? "nil")")

// JSON keeps slashes; JSON5 covers comments, URLs and apostrophes, and skips strict JSON.
let json = await engine.parseAll(#"{"url":"https://example.com/a"}"#)
expect(json.first?.details?.contains(#""https://example.com/a""#) == true, "JSON keeps slashes unescaped")
expect(!json.contains { $0.parserName == "JSON5" }, "strict JSON has no JSON5 result")
let jsonc = """
{
  // tsconfig
  "$schema": "https://json.schemastore.org/tsconfig",
  "compilerOptions": { "strict": true, },
}
"""
expect(await firstParser(jsonc) == "JSON5", "JSONC with a comment and a URL")
expect(await firstParser("{msg: 'it\"s', note: \"it's\",}") == "JSON5", "JSON5 with quotes inside strings")

// Single lines of prose or code are not YAML or TOML documents.
for line in ["Error: file not found", "2024-01-01 12:00:00 ERROR: connection refused", "TODO: fix later"] {
    expect(!(await engine.parseAll(line)).contains { $0.parserName == "YAML" }, "no YAML for \(line)")
}
expect(!(await engine.parseAll("x = compute(1)")).contains { $0.parserName == "TOML" }, "no TOML for one assignment")
expect(await firstParser("title = \"mcga\"\n[server]") == "TOML", "TOML key with a table")

// Dashes without both ends used to crash the cron parser.
expect(!(await engine.parseAll("138 - 1234 - 5678")).contains { $0.parserName == "Cron" }, "a phone number is not cron")
for text in ["5- 1 2 3 4", "-/5 1 2 3 4"] {
    _ = await engine.parseAll(text)
}
expect(await engine.parseAll("1-5 * * * *").first?.parsed == "每月，每天，每小时", "cron range")

let categories = engine.parserCategories
expect(categories["IP"] == .network && categories["IPv4"] == .network, "IP results use the network category")
expect(categories["HTTP Status"] == .identifier, "HTTP Status category")
expect(categories["JSON"] == .dataFormat, "JSON category")
expect(categories["UUID Generator"] == .generator, "generator category")

func fields(_ text: String?) -> (headline: String?, labels: [String], values: [String])? {
    guard case .fields(let headline, let fields) = ResultTextLayout(text ?? "") else { return nil }
    return (headline, fields.map(\.label), fields.map(\.value))
}
let status = fields(await engine.parseAll("404").first { $0.parserName == "HTTP Status" }?.parsed)
expect(status?.headline == "404 Not Found" && status?.labels == ["类型"] && status?.values == ["客户端错误"], "HTTP Status fields")
let base = fields(await engine.parseAll("404").first { $0.parserName == "Number Base" }?.parsed)
expect(base?.headline == nil && base?.labels == ["输入进制", "DEC", "HEX", "OCT", "BIN"], "Number Base fields")
expect(ResultTextLayout("{\n  \"hello\": \"world\"\n}") == .plain("{\n  \"hello\": \"world\"\n}"), "formatted JSON stays verbatim")
expect(ResultTextLayout("DNS/A via Cloudflare DoH\n104.20.23.154") == .plain("DNS/A via Cloudflare DoH\n104.20.23.154"), "lines without labels stay verbatim")
expect(ResultTextLayout("八位组：8.8.8.8\n\n地理位置信息：\n国家：美国") == .plain("八位组：8.8.8.8\n\n地理位置信息：\n国家：美国"), "section headers stay verbatim")

// English results for the English interface.
let english = ParserEngine(language: .en, customParserConfig: nil, fetch: fetch)
let englishStatus = fields(await english.parseAll("404").first { $0.parserName == "HTTP Status" }?.parsed)
expect(englishStatus?.labels == ["Class"] && englishStatus?.values == ["Client error"], "English HTTP Status fields")
let englishCIDR = fields(await english.parseAll("192.168.1.20/24").first?.parsed)
expect(englishCIDR?.labels == ["Input", "Network", "Broadcast", "Usable range"], "English CIDR fields, got \(englishCIDR?.labels ?? [])")
expect(await english.parseAll("*/5 * * * *").first?.details?.hasPrefix("Minute: every 5 minutes") == true, "English cron")
for input in ["550e8400-e29b-41d4-a716-446655440000", "1700000000", "d41d8cd98f00b204e9800998ecf8427e", "{\"a\":1}", "*/5 * * * *", "8.8.8.8"] {
    let text = await english.parseAll(input).map { "\($0.parsed)\n\($0.details ?? "")" }.joined()
    expect(text.range(of: #"\p{Han}"#, options: .regularExpression) == nil, "English output for \(input) has no Chinese: \(text)")
}

// Custom command parsers.
func executable(_ name: String, _ script: String) throws -> String {
    let url = scratch.appendingPathComponent(name)
    try Data(script.utf8).write(to: url)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
    return url.path
}
let firstLine = try executable("first-line.sh", "#!/bin/sh\nread -r line\necho \"first:$line\"\n")
let stamp = try executable("stamp.sh", "#!/bin/sh\necho custom\n")
let sleeper = try executable("sleep.sh", "#!/bin/sh\nsleep 5\necho late\n")
let config = scratch.appendingPathComponent("custom_parsers.json")
try Data("""
{"parsers": [
  {"name": "FirstLine", "match": "^first", "command": "\(firstLine)", "timeoutMs": 5000},
  {"name": "Stamp", "match": "^\\\\d{10}$", "command": "\(stamp)", "timeoutMs": 5000},
  {"name": "Sleeper", "match": "^sleep$", "command": "\(sleeper)", "timeoutMs": 200},
  {"name": "BadRegex", "match": "(", "command": "\(stamp)"},
  {"name": "Script", "kind": "script", "command": "\(stamp)"},
  {"name": "Missing", "command": "/nonexistent/mcga-parser"},
  {"name": "Off", "command": "\(stamp)", "enabled": false}
]}
""".utf8).write(to: config)
let custom = ParserEngine(customParserConfig: config, fetch: fetch)
let customNames = Set(custom.parserNames)
expect(customNames.isSuperset(of: ["FirstLine", "Stamp", "Sleeper", "Missing"]), "custom parsers load")
expect(customNames.isDisjoint(with: ["BadRegex", "Script", "Off"]), "broken and disabled custom parsers are skipped")
expect(custom.customParserIssues.count == 3, "one issue each for the regex, the kind and the command, got \(custom.customParserIssues)")

// A command that reads one line of a large input used to kill MCGA with SIGPIPE.
let large = "first\n" + String(repeating: "x", count: 200 * 1024)
let clock = ContinuousClock()
var started = clock.now
let firstLineResult = await custom.parseAll(large).first?.parsed
expect(firstLineResult == "first:first", "command that stops reading stdin, got \(firstLineResult ?? "nil") after \(clock.now - started)")
started = clock.now
expect(await custom.parseAll("sleep").isEmpty, "timed out command has no result")
expect(clock.now - started < .seconds(2), "timeout stops a slow command")

// Local results come first, slow ones join in parser order.
var updates: [[String]] = []
started = clock.now
for await results in custom.results(for: "1700000000") {
    updates.append(results.map(\.parserName))
}
expect(updates.first == ["Timestamp"] && updates.last == ["Stamp", "Timestamp"], "streamed results, got \(updates) after \(clock.now - started)")

let brokenConfig = scratch.appendingPathComponent("broken.json")
try Data("{\"parsers\": [".utf8).write(to: brokenConfig)
let broken = ParserEngine(customParserConfig: brokenConfig, fetch: fetch)
expect(broken.customParserIssues.count == 1 && !broken.parserNames.contains("Stamp"), "unreadable config is reported")

// History.
let historyDirectory = scratch.appendingPathComponent("history")
let historyPath = historyDirectory.appendingPathComponent("history.json")
let assetsDirectory = historyDirectory.appendingPathComponent("assets")
let historyStore = HistoryStore(path: historyPath, assetsDirectory: assetsDirectory)
let plainID = await historyStore.append(original: "plain clipboard text", results: [])
var historyEntries = await historyStore.allRecent()
expect(historyEntries.count == 1 && historyEntries.first?.originalContent == "plain clipboard text", "plain text history entry")
expect(historyEntries.first?.results.isEmpty == true, "plain text without parsed results")

await historyStore.append(original: "second clipboard text", results: [])
await historyStore.promote(id: plainID)
expect(await historyStore.allRecent().first?.id == plainID, "promoted history entry first")
await historyStore.append(original: "third clipboard text", results: [])
historyEntries = await historyStore.allRecent()
expect(historyEntries.first?.originalContent == "third clipboard text", "new entry after promoted history")
expect(Set(historyEntries.map(\.id)).count == historyEntries.count, "history ids stay unique after promotion")

// Copying the same text again moves its entry up rather than adding one.
let againID = await historyStore.append(original: "plain clipboard text", results: [ParseResult(parserName: "Local", original: "", parsed: "local")])
historyEntries = await historyStore.allRecent()
expect(againID == plainID && historyEntries.count == 3 && historyEntries.first?.id == plainID, "repeated text reuses its entry")
await historyStore.setResults(id: plainID, results: [ParseResult(parserName: "Slow", original: "", parsed: "slow")])
expect(await historyStore.allRecent().first?.results.map(\.parserName) == ["Slow"], "late results update the entry")

let secondID = await historyStore.allRecent().first { $0.originalContent == "second clipboard text" }!.id
await historyStore.setPinned(id: secondID, true)
expect(await historyStore.allRecent().first?.id == secondID, "pinned entry comes first")
let thirdID = await historyStore.allRecent().first { $0.originalContent == "third clipboard text" }!.id
await historyStore.delete(id: thirdID)
expect(await historyStore.allRecent().map(\.id) == [secondID, plainID], "deleted entry is gone")
await historyStore.clear()
expect(await historyStore.allRecent().map(\.id) == [secondID], "clearing keeps pinned entries")

// Pinned entries outlive the retention period.
let old = Date(timeIntervalSinceNow: -10 * 24 * 3600)
let encoder = JSONEncoder()
encoder.dateEncodingStrategy = .iso8601
try encoder.encode([
    HistoryEntry(id: 1, timestamp: old, originalContent: "old pinned", originalPreview: "old pinned", results: [], pinned: true),
    HistoryEntry(id: 2, timestamp: old, originalContent: "old", originalPreview: "old", results: []),
]).write(to: historyPath)
expect(await historyStore.allRecent(retentionDays: 1).map(\.id) == [1], "retention keeps pinned entries")

// Images keep the copied data, or a lossless PNG of it, next to a small preview.
func imageData(width: Int, height: Int, type: UTType) -> Data {
    let context = CGContext(
        data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    context.setFillColor(CGColor(red: 0.2, green: 0.4, blue: 0.6, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: width, height: height / 2))
    let data = NSMutableData()
    let destination = CGImageDestinationCreateWithData(data as CFMutableData, type.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, context.makeImage()!, nil)
    CGImageDestinationFinalize(destination)
    return data as Data
}
func pixelSize(_ path: String?) -> [Int] {
    guard let path, let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil),
          let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
    else { return [] }
    return [kCGImagePropertyPixelWidth, kCGImagePropertyPixelHeight].compactMap { properties[$0] as? Int }
}
let png = imageData(width: 2000, height: 1000, type: .png)
let savedPNG = HistoryImage.save(png, in: assetsDirectory)
expect(savedPNG.flatMap { FileManager.default.contents(atPath: $0.originalPath ?? "") } == png, "PNG kept as copied")
expect(savedPNG?.pixelWidth == 2000 && savedPNG?.pixelHeight == 1000, "pixel size of the copied image")
expect(pixelSize(savedPNG?.previewPath) == [900, 450], "preview fits 900 pixels, got \(pixelSize(savedPNG?.previewPath))")
let savedAgain = HistoryImage.save(png, in: assetsDirectory)
expect(savedAgain.flatMap { FileManager.default.contents(atPath: $0.previewPath) } == savedPNG.flatMap { FileManager.default.contents(atPath: $0.previewPath) }, "same image, same preview bytes")
let savedTIFF = HistoryImage.save(imageData(width: 1200, height: 600, type: .tiff), in: assetsDirectory)
expect(savedTIFF?.originalPath?.hasSuffix(".png") == true && pixelSize(savedTIFF?.originalPath) == [1200, 600], "TIFF kept as full-size PNG")

await historyStore.append(kind: .image, originalPreview: "Image", attachment: HistoryAttachment(previewKind: .image, assetPath: savedPNG?.previewPath, originalAssetPath: savedPNG?.originalPath))
await historyStore.append(kind: .image, originalPreview: "Image", attachment: HistoryAttachment(previewKind: .image, assetPath: savedAgain?.previewPath, originalAssetPath: savedAgain?.originalPath))
let images = await historyStore.allRecent().filter { $0.contentKind == .image }
expect(images.count == 1, "a rewritten unchanged clipboard image is recorded once")
expect(FileManager.default.fileExists(atPath: savedPNG?.originalPath ?? ""), "the recorded image stays")
expect(!FileManager.default.fileExists(atPath: savedAgain?.originalPath ?? ""), "the duplicate's files are removed")
await historyStore.append(original: "copied in between", results: [])
await historyStore.append(kind: .image, originalPreview: "Image", attachment: HistoryAttachment(previewKind: .image, assetPath: HistoryImage.save(png, in: assetsDirectory)?.previewPath))
expect(await historyStore.allRecent().filter { $0.contentKind == .image }.count == 2, "the same image copied again after other content is recorded")
await historyStore.delete(id: images[0].id)
expect(!FileManager.default.fileExists(atPath: savedPNG?.originalPath ?? "") && !FileManager.default.fileExists(atPath: savedPNG?.previewPath ?? ""), "deleting an image removes its files")
expect(FileManager.default.fileExists(atPath: savedTIFF?.originalPath ?? ""), "files of an image still being added are left alone")
await historyStore.clear()
expect((try? FileManager.default.contentsOfDirectory(atPath: assetsDirectory.path))?.isEmpty == true, "clearing sweeps unreferenced files")

try? FileManager.default.removeItem(at: scratch)
print("MCGASmokeTests passed")
