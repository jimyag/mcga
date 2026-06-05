import Foundation

struct CustomCommandParser: ContentParser {
    private let config: CustomParserConfig
    let name: String
    let info: ParserInfo?

    private init(config: CustomParserConfig) {
        self.config = config
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
            }
        )
    }

    static func load() -> [CustomCommandParser] {
        let path = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/mcga/custom_parsers.json")
        guard let data = try? Data(contentsOf: path),
              let file = try? JSONDecoder().decode(CustomParserFile.self, from: data)
        else { return [] }
        return file.parsers
            .filter { $0.enabled ?? true }
            .filter { $0.kind == nil || $0.kind == "command" }
            .map(CustomCommandParser.init(config:))
    }

    func parse(_ content: String, previousContent: String) -> [ParseResult] {
        if let match = config.match, !matches(match, content) {
            return []
        }
        guard let executable = expandedCommandPath(config.command),
              executable.hasPrefix("/"),
              FileManager.default.isExecutableFile(atPath: executable)
        else { return [] }

        guard let output = runCommand(executable: executable, args: config.args ?? [], input: content) else {
            return []
        }
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        let firstLine = trimmed.split(separator: "\n", maxSplits: 1).first.map(String.init) ?? trimmed
        return [ParseResult(
            parserName: name,
            original: content,
            parsed: firstLine,
            details: trimmed == firstLine ? nil : trimmed
        )]
    }

    private func matches(_ pattern: String, _ content: String) -> Bool {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return false }
        let range = NSRange(content.startIndex..<content.endIndex, in: content)
        return regex.firstMatch(in: content, range: range) != nil
    }

    private func expandedCommandPath(_ command: String) -> String? {
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

    private func runCommand(executable: String, args: [String], input: String) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = args

        let stdin = Pipe()
        process.standardInput = stdin
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("mcga-custom-parser-\(UUID().uuidString).out")
        FileManager.default.createFile(atPath: outputURL.path, contents: nil)
        guard let outputHandle = try? FileHandle(forWritingTo: outputURL) else {
            return nil
        }
        defer {
            try? outputHandle.close()
            try? FileManager.default.removeItem(at: outputURL)
        }
        process.standardOutput = outputHandle
        process.standardError = FileHandle(forWritingAtPath: "/dev/null")

        let terminationGroup = DispatchGroup()
        terminationGroup.enter()
        process.terminationHandler = { _ in terminationGroup.leave() }

        do {
            try process.run()
            stdin.fileHandleForWriting.write(Data(input.utf8))
            try? stdin.fileHandleForWriting.close()

            let timeout = DispatchTime.now() + .milliseconds(clampedTimeoutMs)
            if terminationGroup.wait(timeout: timeout) == .timedOut {
                process.terminate()
                _ = terminationGroup.wait(timeout: .now() + .milliseconds(200))
                return nil
            }

            guard process.terminationStatus == 0 else { return nil }
            try? outputHandle.synchronize()
            let data = (try? Data(contentsOf: outputURL)) ?? Data()
            return String(data: data, encoding: .utf8)
        } catch {
            return nil
        }
    }

    private var clampedTimeoutMs: Int {
        min(max(config.timeoutMs ?? 500, 50), 10_000)
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
