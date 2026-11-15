import AppKit
import Combine
import CoreGraphics
import Foundation
import RawForgeCore
import SwiftUI

enum WorkspaceMode: String, CaseIterable, Identifiable {
    case list
    case loupe

    var id: String { rawValue }

    var title: String {
        switch self {
        case .list: return "List & Label"
        case .loupe: return "Big Preview"
        }
    }

    var systemImage: String {
        switch self {
        case .list: return "rectangle.grid.1x2"
        case .loupe: return "photo.artframe"
        }
    }
}

enum ListPresentationStyle: String, CaseIterable, Identifiable {
    case mediumRows
    case mediumCards

    var id: String { rawValue }
}

enum PhotoSortOrder: String, CaseIterable, Identifiable {
    case filename = "Name"
    case captureDate = "Capture Time"
    case groupLabel = "Label Group"
    case fileSize = "File Size"

    var id: String { rawValue }
}

enum SidebarFilter: Hashable {
    case all
    case unlabeled
    case group(UUID)
}

enum SettingsTab: String, CaseIterable, Identifiable {
    case watermark = "Author Watermark"
    case metadata = "Metadata (Add / Subtract)"
    case engine = "Apple Silicon Engine"

    var id: String { rawValue }
}

struct PhotoSectionGroup: Identifiable {
    let id: String
    let group: LabelGroup?
    let title: String
    let colorHex: String
    let photos: [PhotoItem]
}

@MainActor
final class AppViewModel: ObservableObject {
    // Hardware & Engines
    let hardware: HardwareCapabilities = .detect()
    private let loupeRenderer: InteractiveLoupeRenderer
    private let thumbnailGenerator: ThumbnailGenerator
    private let batchEngine: BatchConversionEngine

    // Folder & Photo State
    @Published var currentFolderURL: URL?
    @Published var photos: [PhotoItem] = []
    @Published var groups: [LabelGroup] = LabelGroup.defaultLightingGroups()
    @Published var assignments: [UUID: UUID] = [:]
    @Published var trims: [UUID: PhotoTrim] = [:]
    @Published var clipboardRecipe: EditRecipe?

    // View Modes & Navigation
    @Published var workspaceMode: WorkspaceMode = .list
    @Published var listStyle: ListPresentationStyle = .mediumRows
    @Published var isGroupedByLabel: Bool = false
    @Published var collapsedSectionIDs: Set<String> = []
    @Published var previewSize: Double = 160
    @Published var sortOrder: PhotoSortOrder = .filename
    @Published var sidebarFilter: SidebarFilter = .all
    @Published var searchQuery: String = ""

    @Published var selectedPhotoIDs: Set<UUID> = []
    @Published var selectionAnchorID: UUID?
    @Published var activePhotoID: UUID?
    @Published var focusedGroupID: UUID?

    // Mode 2 Loupe Controls
    @Published var showBeforeOriginal: Bool = false
    @Published var previewWatermarkInLoupe: Bool = true
    @Published var autoAdvanceOnLabel: Bool = true
    @Published var zoomTo100: Bool = false

    // Rendered Previews & Telemetry
    @Published var thumbnails: [UUID: CGImage] = [:]
    @Published var activeLoupeImage: CGImage?
    @Published var activeHistogram: HistogramData = .empty
    @Published var lastRenderMilliseconds: Double = 0
    @Published var activeAsShotTemperature: Float = 5500
    @Published var activeAsShotTint: Float = 0

    // Loading & Status
    @Published var isScanning: Bool = false
    @Published var statusBanner: String?

    // Settings & Export
    @Published var globalSettings: GlobalAppSettings {
        didSet {
            AlbumProjectPersistence.saveGlobalSettings(globalSettings)
            scheduleLoupeRender(draft: false)
        }
    }
    @Published var isSettingsPresented: Bool = false
    @Published var settingsInitialTab: SettingsTab = .watermark
    @Published var isExportSheetPresented: Bool = false
    @Published var exportScope: ExportScope = .allPhotos
    @Published var exportDestinationURL: URL?
    @Published var isExporting: Bool = false
    @Published var exportProgress: BatchProgressSnapshot?
    @Published var exportResult: BatchExportResult?

    // Background Task Coordination
    private var loupeRenderTask: Task<Void, Never>?
    private var settleHighQualityTask: Task<Void, Never>?
    private var thumbnailRefreshTask: Task<Void, Never>?
    private var inFlightThumbnails: Set<UUID> = []
    private var exportTask: Task<Void, Never>?

    init() {
        let pool = CIContextPool(capabilities: hardware)
        self.loupeRenderer = InteractiveLoupeRenderer(metalDevice: pool.metalDevice)
        self.thumbnailGenerator = ThumbnailGenerator(metalDevice: pool.metalDevice)
        self.batchEngine = BatchConversionEngine(contextPool: pool)
        self.globalSettings = AlbumProjectPersistence.loadGlobalSettings()
    }

    // MARK: - Computed Collections

    var filteredPhotos: [PhotoItem] {
        var result = photos.filter { photo in
            switch sidebarFilter {
            case .all:
                break
            case .unlabeled:
                if assignments[photo.id] != nil { return false }
            case .group(let gid):
                if assignments[photo.id] != gid { return false }
            }

            let trimmed = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                let matchesName = photo.filename.localizedCaseInsensitiveContains(trimmed)
                let matchesCam = photo.cameraMakeModel.localizedCaseInsensitiveContains(trimmed)
                let groupName = group(for: photo.id)?.name ?? ""
                let matchesGroup = groupName.localizedCaseInsensitiveContains(trimmed)
                if !(matchesName || matchesCam || matchesGroup) {
                    return false
                }
            }
            return true
        }

        result.sort { lhs, rhs in
            switch sortOrder {
            case .filename:
                return lhs.filename.localizedStandardCompare(rhs.filename) == .orderedAscending
            case .captureDate:
                let ld = lhs.captureDate ?? .distantPast
                let rd = rhs.captureDate ?? .distantPast
                if ld != rd { return ld < rd }
                return lhs.filename.localizedStandardCompare(rhs.filename) == .orderedAscending
            case .groupLabel:
                let lg = group(for: lhs.id)?.name ?? "\u{FFFF}Unlabeled"
                let rg = group(for: rhs.id)?.name ?? "\u{FFFF}Unlabeled"
                if lg != rg { return lg.localizedStandardCompare(rg) == .orderedAscending }
                return lhs.filename.localizedStandardCompare(rhs.filename) == .orderedAscending
            case .fileSize:
                if lhs.fileSizeBytes != rhs.fileSizeBytes { return lhs.fileSizeBytes > rhs.fileSizeBytes }
                return lhs.filename.localizedStandardCompare(rhs.filename) == .orderedAscending
            }
        }
        return result
    }

    var sectionedPhotos: [PhotoSectionGroup] {
        let visible = filteredPhotos
        var sections: [PhotoSectionGroup] = []

        for grp in groups {
            let groupPhotos = visible.filter { assignments[$0.id] == grp.id }
            if !groupPhotos.isEmpty {
                sections.append(PhotoSectionGroup(
                    id: grp.id.uuidString,
                    group: grp,
                    title: grp.name,
                    colorHex: grp.colorHex,
                    photos: groupPhotos
                ))
            }
        }

        let unlabeled = visible.filter { assignments[$0.id] == nil }
        if !unlabeled.isEmpty {
            sections.append(PhotoSectionGroup(
                id: "unlabeled",
                group: nil,
                title: "Unlabeled",
                colorHex: "#6B7280",
                photos: unlabeled
            ))
        }
        return sections
    }

    var visibleOrderedPhotos: [PhotoItem] {
        if workspaceMode == .list && isGroupedByLabel {
            return sectionedPhotos.flatMap { $0.photos }
        }
        return filteredPhotos
    }

    var activePhoto: PhotoItem? {
        if let activePhotoID, let found = photos.first(where: { $0.id == activePhotoID }) {
            return found
        }
        return visibleOrderedPhotos.first
    }

    var inspectorTargetGroup: LabelGroup? {
        if let photo = activePhoto, let gid = assignments[photo.id],
           let found = groups.first(where: { $0.id == gid }) {
            return found
        }
        if case .group(let gid) = sidebarFilter,
           let found = groups.first(where: { $0.id == gid }) {
            return found
        }
        if let focusedGroupID, let found = groups.first(where: { $0.id == focusedGroupID }) {
            return found
        }
        let selectedGroupIDs = Set(selectedPhotoIDs.compactMap { assignments[$0] })
        if selectedGroupIDs.count == 1, let onlyID = selectedGroupIDs.first {
            return groups.first(where: { $0.id == onlyID })
        }
        return nil
    }

    var unlabeledCount: Int {
        photos.reduce(0) { $0 + (assignments[$1.id] == nil ? 1 : 0) }
    }

    func photoCount(in groupID: UUID) -> Int {
        photos.reduce(0) { $0 + (assignments[$1.id] == groupID ? 1 : 0) }
    }

    func group(for photoID: UUID) -> LabelGroup? {
        guard let gid = assignments[photoID] else { return nil }
        return groups.first(where: { $0.id == gid })
    }

    func effectiveRecipe(for photo: PhotoItem) -> EditRecipe {
        let base = group(for: photo.id)?.recipe ?? .neutral
        return base.applying(trim: trims[photo.id])
    }

    // MARK: - Folder & File Loading

    func openFolderPanel() {
        let panel = NSOpenPanel()
        panel.title = "Choose RAW Photo Folder"
        panel.message = "Select a folder containing camera RAW files (.RW2, .CR3, .NEF, .ARW, .RAF, .DNG, etc.)"
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            Task { await openDroppedOrSelectedURL(url) }
        }
    }

    func openDroppedOrSelectedURL(_ url: URL) async {
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) {
            if isDir.boolValue {
                await loadFolder(url: url)
            } else {
                let ext = url.pathExtension.lowercased()
                if RawFormatCatalog.standardExtensions.contains(ext) {
                    globalSettings.includeStandardImages = true
                }
                await loadFolder(url: url.deletingLastPathComponent(), selectFileURL: url)
            }
        }
    }

    func handleDroppedURLs(_ urls: [URL]) async {
        guard let first = urls.first else { return }
        if urls.count == 1 {
            await openDroppedOrSelectedURL(first)
            return
        }
        // Multiple files dropped directly
        isScanning = true
        statusBanner = nil
        let hasStandard = urls.contains { RawFormatCatalog.standardExtensions.contains($0.pathExtension.lowercased()) }
        let items = await FolderScanner.inspectFiles(urls, includeStandardImages: hasStandard || globalSettings.includeStandardImages)
        applyLoadedPhotos(items, folderURL: first.deletingLastPathComponent(), preselectURL: items.first?.url)
        isScanning = false
    }

    func loadFolder(url: URL, selectFileURL: URL? = nil) async {
        isScanning = true
        statusBanner = nil
        let includeStd = globalSettings.includeStandardImages

        do {
            let scanned = try await FolderScanner.scanFolder(
                url,
                includeSubfolders: false,
                includeStandardImages: includeStd
            )
            applyLoadedPhotos(scanned, folderURL: url, preselectURL: selectFileURL)
            recordRecentFolder(url)
        } catch {
            statusBanner = "Unable to scan folder: \(error.localizedDescription)"
        }
        isScanning = false
    }

    func reloadCurrentFolder() async {
        guard let url = currentFolderURL else { return }
        await loadFolder(url: url, selectFileURL: activePhoto?.url)
    }

    func generateAndLoadSampleAlbum() async {
        let baseDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Pictures/RawForge Sample Album", isDirectory: true)
        do {
            _ = try SampleRawGenerator.generateSampleAlbum(in: baseDir, count: 12, width: 720, height: 480)
            await loadFolder(url: baseDir)
            statusBanner = "Generated 12 sample 16-bit DNG RAWs across 4 lighting conditions in ~/Pictures/RawForge Sample Album"
        } catch {
            statusBanner = "Sample generation failed: \(error.localizedDescription)"
        }
    }

    private func applyLoadedPhotos(_ scanned: [PhotoItem], folderURL: URL, preselectURL: URL?) {
        currentFolderURL = folderURL.standardizedFileURL
        photos = scanned
        thumbnails.removeAll()
        inFlightThumbnails.removeAll()
        activeLoupeImage = nil
        activeHistogram = .empty
        selectedPhotoIDs.removeAll()
        sidebarFilter = .all

        Task { await thumbnailGenerator.clearCache() }
        Task { await loupeRenderer.clearCache() }

        if let saved = AlbumProjectPersistence.loadAlbumState(for: folderURL) {
            groups = saved.groups.isEmpty ? LabelGroup.defaultLightingGroups() : saved.groups
            var mappedAssignments: [UUID: UUID] = [:]
            var mappedTrims: [UUID: PhotoTrim] = [:]
            let groupIDSet = Set(groups.map { $0.id })

            for photo in scanned {
                if let gid = saved.assignmentsByFilename[photo.filename], groupIDSet.contains(gid) {
                    mappedAssignments[photo.id] = gid
                }
                if let trim = saved.trimsByFilename[photo.filename] {
                    mappedTrims[photo.id] = trim
                }
            }
            assignments = mappedAssignments
            trims = mappedTrims
        } else {
            groups = LabelGroup.defaultLightingGroups()
            assignments = [:]
            trims = [:]
        }

        if let preselectURL,
           let matched = scanned.first(where: { $0.url.standardizedFileURL == preselectURL.standardizedFileURL }) {
            activePhotoID = matched.id
            selectedPhotoIDs = [matched.id]
            selectionAnchorID = matched.id
        } else if let first = scanned.first {
            activePhotoID = first.id
            selectedPhotoIDs = [first.id]
            selectionAnchorID = first.id
        } else {
            activePhotoID = nil
            statusBanner = "No supported RAW files found in \(folderURL.lastPathComponent). Enable 'Include JPG/HEIC/PNG' in Settings if needed."
        }

        scheduleLoupeRender(draft: false)
    }

    private func recordRecentFolder(_ url: URL) {
        let path = url.standardizedFileURL.path
        var recents = globalSettings.recentFolders.filter { $0 != path }
        recents.insert(path, at: 0)
        globalSettings.recentFolders = Array(recents.prefix(8))
    }

    private func persistAlbumState() {
        guard let folderURL = currentFolderURL else { return }
        var byFilename: [String: UUID] = [:]
        var trimsByName: [String: PhotoTrim] = [:]
        for photo in photos {
            if let gid = assignments[photo.id] {
                byFilename[photo.filename] = gid
            }
            if let trim = trims[photo.id], trim.hasTrim {
                trimsByName[photo.filename] = trim
            }
        }
        let state = FolderAlbumState(
            folderPath: folderURL.path,
            groups: groups,
            assignmentsByFilename: byFilename,
            trimsByFilename: trimsByName
        )
        AlbumProjectPersistence.saveAlbumState(state, for: folderURL)
    }

    // MARK: - Selection & Navigation

    func handlePhotoClick(_ photo: PhotoItem, modifiers: NSEvent.ModifierFlags) {
        let ordered = visibleOrderedPhotos
        if modifiers.contains(.shift), let anchor = selectionAnchorID,
           let anchorIdx = ordered.firstIndex(where: { $0.id == anchor }),
           let targetIdx = ordered.firstIndex(where: { $0.id == photo.id }) {
            let low = min(anchorIdx, targetIdx)
            let high = max(anchorIdx, targetIdx)
            let rangeIDs = Set(ordered[low...high].map { $0.id })
            if modifiers.contains(.command) {
                selectedPhotoIDs.formUnion(rangeIDs)
            } else {
                selectedPhotoIDs = rangeIDs
            }
            setActivePhoto(photo.id)
        } else if modifiers.contains(.command) {
            if selectedPhotoIDs.contains(photo.id) {
                selectedPhotoIDs.remove(photo.id)
            } else {
                selectedPhotoIDs.insert(photo.id)
            }
            selectionAnchorID = photo.id
            setActivePhoto(photo.id)
        } else {
            selectedPhotoIDs = [photo.id]
            selectionAnchorID = photo.id
            setActivePhoto(photo.id)
        }
    }

    func toggleCheckbox(for photoID: UUID) {
        if selectedPhotoIDs.contains(photoID) {
            selectedPhotoIDs.remove(photoID)
        } else {
            selectedPhotoIDs.insert(photoID)
            selectionAnchorID = photoID
        }
        setActivePhoto(photoID)
    }

    func setActivePhoto(_ photoID: UUID?) {
        guard activePhotoID != photoID else { return }
        activePhotoID = photoID
        if let photoID, let gid = assignments[photoID] {
            focusedGroupID = gid
        }
        scheduleLoupeRender(draft: false)
    }

    func selectAllVisible() {
        selectedPhotoIDs = Set(visibleOrderedPhotos.map { $0.id })
    }

    func selectUnlabeledVisible() {
        selectedPhotoIDs = Set(visibleOrderedPhotos.filter { assignments[$0.id] == nil }.map { $0.id })
    }

    func selectAllInGroup(_ groupID: UUID) {
        selectedPhotoIDs = Set(photos.filter { assignments[$0.id] == groupID }.map { $0.id })
        focusedGroupID = groupID
    }

    func clearSelection() {
        selectedPhotoIDs.removeAll()
    }

    func stepActivePhoto(delta: Int) {
        let ordered = visibleOrderedPhotos
        guard !ordered.isEmpty else { return }
        let currentIndex = activePhotoID.flatMap { id in ordered.firstIndex(where: { $0.id == id }) } ?? 0
        let nextIndex = max(0, min(ordered.count - 1, currentIndex + delta))
        let target = ordered[nextIndex]
        selectedPhotoIDs = [target.id]
        selectionAnchorID = target.id
        setActivePhoto(target.id)
    }

    // MARK: - Group Management & Labeling

    func assignSelectedOrActive(to groupID: UUID?, advanceInLoupe: Bool = false) {
        let targetIDs: [UUID]
        if workspaceMode == .loupe {
            if selectedPhotoIDs.count > 1 {
                targetIDs = Array(selectedPhotoIDs)
            } else if let active = activePhoto {
                targetIDs = [active.id]
            } else {
                targetIDs = []
            }
        } else {
            if !selectedPhotoIDs.isEmpty {
                targetIDs = Array(selectedPhotoIDs)
            } else if let active = activePhoto {
                targetIDs = [active.id]
            } else {
                targetIDs = []
            }
        }
        guard !targetIDs.isEmpty else { return }

        for id in targetIDs {
            if let groupID {
                assignments[id] = groupID
            } else {
                assignments.removeValue(forKey: id)
            }
            thumbnails.removeValue(forKey: id)
        }
        if let groupID {
            focusedGroupID = groupID
        }

        persistAlbumState()
        for id in targetIDs {
            if let photo = photos.first(where: { $0.id == id }) {
                requestThumbnail(for: photo, force: true)
            }
        }
        scheduleLoupeRender(draft: false)

        if advanceInLoupe && workspaceMode == .loupe && autoAdvanceOnLabel {
            stepActivePhoto(delta: 1)
        }
    }

    func assignPhoto(_ photoID: UUID, to groupID: UUID?) {
        if let groupID {
            assignments[photoID] = groupID
            focusedGroupID = groupID
        } else {
            assignments.removeValue(forKey: photoID)
        }
        thumbnails.removeValue(forKey: photoID)
        persistAlbumState()
        if let photo = photos.first(where: { $0.id == photoID }) {
            requestThumbnail(for: photo, force: true)
        }
        if activePhotoID == photoID {
            scheduleLoupeRender(draft: false)
        }
    }

    func assignByShortcutNumber(_ number: Int) {
        if number == 0 {
            assignSelectedOrActive(to: nil, advanceInLoupe: true)
            return
        }
        if let match = groups.first(where: { $0.shortcutNumber == number }) {
            assignSelectedOrActive(to: match.id, advanceInLoupe: true)
        } else if number - 1 < groups.count {
            assignSelectedOrActive(to: groups[number - 1].id, advanceInLoupe: true)
        }
    }

    @discardableResult
    func addGroup(name: String, colorHex: String, initialRecipe: EditRecipe = EditRecipe()) -> LabelGroup {
        let usedShortcuts = Set(groups.compactMap { $0.shortcutNumber })
        let nextShortcut = (1...9).first { !usedShortcuts.contains($0) }
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let newGroup = LabelGroup(
            name: cleanName.isEmpty ? "Group \(groups.count + 1)" : cleanName,
            colorHex: colorHex,
            shortcutNumber: nextShortcut,
            recipe: initialRecipe
        )
        groups.append(newGroup)
        focusedGroupID = newGroup.id
        persistAlbumState()
        return newGroup
    }

    func updateGroupMetadata(id: UUID, name: String, colorHex: String) {
        guard let idx = groups.firstIndex(where: { $0.id == id }) else { return }
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !clean.isEmpty {
            groups[idx].name = clean
        }
        groups[idx].colorHex = colorHex
        persistAlbumState()
    }

    func duplicateGroup(id: UUID) {
        guard let source = groups.first(where: { $0.id == id }) else { return }
        let colorIdx = groups.count % LabelGroup.paletteHexes.count
        _ = addGroup(
            name: "\(source.name) Copy",
            colorHex: LabelGroup.paletteHexes[colorIdx],
            initialRecipe: source.recipe
        )
    }

    func deleteGroup(id: UUID) {
        groups.removeAll { $0.id == id }
        for (photoID, gid) in assignments where gid == id {
            assignments.removeValue(forKey: photoID)
            thumbnails.removeValue(forKey: photoID)
        }
        if case .group(let activeGid) = sidebarFilter, activeGid == id {
            sidebarFilter = .all
        }
        if focusedGroupID == id {
            focusedGroupID = groups.first?.id
        }
        persistAlbumState()
        scheduleLoupeRender(draft: false)
    }

    // MARK: - Group Recipe & Per-Photo Trim Editing

    func updateGroupRecipe(groupID: UUID, isDragging: Bool = true, _ mutate: (inout EditRecipe) -> Void) {
        guard let idx = groups.firstIndex(where: { $0.id == groupID }) else { return }
        mutate(&groups[idx].recipe)
        persistAlbumState()

        if let active = activePhoto, assignments[active.id] == groupID {
            scheduleLoupeRender(draft: isDragging)
        }
        scheduleThumbnailRefresh(forGroupID: groupID)
    }

    func setGroupRecipe(groupID: UUID, recipe: EditRecipe) {
        updateGroupRecipe(groupID: groupID, isDragging: false) { $0 = recipe }
    }

    func copyRecipe(from groupID: UUID) {
        clipboardRecipe = groups.first(where: { $0.id == groupID })?.recipe
        statusBanner = "Copied group recipe to clipboard"
    }

    func pasteRecipe(to groupID: UUID) {
        guard let clipboardRecipe else { return }
        setGroupRecipe(groupID: groupID, recipe: clipboardRecipe)
    }

    func updateActivePhotoTrim(_ mutate: (inout PhotoTrim) -> Void) {
        guard let active = activePhoto else { return }
        var current = trims[active.id] ?? PhotoTrim()
        mutate(&current)
        if current.hasTrim {
            trims[active.id] = current
        } else {
            trims.removeValue(forKey: active.id)
        }
        persistAlbumState()
        scheduleLoupeRender(draft: true)
        requestThumbnail(for: active, force: true)
    }

    // MARK: - Rendering & Thumbnails

    func requestThumbnail(for photo: PhotoItem, force: Bool = false) {
        if !force {
            if thumbnails[photo.id] != nil || inFlightThumbnails.contains(photo.id) {
                return
            }
        }
        inFlightThumbnails.insert(photo.id)
        let recipe = effectiveRecipe(for: photo)
        let generator = thumbnailGenerator

        Task {
            let img = await generator.thumbnail(for: photo, recipe: recipe, maxPixelSize: 440)
            await MainActor.run {
                self.inFlightThumbnails.remove(photo.id)
                if let img {
                    self.thumbnails[photo.id] = img
                }
            }
        }
    }

    private func scheduleThumbnailRefresh(forGroupID groupID: UUID) {
        thumbnailRefreshTask?.cancel()
        thumbnailRefreshTask = Task {
            try? await Task.sleep(for: .milliseconds(220))
            guard !Task.isCancelled else { return }
            let members = photos.filter { assignments[$0.id] == groupID }
            for member in members {
                requestThumbnail(for: member, force: true)
            }
        }
    }

    func scheduleLoupeRender(draft: Bool) {
        loupeRenderTask?.cancel()
        settleHighQualityTask?.cancel()

        guard let photo = activePhoto else {
            activeLoupeImage = nil
            activeHistogram = .empty
            return
        }

        let recipe = showBeforeOriginal ? EditRecipe.neutral : effectiveRecipe(for: photo)
        let watermark = (!showBeforeOriginal && previewWatermarkInLoupe && globalSettings.watermark.isEnabled)
            ? globalSettings.watermark
            : nil
        let targetPixels = draft ? 1280 : 2200
        let renderer = loupeRenderer

        loupeRenderTask = Task {
            let output = await renderer.renderPreview(
                photo: photo,
                recipe: recipe,
                maxEdgePixels: targetPixels,
                draftMode: draft,
                watermark: watermark
            )
            guard !Task.isCancelled, let output else { return }
            await MainActor.run {
                if self.activePhoto?.id == photo.id {
                    self.activeLoupeImage = output.image
                    self.activeHistogram = output.histogram
                    self.lastRenderMilliseconds = output.renderMilliseconds
                    self.activeAsShotTemperature = output.asShotTemperature
                    self.activeAsShotTint = output.asShotTint
                }
            }
        }

        if draft {
            settleHighQualityTask = Task {
                try? await Task.sleep(for: .milliseconds(180))
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    self.scheduleLoupeRender(draft: false)
                }
            }
        }
    }

    // MARK: - Batch Export

    func openExportSheet() {
        if exportDestinationURL == nil, let folder = currentFolderURL {
            exportDestinationURL = folder.appendingPathComponent("RawForge Export", isDirectory: true)
        }
        exportResult = nil
        exportProgress = nil
        isExportSheetPresented = true
    }

    func chooseExportDestinationPanel() {
        let panel = NSOpenPanel()
        panel.title = "Select Export Destination Folder"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        if panel.runModal() == .OK, let url = panel.url {
            exportDestinationURL = url
        }
    }

    func itemsForExportScope(_ scope: ExportScope) -> [PhotoItem] {
        switch scope {
        case .allPhotos:
            return photos
        case .selectedPhotos:
            let sel = photos.filter { selectedPhotoIDs.contains($0.id) }
            return sel.isEmpty ? photos : sel
        case .labeledOnly:
            return photos.filter { assignments[$0.id] != nil }
        case .activeGroupOnly:
            if let targetGroup = inspectorTargetGroup {
                return photos.filter { assignments[$0.id] == targetGroup.id }
            }
            return []
        }
    }

    func startBatchExport() {
        guard !isExporting else { return }
        let targetPhotos = itemsForExportScope(exportScope)
        guard !targetPhotos.isEmpty else { return }

        let destination = exportDestinationURL
            ?? (currentFolderURL ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Pictures"))
                .appendingPathComponent("RawForge Export", isDirectory: true)

        let workItems = targetPhotos.map { photo in
            let grp = group(for: photo.id)
            return BatchWorkItem(
                photo: photo,
                recipe: effectiveRecipe(for: photo),
                groupName: grp?.name
            )
        }

        isExporting = true
        exportResult = nil
        exportProgress = BatchProgressSnapshot(
            completedCount: 0,
            totalCount: workItems.count,
            failedCount: 0,
            elapsedSeconds: 0,
            photosPerSecond: 0,
            megapixelsPerSecond: 0,
            activeWorkers: globalSettings.exportConfig.manualWorkerCount > 0
                ? globalSettings.exportConfig.manualWorkerCount
                : hardware.optimalBatchConcurrency,
            gpuName: hardware.metalDeviceName,
            recentFile: "Preparing Apple Silicon Metal pipeline...",
            latestError: nil
        )

        let config = globalSettings.exportConfig
        let watermark = globalSettings.watermark
        let metadata = globalSettings.metadata
        let engine = batchEngine

        exportTask = Task {
            do {
                let result = try await engine.convertBatch(
                    items: workItems,
                    destinationDirectory: destination,
                    configuration: config,
                    watermark: watermark,
                    metadata: metadata,
                    onProgress: { snapshot in
                        Task { @MainActor [weak self] in
                            self?.exportProgress = snapshot
                        }
                    }
                )
                await MainActor.run {
                    self.isExporting = false
                    self.exportResult = result
                }
            } catch {
                await MainActor.run {
                    self.isExporting = false
                    self.statusBanner = "Export error: \(error.localizedDescription)"
                }
            }
        }
    }

    func cancelBatchExport() {
        exportTask?.cancel()
    }

    // MARK: - Self Check for Headless Verification

    @MainActor
    func runSelfCheck(testPhotoPath: String) async -> Bool {
        let testURL = URL(fileURLWithPath: testPhotoPath)
        if FileManager.default.fileExists(atPath: testURL.path) {
            await openDroppedOrSelectedURL(testURL)
            if let first = activePhoto {
                let output = await loupeRenderer.renderPreview(
                    photo: first,
                    recipe: EditRecipe(),
                    maxEdgePixels: 640,
                    draftMode: true,
                    watermark: nil
                )
                return output != nil
            }
        }
        return true
    }
}
