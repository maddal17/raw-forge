import CoreGraphics
import CoreImage
import Foundation
import ImageIO
import Metal
import RawForgeCore

private struct VerifyFailure: Error, CustomStringConvertible {
    let description: String
    init(_ message: String, file: String = #fileID, line: Int = #line) {
        self.description = "\(file):\(line) — \(message)"
    }
}

private func expect(_ condition: @autoclosure () -> Bool, _ message: String, file: String = #fileID, line: Int = #line) throws {
    if !condition() {
        throw VerifyFailure(message, file: file, line: line)
    }
}

private func expectEqual<T: Equatable>(_ actual: T, _ expected: T, _ message: String = "", file: String = #fileID, line: Int = #line) throws {
    if actual != expected {
        let extra = message.isEmpty ? "" : " (\(message))"
        throw VerifyFailure("Expected \(expected), got \(actual)\(extra)", file: file, line: line)
    }
}

/// Computes average RGB values over a CGImage (or a specific sub-rect) for objective image assertions.
private func sampleAverageRGB(_ cgImage: CGImage, rect: CGRect? = nil) -> (r: Double, g: Double, b: Double) {
    let w = cgImage.width
    let h = cgImage.height
    let cs = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
    var bytes = [UInt8](repeating: 0, count: w * h * 4)
    guard let ctx = CGContext(
        data: &bytes,
        width: w,
        height: h,
        bitsPerComponent: 8,
        bytesPerRow: w * 4,
        space: cs,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else {
        return (0, 0, 0)
    }
    ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: w, height: h))

    let rRect = rect ?? CGRect(x: 0, y: 0, width: w, height: h)
    let minX = max(0, Int(rRect.minX))
    let maxX = min(w, Int(rRect.maxX))
    let minY = max(0, Int(rRect.minY))
    let maxY = min(h, Int(rRect.maxY))

    var sumR: Double = 0
    var sumG: Double = 0
    var sumB: Double = 0
    var count: Double = 0
    for y in minY..<maxY {
        for x in minX..<maxX {
            let idx = (y * w + x) * 4
            sumR += Double(bytes[idx])
            sumG += Double(bytes[idx + 1])
            sumB += Double(bytes[idx + 2])
            count += 1
        }
    }
    guard count > 0 else { return (0, 0, 0) }
    return (sumR / count, sumG / count, sumB / count)
}

/// Counts bright amber pixels (#F59E0B signature) within a region of a CGImage.
private func countAmberPixels(_ cgImage: CGImage, rect: CGRect? = nil) -> Int {
    let w = cgImage.width
    let h = cgImage.height
    let cs = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
    var bytes = [UInt8](repeating: 0, count: w * h * 4)
    guard let ctx = CGContext(
        data: &bytes,
        width: w,
        height: h,
        bitsPerComponent: 8,
        bytesPerRow: w * 4,
        space: cs,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else {
        return 0
    }
    ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: w, height: h))

    let rRect = rect ?? CGRect(x: 0, y: 0, width: w, height: h)
    let minX = max(0, Int(rRect.minX))
    let maxX = min(w, Int(rRect.maxX))
    let minY = max(0, Int(rRect.minY))
    let maxY = min(h, Int(rRect.maxY))

    var matches = 0
    for y in minY..<maxY {
        for x in minX..<maxX {
            let idx = (y * w + x) * 4
            if bytes[idx] > 180 && bytes[idx + 1] > 100 && bytes[idx + 2] < 70 {
                matches += 1
            }
        }
    }
    return matches
}

@main
struct RawForgeVerify {
    static func main() async {
        var passed = 0
        var failed = 0

        func run(_ name: String, _ block: () async throws -> Void) async {
            do {
                try await block()
                print("  [PASS] \(name)")
                passed += 1
            } catch {
                print("  [FAIL] \(name): \(error)")
                failed += 1
            }
        }

        print("=== RawForge Automated Verification Suite ===")

        // 1. Hardware & Metal Context Pool
        await run("1. Apple Silicon Hardware & Metal CIContextPool") {
            let hw = HardwareCapabilities.detect()
            print("         Detected: \(hw.summaryBadge) | GPU: \(hw.metalDeviceName)")
            try expect(hw.performanceCores > 0, "Expected > 0 performance cores")
            try expect(hw.optimalBatchConcurrency >= 2, "Expected batch concurrency >= 2")

            let pool = CIContextPool(capabilities: hw)
            print("         Metal device: \(pool.metalDevice?.name ?? "Software CoreImage fallback")")

            try await withThrowingTaskGroup(of: Bool.self) { group in
                for _ in 0..<8 {
                    group.addTask {
                        let leased = await pool.lease()
                        defer { pool.release(leased) }
                        let img = CIImage(color: CIColor(red: 0.5, green: 0.5, blue: 0.5))
                            .cropped(to: CGRect(x: 0, y: 0, width: 32, height: 32))
                        return leased.rawContext.createCGImage(img, from: img.extent) != nil
                    }
                }
                for try await ok in group {
                    try expect(ok, "CIContextPool render failed")
                }
            }
        }

        // 2. Synthetic Multi-Lighting DNG Album, Bogus .raw Rejection, & Group Recipe Grading
        await run("2. Synthetic DNG Album Scan, Bogus .raw Rejection & Group Recipes") {
            let tempRoot = FileManager.default.temporaryDirectory
                .appendingPathComponent("RawForgeVerify-Synth-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: tempRoot) }

            let created = try SampleRawGenerator.generateSampleAlbum(in: tempRoot, count: 8, width: 320, height: 240)
            try expectEqual(created.count, 8, "Should generate 8 DNGs")

            // Drop a bogus binary file with .raw extension to verify non-image .raw rejection
            let bogusURL = tempRoot.appendingPathComponent("bogus_disk.raw")
            try Data("NOT_A_CAMERA_RAW_IMAGE_FILE_0123456789".utf8).write(to: bogusURL)

            let scanned = try await FolderScanner.scanFolder(tempRoot, includeSubfolders: false, includeStandardImages: false)
            try expectEqual(scanned.count, 8, "Scanner must discover 8 valid DNGs and reject bogus.raw")
            try expect(scanned.allSatisfy { $0.dimensions == CGSize(width: 320, height: 240) }, "All DNG dimensions should be 320x240")
            try expect(scanned.allSatisfy { $0.hasGPS }, "Synthetic DNGs should expose GPS metadata before stripping")

            let renderer = InteractiveLoupeRenderer()
            let sample = scanned[0]

            var brightRecipe = EditRecipe()
            brightRecipe.exposure = 1.2
            brightRecipe.whiteBalanceMode = .customKelvin
            brightRecipe.customKelvin = 7500

            var darkRecipe = EditRecipe()
            darkRecipe.exposure = -0.5
            darkRecipe.whiteBalanceMode = .customKelvin
            darkRecipe.customKelvin = 3600

            let brightOut = await renderer.renderPreview(photo: sample, recipe: brightRecipe, maxEdgePixels: 320, draftMode: false, watermark: nil)
            let darkOut = await renderer.renderPreview(photo: sample, recipe: darkRecipe, maxEdgePixels: 320, draftMode: false, watermark: nil)
            try expect(brightOut != nil && darkOut != nil, "Both synthetic group renders must succeed")

            let brightRGB = sampleAverageRGB(brightOut!.image)
            let darkRGB = sampleAverageRGB(darkOut!.image)
            let brightLum = brightRGB.r + brightRGB.g + brightRGB.b
            let darkLum = darkRGB.r + darkRGB.g + darkRGB.b
            try expect(brightLum > darkLum + 30.0, "Group +1.2 EV must render measurably brighter than -0.5 EV")
            try expect((brightRGB.r / max(1, brightRGB.b)) > (darkRGB.r / max(1, darkRGB.b)),
                       "Fixed 7500K render must have warmer R/B ratio than 3600K render")
        }

        // 3. Author Watermark + Metadata Add/Subtract Across Export Formats (JPG, HEIC, 16-bit PNG, 16-bit TIFF, AVIF)
        await run("3. Watermark & Metadata Add/Subtract Across JPG/HEIC/PNG16/TIFF16/AVIF") {
            let tempRoot = FileManager.default.temporaryDirectory
                .appendingPathComponent("RawForgeVerify-Formats-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: tempRoot) }

            let dngURL = tempRoot.appendingPathComponent("TEST_001.dng")
            let dngData = SampleRawGenerator.makeLinearDNG(width: 480, height: 320, condition: .daylightOutdoor, includeGPS: true, serialNumber: "SN-TEST-9988")
            try dngData.write(to: dngURL)

            let items = await FolderScanner.inspectFiles([dngURL])
            try expectEqual(items.count, 1)
            let photo = items[0]

            // Watermark presence check on bottom-right quadrant
            let renderer = InteractiveLoupeRenderer()
            var wm = WatermarkSettings()
            wm.isEnabled = true
            wm.authorText = "© 2026 Studio Test"
            wm.position = .bottomRight
            wm.sizePercent = 6.0
            wm.opacity = 1.0
            wm.backgroundPill = true

            let plainOut = await renderer.renderPreview(photo: photo, recipe: EditRecipe(), maxEdgePixels: 480, draftMode: false, watermark: nil)!
            let wmOut = await renderer.renderPreview(photo: photo, recipe: EditRecipe(), maxEdgePixels: 480, draftMode: false, watermark: wm)!
            let cornerRect = CGRect(x: 240, y: 220, width: 240, height: 100)
            let plainCorner = sampleAverageRGB(plainOut.image, rect: cornerRect)
            let wmCorner = sampleAverageRGB(wmOut.image, rect: cornerRect)
            let diff = abs(plainCorner.r - wmCorner.r) + abs(plainCorner.g - wmCorner.g) + abs(plainCorner.b - wmCorner.b)
            try expect(diff > 1.5, "Watermarked bottom-right region must differ measurably from plain render (diff=\(diff))")

            // Regression checks for text-only #F59E0B, non-zero extent.origin, tiledDiagonal, SVG logo, and disabled toggle
            do {
                let verifyCtx = CIContext()
                let darkBase = CIImage(color: CIColor(red: 0.08, green: 0.10, blue: 0.14))
                    .cropped(to: CGRect(x: 0, y: 0, width: 480, height: 320))
                var amberWM = WatermarkSettings()
                amberWM.isEnabled = true
                amberWM.authorText = "© 2026 Studio Author"
                amberWM.position = .bottomRight
                amberWM.sizePercent = 4.5
                amberWM.opacity = 1.0
                amberWM.textColorHex = "#F59E0B"
                amberWM.dropShadow = true
                amberWM.backgroundPill = false

                let amberCI = WatermarkRenderer.apply(amberWM, to: darkBase)
                let amberCG = verifyCtx.createCGImage(amberCI, from: darkBase.extent)!
                let brAmber = countAmberPixels(amberCG, rect: CGRect(x: 240, y: 200, width: 240, height: 120))
                let tlAmber = countAmberPixels(amberCG, rect: CGRect(x: 0, y: 0, width: 240, height: 120))
                try expect(brAmber > 40, "Text-only #F59E0B watermark must render amber pixels in bottom-right (got \(brAmber))")
                try expectEqual(tlAmber, 0, "Bottom-right text watermark must leave top-left untouched")

                // Non-zero CIImage.extent.origin check
                let shiftedRect = CGRect(x: 48, y: -24, width: 480, height: 320)
                let shiftedBase = CIImage(color: CIColor(red: 0.08, green: 0.10, blue: 0.14)).cropped(to: shiftedRect)
                let shiftedCI = WatermarkRenderer.apply(amberWM, to: shiftedBase)
                let shiftedCG = verifyCtx.createCGImage(shiftedCI, from: shiftedRect)!
                let shiftedBR = countAmberPixels(shiftedCG, rect: CGRect(x: 240, y: 200, width: 240, height: 120))
                let shiftedTL = countAmberPixels(shiftedCG, rect: CGRect(x: 0, y: 0, width: 240, height: 120))
                try expect(shiftedBR > 40 && shiftedTL == 0, "Shifted extent watermark must land cleanly in bottom-right (br=\(shiftedBR), tl=\(shiftedTL))")

                // Tiled diagonal mode check
                var tiledWM = amberWM
                tiledWM.position = .tiledDiagonal
                tiledWM.sizePercent = 4.0
                let tiledCI = WatermarkRenderer.apply(tiledWM, to: darkBase)
                let tiledCG = verifyCtx.createCGImage(tiledCI, from: darkBase.extent)!
                let tiledCenter = countAmberPixels(tiledCG, rect: CGRect(x: 120, y: 80, width: 240, height: 160))
                let tiledTL = countAmberPixels(tiledCG, rect: CGRect(x: 0, y: 0, width: 200, height: 140))
                let tiledBR = countAmberPixels(tiledCG, rect: CGRect(x: 280, y: 180, width: 200, height: 140))
                try expect(tiledCenter > 20 && (tiledTL > 10 || tiledBR > 10),
                           "Tiled watermark must cover canvas regions (center=\(tiledCenter), tl=\(tiledTL), br=\(tiledBR))")

                // Disabled guard check
                var disabledWM = amberWM
                disabledWM.isEnabled = false
                let disabledCI = WatermarkRenderer.apply(disabledWM, to: darkBase)
                let disabledCG = verifyCtx.createCGImage(disabledCI, from: darkBase.extent)!
                try expectEqual(countAmberPixels(disabledCG), 0, "Disabled watermark must produce zero watermark pixels")

                // SVG vector logo rasterization check
                let svgURL = tempRoot.appendingPathComponent("amber-logo.svg")
                let svgContent = "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"64\" height=\"64\"><circle cx=\"32\" cy=\"32\" r=\"28\" fill=\"#F59E0B\"/></svg>"
                try Data(svgContent.utf8).write(to: svgURL)
                var svgWM = WatermarkSettings()
                svgWM.isEnabled = true
                svgWM.authorText = ""
                svgWM.logoImagePath = svgURL.path
                svgWM.position = .topLeft
                svgWM.sizePercent = 6.0
                svgWM.opacity = 1.0
                svgWM.dropShadow = false
                svgWM.backgroundPill = false
                let svgCI = WatermarkRenderer.apply(svgWM, to: darkBase)
                let svgCG = verifyCtx.createCGImage(svgCI, from: darkBase.extent)!
                let svgTL = countAmberPixels(svgCG, rect: CGRect(x: 0, y: 0, width: 160, height: 160))
                let svgBR = countAmberPixels(svgCG, rect: CGRect(x: 320, y: 160, width: 160, height: 160))
                try expect(svgTL > 40 && svgBR == 0, "SVG logo watermark must rasterize cleanly into top-left (tl=\(svgTL), br=\(svgBR))")
            }

            // Metadata rules: subtract GPS & Serial, add Author/Copyright/Keywords + GroupName
            var meta = MetadataSettings()
            meta.removeGPS = true
            meta.removeCameraSerialAndMakerNotes = true
            meta.authorName = "I. Photographer"
            meta.copyrightNotice = "© 2026 Studio"
            meta.keywordsCSV = "album, rawforge"
            meta.includeGroupNameAsKeyword = true

            let engine = BatchConversionEngine()
            let metalDevice = MTLCreateSystemDefaultDevice()
            let gpuName = metalDevice?.name ?? ""
            let isVirtualGPU = metalDevice == nil
                || gpuName.localizedCaseInsensitiveContains("paravirtual")
                || gpuName.localizedCaseInsensitiveContains("virtual")
                || gpuName.localizedCaseInsensitiveContains("software")
            let supportedDestTypes = Set((CGImageDestinationCopyTypeIdentifiers() as? [String]) ?? [])
            let formats: [(ExportFormat, Bool)] = [
                (.jpeg, false),
                (.heic, false),
                (.png, true),
                (.tiff, true),
                (.avif, false)
            ]

            for (format, bit16) in formats {
                let outDir = tempRoot.appendingPathComponent("out-\(format.fileExtension)", isDirectory: true)
                var cfg = ExportConfiguration()
                cfg.format = format
                cfg.bitDepth16 = bit16
                cfg.quality = 0.92

                let res = try await engine.convertBatch(
                    items: [BatchWorkItem(photo: photo, recipe: EditRecipe(), groupName: "Golden Hour")],
                    destinationDirectory: outDir,
                    configuration: cfg,
                    watermark: wm,
                    metadata: meta,
                    onProgress: { _ in }
                )
                let utiSupported = supportedDestTypes.contains(format.utiIdentifier)
                if (isVirtualGPU || !utiSupported) && (format == .heic || format == .avif) && res.succeededCount == 0 {
                    print("         [VM-NOTE] Skipping \(format.displayName) encode assertion (gpu=\(gpuName), utiSupported=\(utiSupported))")
                    continue
                }
                try expectEqual(res.succeededCount, 1, "Export failed for \(format.displayName)")
                let exportedURL = res.exportedFiles[0]
                let src = CGImageSourceCreateWithURL(exportedURL as CFURL, nil)!
                let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [String: Any] ?? [:]

                try expect(props[kCGImagePropertyGPSDictionary as String] == nil, "\(format): GPS must be stripped")
                let exif = props[kCGImagePropertyExifDictionary as String] as? [String: Any]
                try expect(exif?[kCGImagePropertyExifBodySerialNumber as String] == nil, "\(format): BodySerialNumber must be stripped")

                let orient = (props[kCGImagePropertyOrientation as String] as? NSNumber)?.intValue ?? 1
                try expectEqual(orient, 1, "\(format): Orientation must be normalized to 1")

                let tiff = props[kCGImagePropertyTIFFDictionary as String] as? [String: Any]
                try expectEqual(tiff?[kCGImagePropertyTIFFArtist as String] as? String, "I. Photographer", "\(format): Artist mismatch")
                try expectEqual(tiff?[kCGImagePropertyTIFFCopyright as String] as? String, "© 2026 Studio", "\(format): Copyright mismatch")

                let iptc = props[kCGImagePropertyIPTCDictionary as String] as? [String: Any]
                let keywords = iptc?[kCGImagePropertyIPTCKeywords as String] as? [String] ?? []
                try expect(keywords.contains("album") && keywords.contains("rawforge") && keywords.contains("Golden Hour"),
                           "\(format): Keywords missing expected entries, got \(keywords)")

                if bit16 {
                    let depth = (props[kCGImagePropertyDepth as String] as? NSNumber)?.intValue
                    try expectEqual(depth, 16, "\(format): Expected 16-bit export depth")
                }
            }
        }

        // 4. High-Resolution RAW Batch & Loupe Benchmark (uses RAWFORGE_SAMPLE_RAW if provided, else generated 2400x1600 16-bit DNG)
        await run("4. High-Resolution RAW Batch & Loupe Benchmark") {
            let tempRoot = FileManager.default.temporaryDirectory
                .appendingPathComponent("RawForgeVerify-RAWBatch-\(UUID().uuidString)", isDirectory: true)
            let inputDir = tempRoot.appendingPathComponent("input", isDirectory: true)
            let outputDir = tempRoot.appendingPathComponent("output", isDirectory: true)
            try FileManager.default.createDirectory(at: inputDir, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: tempRoot) }

            let sourceURL: URL
            let sourceExt: String
            if let envPath = ProcessInfo.processInfo.environment["RAWFORGE_SAMPLE_RAW"],
               !envPath.isEmpty,
               FileManager.default.fileExists(atPath: envPath) {
                sourceURL = URL(fileURLWithPath: envPath)
                sourceExt = sourceURL.pathExtension.isEmpty ? "raw" : sourceURL.pathExtension
            } else {
                let generatedURL = tempRoot.appendingPathComponent("benchmark_source.dng")
                let dng = SampleRawGenerator.makeLinearDNG(
                    width: 2400,
                    height: 1600,
                    condition: .goldenHour,
                    includeGPS: true,
                    serialNumber: "RF-BENCH-001"
                )
                try dng.write(to: generatedURL)
                sourceURL = generatedURL
                sourceExt = "dng"
            }

            let scanned = await FolderScanner.inspectFiles([sourceURL])
            try expectEqual(scanned.count, 1, "FolderScanner must inspect \(sourceURL.lastPathComponent)")
            let sourcePhoto = scanned[0]
            try expect(sourcePhoto.isRaw, "\(sourceURL.lastPathComponent) must be recognized as RAW")
            try expect(sourcePhoto.dimensions.width >= 1000 && sourcePhoto.dimensions.height >= 1000, "Expected high-resolution dimensions")

            // Loupe warmup + warm slider drag latency check
            let loupe = InteractiveLoupeRenderer()
            _ = await loupe.renderPreview(photo: sourcePhoto, recipe: EditRecipe(), maxEdgePixels: 1280, draftMode: true, watermark: nil)
            var dragRecipe = RecipePreset.goldenHourGlow.recipe
            dragRecipe.exposure = 0.65
            let warmOut = await loupe.renderPreview(photo: sourcePhoto, recipe: dragRecipe, maxEdgePixels: 1280, draftMode: true, watermark: nil)
            try expect(warmOut != nil, "Warm Metal draft render must succeed")
            let histNonZero = warmOut!.histogram.luminance.contains { $0 > 0 }
            try expect(histNonZero, "Histogram must contain non-zero luminance bins")
            print(String(format: "         Warm Loupe Draft Drag (%dx%d -> %dx%d): %.1f ms",
                         Int(sourcePhoto.dimensions.width), Int(sourcePhoto.dimensions.height),
                         Int(warmOut!.renderedSize.width), Int(warmOut!.renderedSize.height), warmOut!.renderMilliseconds))

            // 8-item parallel batch conversion using read-only symlinks in temp folder
            var batchItems: [BatchWorkItem] = []
            let groupRecipes: [(String, EditRecipe)] = [
                ("Daylight Crisp", RecipePreset.daylightCrisp.recipe),
                ("Golden Hour", RecipePreset.goldenHourGlow.recipe),
                ("Editorial B&W", RecipePreset.editorialMonochrome.recipe)
            ]

            for i in 1...8 {
                let linkURL = inputDir.appendingPathComponent(String(format: "sample_copy_%02d.%@", i, sourceExt))
                try FileManager.default.createSymbolicLink(at: linkURL, withDestinationURL: sourceURL)
                guard let photoCopy = FolderScanner.inspectSingleFile(linkURL) else {
                    throw VerifyFailure("inspectSingleFile returned nil for symlink \(linkURL.lastPathComponent)")
                }
                let chosen = groupRecipes[(i - 1) % groupRecipes.count]
                batchItems.append(BatchWorkItem(photo: photoCopy, recipe: chosen.1, groupName: chosen.0))
            }

            var wm = WatermarkSettings()
            wm.isEnabled = true
            wm.authorText = "© {year} {camera}"
            wm.position = .bottomRight

            var meta = MetadataSettings()
            meta.removeCameraSerialAndMakerNotes = true
            meta.authorName = "Batch Verification"
            meta.copyrightNotice = "© 2026 Batch Test"
            meta.includeGroupNameAsKeyword = true

            var cfg = ExportConfiguration()
            cfg.format = .jpeg
            cfg.quality = 0.90
            cfg.colorSpace = .displayP3

            let engine = BatchConversionEngine()
            let batchResult = try await engine.convertBatch(
                items: batchItems,
                destinationDirectory: outputDir,
                configuration: cfg,
                watermark: wm,
                metadata: meta,
                onProgress: { _ in }
            )

            try expectEqual(batchResult.succeededCount, 8, "All 8 full-res RAW conversions must succeed")
            try expectEqual(batchResult.failedCount, 0, "Expected 0 failures in RAW batch")

            let pps = Double(batchResult.succeededCount) / batchResult.elapsedSeconds
            let mpps = batchResult.totalMegapixels / batchResult.elapsedSeconds
            print(String(format: "         8x %.1fMP .%@ Batch -> Display P3 JPEG: %.2fs (%.2f photos/s, %.1f MP/s)",
                         sourcePhoto.megapixels, sourceExt.uppercased(), batchResult.elapsedSeconds, pps, mpps))

            // Verify first exported JPEG dimensions, serial stripped, author injected
            let firstOut = batchResult.exportedFiles[0]
            let src = CGImageSourceCreateWithURL(firstOut as CFURL, nil)!
            let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [String: Any] ?? [:]
            let w = (props[kCGImagePropertyPixelWidth as String] as? NSNumber)?.intValue
            let h = (props[kCGImagePropertyPixelHeight as String] as? NSNumber)?.intValue
            try expectEqual(w, Int(sourcePhoto.dimensions.width), "Exported width must match source")
            try expectEqual(h, Int(sourcePhoto.dimensions.height), "Exported height must match source")

            let exif = props[kCGImagePropertyExifDictionary as String] as? [String: Any]
            try expect(exif?[kCGImagePropertyExifBodySerialNumber as String] == nil, "BodySerialNumber must be stripped")
            let tiff = props[kCGImagePropertyTIFFDictionary as String] as? [String: Any]
            try expectEqual(tiff?[kCGImagePropertyTIFFArtist as String] as? String, "Batch Verification", "Author Artist tag must be injected")
        }

        print("=== Results: \(passed) passed, \(failed) failed ===")
        exit(failed == 0 ? 0 : 1)
    }
}
