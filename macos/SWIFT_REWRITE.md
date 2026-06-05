# MCGA Swift macOS App

This repository is macOS-only and uses SwiftUI/AppKit for a menu bar clipboard parser. It requires macOS 15+.

## Shape

- `Sources/MCGA`: menu bar app, clipboard polling, popover UI, settings window, copy actions, pause, history, quit.
- `Sources/MCGACore`: parser engine, built-in parsers, custom command parsers, history store.
- `Sources/MCGASmokeTests`: executable smoke verification without XCTest dependency.
- `Packaging/Info.plist`: `.app` bundle metadata with `LSUIElement=true`.
- `scripts/build-macos-app.sh`: builds `.build/MCGA.app`.

## Parser Coverage

The parser engine covers:

- keyword generators: UUID v7, timestamp, RFC3339 time, ObjectID, Base64 encode/decode, password
- custom command parsers from `~/.config/mcga/custom_parsers.json`
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
- Unicode escape decoding
- Base64 text decode
- DNS over HTTPS lookup for A, AAAA, and CNAME

The menu bar popover also supports persistent preferences through `UserDefaults`:

- Chinese / English UI labels
- light / dark theme
- per-parser enable / disable switches
- parser descriptions and examples in an independent settings window
- non-blocking copied feedback after copy actions
- activity-ordered clipboard history; copy or paste actions on an existing history entry promote it to the top

## Verification

```bash
swift run MCGASmokeTests
swift build --product MCGA
bash scripts/build-macos-app.sh
```
