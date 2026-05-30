import Foundation
import MCGACore

func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else {
        fputs("FAILED: \(message)\n", stderr)
        exit(1)
    }
}

func expectParser(_ input: String, _ parserName: String, _ message: String) {
    let actual = engine.parse(input)?.parserName
    guard actual == parserName else {
        fputs("FAILED: \(message), got \(actual ?? "nil")\n", stderr)
        exit(1)
    }
}

let engine = ParserEngine()
let names = engine.parserNames
for name in [
    "CIDR", "UUID", "ObjectID", "Hash", "IPv6", "IP", "Timestamp",
    "HTTP Status", "Number Base", "Cron", "URL", "JSON", "JSON5", "XML", "TOML",
    "YAML", "HTML Entity", "Base64", "DNS",
] {
    expect(names.contains(name), "missing parser \(name)")
}

expectParser("192.168.1.20/24", "CIDR", "CIDR")
expectParser("550e8400-e29b-41d4-a716-446655440000", "UUID", "UUID")
expectParser("507f1f77bcf86cd799439011", "ObjectID", "ObjectID")
expectParser("d41d8cd98f00b204e9800998ecf8427e", "Hash", "Hash")
expectParser("2001:db8::1", "IPv6", "IPv6")
expectParser("8.8.8.8", "IPv4", "IP")
expectParser("1700000000", "Timestamp", "Timestamp")
expectParser("404", "HTTP Status", "HTTP Status")
expectParser("0xff", "Number Base", "Number Base")
expectParser("*/5 * * * *", "Cron", "Cron")
expectParser("https://example.com/a/b?x=1&name=mcga", "URL", "URL")
expectParser(#"{"hello":"world"}"#, "JSON", "JSON")
expectParser(#"{hello: "world",}"#, "JSON5", "JSON5")
expectParser("<root><item>1</item></root>", "XML", "XML")
expectParser("name = \"mcga\"\ncount = 1", "TOML", "TOML")
expectParser("hello: world\ncount: 1", "YAML", "YAML")
expectParser("hello &amp; world", "HTML Entity", "HTML Entity")
expectParser("aGVsbG8gd29ybGQ=", "Base64", "Base64")
expectParser("example.com", "DNS", "DNS")
expect(engine.parse("404", enabledParserNames: []) == nil, "disabled all parsers")
expect(
    engine.parse("404", enabledParserNames: Set(["HTTP Status"]))?.parserName == "HTTP Status",
    "enabled parser filter"
)

let encoded = engine.parse("b64", previousContent: "hello world")
expect(encoded?.parserName == "Base64 Encode", "b64 parser")
expect(encoded?.parsed == "aGVsbG8gd29ybGQ=", "b64 output")

let decoded = engine.parse("db64", previousContent: "aGVsbG8gd29ybGQ=")
expect(decoded?.parserName == "Base64 Decode", "db64 parser")
expect(decoded?.parsed == "hello world", "db64 output")

print("MCGASmokeTests passed")
