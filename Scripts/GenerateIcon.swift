import AppKit

let root = URL(fileURLWithPath: CommandLine.arguments[1])
let folder = root.appendingPathComponent("Shared/Assets.xcassets/AppIcon.appiconset")
try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
let image = NSImage(size: NSSize(width: 1024, height: 1024))
image.lockFocus()
NSColor(calibratedRed: 0.025, green: 0.07, blue: 0.10, alpha: 1).setFill()
NSBezierPath(rect: NSRect(x: 0, y: 0, width: 1024, height: 1024)).fill()
NSGradient(starting: NSColor(calibratedRed: 0.07, green: 0.18, blue: 0.24, alpha: 1), ending: .black)!
    .draw(in: NSBezierPath(rect: NSRect(x: 0, y: 0, width: 1024, height: 1024)), angle: -60)
let rear = NSBezierPath(roundedRect: NSRect(x: 180, y: 330, width: 460, height: 480), xRadius: 55, yRadius: 55)
rear.lineWidth = 22; NSColor(calibratedRed: 0.24, green: 0.59, blue: 0.67, alpha: 1).setStroke(); rear.stroke()
let front = NSBezierPath(roundedRect: NSRect(x: 345, y: 215, width: 460, height: 480), xRadius: 55, yRadius: 55)
NSColor(calibratedRed: 0.025, green: 0.07, blue: 0.10, alpha: 1).setFill(); front.fill()
front.lineWidth = 25; NSColor(calibratedRed: 0.39, green: 0.91, blue: 0.96, alpha: 1).setStroke(); front.stroke()
let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 118, weight: .bold), .foregroundColor: NSColor.white]
("PSD" as NSString).draw(at: NSPoint(x: 451, y: 382), withAttributes: attributes)
image.unlockFocus()
var entries: [[String: String]] = []
for size in [16, 23, 32, 46, 48, 64, 96, 128, 256, 512, 1024] {
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    image.draw(in: NSRect(x: 0, y: 0, width: size, height: size)); NSGraphicsContext.restoreGraphicsState()
    try bitmap.representation(using: .png, properties: [:])!.write(to: folder.appendingPathComponent("icon\(size).png"))
}
entries.append(["idiom": "universal", "platform": "ios", "size": "1024x1024", "filename": "icon1024.png"])
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        entries.append(["idiom": "mac", "size": "\(size)x\(size)", "scale": "\(scale)x", "filename": "icon\(size * scale).png"])
    }
}
let contents: [String: Any] = ["images": entries, "info": ["author": "xcode", "version": 1]]
try JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys]).write(to: folder.appendingPathComponent("Contents.json"))
try Data("{\"info\":{\"author\":\"xcode\",\"version\":1}}".utf8).write(to: root.appendingPathComponent("Shared/Assets.xcassets/Contents.json"))
print("Generated app icons")
