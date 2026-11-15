import CoreGraphics
import Foundation
import ImageIO

/// Scans folders or explicit file lists for valid camera RAW and raster photo files.
public enum FolderScanner {
    /// Scans a directory for supported photos and extracts fast ImageIO metadata concurrently.
    public static func scanFolder(
        _ folderURL: URL,
        includeSubfolders: Bool = false,
        includeStandardImages: Bool = false
    ) async throws -> [PhotoItem] {
        let candidateURLs = try collectCandidateURLs(
            in: folderURL,
            includeSubfolders: includeSubfolders,
            includeStandardImages: includeStandardImages
        )
        return await inspectFiles(candidateURLs, includeStandardImages: includeStandardImages)
    }

    /// Inspects a list of file URLs concurrently with bounded concurrency.
    public static func inspectFiles(
        _ urls: [URL],
        includeStandardImages: Bool = true
    ) async -> [PhotoItem] {
        let filtered = urls.filter { RawFormatCatalog.isSupportedFile($0, includeStandardImages: includeStandardImages) }
        guard !filtered.isEmpty else { return [] }

        let maxConcurrent = 8
        var items: [PhotoItem] = []
        items.reserveCapacity(filtered.count)

        await withTaskGroup(of: PhotoItem?.self) { group in
            var index = 0
            while index < min(maxConcurrent, filtered.count) {
                let url = filtered[index]
                group.addTask { inspectSingleFile(url) }
                index += 1
            }

            while let result = await group.next() {
                if let item = result {
                    items.append(item)
                }
                if index < filtered.count {
                    let url = filtered[index]
                    group.addTask { inspectSingleFile(url) }
                    index += 1
                }
            }
        }

        return items.sorted { $0.filename.localizedStandardCompare($1.filename) == .orderedAscending }
    }

    /// Validates a single URL via ImageIO and parses EXIF/TIFF dimensions, camera, and exposure summary.
    public static func inspectSingleFile(_ url: URL) -> PhotoItem? {
        let stdURL = url.standardizedFileURL
        let resolvedURL = stdURL.resolvingSymlinksInPath()
        guard let values = try? resolvedURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
              values.isRegularFile == true else {
            return nil
        }

        let fileSize = Int64(values.fileSize ?? 0)
        guard fileSize > 0 else { return nil }

        guard let source = CGImageSourceCreateWithURL(resolvedURL as CFURL, nil),
              CGImageSourceGetCount(source) > 0 else {
            // Rejects non-image files that happen to carry an extension like .raw
            return nil
        }

        let props = (CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any]) ?? [:]
        let tiff = props[kCGImagePropertyTIFFDictionary as String] as? [String: Any] ?? [:]
        let exif = props[kCGImagePropertyExifDictionary as String] as? [String: Any] ?? [:]

        let rawWidth = (props[kCGImagePropertyPixelWidth as String] as? NSNumber)?.doubleValue
            ?? (exif[kCGImagePropertyExifPixelXDimension as String] as? NSNumber)?.doubleValue
            ?? 0
        let rawHeight = (props[kCGImagePropertyPixelHeight as String] as? NSNumber)?.doubleValue
            ?? (exif[kCGImagePropertyExifPixelYDimension as String] as? NSNumber)?.doubleValue
            ?? 0

        let orientation = (props[kCGImagePropertyOrientation as String] as? NSNumber)?.intValue
            ?? (tiff[kCGImagePropertyTIFFOrientation as String] as? NSNumber)?.intValue
            ?? 1

        let orientedSize: CGSize = (orientation >= 5 && orientation <= 8)
            ? CGSize(width: rawHeight, height: rawWidth)
            : CGSize(width: rawWidth, height: rawHeight)

        let make = (tiff[kCGImagePropertyTIFFMake as String] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let model = (tiff[kCGImagePropertyTIFFModel as String] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        let cameraLabel: String
        if make.isEmpty && model.isEmpty {
            cameraLabel = "Unknown Camera"
        } else if !model.isEmpty && model.localizedCaseInsensitiveContains(make) {
            cameraLabel = model
        } else if make.isEmpty {
            cameraLabel = model
        } else if model.isEmpty {
            cameraLabel = make
        } else {
            cameraLabel = "\(make) \(model)"
        }

        let captureDate = parseExifDate(
            (exif[kCGImagePropertyExifDateTimeOriginal as String] as? String)
                ?? (exif[kCGImagePropertyExifDateTimeDigitized as String] as? String)
                ?? (tiff[kCGImagePropertyTIFFDateTime as String] as? String)
        )

        let exposureSummary = formatExposureSummary(exif: exif)
        let hasGPS = props[kCGImagePropertyGPSDictionary as String] != nil

        return PhotoItem(
            url: stdURL,
            filename: stdURL.lastPathComponent,
            fileExtension: stdURL.pathExtension.lowercased(),
            fileSizeBytes: fileSize,
            isRaw: RawFormatCatalog.isRawExtension(stdURL.pathExtension),
            dimensions: orientedSize,
            captureDate: captureDate,
            cameraMakeModel: cameraLabel,
            exposureSummary: exposureSummary,
            hasGPS: hasGPS
        )
    }

    private static func collectCandidateURLs(
        in folderURL: URL,
        includeSubfolders: Bool,
        includeStandardImages: Bool
    ) throws -> [URL] {
        let fm = FileManager.default
        let keys: [URLResourceKey] = [.isRegularFileKey, .isHiddenKey]

        if includeSubfolders {
            guard let enumerator = fm.enumerator(
                at: folderURL,
                includingPropertiesForKeys: keys,
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) else {
                return []
            }
            var urls: [URL] = []
            for case let fileURL as URL in enumerator {
                if RawFormatCatalog.isSupportedFile(fileURL, includeStandardImages: includeStandardImages) {
                    urls.append(fileURL)
                }
            }
            return urls
        } else {
            let contents = try fm.contentsOfDirectory(
                at: folderURL,
                includingPropertiesForKeys: keys,
                options: [.skipsHiddenFiles]
            )
            return contents.filter {
                RawFormatCatalog.isSupportedFile($0, includeStandardImages: includeStandardImages)
            }
        }
    }

    private static func formatExposureSummary(exif: [String: Any]) -> String {
        var parts: [String] = []
        if let focal = (exif[kCGImagePropertyExifFocalLength as String] as? NSNumber)?.doubleValue, focal > 0 {
            parts.append(String(format: "%.0fmm", focal))
        }
        if let fNumber = (exif[kCGImagePropertyExifFNumber as String] as? NSNumber)?.doubleValue, fNumber > 0 {
            parts.append(String(format: "f/%.1f", fNumber).replacingOccurrences(of: ".0", with: ""))
        }
        if let exposureTime = (exif[kCGImagePropertyExifExposureTime as String] as? NSNumber)?.doubleValue, exposureTime > 0 {
            if exposureTime < 1.0 {
                let denom = max(1, Int((1.0 / exposureTime).rounded()))
                parts.append("1/\(denom)s")
            } else {
                parts.append(String(format: "%.1fs", exposureTime))
            }
        }
        if let isos = exif[kCGImagePropertyExifISOSpeedRatings as String] as? [NSNumber], let iso = isos.first {
            parts.append("ISO \(iso.intValue)")
        }
        return parts.joined(separator: " · ")
    }

    private static func parseExifDate(_ raw: String?) -> Date? {
        guard let raw, !raw.isEmpty else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
        return formatter.date(from: raw)
    }
}
