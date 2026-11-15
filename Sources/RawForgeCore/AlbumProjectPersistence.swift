import CryptoKit
import Foundation

/// Persisted global application settings (watermark, metadata rules, export defaults, recent folders).
public struct GlobalAppSettings: Codable, Equatable, Sendable {
    public var watermark: WatermarkSettings = WatermarkSettings()
    public var metadata: MetadataSettings = MetadataSettings()
    public var exportConfig: ExportConfiguration = ExportConfiguration()
    public var includeStandardImages: Bool = false
    public var recentFolders: [String] = []

    public init() {}
}

/// Persisted per-folder album state (label groups + recipes, filename->group mapping, per-photo micro trims).
public struct FolderAlbumState: Codable, Equatable, Sendable {
    public var folderPath: String
    public var groups: [LabelGroup]
    public var assignmentsByFilename: [String: UUID]
    public var trimsByFilename: [String: PhotoTrim]
    public var lastSavedAt: Date

    public init(
        folderPath: String,
        groups: [LabelGroup] = LabelGroup.defaultLightingGroups(),
        assignmentsByFilename: [String: UUID] = [:],
        trimsByFilename: [String: PhotoTrim] = [:],
        lastSavedAt: Date = Date()
    ) {
        self.folderPath = folderPath
        self.groups = groups
        self.assignmentsByFilename = assignmentsByFilename
        self.trimsByFilename = trimsByFilename
        self.lastSavedAt = lastSavedAt
    }
}

/// Thread-safe JSON persistence backed by `~/Library/Application Support/RawForge`.
public enum AlbumProjectPersistence {
    private static var appSupportRoot: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent("RawForge", isDirectory: true)
    }

    private static var globalSettingsURL: URL {
        appSupportRoot.appendingPathComponent("global-settings.json")
    }

    private static var albumsDirectoryURL: URL {
        appSupportRoot.appendingPathComponent("Albums", isDirectory: true)
    }

    public static func loadGlobalSettings() -> GlobalAppSettings {
        guard let data = try? Data(contentsOf: globalSettingsURL),
              let decoded = try? JSONDecoder().decode(GlobalAppSettings.self, from: data) else {
            return GlobalAppSettings()
        }
        return decoded
    }

    public static func saveGlobalSettings(_ settings: GlobalAppSettings) {
        do {
            try FileManager.default.createDirectory(at: appSupportRoot, withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(settings)
            try data.write(to: globalSettingsURL, options: [.atomic])
        } catch {
            // Non-fatal persistence failure
        }
    }

    public static func loadAlbumState(for folderURL: URL) -> FolderAlbumState? {
        let url = albumFileURL(for: folderURL)
        guard let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode(FolderAlbumState.self, from: data) else {
            return nil
        }
        return decoded
    }

    public static func saveAlbumState(_ state: FolderAlbumState, for folderURL: URL) {
        do {
            try FileManager.default.createDirectory(at: albumsDirectoryURL, withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(state)
            try data.write(to: albumFileURL(for: folderURL), options: [.atomic])
        } catch {
            // Non-fatal persistence failure
        }
    }

    private static func albumFileURL(for folderURL: URL) -> URL {
        let canonical = folderURL.standardizedFileURL.path
        let digest = SHA256.hash(data: Data(canonical.utf8))
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        return albumsDirectoryURL.appendingPathComponent("\(hex).json")
    }
}
