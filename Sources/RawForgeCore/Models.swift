import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Catalog of supported camera RAW formats and optional standard raster formats.
public enum RawFormatCatalog: Sendable {
    public static let rawExtensions: Set<String> = [
        "dng", "cr2", "cr3", "crw",
        "nef", "nrw",
        "arw", "srf", "sr2",
        "raf",
        "rw2", "raw",
        "orf",
        "pef",
        "rwl",
        "3fr", "fff",
        "iiq", "mos",
        "srw",
        "erf", "mef", "mrw", "dcr", "kdc"
    ]

    public static let standardExtensions: Set<String> = [
        "jpg", "jpeg", "heic", "heif", "png", "tif", "tiff"
    ]

    public static func isRawExtension(_ ext: String) -> Bool {
        rawExtensions.contains(ext.lowercased())
    }

    public static func isSupportedFile(_ url: URL, includeStandardImages: Bool) -> Bool {
        let ext = url.pathExtension.lowercased()
        if rawExtensions.contains(ext) { return true }
        if includeStandardImages && standardExtensions.contains(ext) { return true }
        return false
    }
}

/// Target export file formats supported natively via ImageIO + Apple Silicon hardware encoders.
public enum ExportFormat: String, CaseIterable, Codable, Identifiable, Sendable {
    case jpeg
    case heic
    case png
    case tiff
    case avif
    case jp2

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .jpeg: return "JPEG (.jpg)"
        case .heic: return "HEIC (.heic)"
        case .png: return "PNG (.png)"
        case .tiff: return "TIFF (.tiff)"
        case .avif: return "AVIF (.avif)"
        case .jp2: return "JPEG 2000 (.jp2)"
        }
    }

    public var shortLabel: String {
        switch self {
        case .jpeg: return "JPG"
        case .heic: return "HEIC"
        case .png: return "PNG"
        case .tiff: return "TIFF"
        case .avif: return "AVIF"
        case .jp2: return "JP2"
        }
    }

    public var fileExtension: String {
        switch self {
        case .jpeg: return "jpg"
        case .heic: return "heic"
        case .png: return "png"
        case .tiff: return "tiff"
        case .avif: return "avif"
        case .jp2: return "jp2"
        }
    }

    public var utiIdentifier: String {
        switch self {
        case .jpeg: return UTType.jpeg.identifier
        case .heic: return UTType.heic.identifier
        case .png: return UTType.png.identifier
        case .tiff: return UTType.tiff.identifier
        case .avif: return "public.avif"
        case .jp2: return "public.jpeg-2000"
        }
    }

    public var supportsQuality: Bool {
        switch self {
        case .jpeg, .heic, .avif, .jp2: return true
        case .png, .tiff: return false
        }
    }

    public var supports16Bit: Bool {
        switch self {
        case .png, .tiff: return true
        case .jpeg, .heic, .avif, .jp2: return false
        }
    }
}

/// Output ICC color space options for exported photos.
public enum ExportColorSpace: String, CaseIterable, Codable, Identifiable, Sendable {
    case sRGB
    case displayP3
    case adobeRGB1998

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .sRGB: return "sRGB IEC61966-2.1"
        case .displayP3: return "Display P3"
        case .adobeRGB1998: return "Adobe RGB (1998)"
        }
    }

    public var cgColorSpace: CGColorSpace {
        switch self {
        case .sRGB:
            return CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        case .displayP3:
            return CGColorSpace(name: CGColorSpace.displayP3) ?? CGColorSpaceCreateDeviceRGB()
        case .adobeRGB1998:
            return CGColorSpace(name: CGColorSpace.adobeRGB1998) ?? CGColorSpaceCreateDeviceRGB()
        }
    }
}

/// Lightweight RGBA color value parsed from hex strings for cross-layer use.
public struct RGBAColor: Equatable, Sendable {
    public let r: Double
    public let g: Double
    public let b: Double
    public let a: Double

    public init(r: Double, g: Double, b: Double, a: Double = 1.0) {
        self.r = r
        self.g = g
        self.b = b
        self.a = a
    }

    public init(hex: String, fallback: RGBAColor = RGBAColor(r: 0.35, g: 0.65, b: 1.0, a: 1.0)) {
        var cleaned = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.hasPrefix("#") {
            cleaned.removeFirst()
        }
        guard cleaned.count == 6 || cleaned.count == 8, let value = UInt64(cleaned, radix: 16) else {
            self = fallback
            return
        }
        if cleaned.count == 6 {
            self.r = Double((value >> 16) & 0xFF) / 255.0
            self.g = Double((value >> 8) & 0xFF) / 255.0
            self.b = Double(value & 0xFF) / 255.0
            self.a = 1.0
        } else {
            self.r = Double((value >> 24) & 0xFF) / 255.0
            self.g = Double((value >> 16) & 0xFF) / 255.0
            self.b = Double((value >> 8) & 0xFF) / 255.0
            self.a = Double(value & 0xFF) / 255.0
        }
    }
}

/// Represents a discovered RAW or standard image file within the workspace folder.
public struct PhotoItem: Identifiable, Hashable, Codable, Sendable {
    public let id: UUID
    public let url: URL
    public let filename: String
    public let fileExtension: String
    public let fileSizeBytes: Int64
    public let isRaw: Bool
    public let dimensions: CGSize
    public let captureDate: Date?
    public let cameraMakeModel: String
    public let exposureSummary: String
    public let hasGPS: Bool
    public let asShotTemperature: Float
    public let asShotTint: Float

    public init(
        id: UUID? = nil,
        url: URL,
        filename: String? = nil,
        fileExtension: String? = nil,
        fileSizeBytes: Int64 = 0,
        isRaw: Bool? = nil,
        dimensions: CGSize = .zero,
        captureDate: Date? = nil,
        cameraMakeModel: String = "Unknown Camera",
        exposureSummary: String = "",
        hasGPS: Bool = false,
        asShotTemperature: Float = 5500,
        asShotTint: Float = 0
    ) {
        let resolvedURL = url.standardizedFileURL
        self.id = id ?? PhotoItem.deterministicID(for: resolvedURL.path)
        self.url = resolvedURL
        self.filename = filename ?? resolvedURL.lastPathComponent
        let ext = (fileExtension ?? resolvedURL.pathExtension).lowercased()
        self.fileExtension = ext
        self.fileSizeBytes = fileSizeBytes
        self.isRaw = isRaw ?? RawFormatCatalog.isRawExtension(ext)
        self.dimensions = dimensions
        self.captureDate = captureDate
        self.cameraMakeModel = cameraMakeModel
        self.exposureSummary = exposureSummary
        self.hasGPS = hasGPS
        self.asShotTemperature = asShotTemperature
        self.asShotTint = asShotTint
    }

    public var megapixels: Double {
        (Double(dimensions.width) * Double(dimensions.height)) / 1_000_000.0
    }

    public var formattedDimensions: String {
        guard dimensions.width > 0 && dimensions.height > 0 else { return "Unknown size" }
        return "\(Int(dimensions.width)) × \(Int(dimensions.height))"
    }

    public var formattedFileSize: String {
        ByteCountFormatter.string(fromByteCount: fileSizeBytes, countStyle: .file)
    }

    private static func deterministicID(for path: String) -> UUID {
        // Stable UUIDv5-style hash so selection & cache keys survive reloads
        var h1: UInt64 = 0xcbf29ce484222325
        var h2: UInt64 = 0x84222325cbf29ce4
        for byte in path.utf8 {
            h1 ^= UInt64(byte)
            h1 &*= 0x100000001b3
            h2 &+= UInt64(byte)
            h2 &*= 0x9e3779b97f4a7c15
        }
        var bytes = [UInt8](repeating: 0, count: 16)
        withUnsafeBytes(of: h1.bigEndian) { src in
            for i in 0..<8 { bytes[i] = src[i] }
        }
        withUnsafeBytes(of: h2.bigEndian) { src in
            for i in 0..<8 { bytes[8 + i] = src[i] }
        }
        bytes[6] = (bytes[6] & 0x0F) | 0x40
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }
}

/// Controls whether a group's white balance shifts relative to each photo's camera reading or pins a uniform Kelvin across the album.
public enum WhiteBalanceMode: String, CaseIterable, Codable, Identifiable, Sendable {
    case asShotOffset
    case customKelvin

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .asShotOffset: return "As Shot ± Offset"
        case .customKelvin: return "Match Fixed Kelvin"
        }
    }
}

/// Complete non-destructive RAW develop recipe shared by all photos in a Label Group.
public struct EditRecipe: Codable, Equatable, Hashable, Sendable {
    // Light & Tone
    public var exposure: Double = 0.0           // -4.0 ... +4.0 EV
    public var contrast: Double = 0.0           // -100 ... +100
    public var highlights: Double = 0.0         // -100 ... +100
    public var shadows: Double = 0.0            // -100 ... +100
    public var whites: Double = 0.0             // -100 ... +100
    public var blacks: Double = 0.0             // -100 ... +100
    public var rawToneBoost: Double = 100.0     // 0 ... 100 (CIRAWFilter boostAmount)

    // Color & White Balance
    public var whiteBalanceMode: WhiteBalanceMode = .asShotOffset
    public var temperatureShift: Double = 0.0   // -2000 ... +2000 K
    public var customKelvin: Double = 5500.0    // 2200 ... 12000 K
    public var tint: Double = 0.0               // -150 ... +150
    public var vibrance: Double = 0.0           // -100 ... +100
    public var saturation: Double = 0.0         // -100 ... +100

    // Detail & Optics
    public var sharpness: Double = 25.0         // 0 ... 100
    public var clarity: Double = 0.0            // 0 ... 100
    public var luminanceNoiseReduction: Double = 15.0 // 0 ... 100
    public var colorNoiseReduction: Double = 35.0     // 0 ... 100
    public var vignette: Double = 0.0           // -100 ... +100
    public var lensCorrection: Bool = true
    public var highlightRecovery: Bool = true

    public init() {}

    public static let neutral = EditRecipe()

    public var hasAdjustments: Bool {
        self != EditRecipe.neutral
    }

    public var summaryBadges: [String] {
        var badges: [String] = []
        if abs(exposure) >= 0.05 {
            badges.append(String(format: "%+.2f EV", exposure))
        }
        if whiteBalanceMode == .customKelvin {
            badges.append("\(Int(customKelvin.rounded()))K")
        } else if abs(temperatureShift) >= 50 {
            badges.append(String(format: "%+.0fK", temperatureShift))
        }
        if abs(contrast) >= 1 {
            badges.append(String(format: "Ctr %+.0f", contrast))
        }
        if abs(highlights) >= 1 {
            badges.append(String(format: "Hi %+.0f", highlights))
        }
        if abs(shadows) >= 1 {
            badges.append(String(format: "Shad %+.0f", shadows))
        }
        if abs(vibrance) >= 1 {
            badges.append(String(format: "Vib %+.0f", vibrance))
        }
        if abs(saturation) >= 1 {
            badges.append(String(format: "Sat %+.0f", saturation))
        }
        return Array(badges.prefix(4))
    }

    public func applying(trim: PhotoTrim?) -> EditRecipe {
        guard let trim, trim.hasTrim else { return self }
        var copy = self
        copy.exposure = max(-4.0, min(4.0, copy.exposure + trim.exposureTrim))
        if copy.whiteBalanceMode == .customKelvin {
            copy.customKelvin = max(2200, min(12000, copy.customKelvin + trim.temperatureTrim))
        } else {
            copy.temperatureShift = max(-2000, min(2000, copy.temperatureShift + trim.temperatureTrim))
        }
        return copy
    }
}

/// Built-in curated starting presets for common lighting scenarios.
public enum RecipePreset: String, CaseIterable, Identifiable, Sendable {
    case asShot
    case daylightCrisp
    case goldenHourGlow
    case indoorTungstenBalance
    case coolShadeFix
    case highISOClean
    case editorialMonochrome

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .asShot: return "As Shot (Neutral)"
        case .daylightCrisp: return "Daylight Crisp"
        case .goldenHourGlow: return "Golden Hour Glow"
        case .indoorTungstenBalance: return "Indoor Tungsten Fix"
        case .coolShadeFix: return "Cool Shade Warmth"
        case .highISOClean: return "High ISO Clean"
        case .editorialMonochrome: return "Editorial B&W"
        }
    }

    public var recipe: EditRecipe {
        var r = EditRecipe()
        switch self {
        case .asShot:
            return r
        case .daylightCrisp:
            r.contrast = 14
            r.highlights = -25
            r.shadows = 18
            r.clarity = 16
            r.vibrance = 14
            r.sharpness = 35
        case .goldenHourGlow:
            r.exposure = 0.15
            r.whiteBalanceMode = .customKelvin
            r.customKelvin = 6100
            r.tint = 8
            r.highlights = -30
            r.shadows = 28
            r.vibrance = 18
            r.vignette = -14
        case .indoorTungstenBalance:
            r.exposure = 0.45
            r.whiteBalanceMode = .customKelvin
            r.customKelvin = 3950
            r.tint = -4
            r.highlights = -20
            r.shadows = 35
            r.luminanceNoiseReduction = 35
            r.colorNoiseReduction = 55
        case .coolShadeFix:
            r.exposure = 0.25
            r.whiteBalanceMode = .customKelvin
            r.customKelvin = 6200
            r.tint = 6
            r.contrast = 12
            r.shadows = 22
            r.vibrance = 16
        case .highISOClean:
            r.exposure = 0.35
            r.highlights = -18
            r.shadows = 24
            r.contrast = 8
            r.luminanceNoiseReduction = 55
            r.colorNoiseReduction = 75
            r.sharpness = 20
        case .editorialMonochrome:
            r.contrast = 28
            r.highlights = -30
            r.shadows = 24
            r.whites = 12
            r.blacks = -14
            r.saturation = -100
            r.clarity = 22
            r.vignette = -18
        }
        return r
    }
}

/// Optional per-photo micro-offset layered on top of its assigned label group recipe.
public struct PhotoTrim: Codable, Equatable, Hashable, Sendable {
    public var exposureTrim: Double = 0.0     // -1.5 ... +1.5 EV
    public var temperatureTrim: Double = 0.0  // -800 ... +800 K

    public init(exposureTrim: Double = 0.0, temperatureTrim: Double = 0.0) {
        self.exposureTrim = exposureTrim
        self.temperatureTrim = temperatureTrim
    }

    public var hasTrim: Bool {
        abs(exposureTrim) > 0.005 || abs(temperatureTrim) > 1.0
    }
}

/// A named lighting/color label group that owns a shared EditRecipe applied to all tagged photos.
public struct LabelGroup: Identifiable, Codable, Equatable, Hashable, Sendable {
    public let id: UUID
    public var name: String
    public var colorHex: String
    public var shortcutNumber: Int?
    public var recipe: EditRecipe

    public init(
        id: UUID = UUID(),
        name: String,
        colorHex: String,
        shortcutNumber: Int? = nil,
        recipe: EditRecipe = EditRecipe()
    ) {
        self.id = id
        self.name = name
        self.colorHex = colorHex
        self.shortcutNumber = shortcutNumber
        self.recipe = recipe
    }

    public static let paletteHexes: [String] = [
        "#4F8EF7", "#F59E0B", "#EC4899", "#10B981", "#8B5CF6",
        "#06B6D4", "#EF4444", "#84CC16", "#F97316"
    ]

    public static func defaultLightingGroups() -> [LabelGroup] {
        [
            LabelGroup(
                id: UUID(uuidString: "11111111-1111-4111-8111-111111111101")!,
                name: "Daylight / Outdoor",
                colorHex: "#4F8EF7",
                shortcutNumber: 1,
                recipe: EditRecipe()
            ),
            LabelGroup(
                id: UUID(uuidString: "11111111-1111-4111-8111-111111111102")!,
                name: "Golden Hour",
                colorHex: "#F59E0B",
                shortcutNumber: 2,
                recipe: EditRecipe()
            ),
            LabelGroup(
                id: UUID(uuidString: "11111111-1111-4111-8111-111111111103")!,
                name: "Indoor Warm",
                colorHex: "#EC4899",
                shortcutNumber: 3,
                recipe: EditRecipe()
            ),
            LabelGroup(
                id: UUID(uuidString: "11111111-1111-4111-8111-111111111104")!,
                name: "Shade / Overcast",
                colorHex: "#10B981",
                shortcutNumber: 4,
                recipe: EditRecipe()
            ),
            LabelGroup(
                id: UUID(uuidString: "11111111-1111-4111-8111-111111111105")!,
                name: "Night / High ISO",
                colorHex: "#8B5CF6",
                shortcutNumber: 5,
                recipe: EditRecipe()
            )
        ]
    }
}

public enum WatermarkPosition: String, CaseIterable, Codable, Identifiable, Sendable {
    case topLeft, topCenter, topRight
    case middleLeft, center, middleRight
    case bottomLeft, bottomCenter, bottomRight
    case tiledDiagonal

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .topLeft: return "Top Left"
        case .topCenter: return "Top Center"
        case .topRight: return "Top Right"
        case .middleLeft: return "Middle Left"
        case .center: return "Center"
        case .middleRight: return "Middle Right"
        case .bottomLeft: return "Bottom Left"
        case .bottomCenter: return "Bottom Center"
        case .bottomRight: return "Bottom Right"
        case .tiledDiagonal: return "Tiled Diagonal"
        }
    }
}

public enum WatermarkFontStyle: String, CaseIterable, Codable, Identifiable, Sendable {
    case modernSans
    case editorialSerif
    case technicalMono

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .modernSans: return "Modern Sans"
        case .editorialSerif: return "Editorial Serif"
        case .technicalMono: return "Technical Mono"
        }
    }

    public var postScriptFontName: String {
        switch self {
        case .modernSans: return "HelveticaNeue-Medium"
        case .editorialSerif: return "Georgia-Italic"
        case .technicalMono: return "Menlo-Regular"
        }
    }
}

/// Author watermark configuration persisted in Settings and burned in during export/preview.
public struct WatermarkSettings: Codable, Equatable, Sendable {
    public var isEnabled: Bool = false
    public var authorText: String = "© {year} Author Name"
    public var logoImagePath: String = ""
    public var position: WatermarkPosition = .bottomRight
    public var fontStyle: WatermarkFontStyle = .modernSans
    public var sizePercent: Double = 3.0       // 1.0 ... 12.0 % of short edge
    public var opacity: Double = 0.80          // 0.05 ... 1.0
    public var marginPercent: Double = 2.5     // 0.5 ... 10.0 %
    public var textColorHex: String = "#FFFFFF"
    public var dropShadow: Bool = true
    public var backgroundPill: Bool = false

    public init() {}
}

/// Metadata addition and subtraction rules applied to exported files via ImageIO dictionaries.
public struct MetadataSettings: Codable, Equatable, Sendable {
    // Subtract
    public var stripAllOriginalMetadata: Bool = false
    public var removeGPS: Bool = false
    public var removeCameraSerialAndMakerNotes: Bool = false
    public var removeCaptureExif: Bool = false
    public var removeOriginalAttribution: Bool = false

    // Add / Override
    public var authorName: String = ""
    public var copyrightNotice: String = ""
    public var albumTitle: String = ""
    public var imageDescription: String = ""
    public var keywordsCSV: String = ""
    public var includeGroupNameAsKeyword: Bool = false
    public var creatorCredit: String = ""

    public init() {}

    public var hasAdditions: Bool {
        !authorName.trimmingCharacters(in: .whitespaces).isEmpty ||
        !copyrightNotice.trimmingCharacters(in: .whitespaces).isEmpty ||
        !albumTitle.trimmingCharacters(in: .whitespaces).isEmpty ||
        !imageDescription.trimmingCharacters(in: .whitespaces).isEmpty ||
        !keywordsCSV.trimmingCharacters(in: .whitespaces).isEmpty ||
        !creatorCredit.trimmingCharacters(in: .whitespaces).isEmpty ||
        includeGroupNameAsKeyword
    }

    public var hasSubtractions: Bool {
        stripAllOriginalMetadata || removeGPS || removeCameraSerialAndMakerNotes || removeCaptureExif || removeOriginalAttribution
    }
}

public enum ResizeMode: String, CaseIterable, Codable, Identifiable, Sendable {
    case original
    case maxLongEdge

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .original: return "Original Resolution"
        case .maxLongEdge: return "Fit Long Edge (px)"
        }
    }
}

public enum ExportScope: String, CaseIterable, Codable, Identifiable, Sendable {
    case allPhotos
    case selectedPhotos
    case labeledOnly
    case activeGroupOnly

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .allPhotos: return "All Photos in Folder"
        case .selectedPhotos: return "Selected Photos"
        case .labeledOnly: return "All Labeled Photos"
        case .activeGroupOnly: return "Active Group Only"
        }
    }
}

public enum FilenameCollisionPolicy: String, CaseIterable, Codable, Identifiable, Sendable {
    case incrementSuffix
    case overwrite

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .incrementSuffix: return "Auto-Number (_1, _2)"
        case .overwrite: return "Overwrite Existing"
        }
    }
}

/// Complete batch conversion configuration chosen by the user.
public struct ExportConfiguration: Codable, Equatable, Sendable {
    public var format: ExportFormat = .jpeg
    public var quality: Double = 0.92
    public var bitDepth16: Bool = false
    public var colorSpace: ExportColorSpace = .sRGB
    public var resizeMode: ResizeMode = .original
    public var maxLongEdgePixels: Int = 3840
    public var filenamePrefix: String = ""
    public var filenameSuffix: String = ""
    public var organizeIntoGroupSubfolders: Bool = false
    public var collisionPolicy: FilenameCollisionPolicy = .incrementSuffix
    public var manualWorkerCount: Int = 0 // 0 = Automatic Apple Silicon tuning

    public init() {}
}

/// 64-bin RGB + Luminance histogram sampled directly from rendered preview pixels.
public struct HistogramData: Equatable, Sendable {
    public let red: [Double]
    public let green: [Double]
    public let blue: [Double]
    public let luminance: [Double]

    public static let empty = HistogramData(
        red: [Double](repeating: 0, count: 64),
        green: [Double](repeating: 0, count: 64),
        blue: [Double](repeating: 0, count: 64),
        luminance: [Double](repeating: 0, count: 64)
    )
}

/// Live batch export telemetry snapshot streamed to the progress UI.
public struct BatchProgressSnapshot: Sendable {
    public let completedCount: Int
    public let totalCount: Int
    public let failedCount: Int
    public let elapsedSeconds: Double
    public let photosPerSecond: Double
    public let megapixelsPerSecond: Double
    public let activeWorkers: Int
    public let gpuName: String
    public let recentFile: String
    public let latestError: String?

    public init(
        completedCount: Int,
        totalCount: Int,
        failedCount: Int,
        elapsedSeconds: Double,
        photosPerSecond: Double,
        megapixelsPerSecond: Double,
        activeWorkers: Int,
        gpuName: String,
        recentFile: String,
        latestError: String?
    ) {
        self.completedCount = completedCount
        self.totalCount = totalCount
        self.failedCount = failedCount
        self.elapsedSeconds = elapsedSeconds
        self.photosPerSecond = photosPerSecond
        self.megapixelsPerSecond = megapixelsPerSecond
        self.activeWorkers = activeWorkers
        self.gpuName = gpuName
        self.recentFile = recentFile
        self.latestError = latestError
    }

    public var fractionCompleted: Double {
        guard totalCount > 0 else { return 0 }
        return Double(completedCount) / Double(totalCount)
    }
}

/// Final summary returned when a batch conversion job finishes or cancels.
public struct BatchExportResult: Sendable {
    public let succeededCount: Int
    public let failedCount: Int
    public let totalMegapixels: Double
    public let elapsedSeconds: Double
    public let outputDirectory: URL
    public let exportedFiles: [URL]
    public let errors: [String]
    public let wasCancelled: Bool
}
