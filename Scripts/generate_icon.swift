import AppKit
import CoreGraphics
import Foundation

guard CommandLine.arguments.count >= 2 else {
    fputs("Usage: generate_icon.swift <output-icns-path>\n", stderr)
    exit(1)
}

let outputICNSPath = CommandLine.arguments[1]
let tempDir = FileManager.default.temporaryDirectory
    .appendingPathComponent("RawForgeIcon-\(UUID().uuidString)", isDirectory: true)
let iconsetURL = tempDir.appendingPathComponent("AppIcon.iconset", isDirectory: true)

try FileManager.default.createDirectory(at: iconsetURL, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: tempDir) }

let iconSpecs: [(name: String, px: Int)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024)
]

func renderIcon(size: Int) -> CGImage? {
    let s = CGFloat(size)
    let cs = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
    guard let ctx = CGContext(
        data: nil,
        width: size,
        height: size,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: cs,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else {
        return nil
    }

    ctx.setAllowsAntialiasing(true)
    ctx.setShouldAntialias(true)

    // macOS rounded squircle background
    let inset = s * 0.06
    let rect = CGRect(x: inset, y: inset, width: s - 2 * inset, height: s - 2 * inset)
    let cornerRadius = s * 0.21
    let bgPath = CGPath(roundedRect: rect, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)

    ctx.saveGState()
    ctx.addPath(bgPath)
    ctx.clip()

    // Studio dark charcoal vertical gradient
    let bgColors = [
        CGColor(colorSpace: cs, components: [0.16, 0.18, 0.22, 1.0])!,
        CGColor(colorSpace: cs, components: [0.08, 0.09, 0.11, 1.0])!
    ] as CFArray
    if let grad = CGGradient(colorsSpace: cs, colors: bgColors, locations: [0.0, 1.0]) {
        ctx.drawLinearGradient(grad, start: CGPoint(x: 0, y: s), end: CGPoint(x: 0, y: 0), options: [])
    }

    // Subtle radial highlight
    let glowColors = [
        CGColor(colorSpace: cs, components: [0.35, 0.62, 0.98, 0.24])!,
        CGColor(colorSpace: cs, components: [0.35, 0.62, 0.98, 0.0])!
    ] as CFArray
    if let glow = CGGradient(colorsSpace: cs, colors: glowColors, locations: [0.0, 1.0]) {
        ctx.drawRadialGradient(
            glow,
            startCenter: CGPoint(x: s * 0.5, y: s * 0.52),
            startRadius: s * 0.02,
            endCenter: CGPoint(x: s * 0.5, y: s * 0.52),
            endRadius: s * 0.48,
            options: []
        )
    }
    ctx.restoreGState()

    // Outer subtle metallic rim
    ctx.saveGState()
    ctx.addPath(bgPath)
    ctx.setStrokeColor(CGColor(colorSpace: cs, components: [1.0, 1.0, 1.0, 0.14])!)
    ctx.setLineWidth(max(1.0, s * 0.012))
    ctx.strokePath()
    ctx.restoreGState()

    // Lens outer barrel ring
    let center = CGPoint(x: s * 0.5, y: s * 0.5)
    let outerRadius = s * 0.31
    let ringRect = CGRect(x: center.x - outerRadius, y: center.y - outerRadius, width: outerRadius * 2, height: outerRadius * 2)
    ctx.saveGState()
    ctx.setStrokeColor(CGColor(colorSpace: cs, components: [0.85, 0.88, 0.94, 0.85])!)
    ctx.setLineWidth(max(1.2, s * 0.032))
    ctx.strokeEllipse(in: ringRect)
    ctx.restoreGState()

    // 6-blade color prism aperture
    let prismColors: [(CGFloat, CGFloat, CGFloat)] = [
        (0.98, 0.42, 0.32), // Warm Coral / Exposure
        (0.98, 0.72, 0.24), // Golden Hour Amber
        (0.32, 0.82, 0.55), // Emerald / Daylight
        (0.24, 0.76, 0.96), // Cyan / Cool Shade
        (0.36, 0.54, 0.98), // Cobalt / Metal
        (0.76, 0.44, 0.96)  // Violet / Tint
    ]
    let bladeCount = 6
    let innerR = s * 0.125
    let midR = s * 0.255

    for i in 0..<bladeCount {
        let a0 = CGFloat(i) * (.pi * 2.0 / CGFloat(bladeCount)) + .pi / 12.0
        let a1 = a0 + (.pi * 2.0 / CGFloat(bladeCount)) * 0.82
        let p0 = CGPoint(x: center.x + cos(a0) * innerR, y: center.y + sin(a0) * innerR)
        let p1 = CGPoint(x: center.x + cos(a0 + 0.35) * midR, y: center.y + sin(a0 + 0.35) * midR)
        let p2 = CGPoint(x: center.x + cos(a1 + 0.25) * midR, y: center.y + sin(a1 + 0.25) * midR)
        let p3 = CGPoint(x: center.x + cos(a1) * innerR, y: center.y + sin(a1) * innerR)

        let c = prismColors[i % prismColors.count]
        ctx.saveGState()
        ctx.beginPath()
        ctx.move(to: p0)
        ctx.addLine(to: p1)
        ctx.addLine(to: p2)
        ctx.addLine(to: p3)
        ctx.closePath()
        ctx.setFillColor(CGColor(colorSpace: cs, components: [c.0, c.1, c.2, 0.92])!)
        ctx.fillPath()
        ctx.restoreGState()
    }

    // Center dark glass pupil + highlight glint
    let pupilR = s * 0.105
    let pupilRect = CGRect(x: center.x - pupilR, y: center.y - pupilR, width: pupilR * 2, height: pupilR * 2)
    ctx.setFillColor(CGColor(colorSpace: cs, components: [0.06, 0.08, 0.12, 1.0])!)
    ctx.fillEllipse(in: pupilRect)

    let glintR = s * 0.032
    let glintRect = CGRect(x: center.x - pupilR * 0.45, y: center.y + pupilR * 0.18, width: glintR * 2, height: glintR * 2)
    ctx.setFillColor(CGColor(colorSpace: cs, components: [1.0, 1.0, 1.0, 0.65])!)
    ctx.fillEllipse(in: glintRect)

    return ctx.makeImage()
}

for spec in iconSpecs {
    guard let cg = renderIcon(size: spec.px) else {
        fputs("Failed rendering icon \(spec.name)\n", stderr)
        exit(1)
    }
    let rep = NSBitmapImageRep(cgImage: cg)
    guard let pngData = rep.representation(using: .png, properties: [:]) else {
        fputs("Failed PNG encoding \(spec.name)\n", stderr)
        exit(1)
    }
    try pngData.write(to: iconsetURL.appendingPathComponent(spec.name))
}

let outURL = URL(fileURLWithPath: outputICNSPath)
try FileManager.default.createDirectory(at: outURL.deletingLastPathComponent(), withIntermediateDirectories: true)

let proc = Process()
proc.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
proc.arguments = ["-c", "icns", iconsetURL.path, "-o", outURL.path]
try proc.run()
proc.waitUntilExit()
if proc.terminationStatus != 0 {
    fputs("iconutil failed with status \(proc.terminationStatus)\n", stderr)
    exit(proc.terminationStatus)
}
print("Generated \(outURL.path)")
