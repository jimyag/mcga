import Foundation

struct CustomCommandParser: ContentParser {
    let name: String
    let info: ParserInfo?
    let isSlow = true
    private let match: NSRegularExpression?
    private let executable: String
    private let args: [String]
    private let timeoutMs: Int

    private init(config: CustomParserConfig, match: NSRegularExpression?, executable: String) {
        self.name = config.name
        self.info = ParserInfo(
            name: config.name,
            zhDescription: config.description?.zh ?? "执行本地命令解析剪切板内容。",
            enDescription: config.description?.en ?? "Runs a local command to parse clipboard content.",
            examples: (config.examples ?? []).map {
                ParserExample(
                    input: $0.input,
                    zhExpected: $0.expected?.zh ?? $0.expectedText ?? "",
                    enExpected: $0.expected?.en ?? $0.expectedText ?? ""
                )
            },
            category: .custom
        )
        self.match = match
        self.executable = executable
        self.args = config.args ?? []
        self.timeoutMs = min(max(config.timeoutMs ?? 500, 50), 10_000)
    }

    static var configURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/mcga/custom_parsers.json")
    }

    /// The parsers in the config, and the problems that keep one from loading or running.
    static func load(from url: URL) -> (parsers: [CustomCommandParser], issues: [String]) {
        guard FileManager.default.fileExists(atPath: url.path) else { return ([], []) }
        let file: CustomParserFile
        do {
            file = try JSONDecoder().decode(CustomParserFile.self, from: Data(contentsOf: url))
        } catch {
            return ([], [tr("配置无法解析：\(describe(error))", "The config cannot be read: \(describe(error))")])
        }
        var parsers: [CustomCommandParser] = []
        var issues: [String] = []
        for config in file.parsers where config.enabled ?? true {
            if let kind = config.kind, kind != "command" {
                issues.append(tr("\(config.name)：只支持 command，不支持 \(kind)", "\(config.name): only command is supported, not \(kind)"))
                continue
            }
            var match: NSRegularExpression?
            if let pattern = config.match {
                guard let regex = try? NSRegularExpression(pattern: pattern) else {
                    issues.append(tr("\(config.name)：match 不是有效的正则表达式", "\(config.name): match is not a valid regular expression"))
                    continue
                }
                match = regex
            }
            let executable = expandedCommandPath(config.command)
            // Still loaded: making the file executable fixes it without touching the config.
            if !isRunnable(executable) {
                issues.append(tr("\(config.name)：命令不存在或不可执行：\(executable)", "\(config.name): the command is missing or not executable: \(executable)"))
            }
            parsers.append(CustomCommandParser(config: config, match: match, executable: executable))
        }
        return (parsers, issues)
    }

    func parse(_ content: String, previousContent: String) async -> [ParseResult] {
        if let match, match.firstMatch(in: content, range: NSRange(content.startIndex..., in: content)) == nil {
            return []
        }
        guard Self.isRunnable(executable), let output = await run(input: content) else { return [] }
        let trimmed = output.mcgaTrimmed
        guard !trimmed.isEmpty else { return [] }
        let firstLine = trimmed.split(separator: "\n", maxSplits: 1).first.map(String.init) ?? trimmed
        return [ParseResult(
            parserName: name,
            original: content,
            parsed: firstLine,
            details: trimmed == firstLine ? nil : trimmed
        )]
    }

    private static func isRunnable(_ path: String) -> Bool {
        path.hasPrefix("/") && FileManager.default.isExecutableFile(atPath: path)
    }

    private static func expandedCommandPath(_ command: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        var path = command
        if path == "~" {
            path = home
        } else if path.hasPrefix("~/") {
            path = home + String(path.dropFirst())
        }
        path = path.replacingOccurrences(of: "$HOME", with: home)
        path = path.replacingOccurrences(of: "${HOME}", with: home)
        return path
    }

    /// Stdin and stdout are temporary files rather than pipes: a command that exits without
    /// reading all of its input must not raise SIGPIPE in MCGA, and nothing blocks before the
    /// timeout starts.
    private func run(input: String) async -> String? {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("mcga-custom-parser-\(UUID().uuidString)")
        let inputURL = base.appendingPathExtension("in")
        let outputURL = base.appendingPathExtension("out")
        defer {
            try? FileManager.default.removeItem(at: inputURL)
            try? FileManager.default.removeItem(at: outputURL)
        }
        do {
            try Data(input.utf8).write(to: inputURL)
            try Data().write(to: outputURL)
            let stdin = try FileHandle(forReadingFrom: inputURL)
            let stdout = try FileHandle(forWritingTo: outputURL)
            defer {
                try? stdin.close()
                try? stdout.close()
            }
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = args
            process.standardInput = stdin
            process.standardOutput = stdout
            process.standardError = FileHandle.nullDevice
            guard try await exitStatus(of: process) == 0 else { return nil }
            return String(data: try Data(contentsOf: outputURL), encoding: .utf8)
        } catch {
            return nil
        }
    }

    /// The exit status, or nil when the command was killed, by the timeout or otherwise.
    private func exitStatus(of process: Process) async throws -> Int32? {
        // Only the timeout reaches the process from another thread, to terminate it. Newer SDKs
        // mark Process Sendable and warn that this is unnecessary; the macOS 15 SDK in CI may not.
        nonisolated(unsafe) let process = process
        let timeout = DispatchTimeInterval.milliseconds(timeoutMs)
        return try await withCheckedThrowingContinuation { continuation in
            process.terminationHandler = { process in
                continuation.resume(returning: process.terminationReason == .exit ? process.terminationStatus : nil)
            }
            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
                return
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                if process.isRunning {
                    process.terminate()
                }
            }
        }
    }

    /// Decoding errors say where the config went wrong; their default message does not.
    private static func describe(_ error: Error) -> String {
        switch error as? DecodingError {
        case .keyNotFound(let key, let context)?:
            return tr("\(path(context.codingPath + [key])) 缺失", "\(path(context.codingPath + [key])) is missing")
        case .typeMismatch(_, let context)?, .valueNotFound(_, let context)?:
            return "\(path(context.codingPath)): \(context.debugDescription)"
        case .dataCorrupted(let context)?:
            // JSON syntax errors keep the line and column in the underlying error.
            let underlying = (context.underlyingError as NSError?)?.userInfo[NSDebugDescriptionErrorKey] as? String
            return underlying ?? context.debugDescription
        default:
            return error.localizedDescription
        }
    }

    /// "parsers[1].command" style.
    private static func path(_ codingPath: [any CodingKey]) -> String {
        var path = ""
        for key in codingPath {
            if let index = key.intValue {
                path += "[\(index)]"
            } else {
                path += path.isEmpty ? key.stringValue : ".\(key.stringValue)"
            }
        }
        return path
    }
}

private struct CustomParserFile: Decodable, Sendable {
    let parsers: [CustomParserConfig]
}

private struct CustomParserConfig: Decodable, Sendable {
    let name: String
    let kind: String?
    let description: LocalizedText?
    let examples: [CustomParserExample]?
    let match: String?
    let command: String
    let args: [String]?
    let timeoutMs: Int?
    let enabled: Bool?
}

private struct LocalizedText: Decodable, Sendable {
    let zh: String?
    let en: String?
}

private struct CustomParserExample: Decodable, Sendable {
    let input: String
    let expected: LocalizedText?
    let expectedText: String?

    enum CodingKeys: String, CodingKey {
        case input
        case expected
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.input = try container.decode(String.self, forKey: .input)
        self.expected = try? container.decode(LocalizedText.self, forKey: .expected)
        self.expectedText = try? container.decode(String.self, forKey: .expected)
    }
}
