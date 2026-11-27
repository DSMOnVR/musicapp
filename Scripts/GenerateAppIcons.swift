import AppKit
import Foundation

let root = URL(fileURLWithPath: "Sources/Assets.xcassets", isDirectory: true)
let icons: [(String, NSColor, NSColor)] = [
    ("AppIcon", NSColor(calibratedWhite: 0.10, alpha: 1), NSColor(calibratedWhite: 0.42, alpha: 1)),
    ("DSMMono", NSColor(calibratedWhite: 0.78, alpha: 1), NSColor(calibratedWhite: 0.18, alpha: 1)),
    ("DSMBlue", NSColor(calibratedRed: 0.10, green: 0.65, blue: 0.92, alpha: 1), NSColor(calibratedRed: 0.08, green: 0.18, blue: 0.48, alpha: 1)),
    ("DSMPurple", NSColor(calibratedRed: 0.66, green: 0.32, blue: 0.92, alpha: 1), NSColor(calibratedRed: 0.20, green: 0.10, blue: 0.42, alpha: 1))
]
try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
for (name, top, bottom) in icons {
    let folder = root.appendingPathComponent("\(name).appiconset", isDirectory: true)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let image = NSImage(size: NSSize(width: 1024, height: 1024))
    image.lockFocus()
    let rect = NSRect(x: 0, y: 0, width: 1024, height: 1024)
    NSGradient(starting: top, ending: bottom)?.draw(in: rect, angle: 90)
    let heights: [CGFloat] = [150, 280, 420, 330, 210, 390, 260]
    let width: CGFloat = 66, gap: CGFloat = 36
    let total = CGFloat(heights.count) * width + CGFloat(heights.count - 1) * gap
    let start = (1024 - total) / 2
    for (index, height) in heights.enumerated() {
        let x = start + CGFloat(index) * (width + gap)
        let bar = NSBezierPath(roundedRect: NSRect(x: x, y: (1024 - height) / 2, width: width, height: height), xRadius: 33, yRadius: 33)
        NSColor.white.withAlphaComponent(0.96).setFill()
        bar.fill()
    }
    image.unlockFocus()
    guard let tiff = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiff),
          let png = bitmap.representation(using: .png, properties: [:]) else { fatalError("Could not render \(name)") }
    try png.write(to: folder.appendingPathComponent("\(name).png"))
    let contents = """
    {
      "images": [{"filename": "\(name).png", "idiom": "universal", "platform": "ios", "size": "1024x1024"}],
      "info": {"author": "xcode", "version": 1}
    }
    """
    try contents.write(to: folder.appendingPathComponent("Contents.json"), atomically: true, encoding: .utf8)
}
