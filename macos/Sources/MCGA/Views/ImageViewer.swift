import AppKit
import SwiftUI

/// Drives a `ZoomableImageView` from buttons and shortcuts; the trackpad pinches and pans it directly.
@MainActor
final class ImageZoomController {
    fileprivate weak var scrollView: NSScrollView?

    func zoomIn() {
        zoom(to: (scrollView?.magnification ?? 1) * 1.5)
    }

    func zoomOut() {
        zoom(to: (scrollView?.magnification ?? 1) / 1.5)
    }

    func actualSize() {
        zoom(to: 1)
    }

    /// Shows the whole image without enlarging one that already fits.
    func zoomToFit() {
        guard let scrollView, let image = scrollView.documentView?.frame.size, image.width > 0, image.height > 0 else { return }
        // The whole frame, not the clip view: once the image fits, legacy scrollers hide and give their room back.
        let visible = scrollView.bounds.size
        zoom(to: min(1, visible.width / image.width, visible.height / image.height))
    }

    private func zoom(to magnification: CGFloat) {
        guard let scrollView else { return }
        let visible = scrollView.contentView.bounds
        scrollView.setMagnification(magnification, centeredAt: NSPoint(x: visible.midX, y: visible.midY))
    }
}

/// Pinch to zoom, two-finger scroll to pan and double-tap to smart zoom, as in Preview.
struct ZoomableImageView: NSViewRepresentable {
    let image: NSImage
    let controller: ImageZoomController

    func makeNSView(context: Context) -> ImageScrollView {
        let scrollView = ImageScrollView()
        scrollView.contentView = CenteringClipView()
        scrollView.drawsBackground = false
        scrollView.hasHorizontalScroller = true
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.allowsMagnification = true
        scrollView.minMagnification = 0.05
        scrollView.maxMagnification = 16
        let imageView = DraggableImageView(image: image)
        imageView.frame = NSRect(origin: .zero, size: image.size)
        scrollView.documentView = imageView
        controller.scrollView = scrollView
        scrollView.onFirstLayout = { [weak controller] in controller?.zoomToFit() }
        return scrollView
    }

    func updateNSView(_ scrollView: ImageScrollView, context: Context) {}
}

final class ImageScrollView: NSScrollView {
    /// Fitting needs the final viewport size, which only exists after the first layout.
    var onFirstLayout: (@MainActor () -> Void)?

    override func layout() {
        super.layout()
        if contentView.frame.width > 0, let onFirstLayout {
            self.onFirstLayout = nil
            onFirstLayout()
        }
    }
}

/// Dragging with the mouse pans, like Preview's hand tool.
final class DraggableImageView: NSImageView {
    private var lastDragLocation: NSPoint?

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .openHand)
    }

    override func mouseDown(with event: NSEvent) {
        lastDragLocation = event.locationInWindow
        NSCursor.closedHand.push()
    }

    override func mouseDragged(with event: NSEvent) {
        guard let last = lastDragLocation, let scrollView = enclosingScrollView else { return }
        let location = event.locationInWindow
        lastDragLocation = location
        // Window and image coordinates both grow upward, so the visible origin moves against the
        // pointer, scaled back to image points, and the spot under the pointer stays under it.
        let clipView = scrollView.contentView
        var origin = clipView.bounds.origin
        origin.x -= (location.x - last.x) / scrollView.magnification
        origin.y -= (location.y - last.y) / scrollView.magnification
        clipView.scroll(to: clipView.constrainBoundsRect(NSRect(origin: origin, size: clipView.bounds.size)).origin)
        scrollView.reflectScrolledClipView(clipView)
    }

    override func mouseUp(with event: NSEvent) {
        lastDragLocation = nil
        NSCursor.pop()
    }
}

/// A resizable window's worth of image: pinch, the controls or Preview's shortcuts zoom it, and
/// the trackpad or a mouse drag pans it.
struct ImageViewerView: View {
    let image: NSImage
    /// The file "Open in Preview" hands over: the copied file when there is one, else the stored preview.
    let url: URL
    @ObservedObject var preferences: AppPreferences
    let close: () -> Void
    @State private var controller = ImageZoomController()

    var body: some View {
        ZStack(alignment: .bottom) {
            ZoomableImageView(image: image, controller: controller)
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 64)
            controls
                .padding(.bottom, 14)
        }
        .background(Color(nsColor: .underPageBackgroundColor).ignoresSafeArea())
        .preferredColorScheme(preferences.theme.colorScheme)
    }

    private var controls: some View {
        HStack(spacing: 2) {
            button("minus.magnifyingglass", .zoomOut) { controller.zoomOut() }
                .keyboardShortcut("-", modifiers: .command)
            button("1.magnifyingglass", .actualSize) { controller.actualSize() }
                .keyboardShortcut("0", modifiers: .command)
            button("plus.magnifyingglass", .zoomIn) { controller.zoomIn() }
                .keyboardShortcut("=", modifiers: .command)
            button("arrow.down.right.and.arrow.up.left", .zoomToFit) { controller.zoomToFit() }
                .keyboardShortcut("9", modifiers: .command)
            Divider()
                .frame(height: 16)
                .padding(.horizontal, 4)
            button("arrow.up.forward.app", .openInPreview) { openInPreview() }
            button("xmark", .close, action: close)
                .keyboardShortcut(.escape, modifiers: [])
        }
        .padding(.horizontal, 6)
        .frame(height: 36)
        .background(Capsule().fill(.regularMaterial))
        .overlay(Capsule().strokeBorder(Color(nsColor: .separatorColor), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.1), radius: 8, y: 2)
    }

    private func button(_ symbol: String, _ help: TextKey, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
        }
        .buttonStyle(InteractiveIconButtonStyle())
        .help(preferences.text(help))
    }

    private func openInPreview() {
        let workspace = NSWorkspace.shared
        if let preview = workspace.urlForApplication(withBundleIdentifier: "com.apple.Preview") {
            workspace.open([url], withApplicationAt: preview, configuration: NSWorkspace.OpenConfiguration())
        } else {
            workspace.open(url)
        }
    }
}

/// Keeps an image smaller than the viewport centered instead of pinned to a corner.
final class CenteringClipView: NSClipView {
    override func constrainBoundsRect(_ proposedBounds: NSRect) -> NSRect {
        var rect = super.constrainBoundsRect(proposedBounds)
        if let document = documentView?.frame {
            if rect.width > document.width {
                rect.origin.x = (document.width - rect.width) / 2
            }
            if rect.height > document.height {
                rect.origin.y = (document.height - rect.height) / 2
            }
        }
        return rect
    }
}
