# CLAUDE.md

This file provides guidance to Claude Code when working with this repository.

## Project

MCGA is a macOS-only Swift menu bar app that watches clipboard changes and displays parsed results.

## Commands

```bash
source ~/.zshrc && swift run MCGASmokeTests
source ~/.zshrc && swift build --product MCGA
source ~/.zshrc && bash scripts/build-macos-app.sh
source ~/.zshrc && open .build/MCGA.app
source ~/.zshrc && pkill MCGA
```

## Architecture

```
Package.swift
Sources/MCGA/MCGAApp.swift
Sources/MCGACore/ParserEngine.swift
Sources/MCGACore/*Parsers.swift
Sources/MCGACore/CustomCommandParser.swift
Sources/MCGACore/HistoryStore.swift
Sources/MCGASmokeTests/main.swift
Packaging/Info.plist
scripts/build-macos-app.sh
```

## Parser Notes

`Sources/MCGACore/ParserEngine.swift` defines parser order. More specific parsers should be registered before broader parsers.

Custom parsers are command-only and loaded from `~/.config/mcga/custom_parsers.json`. MCGA writes clipboard text to command stdin and reads stdout as the parse result. Command paths may use `~`, `$HOME`, or `${HOME}`.
