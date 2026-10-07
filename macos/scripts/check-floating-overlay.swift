import AppKit
import MCGACore
import SwiftUI

// After `swift build --product MCGACore`, run:
// swiftc -parse-as-library -I .build/out/Products/Debug -I .build/checkouts/Yams/Sources/CYaml/include scripts/check-floating-overlay.swift Sources/MCGA/AppPreferences.swift Sources/MCGA/VideoDownloadModel.swift Sources/MCGA/UIComponents.swift Sources/MCGA/Views/FloatingOverlayView.swift Sources/MCGA/Views/VideoDownloadView.swift Sources/MCGA/Views/VideoPreviewView.swift .build/out/Products/Debug/libMCGACore.a -o .build/check-floating-overlay
// .build/check-floating-overlay

@main
struct FloatingOverlayCheck {
    @MainActor
    static func main() throws {
        NSApplication.shared.setActivationPolicy(.prohibited)
        let first = ParseResult(parserName: "QiniuIP", original: "las-tky3", parsed: "IP:10.26.172.31")
        let regionText = """
        ap-northeast-2
        Region ID：ap-northeast-2
        中文名：日本（东京2）
        英文名：Japan(Tokyo2)
        中国大陆：否
        简称：tky2
        集群：las-ovn-bgp-las-tky1
        节点列表：
        - las-tky1
        - las-tky2
        - las-tky3
        - las-tky4
        """
        let region = ParseResult(parserName: "QiniuLASRegion", original: "las-tky3", parsed: "ap-northeast-2", details: regionText)
        let hosting = NSHostingView(rootView: FloatingOverlayView(
            content: "las-tky3", results: [first], category: { _ in .custom },
            preferences: AppPreferences(), countdown: OverlayCountdown(), maxHeight: 400,
            copy: { _ in }, showHistory: {}, close: {}
        ))
        let window = NSWindow(contentRect: .zero, styleMask: .borderless, backing: .buffered, defer: false)
        window.contentView = hosting

        func layout(until text: String) {
            let deadline = Date().addingTimeInterval(3)
            repeat {
                window.setContentSize(hosting.fittingSize)
                hosting.layoutSubtreeIfNeeded()
                if descendants(hosting).contains(where: { ($0 as? NSTextField)?.stringValue == text }) {
                    return
                }
                RunLoop.current.run(until: Date().addingTimeInterval(0.01))
            } while Date() < deadline
            fatalError("Result text was not rendered: \(text)")
        }

        layout(until: first.parsed)
        let singleHeight = hosting.fittingSize.height
        hosting.rootView.results = [first, region]
        layout(until: regionText)
        let fields = descendants(hosting).compactMap { $0 as? NSTextField }
        assert(fields.contains { $0.stringValue == first.parsed }, "The first result must remain visible")
        assert(fields.first { $0.stringValue == regionText }?.maximumNumberOfLines == 0, "Custom output must not be truncated")
        assert(hosting.fittingSize.height > singleHeight, "Late results must grow the overlay")
        assert(hosting.fittingSize.height <= 400, "The overlay must respect the height limit")

        if CommandLine.arguments.count > 1 {
            let bitmap = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds)!
            hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
            try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
        }

        let longText = (1...80).map { "- node-\($0)" }.joined(separator: "\n")
        hosting.rootView.results.append(ParseResult(parserName: "QiniuLASRegion", original: "las-tky3", parsed: "nodes", details: longText))
        layout(until: longText)
        assert(hosting.fittingSize.height <= 400, "Long output must respect the height limit")
        assert(descendants(hosting).contains { view in
            guard let scroll = view as? NSScrollView, let document = scroll.documentView else { return false }
            return document.bounds.height > scroll.contentView.bounds.height
        }, "Long results must have scrollable overflow")
        guard let screen = NSScreen.main else { fatalError("No screen available for placement check") }
        let presenter = FloatingOverlayPresenter()
        for id in UInt64(1)...2 {
            presenter.show(
                id: id, content: "placement-\(id)", results: [first], lifetime: 30,
                category: { _ in .custom }, preferences: hosting.rootView.preferences,
                copy: { _ in }, showHistory: {}
            )
        }
        let panels = NSApp.windows.compactMap { $0 as? NonActivatingOverlayPanel }
        defer { panels.forEach { $0.orderOut(nil) } }
        let newest = panels.first { ($0.contentView as? NSHostingView<FloatingOverlayView>)?.rootView.content == "placement-2" }!
        let older = panels.first { ($0.contentView as? NSHostingView<FloatingOverlayView>)?.rootView.content == "placement-1" }!
        let visible = screen.visibleFrame
        let top = visible.maxY - 8
        let right = visible.maxX - 8
        let gap = max(10, visible.height * 0.012)
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while abs(newest.frame.maxY - top) > 1 || abs(older.frame.maxY - (newest.frame.minY - gap)) > 1 {
            guard ContinuousClock.now < deadline else { fatalError("Panels did not stack downward from the top-right corner") }
            RunLoop.current.run(until: Date().addingTimeInterval(0.01))
        }
        assert(abs(newest.frame.maxX - right) <= 1 && abs(older.frame.maxX - right) <= 1, "Panels must stay 8 points from the right edge")
        let newestView = newest.contentView as! NSHostingView<FloatingOverlayView>
        newestView.rootView.close()
        assert(!newest.isVisible && older.isVisible, "Close must immediately dismiss only its own panel")
        presenter.show(
            id: 2, content: "placement-2", results: [first, region], lifetime: 30,
            category: { _ in .custom }, preferences: hosting.rootView.preferences,
            copy: { _ in }, showHistory: {}
        )
        assert(!newest.isVisible, "Late results must not reopen a dismissed panel")
        let closeDeadline = ContinuousClock.now.advanced(by: .seconds(3))
        while abs(older.frame.maxY - top) > 1 {
            guard ContinuousClock.now < closeDeadline else { fatalError("Remaining panel did not move up after close") }
            RunLoop.current.run(until: Date().addingTimeInterval(0.01))
        }
        print("PASS: all results, scrolling, top-right placement, immediate close, remaining panel layout, and no reopening for late results")
    }

    @MainActor
    static func descendants(_ view: NSView) -> [NSView] {
        [view] + view.subviews.flatMap(descendants)
    }
}
