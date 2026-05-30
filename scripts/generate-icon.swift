import AppKit
import CoreGraphics

let size = CGSize(width: 1024, height: 1024)
let image = NSImage(size: size)
image.lockFocus()

guard let context = NSGraphicsContext.current?.cgContext else { exit(1) }

// 1. Draw Background Squircle (Dark slate)
let bgRect = CGRect(x: 0, y: 0, width: 1024, height: 1024)
let bgPath = NSBezierPath(roundedRect: bgRect, xRadius: 230, yRadius: 230)
NSColor(calibratedRed: 0.12, green: 0.13, blue: 0.16, alpha: 1.0).setFill()
bgPath.fill()

// 2. Draw Clipboard Board (Slightly lighter gray)
let boardRect = CGRect(x: 212, y: 150, width: 600, height: 700)
let boardPath = NSBezierPath(roundedRect: boardRect, xRadius: 50, yRadius: 50)
NSColor(calibratedRed: 0.18, green: 0.20, blue: 0.24, alpha: 1.0).setFill()
boardPath.fill()

// 3. Draw Paper (Very dark gray/black)
let paperRect = CGRect(x: 250, y: 150, width: 524, height: 650)
let paperPath = NSBezierPath(roundedRect: paperRect, xRadius: 20, yRadius: 20)
NSColor(calibratedRed: 0.08, green: 0.09, blue: 0.11, alpha: 1.0).setFill()
paperPath.fill()

// 4. Draw Clip Metal Hardware
let clipRect = CGRect(x: 362, y: 800, width: 300, height: 80)
let clipPath = NSBezierPath(roundedRect: clipRect, xRadius: 30, yRadius: 30)
let gradient = NSGradient(colors: [NSColor(calibratedWhite: 0.7, alpha: 1.0), NSColor(calibratedWhite: 0.4, alpha: 1.0)])
gradient?.draw(in: clipPath, angle: -90)

let clipHole = CGRect(x: 487, y: 830, width: 50, height: 20)
let clipHolePath = NSBezierPath(roundedRect: clipHole, xRadius: 10, yRadius: 10)
NSColor(calibratedRed: 0.12, green: 0.13, blue: 0.16, alpha: 1.0).setFill()
clipHolePath.fill()

// 5. Draw Code text "{}"
let font1 = NSFont.monospacedSystemFont(ofSize: 220, weight: .bold)
let text1 = "{ }" as NSString
let attr1: [NSAttributedString.Key: Any] = [
    .font: font1,
    .foregroundColor: NSColor(calibratedRed: 0.35, green: 0.78, blue: 0.98, alpha: 1.0) // Cyan
]
let t1Size = text1.size(withAttributes: attr1)
text1.draw(at: NSPoint(x: 512 - t1Size.width / 2, y: 480), withAttributes: attr1)

// 6. Draw Code text ">_"
let font2 = NSFont.monospacedSystemFont(ofSize: 180, weight: .bold)
let text2 = ">_" as NSString
let attr2: [NSAttributedString.Key: Any] = [
    .font: font2,
    .foregroundColor: NSColor(calibratedRed: 0.20, green: 0.84, blue: 0.29, alpha: 1.0) // Neon Green
]
let t2Size = text2.size(withAttributes: attr2)
text2.draw(at: NSPoint(x: 512 - t2Size.width / 2, y: 280), withAttributes: attr2)

image.unlockFocus()

if let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff) {
    let png = bitmap.representation(using: .png, properties: [:])
    try? png?.write(to: URL(fileURLWithPath: "Packaging/icon_1024.png"))
}