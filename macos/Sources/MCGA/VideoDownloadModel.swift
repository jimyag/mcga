import AppKit
import Darwin
import MCGACore

struct VideoPreview: Sendable {
    let title: String
    let thumbnail: URL?
    let stream: URL?
    let duration: Double?
    let headers: [String: String]

    static func decode(_ data: Data) -> VideoPreview? {
        guard var info = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return nil }
        if let entries = info["entries"] as? [[String: Any]], let first = entries.first { info = first }
        var formats = info["formats"] as? [[String: Any]] ?? []
        formats.append(info)
        let videos = formats.filter {
            let codec = $0["vcodec"] as? String
            return codec != "none" && (codec != nil || ["mp4", "webm", "mov", "mkv"].contains($0["ext"] as? String ?? ""))
                && ($0["url"] as? String).flatMap(URL.init(string:)).map { ["http", "https"].contains($0.scheme ?? "") } == true
        }
        guard !videos.isEmpty else { return nil }
        // Prefer a muxed MP4 preview; downloads still select the highest available format.
        let ordered = videos.sorted {
            func score(_ item: [String: Any]) -> Double {
                let audio = (item["acodec"] as? String).map { $0 != "none" } ?? false
                return (audio ? 1_000_000 : 0) + ((item["ext"] as? String) == "mp4" ? 100_000 : 0)
                    + ((item["height"] as? NSNumber)?.doubleValue ?? 0)
            }
            return score($0) > score($1)
        }
        return VideoPreview(title: info["title"] as? String ?? "Video",
            thumbnail: (info["thumbnail"] as? String).flatMap(URL.init(string:)).flatMap { ["http", "https"].contains($0.scheme ?? "") ? $0 : nil },
            stream: (ordered.first?["url"] as? String).flatMap(URL.init(string:)),
            duration: (info["duration"] as? NSNumber)?.doubleValue,
            headers: ordered.first?["http_headers"] as? [String: String] ?? info["http_headers"] as? [String: String] ?? [:])
    }
}

@MainActor
final class VideoDownloadModel: ObservableObject {
    enum PreviewState: Sendable { case loading, ready(VideoPreview), unavailable(String) }
    @Published private(set) var previews: [String: PreviewState] = [:]
    private var previewBrowsers: [String: String] = [:]
    enum Phase { case preparing, downloading, processing, completed, failed, cancelled }
    @Published private(set) var phase: Phase?
    @Published private(set) var fraction: Double?
    @Published private(set) var filename = ""
    @Published private(set) var speed: Double?
    @Published private(set) var eta: Double?
    @Published private(set) var error = ""
    @Published private(set) var files: [URL] = []
    private(set) var source = ""
    @Published private var process: Process?
    private var generation = UUID()
    private var buffer = Data()
    private var lastError = ""
    private let destination: URL
    private let executableOverride: URL?
    private let ffmpegOverride: URL?

    var isRunning: Bool { phase == .preparing || phase == .downloading || phase == .processing }
    var canStart: Bool { process == nil }

    func preview(for content: String) -> PreviewState? {
        guard let target = VideoDownloadTarget(content) else { return nil }
        return previews[target.url.absoluteString]
    }

    func loadPreview(_ content: String, browser: String? = nil, retry: Bool = false) async {
        guard let target = VideoDownloadTarget(content) else { return }
        let key = target.url.absoluteString
        guard retry || previews[key] == nil else { return }
        if case .loading = previews[key] { return }
        previews[key] = .loading
        guard let executable = downloader else {
            previews[key] = .unavailable("下载不可用：缺少 yt-dlp / Download unavailable: missing yt-dlp")
            return
        }
        let result = await Task.detached {
            Self.probe(target.url, executable: executable, browser: browser)
        }.value
        if case .ready = result { previewBrowsers[key] = browser }
        previews[key] = result
    }

    nonisolated private static func probe(_ url: URL, executable: URL, browser: String?) -> PreviewState {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("mcga-preview-\(UUID())")
        defer { try? FileManager.default.removeItem(at: folder) }
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let stdout = folder.appendingPathComponent("stdout")
            let stderr = folder.appendingPathComponent("stderr")
            guard FileManager.default.createFile(atPath: stdout.path, contents: nil),
                  FileManager.default.createFile(atPath: stderr.path, contents: nil) else {
                throw CocoaError(.fileWriteUnknown)
            }
            let output = try FileHandle(forWritingTo: stdout)
            let errors = try FileHandle(forWritingTo: stderr)
            defer { try? output.close(); try? errors.close() }
            let process = Process()
            process.executableURL = executable
            process.arguments = ["--ignore-config", "--no-playlist", "--skip-download", "--dump-single-json", "--no-warnings",
                "--socket-timeout", "15", "--retries", "1"]
            if let browser, ["safari", "chrome", "firefox"].contains(browser) { process.arguments! += ["--cookies-from-browser", browser] }
            process.arguments! += ["--", url.absoluteString]
            var environment = ProcessInfo.processInfo.environment
            environment["PATH"] = searchPaths.joined(separator: ":")
            process.environment = environment
            process.standardInput = FileHandle.nullDevice
            process.standardOutput = output
            process.standardError = errors
            try process.run()
            let timeout = DispatchWorkItem {
                guard process.isRunning else { return }
                if getpgid(process.processIdentifier) == process.processIdentifier { kill(-process.processIdentifier, SIGKILL) }
                else { kill(process.processIdentifier, SIGKILL) }
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + 90, execute: timeout)
            defer { timeout.cancel() }
            process.waitUntilExit()
            let reader = try FileHandle(forReadingFrom: stdout)
            defer { try? reader.close() }
            let data = try reader.read(upToCount: 8 * 1024 * 1024 + 1) ?? Data()
            if process.terminationStatus == 0, data.count <= 8 * 1024 * 1024, let preview = VideoPreview.decode(data) { return .ready(preview) }
            let errorReader = try FileHandle(forReadingFrom: stderr)
            defer { try? errorReader.close() }
            let diagnostics = String(decoding: try errorReader.read(upToCount: 2000) ?? Data(), as: UTF8.self)
            return .unavailable(diagnostics.isEmpty ? "未解析到可播放的视频 / No playable video found" : diagnostics)
        } catch { return .unavailable(error.localizedDescription) }
    }
    var missingTools: [String] {
        [("yt-dlp", downloader), ("ffmpeg", ffmpeg)].compactMap { $0.1 == nil ? $0.0 : nil }
    }

    private var downloader: URL? { resolved(executableOverride, name: "yt-dlp") }
    private var ffmpeg: URL? { resolved(ffmpegOverride, name: "ffmpeg") }

    private func resolved(_ override: URL?, name: String) -> URL? {
        guard let override else { return Self.tool(name) }
        return FileManager.default.isExecutableFile(atPath: override.path) ? override : nil
    }

    init(destination: URL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0], executable: URL? = nil, ffmpegExecutable: URL? = nil) {
        self.destination = destination
        executableOverride = executable
        ffmpegOverride = ffmpegExecutable
    }

    func start(_ content: String, browser: String? = nil) {
        guard process == nil, let target = VideoDownloadTarget(content) else { return }
        let browser = browser ?? previewBrowsers[target.url.absoluteString]
        source = content
        generation = UUID()
        let id = generation
        phase = .preparing
        fraction = nil
        speed = nil
        eta = nil
        filename = target.url.host ?? target.platform
        error = ""
        lastError = ""
        files = []
        buffer = Data()
        guard let executable = downloader, let ffmpeg = ffmpeg else {
            fail("下载不可用 / Download unavailable: \(missingTools.joined(separator: ", "))")
            return
        }
        let process = Process()
        let output = Pipe()
        process.executableURL = executable
        process.arguments = ["--ignore-config", "--no-playlist", "--no-overwrites", "--no-colors",
            "--socket-timeout", "30", "--retries", "3", "--fragment-retries", "3",
            "--newline", "--progress", "--progress-delta", "0.3", "--no-simulate",
            "--format", "bestvideo+bestaudio/best", "--ffmpeg-location", ffmpeg.deletingLastPathComponent().path,
            "--paths", destination.path, "--output", "%(title).150B [%(id)s].%(ext)s",
            "--progress-template", "download:MCGA_PROGRESS:%(progress)j",
            "--progress-template", "postprocess:MCGA_PROCESSING",
            "--print", "after_move:MCGA_FILE:%(filepath)j"]
        if let browser, ["safari", "chrome", "firefox"].contains(browser) {
            process.arguments! += ["--cookies-from-browser", browser]
        }
        process.arguments! += ["--", target.url.absoluteString]
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = Self.searchPaths.joined(separator: ":")
        process.environment = environment
        process.standardOutput = output
        process.standardError = output
        process.standardInput = FileHandle.nullDevice
        do {
            try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
            try process.run()
        } catch { fail(error.localizedDescription); return }
        self.process = process
        // Reading and waiting stay off the main actor; UI updates preserve stream order.
        Task.detached { [weak self] in
            let reader = output.fileHandleForReading
            while true {
                let chunk = reader.availableData
                if chunk.isEmpty { break }
                await self?.consume(chunk, id: id)
            }
            process.waitUntilExit()
            try? reader.close()
            await self?.finish(status: process.terminationStatus, id: id)
        }
    }

    func cancel() {
        guard let process, isRunning else { return }
        phase = .cancelled
        // Stop ffmpeg as well when Foundation gave the downloader its own process group.
        if getpgid(process.processIdentifier) == process.processIdentifier {
            kill(-process.processIdentifier, SIGTERM)
        } else { process.terminate() }
        Task {
            try? await Task.sleep(for: .seconds(2))
            guard self.process === process, process.isRunning else { return }
            if getpgid(process.processIdentifier) == process.processIdentifier {
                kill(-process.processIdentifier, SIGKILL)
            } else { kill(process.processIdentifier, SIGKILL) }
        }
    }

    func clear() {
        guard process == nil else { return }
        phase = nil
    }

    private func consume(_ data: Data, id: UUID) {
        guard id == generation, phase != .cancelled else { return }
        buffer.append(data)
        while let newline = buffer.firstIndex(of: 10) {
            let line = String(decoding: buffer[..<newline], as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            buffer.removeSubrange(...newline)
            consumeLine(line)
        }
        // Ignore oversized diagnostic lines without retaining unbounded tool output.
        if buffer.count > 256 * 1024 { buffer.removeAll() }
    }

    private func consumeLine(_ line: String) {
        if line.hasPrefix("MCGA_PROGRESS:"),
           let progress = try? JSONSerialization.jsonObject(with: Data(line.dropFirst(14).utf8)) as? [String: Any] {
            phase = progress["status"] as? String == "finished" ? .processing : .downloading
            if let path = progress["filename"] as? String { filename = URL(fileURLWithPath: path).lastPathComponent }
            let total = (progress["total_bytes"] as? NSNumber)?.doubleValue ?? (progress["total_bytes_estimate"] as? NSNumber)?.doubleValue
            if let total, total > 0, let downloaded = progress["downloaded_bytes"] as? NSNumber {
                fraction = min(1, max(0, downloaded.doubleValue / total))
            } else { fraction = nil }
            speed = (progress["speed"] as? NSNumber)?.doubleValue
            eta = (progress["eta"] as? NSNumber)?.doubleValue
        } else if line.hasPrefix("MCGA_PROCESSING") {
            phase = .processing
            fraction = nil
            speed = nil
            eta = nil
        } else if line.hasPrefix("MCGA_FILE:"),
                  let path = try? JSONSerialization.jsonObject(with: Data(line.dropFirst(10).utf8), options: .fragmentsAllowed) as? String {
            let file = URL(fileURLWithPath: path).standardizedFileURL
            if file.path.hasPrefix(destination.standardizedFileURL.path + "/"), FileManager.default.fileExists(atPath: file.path) {
                files.append(file)
                filename = file.lastPathComponent
            }
        } else if line.hasPrefix("ERROR:") { lastError = String(line.prefix(1500)) }
    }

    private func finish(status: Int32, id: UUID) {
        guard id == generation else { return }
        if phase != .cancelled {
            if !buffer.isEmpty { consumeLine(String(decoding: buffer, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)) }
            if status == 0 && !files.isEmpty { phase = .completed; fraction = 1 }
            else { fail(lastError.isEmpty ? "下载失败 / Download failed (exit \(status))" : lastError) }
        }
        process = nil
        buffer.removeAll()
    }

    private func fail(_ message: String) { error = message; phase = .failed }

    nonisolated private static var searchPaths: [String] {
        [FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".local/bin").path, "/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin"]
            + (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":").map(String.init)
    }

    private static func tool(_ name: String) -> URL? {
        searchPaths.map { URL(fileURLWithPath: $0).appendingPathComponent(name) }
            .first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }
}
