import AppKit
import MCGACore

// After `swift build --product MCGA`, run:
// swiftc -parse-as-library -I .build/out/Products/Debug -I .build/checkouts/Yams/Sources/CYaml/include -F .build/out/Products/Debug -framework Sparkle -Xlinker -rpath -Xlinker "$PWD/.build/out/Products/Debug" scripts/check-clipboard-copy.swift Sources/MCGA/AppPreferences.swift Sources/MCGA/ClipboardModel.swift Sources/MCGA/AppDelegate.swift Sources/MCGA/UIComponents.swift Sources/MCGA/Views/*.swift .build/out/Products/Debug/libMCGACore.a -o .build/check-clipboard-copy
// .build/check-clipboard-copy

@main
struct ClipboardCopyCheck {
    @MainActor
    static func main() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("mcga-copy-check-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        let store = HistoryStore(path: directory.appendingPathComponent("history.json"), assetsDirectory: directory.appendingPathComponent("assets"))
        let engine = ParserEngine(customParserConfig: nil, fetch: { _ in nil })
        let model = ClipboardModel(preferences: AppPreferences(), pasteboard: pasteboard, historyStore: store, engine: engine)
        var events: [(generation: UInt64, content: String, results: [ParseResult])] = []
        model.onResults = { events.append(($0, $1, $2)) }

        // A history copy supplies the previous value without opening an overlay.
        model.copy("hello")
        model.copyAndRecord("b64")
        try await wait("overlay copy must publish results") { events.contains { $0.content == "b64" } }
        let encoded = events.first { $0.content == "b64" }!
        assert(encoded.generation == 1, "History copies must not start a parse")
        assert(encoded.results.contains { $0.parserName == "Base64 Encode" && $0.parsed == "aGVsbG8=" })
        assert(pasteboard.string(forType: .string) == "b64")

        // Copying a result starts another parse and overlay, enabling chained transformations.
        model.copyAndRecord("aGVsbG8=")
        try await wait("copied output must publish a new overlay") { events.contains { $0.content == "aGVsbG8=" } }
        let decoded = events.first { $0.content == "aGVsbG8=" }!
        assert(decoded.generation == encoded.generation + 1)
        assert(decoded.results.contains { $0.parserName == "Base64" && $0.parsed == "hello" })

        // Re-copying the current content and copying while paused must not start a parse.
        model.copyAndRecord("aGVsbG8=")
        model.isPaused = true
        model.copyAndRecord("uuid")
        model.isPaused = false
        model.copyAndRecord("404")
        try await wait("resumed copies must publish results") { events.contains { $0.content == "404" } }
        let resumed = events.first { $0.content == "404" }!
        assert(resumed.generation == decoded.generation + 1, "Duplicate and paused copies must not advance the generation")
        assert(resumed.results.contains { $0.parserName == "HTTP Status" })
        assert(!events.contains { $0.content == "uuid" })

        try await wait("overlay copies must retain parsed history") {
            let entries = await store.allRecent()
            return ["b64", "aGVsbG8=", "404"].allSatisfy { content in
                entries.contains { $0.originalContent == content && !$0.results.isEmpty }
            }
        }
        let history = await store.allRecent()
        assert(history.count == 3, "History copies, duplicates, and paused copies must not add entries")
        assert(pasteboard.string(forType: .string) == "404")
        print("PASS: overlay copy publishes results, chained parsing, parsed history, history-copy suppression, duplicates, and pause/resume")
    }

    @MainActor
    static func wait(_ message: String, until condition: () async -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while !(await condition()) {
            guard ContinuousClock.now < deadline else { fatalError(message) }
            try await Task.sleep(for: .milliseconds(10))
        }
    }
}
