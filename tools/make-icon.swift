// Generates a macOS .iconset (10 PNGs at the standard sizes) for the
// micflip app icon — `mic.fill` SF Symbol on an orange rounded square.
// Build the .icns from the output with:
//
//   iconutil -c icns <iconset-dir> -o micflip.icns
//
// Re-run only when you want to tweak the colour/glyph; the produced
// .icns is committed alongside the source.

import AppKit
import Foundation

let sizes: [(name: String, pixels: Int)] = [
    ("icon_16x16.png",      16),
    ("icon_16x16@2x.png",   32),
    ("icon_32x32.png",      32),
    ("icon_32x32@2x.png",   64),
    ("icon_128x128.png",    128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png",    256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png",    512),
    ("icon_512x512@2x.png", 1024),
]

guard CommandLine.arguments.count == 2 else {
    FileHandle.standardError.write(Data("usage: make-icon <iconset-output-dir>\n".utf8))
    exit(2)
}
let outDir = CommandLine.arguments[1]
try FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)

let background = NSColor(srgbRed: 1.0, green: 0.42, blue: 0.21, alpha: 1.0)

func render(pixels: Int) -> Data {
    let s = CGFloat(pixels)
    let img = NSImage(size: NSSize(width: s, height: s))
    img.lockFocus()

    let inset = s * 0.08
    let cornerRadius = s * 0.22
    let bgRect = NSRect(x: 0, y: 0, width: s, height: s).insetBy(dx: inset, dy: inset)
    background.setFill()
    NSBezierPath(roundedRect: bgRect, xRadius: cornerRadius, yRadius: cornerRadius).fill()

    let cfg = NSImage.SymbolConfiguration(pointSize: s * 0.5, weight: .semibold)
        .applying(NSImage.SymbolConfiguration(paletteColors: [.white]))
    if let mic = NSImage(systemSymbolName: "mic.fill", accessibilityDescription: nil)?
        .withSymbolConfiguration(cfg) {
        let m = mic.size
        mic.draw(in: NSRect(
            x: (s - m.width) / 2,
            y: (s - m.height) / 2,
            width: m.width,
            height: m.height
        ))
    }

    img.unlockFocus()
    let rep = NSBitmapImageRep(data: img.tiffRepresentation!)!
    return rep.representation(using: .png, properties: [:])!
}

for (name, pixels) in sizes {
    let png = render(pixels: pixels)
    try png.write(to: URL(fileURLWithPath: "\(outDir)/\(name)"))
}
