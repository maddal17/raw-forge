import CoreGraphics
import CoreImage
import Foundation
import ImageIO

/// One unit of work in a mass batch conversion job.
public struct BatchWorkItem: Sendable {
    public let photo: PhotoItem
    public let recipe: EditRecipe
    public let groupName: String?

    public init(photo: PhotoItem, recipe: EditRecipe, groupName: String?) {
        self.photo = photo
        self.recipe = recipe
        self.groupName = groupName
    }
}

/// High-throughput Apple Silicon batch RAW conversion engine utilizing Metal `CIContextPool` and concurrent P-core workers.
public final class BatchConversionEngine: Sendable {
    private let contextPool: CIContextPool

    public init(contextPool: CIContextPool = CIContextPool()) {
        self.contextPool = contextPool
    }

    public func convertBatch(
        items: [BatchWorkItem],
        destinationDirectory: URL,
        configuration: ExportConfiguration,
        watermark: WatermarkSettings,
        metadata: MetadataSettings,
        onProgress: @escaping @Sendable (BatchProgressSnapshot) -> Void
    ) async throws -> BatchExportResult {
        let startTime = CFAbsoluteTimeGetCurrent()
        try FileManager.default.createDirectory(at: destinationDirectory, withIntermediateDirectories: true)

        let total = items.count
        let workerCount: Int
        if configuration.manualWorkerCount > 0 {
            workerCount = max(1, min(16, configuration.manualWorkerCount))
        } else {
            workerCount = contextPool.capabilities.optimalBatchConcurrency
        }

        let gpuName = contextPool.capabilities.metalDeviceName
        var completed = 0
        var failed = 0
        var totalMP = 0.0
        var exportedFiles: [URL] = []
        var errors: [String] = []
        var wasCancelled = false

        try await withThrowingTaskGroup(of: Result<(URL, Double), Error>.self) { group in
            var nextIndex = 0

            func enqueueOne() {
                guard nextIndex < items.count, !Task.isCancelled else { return }
                let item = items[nextIndex]
                nextIndex += 1
                group.addTask(priority: .userInitiated) { [self] in
                    if Task.isCancelled {
                        return .failure(CancellationError())
                    }
                    return await self.processSingleItem(
                        item,
                        destinationDirectory: destinationDirectory,
                        configuration: configuration,
                        watermark: watermark,
                        metadata: metadata
                    )
                }
            }

            for _ in 0..<min(workerCount, items.count) {
                enqueueOne()
            }

            for try await outcome in group {
                if Task.isCancelled {
                    wasCancelled = true
                    group.cancelAll()
                    break
                }

                completed += 1
                var recentName = ""
                var latestErr: String?

                switch outcome {
                case .success(let (outURL, mp)):
                    exportedFiles.append(outURL)
                    totalMP += mp
                    recentName = outURL.lastPathComponent
                case .failure(let error):
                    if error is CancellationError {
                        wasCancelled = true
                    } else {
                        failed += 1
                        let msg = error.localizedDescription
                        errors.append(msg)
                        latestErr = msg
                    }
                }

                let elapsed = max(0.001, CFAbsoluteTimeGetCurrent() - startTime)
                let snapshot = BatchProgressSnapshot(
                    completedCount: completed,
                    totalCount: total,
                    failedCount: failed,
                    elapsedSeconds: elapsed,
                    photosPerSecond: Double(completed) / elapsed,
                    megapixelsPerSecond: totalMP / elapsed,
                    activeWorkers: workerCount,
                    gpuName: gpuName,
                    recentFile: recentName,
                    latestError: latestErr
                )
                onProgress(snapshot)

                if !Task.isCancelled {
                    enqueueOne()
                }
            }
        }

        let elapsed = max(0.001, CFAbsoluteTimeGetCurrent() - startTime)
        return BatchExportResult(
            succeededCount: exportedFiles.count,
            failedCount: failed,
            totalMegapixels: totalMP,
            elapsedSeconds: elapsed,
            outputDirectory: destinationDirectory,
            exportedFiles: exportedFiles,
            errors: errors,
            wasCancelled: wasCancelled
        )
    }

    private func processSingleItem(
        _ item: BatchWorkItem,
        destinationDirectory: URL,
        configuration: ExportConfiguration,
        watermark: WatermarkSettings,
        metadata: MetadataSettings
    ) async -> Result<(URL, Double), Error> {
        let context = await contextPool.lease()
        defer { contextPool.release(context) }

        return autoreleasepool {
            do {
                let targetDir = resolveTargetDirectory(
                    base: destinationDirectory,
                    groupName: item.groupName,
                    organizeSubfolders: configuration.organizeIntoGroupSubfolders
                )
                try FileManager.default.createDirectory(at: targetDir, withIntermediateDirectories: true)

                guard let built = RawRenderPipeline.buildCIImage(
                    url: item.photo.url,
                    isRaw: item.photo.isRaw,
                    recipe: item.recipe,
                    draftMode: false,
                    scaleFactor: 1.0,
                    resizeMode: configuration.resizeMode,
                    maxLongEdgePixels: configuration.maxLongEdgePixels,
                    watermark: watermark,
                    cameraModel: item.photo.cameraMakeModel
                ) else {
                    throw NSError(
                        domain: "RawForgeBatch",
                        code: 1001,
                        userInfo: [NSLocalizedDescriptionKey: "Failed to decode \(item.photo.filename)"]
                    )
                }

                let renderFormat: CIFormat = (configuration.bitDepth16 && configuration.format.supports16Bit)
                    ? .RGBA16
                    : .RGBA8
                let colorSpace = configuration.colorSpace.cgColorSpace

                guard let cgImage = context.createCGImage(
                    built.image,
                    from: built.image.extent,
                    format: renderFormat,
                    colorSpace: colorSpace
                ) else {
                    throw NSError(
                        domain: "RawForgeBatch",
                        code: 1002,
                        userInfo: [NSLocalizedDescriptionKey: "Metal GPU failed rendering \(item.photo.filename)"]
                    )
                }

                // Read source metadata properties cleanly
                let sourceProps: [String: Any]
                if let src = CGImageSourceCreateWithURL(item.photo.url as CFURL, nil),
                   let rawProps = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [String: Any] {
                    sourceProps = rawProps
                } else {
                    sourceProps = [:]
                }

                let destProps = MetadataProcessor.buildDestinationProperties(
                    sourceProperties: sourceProps,
                    settings: metadata,
                    groupName: item.groupName,
                    format: configuration.format,
                    quality: configuration.quality
                )

                let finalURL = resolveDestinationURL(
                    directory: targetDir,
                    sourceFilename: item.photo.filename,
                    configuration: configuration
                )
                let tmpURL = targetDir.appendingPathComponent(".tmp-\(UUID().uuidString).\(configuration.format.fileExtension)")
                defer { try? FileManager.default.removeItem(at: tmpURL) }

                guard let dest = CGImageDestinationCreateWithURL(
                    tmpURL as CFURL,
                    configuration.format.utiIdentifier as CFString,
                    1,
                    nil
                ) else {
                    throw NSError(
                        domain: "RawForgeBatch",
                        code: 1003,
                        userInfo: [NSLocalizedDescriptionKey: "ImageIO cannot encode \(configuration.format.displayName) for \(item.photo.filename)"]
                    )
                }

                CGImageDestinationAddImage(dest, cgImage, destProps as CFDictionary)
                guard CGImageDestinationFinalize(dest) else {
                    throw NSError(
                        domain: "RawForgeBatch",
                        code: 1004,
                        userInfo: [NSLocalizedDescriptionKey: "ImageIO finalize failed for \(finalURL.lastPathComponent)"]
                    )
                }

                if FileManager.default.fileExists(atPath: finalURL.path) {
                    try FileManager.default.removeItem(at: finalURL)
                }
                try FileManager.default.moveItem(at: tmpURL, to: finalURL)

                let mp = (Double(cgImage.width) * Double(cgImage.height)) / 1_000_000.0
                return .success((finalURL, mp))
            } catch {
                return .failure(error)
            }
        }
    }

    private func resolveTargetDirectory(
        base: URL,
        groupName: String?,
        organizeSubfolders: Bool
    ) -> URL {
        guard organizeSubfolders else { return base }
        let rawName = (groupName?.isEmpty == false) ? groupName! : "Unlabeled"
        let sanitized = rawName
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return base.appendingPathComponent(sanitized.isEmpty ? "Unlabeled" : sanitized, isDirectory: true)
    }

    private func resolveDestinationURL(
        directory: URL,
        sourceFilename: String,
        configuration: ExportConfiguration
    ) -> URL {
        let stem = (sourceFilename as NSString).deletingPathExtension
        let baseName = "\(configuration.filenamePrefix)\(stem)\(configuration.filenameSuffix)"
        let ext = configuration.format.fileExtension
        let candidate = directory.appendingPathComponent("\(baseName).\(ext)")

        if configuration.collisionPolicy == .overwrite || !FileManager.default.fileExists(atPath: candidate.path) {
            return candidate
        }

        var counter = 1
        while counter < 10_000 {
            let numbered = directory.appendingPathComponent("\(baseName)_\(counter).\(ext)")
            if !FileManager.default.fileExists(atPath: numbered.path) {
                return numbered
            }
            counter += 1
        }
        return directory.appendingPathComponent("\(baseName)_\(UUID().uuidString.prefix(6)).\(ext)")
    }
}
