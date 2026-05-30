# MCGA Swift macOS App

This is the macOS-only Swift rewrite target for MCGA. It requires macOS 15+ and uses SwiftUI/AppKit for a menu bar app.

## Shape

- `Sources/MCGA`: menu bar app, clipboard polling, popover UI, copy actions, pause, history, quit.
- `Sources/MCGACore`: parser engine, parser implementations, history store.
- `Sources/MCGASmokeTests`: executable smoke verification without XCTest dependency.
- `Packaging/Info.plist`: minimal `.app` bundle metadata with `LSUIElement=true`.
- `scripts/build-macos-app.sh`: builds `.build/MCGA.app`.

## Parser Coverage

The Swift parser engine keeps the current Rust parser priority and covers:

- keyword generators: UUID v7, timestamp, RFC3339 time, ObjectID, Base64 encode/decode, password
- CIDR
- UUID
- ObjectID
- Hash
- IPv6
- public IPv4 with best-effort ip-api lookup
- timestamp
- HTTP status code
- integer base conversion
- Cron
- URL structure and query parsing
- JSON
- JSON5/JSONC common clipboard forms
- XML formatting
- TOML formatting
- YAML
- HTML entity decoding
- Base64 text decode
- DNS over HTTPS lookup for A, AAAA, and CNAME

The menu bar popover also supports persistent preferences through `UserDefaults`:

- Chinese / English UI labels
- light / dark theme
- per-parser enable / disable switches
- parser descriptions and examples in a dedicated settings sheet
- non-blocking copied feedback after copy actions

## Verification

```bash
source ~/.zshrc && swift run MCGASmokeTests
source ~/.zshrc && swift build --product MCGA
source ~/.zshrc && bash scripts/build-macos-app.sh
```
