import AppKit
import MCGACore
import SwiftUI
import WebKit

struct VideoPreviewView: View {
    @ObservedObject var downloads: VideoDownloadModel
    @ObservedObject var preferences: AppPreferences
    let content: String
    @State private var playing = false

    private func text(_ zh: String, _ en: String) -> String { preferences.language == .zh ? zh : en }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            switch downloads.preview(for: content) {
            case .ready(let preview):
                Text(preview.title).font(.system(size: 14, weight: .semibold)).lineLimit(3)
                ZStack {
                    Color.primary.opacity(0.04)
                    if playing, let stream = preview.stream {
                        InlineVideoPreview(url: stream, headers: preview.headers)
                    } else if let thumbnail = preview.thumbnail {
                        AsyncImage(url: thumbnail) { image in
                            image.resizable().scaledToFit()
                        } placeholder: { Color.clear }
                    } else {
                        Image(systemName: "play.rectangle").font(.system(size: 32)).foregroundStyle(Color.mutedText)
                    }
                }
                .frame(height: 190).clipShape(RoundedRectangle(cornerRadius: 8))
                if let duration = preview.duration, duration.isFinite, duration >= 0, duration < Double(Int.max) {
                    Text(text("时长：\(Int(duration)) 秒", "Duration: \(Int(duration))s"))
                        .font(.system(size: 12)).foregroundStyle(Color.mutedText)
                }
                if preview.stream != nil {
                    Button(text(playing ? "关闭预览" : "预览视频", playing ? "Close preview" : "Preview video")) { playing.toggle() }
                }
                VideoDownloadButton(downloads: downloads, preferences: preferences, content: content)
            case .unavailable(let error):
                Text(text("视频解析不可用", "Video unavailable")).font(.system(size: 12, weight: .semibold))
                Text(error).font(.system(size: 11)).foregroundStyle(Color.mutedText).lineLimit(4)
                if !downloads.missingTools.contains("yt-dlp") {
                    HStack {
                        Button(text("重新解析", "Retry")) { Task { await downloads.loadPreview(content, retry: true) } }
                        Menu(text("使用登录状态解析", "Resolve with login")) {
                            ForEach(["safari", "chrome", "firefox"], id: \.self) { browser in
                                Button(browser.capitalized) { Task { await downloads.loadPreview(content, browser: browser, retry: true) } }
                            }
                        }
                    }
                }
            case .loading, nil:
                HStack {
                    ProgressView().controlSize(.small)
                    Text(text("正在解析视频…", "Resolving video…")).font(.system(size: 12))
                }
            }
        }
        .task(id: content) { await downloads.loadPreview(content) }
        .onChange(of: content) { playing = false }
    }
}

struct InlineVideoPreview: NSViewRepresentable {
    let url: URL
    let headers: [String: String]

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.mediaTypesRequiringUserActionForPlayback = .all
        // Direct media documents use WebKit's page layout; constrain it to the embedded player.
        configuration.userContentController.addUserScript(WKUserScript(source: """
            const style = document.createElement('style');
            style.textContent = `html, body { margin: 0 !important; width: 100%; height: 100%; overflow: hidden; background: #202020; }
              video { position: fixed !important; inset: 0 !important; margin: 0 !important;
                width: 100% !important; height: 100% !important; min-width: 0 !important; min-height: 0 !important;
                max-width: 100% !important; max-height: 100% !important; object-fit: contain !important; object-position: center !important; }`;
            document.head.appendChild(style);
            """, injectionTime: .atDocumentEnd, forMainFrameOnly: true))
        let view = WKWebView(frame: .zero, configuration: configuration)
        var request = URLRequest(url: url)
        request.allHTTPHeaderFields = headers
        view.load(request)
        return view
    }

    func updateNSView(_ view: WKWebView, context: Context) {}

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: WKWebView, context: Context) -> CGSize? {
        guard let width = proposal.width, let height = proposal.height else { return nil }
        return CGSize(width: width, height: height)
    }

    static func dismantleNSView(_ view: WKWebView, coordinator: ()) { stopPlayback(in: view) }

    static func stopPlayback(in view: NSView) {
        if let web = view as? WKWebView {
            web.setAllMediaPlaybackSuspended(true, completionHandler: nil)
            web.stopLoading()
            web.loadHTMLString("", baseURL: nil)
        } else {
            view.subviews.forEach { stopPlayback(in: $0) }
        }
    }
}
