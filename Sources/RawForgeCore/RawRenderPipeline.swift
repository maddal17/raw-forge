import CoreGraphics
import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation
import ImageIO
import Metal

/// Result returned by interactive loupe rendering including preview pixels, histogram, and camera WB baseline.
public struct LoupeRenderOutput: Sendable {
    public let image: CGImage
    public let histogram: HistogramData
    public let asShotTemperature: Float
    public let asShotTint: Float
    public let renderMilliseconds: Double
    public let renderedSize: CGSize
}

/// Pure CoreImage + CIRAWFilter processing graph for RAW decoding, group recipe grading, resizing, and watermarking.
public enum RawRenderPipeline {
    /// Builds the full-pipeline `CIImage` for a RAW or standard photo URL.
    public static func buildCIImage(
        url: URL,
        isRaw: Bool,
        recipe: EditRecipe,
        draftMode: Bool,
        scaleFactor: Double,
        resizeMode: ResizeMode = .original,
        maxLongEdgePixels: Int = 0,
        watermark: WatermarkSettings? = nil,
        cameraModel: String = ""
    ) -> (image: CIImage, asShotTemp: Float, asShotTint: Float)? {
        if isRaw, let rawFilter = CIRAWFilter(imageURL: url) {
            let asShotTemp = rawFilter.neutralTemperature
            let asShotTint = rawFilter.neutralTint
            configureRAWFilter(
                rawFilter,
                recipe: recipe,
                asShotTemp: asShotTemp,
                asShotTint: asShotTint,
                draftMode: draftMode,
                scaleFactor: scaleFactor
            )
            if let rawOut = rawFilter.outputImage,
               !rawOut.extent.isEmpty,
               rawOut.extent.width.isFinite,
               rawOut.extent.width > 0 {
                let final = finalizePostChain(
                    rawOut,
                    recipe: recipe,
                    resizeMode: resizeMode,
                    maxLongEdgePixels: maxLongEdgePixels,
                    watermark: watermark,
                    cameraModel: cameraModel
                )
                return (final, asShotTemp, asShotTint)
            }
        }

        // Standard raster fallback (or fallback if a RAW has unsupported raw decode)
        guard let base = CIImage(contentsOf: url, options: [.applyOrientationProperty: true]),
              !base.extent.isEmpty else {
            return nil
        }

        var working = base
        if scaleFactor < 0.999 && scaleFactor > 0.01 {
            let scale = CIFilter.lanczosScaleTransform()
            scale.inputImage = working
            scale.scale = Float(scaleFactor)
            scale.aspectRatio = 1.0
            if let scaled = scale.outputImage { working = scaled }
        }

        working = applyFallbackExposureAndWB(working, recipe: recipe, asShotTemp: 5500, asShotTint: 0)
        let final = finalizePostChain(
            working,
            recipe: recipe,
            resizeMode: resizeMode,
            maxLongEdgePixels: maxLongEdgePixels,
            watermark: watermark,
            cameraModel: cameraModel
        )
        return (final, 5500, 0)
    }

    /// Configures a `CIRAWFilter` instance cleanly against a stable camera baseline WB.
    public static func configureRAWFilter(
        _ raw: CIRAWFilter,
        recipe: EditRecipe,
        asShotTemp: Float,
        asShotTint: Float,
        draftMode: Bool,
        scaleFactor: Double
    ) {
        raw.isDraftModeEnabled = draftMode
        raw.scaleFactor = Float(max(0.05, min(1.0, scaleFactor)))
        raw.exposure = Float(max(-4.0, min(4.0, recipe.exposure)))
        raw.boostAmount = Float(max(0.0, min(1.0, recipe.rawToneBoost / 100.0)))
        raw.boostShadowAmount = Float(max(0.35, min(2.0, 1.0 + recipe.shadows / 200.0)))

        switch recipe.whiteBalanceMode {
        case .asShotOffset:
            raw.neutralTemperature = Float(max(2000.0, min(50000.0, Double(asShotTemp) + recipe.temperatureShift)))
            raw.neutralTint = Float(max(-150.0, min(150.0, Double(asShotTint) + recipe.tint)))
        case .customKelvin:
            raw.neutralTemperature = Float(max(2000.0, min(50000.0, recipe.customKelvin)))
            raw.neutralTint = Float(max(-150.0, min(150.0, recipe.tint)))
        }

        if raw.isSharpnessSupported {
            raw.sharpnessAmount = Float(max(0.0, min(1.0, recipe.sharpness / 100.0)))
        }
        if raw.isContrastSupported {
            raw.contrastAmount = Float(max(0.0, min(1.0, max(0.0, recipe.clarity) / 100.0)))
        }
        if raw.isDetailSupported {
            raw.detailAmount = Float(max(0.0, min(3.0, (max(0.0, recipe.clarity) / 100.0) * 1.4)))
        }
        if raw.isLuminanceNoiseReductionSupported {
            raw.luminanceNoiseReductionAmount = Float(max(0.0, min(1.0, recipe.luminanceNoiseReduction / 100.0)))
        }
        if raw.isColorNoiseReductionSupported {
            raw.colorNoiseReductionAmount = Float(max(0.0, min(1.0, recipe.colorNoiseReduction / 100.0)))
        }
        if raw.isLensCorrectionSupported {
            raw.isLensCorrectionEnabled = recipe.lensCorrection
        }
        if #available(macOS 16.0, *), raw.isHighlightRecoverySupported {
            raw.isHighlightRecoveryEnabled = recipe.highlightRecovery
        }
    }

    /// Applies post-RAW tone/color filters, optional resize, and optional author watermark.
    public static func finalizePostChain(
        _ input: CIImage,
        recipe: EditRecipe,
        resizeMode: ResizeMode = .original,
        maxLongEdgePixels: Int = 0,
        watermark: WatermarkSettings? = nil,
        cameraModel: String = ""
    ) -> CIImage {
        var current = applyPostFilters(input, recipe: recipe)

        if resizeMode == .maxLongEdge && maxLongEdgePixels >= 64 {
            let longEdge = max(current.extent.width, current.extent.height)
            if longEdge > CGFloat(maxLongEdgePixels) {
                let scaleFactor = CGFloat(maxLongEdgePixels) / longEdge
                let scaleFilter = CIFilter.lanczosScaleTransform()
                scaleFilter.inputImage = current
                scaleFilter.scale = Float(scaleFactor)
                scaleFilter.aspectRatio = 1.0
                if let resized = scaleFilter.outputImage {
                    current = resized
                }
            }
        }

        if let watermark, watermark.isEnabled {
            current = WatermarkRenderer.apply(watermark, to: current, cameraModel: cameraModel)
        }

        return current
    }

    public static func applyPostFilters(_ input: CIImage, recipe: EditRecipe) -> CIImage {
        var current = input

        // 1. Highlight recovery (<= 1.0) & Shadow lift/crush (-1...1)
        if recipe.highlights < -0.5 || abs(recipe.shadows) >= 0.5 {
            let hs = CIFilter.highlightShadowAdjust()
            hs.inputImage = current
            hs.highlightAmount = recipe.highlights < 0
                ? Float(max(0.3, 1.0 + recipe.highlights / 145.0))
                : 1.0
            hs.shadowAmount = Float(max(-1.0, min(1.0, recipe.shadows / 100.0)))
            if let out = hs.outputImage { current = out }
        }

        // 2. Tone curve for Blacks, Whites, and positive Highlight boost
        if abs(recipe.blacks) >= 0.5 || abs(recipe.whites) >= 0.5 || recipe.highlights > 0.5 {
            let tone = CIFilter.toneCurve()
            tone.inputImage = current
            let bLift = max(0.0, recipe.blacks / 450.0)
            let bCrush = max(0.0, -recipe.blacks / 450.0)
            let wBoost = max(0.0, recipe.whites / 500.0)
            let wPull = max(0.0, -recipe.whites / 450.0)
            let p1y = clamp(0.25 + recipe.blacks / 600.0, min: 0.05, max: 0.45)
            let p3y = clamp(0.75 + recipe.highlights / 600.0 + recipe.whites / 700.0, min: 0.55, max: 0.96)

            tone.point0 = CGPoint(x: bCrush, y: bLift)
            tone.point1 = CGPoint(x: 0.25, y: p1y)
            tone.point2 = CGPoint(x: 0.50, y: 0.50)
            tone.point3 = CGPoint(x: 0.75, y: p3y)
            tone.point4 = CGPoint(x: 1.0 - wBoost, y: 1.0 - wPull)
            if let out = tone.outputImage { current = out }
        }

        // 3. Global Contrast & Saturation
        if abs(recipe.contrast) >= 0.5 || abs(recipe.saturation) >= 0.5 {
            let cc = CIFilter.colorControls()
            cc.inputImage = current
            cc.contrast = Float(clamp(1.0 + recipe.contrast / 180.0, min: 0.4, max: 1.8))
            cc.saturation = Float(clamp(1.0 + recipe.saturation / 100.0, min: 0.0, max: 2.0))
            cc.brightness = 0.0
            if let out = cc.outputImage { current = out }
        }

        // 4. Vibrance
        if abs(recipe.vibrance) >= 0.5 {
            let vib = CIFilter.vibrance()
            vib.inputImage = current
            vib.amount = Float(clamp(recipe.vibrance / 100.0, min: -1.0, max: 1.0))
            if let out = vib.outputImage { current = out }
        }

        // 5. Vignette
        if abs(recipe.vignette) >= 0.5 {
            let vig = CIFilter.vignette()
            vig.inputImage = current
            vig.intensity = Float(clamp(-recipe.vignette / 60.0, min: -2.0, max: 2.0))
            vig.radius = 1.6
            if let out = vig.outputImage { current = out.cropped(to: current.extent) }
        }

        return current
    }

    public static func applyFallbackExposureAndWB(
        _ input: CIImage,
        recipe: EditRecipe,
        asShotTemp: Float,
        asShotTint: Float
    ) -> CIImage {
        var current = input

        if abs(recipe.exposure) >= 0.01 {
            let exp = CIFilter.exposureAdjust()
            exp.inputImage = current
            exp.ev = Float(recipe.exposure)
            if let out = exp.outputImage { current = out }
        }

        let targetTemp: Double
        if recipe.whiteBalanceMode == .customKelvin {
            targetTemp = recipe.customKelvin
        } else {
            targetTemp = Double(asShotTemp) + recipe.temperatureShift
        }
        let targetTint = Double(asShotTint) + recipe.tint

        if abs(targetTemp - Double(asShotTemp)) >= 10 || abs(targetTint - Double(asShotTint)) >= 0.5 {
            let wb = CIFilter.temperatureAndTint()
            wb.inputImage = current
            wb.neutral = CIVector(x: CGFloat(asShotTemp), y: CGFloat(asShotTint))
            wb.targetNeutral = CIVector(x: CGFloat(clamp(targetTemp, min: 2000, max: 25000)), y: CGFloat(targetTint))
            if let out = wb.outputImage { current = out }
        }

        return current
    }

    private static func clamp(_ val: Double, min minVal: Double, max maxVal: Double) -> Double {
        Swift.max(minVal, Swift.min(maxVal, val))
    }
}

/// Interactive Metal-backed loupe renderer that caches the active `CIRAWFilter` across live slider drags.
public actor InteractiveLoupeRenderer {
    private let context: CIContext
    private var cachedURL: URL?
    private var cachedFilter: CIRAWFilter?
    private var cachedAsShotTemp: Float = 5500
    private var cachedAsShotTint: Float = 0

    public init(metalDevice: MTLDevice? = MTLCreateSystemDefaultDevice()) {
        let workingCS = CGColorSpace(name: CGColorSpace.extendedLinearDisplayP3) ?? CGColorSpaceCreateDeviceRGB()
        if let metalDevice {
            self.context = CIContext(mtlDevice: metalDevice, options: [
                .workingColorSpace: workingCS,
                .workingFormat: CIFormat.RGBAh,
                .cacheIntermediates: true
            ])
        } else {
            self.context = CIContext(options: [
                .workingColorSpace: workingCS,
                .workingFormat: CIFormat.RGBAh,
                .cacheIntermediates: true
            ])
        }
    }

    public func clearCache() {
        cachedURL = nil
        cachedFilter = nil
    }

    /// Renders a photo for Mode 2 Big Preview, reusing the cached `CIRAWFilter` on repeated drags of the same photo.
    public func renderPreview(
        photo: PhotoItem,
        recipe: EditRecipe,
        maxEdgePixels: Int,
        draftMode: Bool,
        watermark: WatermarkSettings?
    ) -> LoupeRenderOutput? {
        let start = CFAbsoluteTimeGetCurrent()
        let longEdge = max(photo.dimensions.width, photo.dimensions.height)
        let computedScale: Double = longEdge > 0
            ? min(1.0, max(0.12, Double(maxEdgePixels) / Double(longEdge)))
            : 0.35

        var outputCI: CIImage?
        var baselineTemp: Float = photo.asShotTemperature
        var baselineTint: Float = photo.asShotTint

        if photo.isRaw {
            let filter: CIRAWFilter?
            if cachedURL == photo.url, let existing = cachedFilter {
                filter = existing
            } else if let created = CIRAWFilter(imageURL: photo.url) {
                cachedURL = photo.url
                cachedFilter = created
                cachedAsShotTemp = created.neutralTemperature
                cachedAsShotTint = created.neutralTint
                filter = created
            } else {
                filter = nil
            }

            if let filter {
                baselineTemp = cachedAsShotTemp
                baselineTint = cachedAsShotTint
                RawRenderPipeline.configureRAWFilter(
                    filter,
                    recipe: recipe,
                    asShotTemp: baselineTemp,
                    asShotTint: baselineTint,
                    draftMode: draftMode,
                    scaleFactor: computedScale
                )
                if let rawOut = filter.outputImage,
                   !rawOut.extent.isEmpty,
                   rawOut.extent.width.isFinite,
                   rawOut.extent.width > 0 {
                    outputCI = RawRenderPipeline.finalizePostChain(
                        rawOut,
                        recipe: recipe,
                        watermark: watermark,
                        cameraModel: photo.cameraMakeModel
                    )
                }
            }
        }

        if outputCI == nil,
           let base = CIImage(contentsOf: photo.url, options: [.applyOrientationProperty: true]),
           !base.extent.isEmpty {
            var working = base
            if computedScale < 0.999 {
                let scaleFilter = CIFilter.lanczosScaleTransform()
                scaleFilter.inputImage = working
                scaleFilter.scale = Float(computedScale)
                scaleFilter.aspectRatio = 1.0
                if let scaled = scaleFilter.outputImage { working = scaled }
            }
            working = RawRenderPipeline.applyFallbackExposureAndWB(
                working,
                recipe: recipe,
                asShotTemp: baselineTemp,
                asShotTint: baselineTint
            )
            outputCI = RawRenderPipeline.finalizePostChain(
                working,
                recipe: recipe,
                watermark: watermark,
                cameraModel: photo.cameraMakeModel
            )
        }

        guard let finalCI = outputCI, !finalCI.extent.isEmpty else { return nil }
        let srgbCS = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        guard let cgImage = context.createCGImage(
            finalCI,
            from: finalCI.extent,
            format: .RGBA8,
            colorSpace: srgbCS
        ) else {
            return nil
        }

        let histogram = computeHistogram(from: finalCI, colorSpace: srgbCS)
        let elapsedMs = (CFAbsoluteTimeGetCurrent() - start) * 1000.0
        return LoupeRenderOutput(
            image: cgImage,
            histogram: histogram,
            asShotTemperature: baselineTemp,
            asShotTint: baselineTint,
            renderMilliseconds: elapsedMs,
            renderedSize: CGSize(width: cgImage.width, height: cgImage.height)
        )
    }

    private func computeHistogram(from image: CIImage, colorSpace: CGColorSpace) -> HistogramData {
        let extent = image.extent
        guard extent.width >= 4 && extent.height >= 4 else { return .empty }
        let sampleSize = 72
        let scaleX = CGFloat(sampleSize) / extent.width
        let scaleY = CGFloat(sampleSize) / extent.height
        let normalized = image
            .transformed(by: CGAffineTransform(translationX: -extent.origin.x, y: -extent.origin.y))
            .transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))
        let targetRect = CGRect(x: 0, y: 0, width: sampleSize, height: sampleSize)
        var bytes = [UInt8](repeating: 0, count: sampleSize * sampleSize * 4)
        context.render(
            normalized,
            toBitmap: &bytes,
            rowBytes: sampleSize * 4,
            bounds: targetRect,
            format: .RGBA8,
            colorSpace: colorSpace
        )

        var rBins = [Double](repeating: 0, count: 64)
        var gBins = [Double](repeating: 0, count: 64)
        var bBins = [Double](repeating: 0, count: 64)
        var lBins = [Double](repeating: 0, count: 64)

        let count = sampleSize * sampleSize
        for i in 0..<count {
            let base = i * 4
            let r = bytes[base]
            let g = bytes[base + 1]
            let b = bytes[base + 2]
            rBins[Int(r >> 2)] += 1
            gBins[Int(g >> 2)] += 1
            bBins[Int(b >> 2)] += 1
            let lumInt = min(255, (54 * Int(r) + 183 * Int(g) + 19 * Int(b)) >> 8)
            lBins[lumInt >> 2] += 1
        }

        let peak = max(
            1.0,
            rBins[1..<63].max() ?? 1.0,
            gBins[1..<63].max() ?? 1.0,
            bBins[1..<63].max() ?? 1.0,
            lBins[1..<63].max() ?? 1.0
        )

        return HistogramData(
            red: rBins.map { min(1.0, $0 / peak) },
            green: gBins.map { min(1.0, $0 / peak) },
            blue: bBins.map { min(1.0, $0 / peak) },
            luminance: lBins.map { min(1.0, $0 / peak) }
        )
    }
}

/// Fast thumbnail generator that extracts embedded/RAW thumbnails and applies fast GPU recipe grading.
public actor ThumbnailGenerator {
    private let context: CIContext
    private var rawThumbnailCache: [URL: CGImage] = [:]

    public init(metalDevice: MTLDevice? = MTLCreateSystemDefaultDevice()) {
        if let metalDevice {
            self.context = CIContext(mtlDevice: metalDevice, options: [.cacheIntermediates: false])
        } else {
            self.context = CIContext(options: [.cacheIntermediates: false])
        }
    }

    public func clearCache() {
        rawThumbnailCache.removeAll()
    }

    /// Generates a medium-resolution thumbnail reflecting the group's current recipe.
    public func thumbnail(for photo: PhotoItem, recipe: EditRecipe, maxPixelSize: Int = 440) -> CGImage? {
        let baseThumb = extractBaseThumbnail(for: photo, maxPixelSize: maxPixelSize)
        guard let baseThumb else { return nil }
        guard recipe.hasAdjustments else { return baseThumb }

        var ci = CIImage(cgImage: baseThumb)
        ci = RawRenderPipeline.applyFallbackExposureAndWB(
            ci,
            recipe: recipe,
            asShotTemp: photo.asShotTemperature,
            asShotTint: photo.asShotTint
        )
        ci = RawRenderPipeline.applyPostFilters(ci, recipe: recipe)
        let cs = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        return context.createCGImage(ci, from: ci.extent, format: .RGBA8, colorSpace: cs) ?? baseThumb
    }

    private func extractBaseThumbnail(for photo: PhotoItem, maxPixelSize: Int) -> CGImage? {
        if let cached = rawThumbnailCache[photo.url] {
            return cached
        }
        guard let source = CGImageSourceCreateWithURL(photo.url as CFURL, nil) else {
            return nil
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageIfAbsent: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
        ]
        var thumb = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
        if thumb == nil, let raw = CIRAWFilter(imageURL: photo.url) {
            raw.isDraftModeEnabled = true
            let maxDim = max(photo.dimensions.width, photo.dimensions.height)
            raw.scaleFactor = maxDim > 0 ? Float(min(1.0, Double(maxPixelSize) / Double(maxDim))) : 0.2
            if let out = raw.outputImage, !out.extent.isEmpty {
                let cs = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
                thumb = context.createCGImage(out, from: out.extent, format: .RGBA8, colorSpace: cs)
            }
        }
        if let thumb {
            if rawThumbnailCache.count > 600 {
                rawThumbnailCache.removeAll()
            }
            rawThumbnailCache[photo.url] = thumb
        }
        return thumb
    }
}
