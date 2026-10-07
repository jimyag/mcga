import AppKit
import MCGACore
import SwiftUI
import WebKit

// After `swift build --product MCGACore`, run:
// swiftc -parse-as-library -I .build/out/Products/Debug -I .build/checkouts/Yams/Sources/CYaml/include scripts/check-video-download.swift Sources/MCGA/VideoDownloadModel.swift Sources/MCGA/AppPreferences.swift Sources/MCGA/UIComponents.swift Sources/MCGA/Views/VideoDownloadView.swift Sources/MCGA/Views/VideoPreviewView.swift Sources/MCGA/Views/FloatingOverlayView.swift .build/out/Products/Debug/libMCGACore.a -o .build/check-video-download
// .build/check-video-download
// Optional real yt-dlp check against a local HTTP fixture: .build/check-video-download http://127.0.0.1:PORT/clip.mp4

@main
struct VideoDownloadCheck {
    @MainActor
    static func main() async throws {
        NSApplication.shared.setActivationPolicy(.prohibited)
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("mcga-download-check-\(UUID())")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        if CommandLine.arguments.count > 1 {
            let model = VideoDownloadModel(destination: folder)
            await model.loadPreview(CommandLine.arguments[1])
            guard case .ready(let preview) = model.preview(for: CommandLine.arguments[1]) else { fatalError("Real video metadata resolution failed") }
            assert(preview.stream != nil && !preview.title.isEmpty && model.phase == nil)
            let host = NSHostingView(rootView: VStack(alignment: .leading) {
                ScrollView {
                    VStack(alignment: .leading) {
                        ZStack {
                            Color.black
                            InlineVideoPreview(url: preview.stream!, headers: preview.headers)
                        }.frame(height: 190)
                    }.padding(.horizontal, 14)
                }
            }.frame(width: 360))
            let window = NonActivatingOverlayPanel(contentRect: NSRect(x: 0, y: 0, width: 320, height: 180), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            window.contentView = host
            if let screen = NSScreen.main {
                window.setFrameOrigin(NSPoint(x: screen.visibleFrame.maxX - window.frame.width - 8, y: screen.visibleFrame.maxY - window.frame.height - 8))
            }
            window.orderFrontRegardless()
            defer { window.orderOut(nil) }
            func webView(in view: NSView) -> WKWebView? {
                if let web = view as? WKWebView { return web }
                return view.subviews.compactMap { webView(in: $0) }.first
            }
            try await wait { webView(in: host) != nil }
            let web = webView(in: host)!
            assert(web.bounds.width <= 332, "Player must stay within the popup content width")
            let deadline = ContinuousClock.now.advanced(by: .seconds(90))
            while true {
                if let ready = try? await web.evaluateJavaScript("document.querySelector('video')?.readyState"),
                   let state = ready as? NSNumber, state.intValue >= 1 { break }
                guard ContinuousClock.now < deadline else { fatalError("Native video preview did not load metadata") }
                try await Task.sleep(for: .milliseconds(50))
            }
            let fits = try await web.evaluateJavaScript("""
                (() => {
                  const r = document.querySelector('video').getBoundingClientRect();
                  return r.width <= innerWidth + 1 && r.height <= innerHeight + 1
                    && Math.abs(r.x + r.width / 2 - innerWidth / 2) <= 1
                    && Math.abs(r.y + r.height / 2 - innerHeight / 2) <= 1;
                })()
                """)
            assert(fits as? Bool == true, "Preview video must fit and center inside the floating player")
            assert(model.phase == nil && model.files.isEmpty)
            let previewFiles = try FileManager.default.contentsOfDirectory(atPath: folder.path)
            assert(previewFiles.isEmpty, "Preview must not save video files into the download destination")
            _ = try await web.evaluateJavaScript("(() => { const v = document.querySelector('video'); v.muted = true; v.loop = true; v.play(); return true; })()")
            try await waitForPlayback(web, playing: true)
            window.orderOut(nil)
            try await waitForPlayback(web, playing: false)
            model.start(CommandLine.arguments[1])
            try await wait { !model.isRunning }
            assert(model.phase == .completed, model.error)
            assert(!model.files.isEmpty && FileManager.default.fileExists(atPath: model.files[0].path))
            print("PASS: real video resolution, centered preview, no preview downloads, playback stopped on popup dismissal, and completed download")
            return
        }
        let fixture = folder.appendingPathComponent("demo.mp4")
        try Data("fixture".utf8).write(to: fixture)
        let executable = folder.appendingPathComponent("downloader")
        let script = """
        #!/bin/sh
        set -eu
        last=''
        probe=0
        for argument do
          last="$argument"
          if [ "$argument" = '--dump-single-json' ]; then probe=1; fi
        done
        if [ "$probe" = 1 ]; then
          case "$last" in
            *failed*) printf 'ERROR: login required\\n' >&2; exit 1 ;;
            *photo*) printf '{"title":"Photo","url":"https://example.com/photo.jpg","ext":"jpg"}\\n'; exit 0 ;;
          esac
          printf '{"title":"Preview demo","duration":12,"thumbnail":"https://example.com/cover.jpg","formats":[{"url":"https://example.com/audio.mp4","vcodec":"none","acodec":"aac","ext":"mp4"},{"url":"https://example.com/video.mp4","vcodec":"h264","acodec":"aac","ext":"mp4","http_headers":{"Referer":"https://example.com/"}}]}\\n'
          exit 0
        fi
        case "$last" in
          *failed*) printf 'ERROR: login required\\n'; exit 1 ;;
          *cancel*) printf 'MCGA_PROGRESS:{"status":"downloading","downloaded_bytes":1,"total_bytes":100}\\n'; read unused; exit 1 ;;
        esac
        printf 'MCGA_PROGRESS:{"status":"downloading","downloaded_bytes":50,"total_bytes":100,"speed":25,"eta":2}\\n'
        printf 'MCGA_PROCESSING\\n'
        printf 'MCGA_FILE:"%s"\\n' '\(fixture.path)'
        """
        // The cancel fixture waits for a signal, rather than depending on an arbitrary sleep.
        let cancelScript = script.replacingOccurrences(of: "read unused; exit 1", with: "while :; do :; done")
        try cancelScript.write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
        let model = VideoDownloadModel(destination: folder, executable: executable)
        await model.loadPreview("https://example.com/demo.mp4")
        guard case .ready(let preview) = model.preview(for: "https://example.com/demo.mp4") else { fatalError("Video metadata should be ready") }
        assert(preview.title == "Preview demo" && preview.duration == 12 && preview.stream?.lastPathComponent == "video.mp4")
        assert(preview.headers["Referer"] == "https://example.com/" && model.phase == nil && model.files.isEmpty)
        await model.loadPreview("https://example.com/photo.mp4")
        guard case .unavailable = model.preview(for: "https://example.com/photo.mp4") else { fatalError("Image-only metadata must not enable downloading") }
        await model.loadPreview("https://example.com/failed.mp4")
        guard case .unavailable(let diagnostic) = model.preview(for: "https://example.com/failed.mp4") else { fatalError("Resolution failure must not enable downloading") }
        assert(diagnostic.contains("login required"))
        let absent = folder.appendingPathComponent("not-installed")
        for (yt, ffmpeg, expected) in [(absent, executable, ["yt-dlp"]), (executable, absent, ["ffmpeg"]), (absent, absent, ["yt-dlp", "ffmpeg"])] {
            let unavailable = VideoDownloadModel(destination: folder, executable: yt, ffmpegExecutable: ffmpeg)
            assert(unavailable.missingTools == expected)
            unavailable.start("https://example.com/demo.mp4")
            assert(unavailable.phase == .failed && unavailable.canStart && unavailable.error.contains("Download unavailable"))
        }
        let preferences = AppPreferences()
        let presenter = FloatingOverlayPresenter()
        presenter.observeDownloads(model, preferences: preferences)
        defer { NSApp.windows.forEach { $0.orderOut(nil) } }
        var sawProgress = false
        let subscription = model.$fraction.sink { if $0 == 0.5 { sawProgress = true } }
        defer { subscription.cancel() }
        model.start("https://example.com/demo.mp4")
        try await wait { model.canStart }
        assert(model.phase == .completed && model.files == [fixture] && sawProgress)
        try await wait { NSApp.windows.contains { $0.title == "MCGA Video Download" && $0.isVisible } }
        let panel = NSApp.windows.first { $0.title == "MCGA Video Download" }!
        guard let screen = NSScreen.main else { fatalError("No screen for download placement check") }
        try await wait { abs(panel.frame.maxX - (screen.visibleFrame.maxX - 8)) <= 1 && abs(panel.frame.maxY - (screen.visibleFrame.maxY - 8)) <= 1 }
        presenter.show(id: 1, content: "404", results: [ParseResult(parserName: "HTTP Status", original: "404", parsed: "404 Not Found")], lifetime: 30, category: { _ in .identifier }, preferences: preferences, copy: { _ in }, showHistory: {})
        let clipboardPanel = NSApp.windows.first { $0 is NonActivatingOverlayPanel && $0 !== panel }!
        try await wait { clipboardPanel.frame.maxY < panel.frame.minY }
        model.start("https://example.com/failed.mp4")
        try await wait { model.canStart }
        assert(model.phase == .failed && model.error.contains("login required"))
        model.start("https://example.com/cancel.mp4")
        try await wait { model.phase == .downloading }
        model.cancel()
        try await wait { model.canStart }
        assert(model.phase == .cancelled && model.files.isEmpty)
        model.start("https://example.com/demo.mp4")
        try await wait { model.canStart }
        assert(model.phase == .completed, "Retry after cancellation must work")
        model.start("https://example.com/cancel.mp4")
        try await wait { model.phase == .downloading }
        let host = NSHostingView(rootView: VideoDownloadProgressView(downloads: model, preferences: AppPreferences())
            .background(Color(nsColor: .windowBackgroundColor)).preferredColorScheme(.light))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 360, height: 120), styleMask: .borderless, backing: .buffered, defer: false)
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        assert(host.fittingSize.height > 0, "Progress header renders in a native window")
        try snapshot(host)
        model.cancel()
        try await wait { model.canStart }
        model.clear()
        assert(model.phase == nil)
        try await wait { !panel.isVisible && abs(clipboardPanel.frame.maxY - (screen.visibleFrame.maxY - 8)) <= 1 }
        let existingWindows = Set(NSApp.windows.map(\.windowNumber))
        presenter.show(id: 2, content: "https://example.com/resize.mp4", results: [ParseResult(parserName: "Video Download", original: "https://example.com/resize.mp4", parsed: "Video")], lifetime: 30, category: { _ in .network }, preferences: preferences, copy: { _ in }, showHistory: {}, downloads: model)
        let videoPanel = NSApp.windows.first { !existingWindows.contains($0.windowNumber) && $0 is NonActivatingOverlayPanel }!
        let initialHeight = videoPanel.frame.height
        try await wait {
            if case .ready = model.preview(for: "https://example.com/resize.mp4") { return videoPanel.frame.height > initialHeight + 100 }
            return false
        }
        print("PASS: video metadata, image-only rejection, resolution errors, missing tools, progress, files, cancellation, retry, top-right popup, stacking, and dismissal")
    }

    @MainActor
    static func waitForPlayback(_ web: WKWebView, playing: Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while true {
            let active = try? await web.evaluateJavaScript("document.querySelector('video')?.paused === false")
            if active as? Bool == playing { return }
            guard ContinuousClock.now < deadline else { fatalError(playing ? "Preview did not start" : "Preview kept playing after hiding the popup") }
            try await Task.sleep(for: .milliseconds(50))
        }
    }

    @MainActor
    static func snapshot(_ host: NSView) throws {
        host.layoutSubtreeIfNeeded()
        guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { fatalError("Cannot capture progress header") }
        host.cacheDisplay(in: host.bounds, to: bitmap)
        guard let png = bitmap.representation(using: .png, properties: [:]) else { fatalError("Cannot encode progress header") }
        try png.write(to: URL(fileURLWithPath: ".build/video-download-progress.png"))
    }

    @MainActor
    static func wait(_ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(90))
        while !condition() {
            guard ContinuousClock.now < deadline else { fatalError("Download check timed out") }
            try await Task.sleep(for: .milliseconds(10))
        }
    }
}
