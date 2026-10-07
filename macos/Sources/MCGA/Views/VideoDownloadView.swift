import AppKit
import SwiftUI

struct VideoDownloadButton: View {
    @ObservedObject var downloads: VideoDownloadModel
    @ObservedObject var preferences: AppPreferences
    let content: String

    var body: some View {
        let missing = downloads.missingTools
        VStack(alignment: .leading, spacing: 6) {
            Button {
                downloads.start(content)
            } label: {
                Label(preferences.language == .zh ? "下载视频（最高画质）" : "Download video (best quality)", systemImage: "arrow.down.circle")
            }
            .disabled(!downloads.canStart || !missing.isEmpty)
            .buttonStyle(.bordered)
            if !missing.isEmpty {
                Text((preferences.language == .zh ? "下载不可用：缺少 " : "Download unavailable: missing ") + missing.joined(separator: ", "))
                    .font(.system(size: 12)).foregroundStyle(Color.mutedText)
            }
        }
    }
}

struct VideoDownloadProgressView: View {
    @ObservedObject var downloads: VideoDownloadModel
    @ObservedObject var preferences: AppPreferences

    private func text(_ zh: String, _ en: String) -> String { preferences.language == .zh ? zh : en }

    var body: some View {
        if let phase = downloads.phase {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 10) {
                    Image(systemName: phase == .completed ? "checkmark.circle" : "arrow.down.circle")
                    Text(title(phase)).fontWeight(.semibold)
                    Spacer(minLength: 8)
                    if downloads.isRunning {
                        Button(text("取消", "Cancel")) { downloads.cancel() }
                    }
                    if !downloads.isRunning {
                        Button { downloads.clear() } label: { Image(systemName: "xmark") }
                            .buttonStyle(.plain).disabled(!downloads.canStart)
                    }
                }
                Text(downloads.filename).lineLimit(2).truncationMode(.middle)
                    .foregroundStyle(Color.mutedText)
                if !downloads.isRunning {
                    HStack {
                        if phase == .completed {
                            Button(text("打开", "Open")) {
                                if let file = downloads.files.first { NSWorkspace.shared.open(file) }
                            }
                            Button(text("在 Finder 中显示", "Show in Finder")) {
                                NSWorkspace.shared.activateFileViewerSelecting(downloads.files)
                            }
                        } else {
                            Button(text("重试", "Retry")) { downloads.start(downloads.source) }
                                .disabled(!downloads.canStart || !downloads.missingTools.isEmpty)
                            Menu(text("使用登录状态重试", "Retry with login")) {
                                ForEach(["safari", "chrome", "firefox"], id: \.self) { browser in
                                    Button(browser.capitalized) { downloads.start(downloads.source, browser: browser) }
                                }
                            }
                            .disabled(!downloads.canStart || !downloads.missingTools.isEmpty)
                        }
                    }
                }
                if downloads.isRunning {
                    if let fraction = downloads.fraction, phase == .downloading {
                        ProgressView(value: fraction)
                        HStack {
                            Text(fraction, format: .percent.precision(.fractionLength(0)))
                            if let speed = downloads.speed, speed.isFinite, speed >= 0, speed < Double(Int64.max) {
                                Text(ByteCountFormatter.string(fromByteCount: Int64(speed), countStyle: .file) + "/s")
                            }
                            if let eta = downloads.eta, eta.isFinite, eta >= 0, eta < Double(Int.max) {
                                Text(text("剩余 \(Int(eta)) 秒", "\(Int(eta))s remaining"))
                            }
                        }
                        .foregroundStyle(Color.mutedText).monospacedDigit()
                    } else { ProgressView().progressViewStyle(.linear) }
                }
                if phase == .failed {
                    Text(downloads.error).foregroundStyle(Color.warningText)
                        .lineLimit(3).textSelection(.enabled)
                }
            }
            .font(.system(size: 12))
            .padding(.horizontal, 16).padding(.vertical, 10)
            .frame(width: FloatingOverlayPresenter.width, alignment: .leading)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color(nsColor: .separatorColor), lineWidth: 0.5))
            .preferredColorScheme(preferences.theme.colorScheme)
        }
    }

    private func title(_ phase: VideoDownloadModel.Phase) -> String {
        switch phase {
        case .preparing: text("正在解析视频", "Preparing video")
        case .downloading: text("正在下载", "Downloading")
        case .processing: text("正在合并/处理", "Merging / processing")
        case .completed: text("下载完成", "Download complete")
        case .failed: text("下载失败", "Download failed")
        case .cancelled: text("已取消", "Cancelled")
        }
    }
}
