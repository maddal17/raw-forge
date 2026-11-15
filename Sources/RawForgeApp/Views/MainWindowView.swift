import RawForgeCore
import SwiftUI
import UniformTypeIdentifiers

struct MainWindowView: View {
    @ObservedObject var viewModel: AppViewModel
    @State private var isDropTargeted = false

    var body: some View {
        VStack(spacing: 0) {
            studioHeaderToolbar
            Divider().background(StudioTheme.borderSubtle)

            if let banner = viewModel.statusBanner {
                HStack(spacing: 8) {
                    Image(systemName: "info.circle.fill")
                        .foregroundStyle(StudioTheme.accentBlue)
                    Text(banner)
                        .font(.system(size: 12))
                    Spacer()
                    Button {
                        viewModel.statusBanner = nil
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 10))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(StudioTheme.accentBlue.opacity(0.16))
                Divider().background(StudioTheme.borderSubtle)
            }

            if viewModel.photos.isEmpty && !viewModel.isScanning {
                welcomeDropZone
            } else {
                HStack(spacing: 0) {
                    GroupSidebarView(viewModel: viewModel)
                        .frame(width: 238)

                    Divider().background(StudioTheme.borderSubtle)

                    Group {
                        if viewModel.workspaceMode == .list {
                            PhotoListModeView(viewModel: viewModel)
                        } else {
                            LoupeDevelopModeView(viewModel: viewModel)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                    Divider().background(StudioTheme.borderSubtle)

                    RecipeInspectorView(viewModel: viewModel)
                        .frame(width: 295)
                }
            }
        }
        .background(StudioTheme.canvasBg)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(StudioTheme.accentBlue, lineWidth: isDropTargeted ? 3 : 0)
                .padding(4)
        )
        .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
            handleDrop(providers: providers)
        }
        .sheet(item: $viewModel.activeModal) { modal in
            switch modal {
            case .settings(let initialTab, let returnToExport):
                SettingsSheetView(
                    viewModel: viewModel,
                    initialTab: initialTab,
                    returnToExport: returnToExport
                )
            case .export:
                ExportModalView(viewModel: viewModel)
            }
        }
    }

    private var studioHeaderToolbar: some View {
        HStack(spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "camera.aperture")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(StudioTheme.accentBlue)
                Text("RawForge")
                    .font(.system(size: 14, weight: .bold))
                if let folder = viewModel.currentFolderURL {
                    Text("/ \(folder.lastPathComponent)")
                        .font(.system(size: 12))
                        .foregroundStyle(StudioTheme.textSecondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }

            Button {
                viewModel.openFolderPanel()
            } label: {
                Label("Open Folder…", systemImage: "folder.badge.plus")
                    .font(.system(size: 12, weight: .medium))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

            Spacer()

            // Two Primary Viewing Modes
            Picker("View Mode", selection: $viewModel.workspaceMode) {
                ForEach(WorkspaceMode.allCases) { mode in
                    Label(mode.title, systemImage: mode.systemImage)
                        .tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 250)

            Spacer()

            // M-chip Hardware Pill
            HStack(spacing: 5) {
                Image(systemName: "bolt.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(.yellow)
                Text(viewModel.hardware.chipName)
                    .font(.system(size: 11, weight: .medium))
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(Color.white.opacity(0.06))
            .clipShape(Capsule())
            .help(viewModel.hardware.summaryBadge)

            Button {
                viewModel.openSettings(tab: .watermark)
            } label: {
                Label("Settings", systemImage: "gearshape")
                    .font(.system(size: 12))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

            Button {
                viewModel.openExportSheet()
            } label: {
                Label("Convert & Export…", systemImage: "square.and.arrow.up.on.square")
                    .font(.system(size: 12, weight: .semibold))
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .disabled(viewModel.photos.isEmpty)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(StudioTheme.surfaceBg)
    }

    private var welcomeDropZone: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "camera.metering.matrix")
                .font(.system(size: 56))
                .foregroundStyle(StudioTheme.accentBlue)

            VStack(spacing: 6) {
                Text("Mass RAW Photo Studio for Apple Silicon")
                    .font(.title2.bold())
                Text("Drop a folder of RAW files (.RW2, .CR3, .CR2, .NEF, .ARW, .RAF, .DNG, .ORF) or open a shoot folder to label lighting groups and batch convert on Metal GPU.")
                    .font(.system(size: 13))
                    .foregroundStyle(StudioTheme.textSecondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 540)
            }

            HStack(spacing: 12) {
                Button {
                    viewModel.openFolderPanel()
                } label: {
                    Label("Open Photo Folder…", systemImage: "folder.badge.plus")
                        .font(.system(size: 13, weight: .semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                Button {
                    Task { await viewModel.generateAndLoadSampleAlbum() }
                } label: {
                    Label("Generate Sample 16-bit RAW Album", systemImage: "sparkles")
                        .font(.system(size: 13))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 4)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }

            if !viewModel.globalSettings.recentFolders.isEmpty {
                VStack(spacing: 6) {
                    Text("RECENT FOLDERS")
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(StudioTheme.textSecondary)
                        .padding(.top, 10)

                    ForEach(viewModel.globalSettings.recentFolders.prefix(4), id: \.self) { path in
                        Button {
                            Task { await viewModel.loadFolder(url: URL(fileURLWithPath: path)) }
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "folder")
                                Text(path)
                                    .lineLimit(1)
                                    .truncationMode(.head)
                            }
                            .font(.system(size: 12))
                            .foregroundStyle(StudioTheme.accentBlue)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        let lock = NSLock()
        final class Box: @unchecked Sendable {
            var urls: [URL] = []
        }
        let box = Box()
        let group = DispatchGroup()

        for provider in providers where provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            group.enter()
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                defer { group.leave() }
                let resolved: URL?
                if let data = item as? Data {
                    resolved = URL(dataRepresentation: data, relativeTo: nil)
                } else if let url = item as? URL {
                    resolved = url
                } else {
                    resolved = nil
                }
                if let resolved {
                    lock.lock()
                    box.urls.append(resolved)
                    lock.unlock()
                }
            }
        }

        group.notify(queue: .main) {
            lock.lock()
            let dropped = box.urls
            lock.unlock()
            guard !dropped.isEmpty else { return }
            Task { @MainActor in
                await viewModel.handleDroppedURLs(dropped)
            }
        }
        return true
    }
}
