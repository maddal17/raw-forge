import AppKit
import CoreGraphics
import CoreImage
import CoreText
import Foundation
import ImageIO

/// Composites configurable text and/or logo author watermarks directly onto CoreImage pipelines.
public enum WatermarkRenderer {
    public static func apply(
        _ settings: WatermarkSettings,
        to image: CIImage,
        cameraModel: String = ""
    ) -> CIImage {
        guard settings.isEnabled else { return image }

        let extent = image.extent
        guard extent.width >= 16, extent.height >= 16 else { return image }

        let expandedText = expandTokens(settings.authorText, cameraModel: cameraModel)
        let logoImage = loadLogoCGImage(from: settings.logoImagePath)

        guard !expandedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || logoImage != nil else {
            return image
        }

        let targetWidth = max(1, Int(extent.width.rounded()))
        let targetHeight = max(1, Int(extent.height.rounded()))
        let srgbCS = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()

        guard let rendered = renderOverlay(
            canvasWidth: targetWidth,
            canvasHeight: targetHeight,
            text: expandedText,
            logo: logoImage,
            settings: settings,
            colorSpace: srgbCS
        ) else {
            return image
        }

        let overlayCI = CIImage(cgImage: rendered.cgImage, options: [.colorSpace: srgbCS])
            .transformed(by: CGAffineTransform(
                translationX: extent.origin.x + rendered.offset.x,
                y: extent.origin.y + rendered.offset.y
            ))
        return overlayCI.composited(over: image).cropped(to: extent)
    }

    public static func expandTokens(_ template: String, cameraModel: String) -> String {
        let year = Calendar.current.component(.year, from: Date())
        return template
            .replacingOccurrences(of: "{year}", with: "\(year)")
            .replacingOccurrences(of: "{camera}", with: cameraModel.isEmpty ? "Camera" : cameraModel)
    }

    private static func loadLogoCGImage(from path: String) -> CGImage? {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let url = URL(fileURLWithPath: trimmed)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }

        if let src = CGImageSourceCreateWithURL(url as CFURL, nil),
           let cgImage = CGImageSourceCreateImageAtIndex(src, 0, nil) {
            return cgImage
        }

        // Vector logos (.svg / .pdf) via AppKit NSImage rasterization
        guard let nsImage = NSImage(contentsOf: url) else { return nil }
        let rawSize = nsImage.size
        let aspect = (rawSize.width > 0 && rawSize.height > 0) ? (rawSize.width / rawSize.height) : 1.0
        let targetHeight: CGFloat = 512.0
        let targetWidth = max(64.0, (targetHeight * aspect).rounded())
        let pixelW = Int(targetWidth)
        let pixelH = Int(targetHeight)

        let srgbCS = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil,
            width: pixelW,
            height: pixelH,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: srgbCS,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }

        ctx.clear(CGRect(x: 0, y: 0, width: pixelW, height: pixelH))
        var proposedRect = CGRect(x: 0, y: 0, width: pixelW, height: pixelH)
        let gfx = NSGraphicsContext(cgContext: ctx, flipped: false)
        if let cgFromNS = nsImage.cgImage(forProposedRect: &proposedRect, context: gfx, hints: nil) {
            return cgFromNS
        }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = gfx
        nsImage.draw(in: proposedRect, from: .zero, operation: .sourceOver, fraction: 1.0)
        NSGraphicsContext.restoreGraphicsState()
        return ctx.makeImage()
    }

    private static func makeBitmapContext(width: Int, height: Int, colorSpace: CGColorSpace) -> CGContext? {
        CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
    }

    private static func renderOverlay(
        canvasWidth: Int,
        canvasHeight: Int,
        text: String,
        logo: CGImage?,
        settings: WatermarkSettings,
        colorSpace cs: CGColorSpace
    ) -> (cgImage: CGImage, offset: CGPoint)? {
        let shortEdge = CGFloat(min(canvasWidth, canvasHeight))
        let fontSize = max(10.0, shortEdge * CGFloat(settings.sizePercent) / 100.0)
        let margin = shortEdge * CGFloat(settings.marginPercent) / 100.0

        let rgba = RGBAColor(hex: settings.textColorHex, fallback: RGBAColor(r: 1, g: 1, b: 1, a: 1))
        let cgTextColor = CGColor(
            colorSpace: cs,
            components: [CGFloat(rgba.r), CGFloat(rgba.g), CGFloat(rgba.b), 1.0]
        ) ?? CGColor(gray: 1.0, alpha: 1.0)

        let font = CTFontCreateWithName(settings.fontStyle.postScriptFontName as CFString, fontSize, nil)

        var ctLine: CTLine?
        var textBounds = CGRect.zero
        if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let attrs: [CFString: Any] = [
                kCTFontAttributeName: font,
                kCTForegroundColorAttributeName: cgTextColor
            ]
            let attrStr = CFAttributedStringCreate(kCFAllocatorDefault, text as CFString, attrs as CFDictionary)
            if let attrStr {
                let line = CTLineCreateWithAttributedString(attrStr)
                ctLine = line
                var ascent: CGFloat = 0
                var descent: CGFloat = 0
                var leading: CGFloat = 0
                let lineWidth = CGFloat(CTLineGetTypographicBounds(line, &ascent, &descent, &leading))
                textBounds = CGRect(x: 0, y: -descent, width: lineWidth, height: ascent + descent)
            }
        }

        // Compute logo size scaled cleanly to font cap height
        var logoSize = CGSize.zero
        if let logo, logo.width > 0, logo.height > 0 {
            let targetH = max(fontSize * 1.45, shortEdge * CGFloat(settings.sizePercent) / 100.0 * 1.45)
            let aspect = CGFloat(logo.width) / CGFloat(logo.height)
            logoSize = CGSize(width: targetH * aspect, height: targetH)
        }

        let gap: CGFloat = (logoSize.width > 0 && textBounds.width > 0) ? fontSize * 0.45 : 0
        let contentWidth = logoSize.width + gap + textBounds.width
        let contentHeight = max(logoSize.height, textBounds.height)
        guard contentWidth > 1 && contentHeight > 1 else { return nil }

        let pillPadX: CGFloat = settings.backgroundPill ? fontSize * 0.55 : 0
        let pillPadY: CGFloat = settings.backgroundPill ? fontSize * 0.35 : 0
        let stampSize = CGSize(width: contentWidth + pillPadX * 2, height: contentHeight + pillPadY * 2)

        func drawStamp(in ctx: CGContext, at origin: CGPoint) {
            ctx.saveGState()
            let stampRect = CGRect(origin: origin, size: stampSize)

            if settings.backgroundPill {
                let radius = min(stampRect.height * 0.32, 18.0)
                let path = CGPath(roundedRect: stampRect, cornerWidth: radius, cornerHeight: radius, transform: nil)
                ctx.setFillColor(CGColor(colorSpace: cs, components: [0.05, 0.05, 0.07, 0.58])!)
                ctx.addPath(path)
                ctx.fillPath()
            }

            if settings.dropShadow && !settings.backgroundPill {
                ctx.setShadow(
                    offset: CGSize(width: 0, height: -max(1.0, fontSize * 0.06)),
                    blur: max(2.0, fontSize * 0.14),
                    color: CGColor(colorSpace: cs, components: [0, 0, 0, 0.72])
                )
            }

            var cursorX = stampRect.minX + pillPadX
            if let logo, logoSize.width > 0 {
                let logoY = stampRect.minY + pillPadY + (contentHeight - logoSize.height) / 2.0
                ctx.draw(logo, in: CGRect(x: cursorX, y: logoY, width: logoSize.width, height: logoSize.height))
                cursorX += logoSize.width + gap
            }

            if let ctLine {
                let baselineY = stampRect.minY + pillPadY + (contentHeight - textBounds.height) / 2.0 - textBounds.origin.y
                ctx.textMatrix = .identity
                ctx.textPosition = CGPoint(x: cursorX, y: baselineY)
                CTLineDraw(ctLine, ctx)
            }
            ctx.restoreGState()
        }

        let alpha = CGFloat(max(0.05, min(1.0, settings.opacity)))

        if settings.position == .tiledDiagonal {
            guard let ctx = makeBitmapContext(width: canvasWidth, height: canvasHeight, colorSpace: cs) else {
                return nil
            }
            ctx.clear(CGRect(x: 0, y: 0, width: canvasWidth, height: canvasHeight))
            ctx.setAlpha(alpha)

            let stepX = max(stampSize.width * 1.9, CGFloat(canvasWidth) * 0.28)
            let stepY = max(stampSize.height * 3.0, CGFloat(canvasHeight) * 0.24)
            let diagonal = hypot(CGFloat(canvasWidth), CGFloat(canvasHeight))
            ctx.saveGState()
            ctx.translateBy(x: CGFloat(canvasWidth) / 2.0, y: CGFloat(canvasHeight) / 2.0)
            ctx.rotate(by: -CGFloat.pi / 6.0)
            var y = -diagonal * 0.65
            var row = 0
            while y < diagonal * 0.65 {
                var x = -diagonal * 0.65 + (row % 2 == 0 ? 0 : stepX * 0.5)
                while x < diagonal * 0.65 {
                    drawStamp(in: ctx, at: CGPoint(x: x - stampSize.width / 2.0, y: y - stampSize.height / 2.0))
                    x += stepX
                }
                y += stepY
                row += 1
            }
            ctx.restoreGState()
            guard let cgImage = ctx.makeImage() else { return nil }
            return (cgImage, .zero)
        } else {
            // Tight-stamp allocation avoids ~80 MB full-frame clear per photo on high-MP exports
            let shadowPad: CGFloat = (settings.dropShadow && !settings.backgroundPill)
                ? ceil(max(6.0, fontSize * 0.45))
                : 2.0
            let bitmapWidth = max(1, Int(ceil(stampSize.width + shadowPad * 2.0)))
            let bitmapHeight = max(1, Int(ceil(stampSize.height + shadowPad * 2.0)))

            guard let ctx = makeBitmapContext(width: bitmapWidth, height: bitmapHeight, colorSpace: cs) else {
                return nil
            }
            ctx.clear(CGRect(x: 0, y: 0, width: bitmapWidth, height: bitmapHeight))
            ctx.setAlpha(alpha)
            drawStamp(in: ctx, at: CGPoint(x: shadowPad, y: shadowPad))

            guard let cgImage = ctx.makeImage() else { return nil }
            let origin = anchorOrigin(
                position: settings.position,
                canvasSize: CGSize(width: canvasWidth, height: canvasHeight),
                stampSize: stampSize,
                margin: margin
            )
            return (cgImage, CGPoint(x: origin.x - shadowPad, y: origin.y - shadowPad))
        }
    }

    private static func anchorOrigin(
        position: WatermarkPosition,
        canvasSize: CGSize,
        stampSize: CGSize,
        margin: CGFloat
    ) -> CGPoint {
        let w = canvasSize.width
        let h = canvasSize.height
        let sw = stampSize.width
        let sh = stampSize.height

        let x: CGFloat
        switch position {
        case .topLeft, .middleLeft, .bottomLeft:
            x = margin
        case .topCenter, .center, .bottomCenter:
            x = (w - sw) / 2.0
        case .topRight, .middleRight, .bottomRight, .tiledDiagonal:
            x = max(margin, w - sw - margin)
        }

        // CoreGraphics origin is bottom-left
        let y: CGFloat
        switch position {
        case .bottomLeft, .bottomCenter, .bottomRight:
            y = margin
        case .middleLeft, .center, .middleRight:
            y = (h - sh) / 2.0
        case .topLeft, .topCenter, .topRight, .tiledDiagonal:
            y = max(margin, h - sh - margin)
        }

        return CGPoint(x: x, y: y)
    }
}
