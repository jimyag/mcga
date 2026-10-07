import Foundation

public struct VideoDownloadTarget: Sendable {
    public let url: URL
    public let platform: String

    public init?(_ content: String) {
        let regex = ParserUtilities.regex(#"https?://[^\s<>\"\\]+"#)
        let matches = regex.matches(in: content, range: NSRange(content.startIndex..<content.endIndex, in: content))
        guard matches.count == 1, let range = Range(matches[0].range, in: content) else { return nil }
        let text = String(content[range]).trimmingCharacters(in: CharacterSet(charactersIn: ".,;，。；!！)）]】"))
        guard let url = URL(string: text), let host = url.host?.lowercased(),
              url.user == nil, url.password == nil, !url.path.isEmpty, url.path != "/" else { return nil }
        func belongs(_ domain: String) -> Bool { host == domain || host.hasSuffix("." + domain) }
        let platform: String
        if (belongs("x.com") || belongs("twitter.com")) && url.path.contains("/status/") { platform = "X / Twitter" }
        else if belongs("b23.tv") || (belongs("bilibili.com") && url.path.hasPrefix("/video/")) { platform = tr("哔哩哔哩", "Bilibili") }
        else if host == "v.douyin.com" || (belongs("douyin.com") && url.path.hasPrefix("/video/")) { platform = tr("抖音", "Douyin") }
        else if host == "vm.tiktok.com" || host == "vt.tiktok.com" || (belongs("tiktok.com") && url.path.contains("/video/")) { platform = "TikTok" }
        else if belongs("youtu.be") || (belongs("youtube.com") && ["/watch", "/shorts/"].contains(where: { url.path.hasPrefix($0) })) { platform = "YouTube" }
        else if belongs("vimeo.com") { platform = "Vimeo" }
        else if ["mp4", "webm", "mov", "mkv", "m3u8"].contains(url.pathExtension.lowercased()) { platform = tr("视频直链", "Direct video") }
        else { return nil }
        self.url = url
        self.platform = platform
    }
}

struct VideoDownloadParser: ContentParser {
    let name = "Video Download"

    func parse(_ content: String, previousContent: String) -> [ParseResult] {
        guard let target = VideoDownloadTarget(content) else { return [] }
        let text = [labeled("平台", "Platform", target.platform),
                    labeled("画质", "Quality", tr("最高可用画质", "Highest available")),
                    labeled("保存目录", "Save to", "~/Downloads")].joined(separator: "\n")
        return [ParseResult(parserName: name, original: content, parsed: text)]
    }
}
