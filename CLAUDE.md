# CLAUDE.md

This file provides guidance to Claude Code when working with this repository.

## Project

MCGA watches clipboard changes and displays parsed results. The Swift menu bar app for macOS lives in `macos/` and is what this file covers; a Windows port lives in `windows/`.

## Commands

Run these in `macos/`:

```bash
swift run MCGASmokeTests
swift build --product MCGA
bash scripts/build-macos-app.sh
open .build/MCGA.app
pkill MCGA
```

## Architecture

```
macos/Package.swift
macos/Sources/MCGA/MCGAApp.swift
macos/Sources/MCGA/AppDelegate.swift
macos/Sources/MCGA/ClipboardModel.swift
macos/Sources/MCGA/AppPreferences.swift
macos/Sources/MCGA/Views/*.swift
macos/Sources/MCGACore/ParserEngine.swift
macos/Sources/MCGACore/*Parsers.swift
macos/Sources/MCGACore/CustomCommandParser.swift
macos/Sources/MCGACore/HistoryStore.swift
macos/Sources/MCGASmokeTests/main.swift
macos/Packaging/Info.plist
macos/scripts/build-macos-app.sh
```

## Parser Notes

`macos/Sources/MCGACore/ParserEngine.swift` defines parser order. More specific parsers should be registered before broader parsers. Parsers marked `isSlow` (custom commands, IP, DNS) run concurrently after the others, and their results join in parser order as they arrive.

Parser text follows the interface language through `tr("中文", "English")` and `labeled(...)`.

Custom parsers are command-only and loaded from `~/.config/mcga/custom_parsers.json`, reloaded when the file changes. MCGA writes clipboard text to command stdin and reads stdout as the parse result, both through temporary files. Command paths may use `~`, `$HOME`, or `${HOME}`.

The smoke tests pass `customParserConfig: nil` and a stub `fetch`, so they run offline and ignore the local config.
