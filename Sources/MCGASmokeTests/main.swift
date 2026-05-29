import Foundation
import MCGACore

func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else {
        fputs("FAILED: \(message)\n", stderr)
        exit(1)
    }
}

let engine = ParserEngine()
let names = engine.parserNames
for name in [
] {
    expect(names.contains(name), "missing parser \(name)")
}

expect(engine.parse("192.168.1.20/24")?.parserName == "CIDR", "CIDR")
expect(engine.parse("550e8400-e29b-41d4-a716-446655440000")?.parserName == "UUID", "UUID")
expect(engine.parse("507f1f77bcf86cd799439011")?.parserName == "ObjectID", "ObjectID")
expect(engine.parse("d41d8cd98f00b204e9800998ecf8427e")?.parserName == "Hash", "Hash")
expect(engine.parse("2001:db8::1")?.parserName == "IPv6", "IPv6")
expect(engine.parse("8.8.8.8")?.parserName == "IPv4", "IP")
expect(engine.parse("1700000000")?.parserName == "Timestamp", "Timestamp")
expect(engine.parse("*/5 * * * *")?.parserName == "Cron", "Cron")
expect(engine.parse(#"{"hello":"world"}"#)?.parserName == "JSON", "JSON")
expect(engine.parse(#"{hello: "world",}"#)?.parserName == "JSON5", "JSON5")
expect(engine.parse("hello: world\ncount: 1")?.parserName == "YAML", "YAML")
expect(engine.parse("aGVsbG8gd29ybGQ=")?.parserName == "Base64", "Base64")
expect(engine.parse("example.com")?.parserName == "DNS", "DNS")

let encoded = engine.parse("b64", previousContent: "hello world")
expect(encoded?.parserName == "Base64 Encode", "b64 parser")
expect(encoded?.parsed == "aGVsbG8gd29ybGQ=", "b64 output")

let decoded = engine.parse("db64", previousContent: "aGVsbG8gd29ybGQ=")
expect(decoded?.parserName == "Base64 Decode", "db64 parser")
expect(decoded?.parsed == "hello world", "db64 output")

print("MCGASmokeTests passed")
