import AppKit
import RawForgeCore
import SwiftUI

struct PhotoListModeView: View {
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        VStack(spacing: 0) {
            listToolbar
            Divider().background(StudioTheme.borderSubtle)

            if !viewModel.selectedPhotoIDs.isEmpty {
                massSelectionActionBar
                Divider().background(StudioTheme.borderSubtle)
            }

            if viewModel.filteredPhotos.isEmpty {
                emptyFilteredState
            } else if viewModel.isGroupedByLabel {
                groupedContent
            } else {
                flatContent
            }
        }
        .background(StudioTheme.canvasBg)
    }

    private var listToolbar: some View {
        HStack(spacing: 12) {
            // Group by Label Toggle
            Toggle(isOn: $viewModel.isGroupedByLabel) {
                Label("Group by Labels", systemImage: "rectangle.3.group")
                    .font(.system(size: 12, weight: .medium))
            }
            .toggleStyle(.button)
            .tint(viewModel.isGroupedByLabel ? StudioTheme.accentBlue : .secondary)
            .help("Organize the photo list into collapsible sections grouped by their assigned label")

            Picker("", selection: $viewModel.listStyle) {
                Image(systemName: "list.bullet.below.rectangle").tag(ListPresentationStyle.mediumRows)
                    .help("List with medium previews")
                Image(systemName: "square.grid.2x2").tag(ListPresentationStyle.mediumCards)
                    .help("Medium preview cards grid")
            }
            .pickerStyle(.segmented)
            .frame(width: 82)

            HStack(spacing: 5) {
                Image(systemName: "photo")
                    .font(.system(size: 10))
                    .foregroundStyle(StudioTheme.textSecondary)
                Slider(value: $viewModel.previewSize, in: 110...240)
                    .frame(width: 90)
                    .controlSize(.small)
                    .help("Adjust medium preview size")
                Image(systemName: "photo.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(StudioTheme.textSecondary)
            }

            Spacer()

            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11))
                    .foregroundStyle(StudioTheme.textSecondary)
                TextField("Filter filename, camera, label...", text: $viewModel.searchQuery)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .frame(width: 170)
                if !viewModel.searchQuery.isEmpty {
                    Button {
                        viewModel.searchQuery = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(StudioTheme.textSecondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(StudioTheme.elevatedBg)
            .clipShape(RoundedRectangle(cornerRadius: 6))

            Picker("Sort", selection: $viewModel.sortOrder) {
                ForEach(PhotoSortOrder.allCases) { order in
                    Text(order.rawValue).tag(order)
                }
            }
            .frame(width: 135)
            .controlSize(.small)

            Menu {
                Button("Select All (\(viewModel.visibleOrderedPhotos.count))") {
                    viewModel.selectAllVisible()
                }
                Button("Select Unlabeled") {
                    viewModel.selectUnlabeledVisible()
                }
                Button("Clear Selection") {
                    viewModel.clearSelection()
                }
            } label: {
                Label("Select", systemImage: "checklist")
                    .font(.system(size: 12))
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(StudioTheme.surfaceBg)
    }

    private var massSelectionActionBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                Text("\(viewModel.selectedPhotoIDs.count) selected")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(StudioTheme.accentBlue.opacity(0.32))
                    .clipShape(Capsule())

                Text("Assign Label:")
                    .font(.system(size: 11.5))
                    .foregroundStyle(StudioTheme.textSecondary)

                ForEach(viewModel.groups) { group in
                    Button {
                        viewModel.assignSelectedOrActive(to: group.id)
                    } label: {
                        HStack(spacing: 5) {
                            Circle()
                                .fill(Color(hex: group.colorHex))
                                .frame(width: 8, height: 8)
                            Text(group.name)
                                .font(.system(size: 11.5, weight: .medium))
                            if let shortcut = group.shortcutNumber {
                                Text("\(shortcut)")
                                    .font(.system(size: 9.5, design: .monospaced))
                                    .opacity(0.65)
                            }
                        }
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .background(Color(hex: group.colorHex).opacity(0.18))
                        .overlay(
                            Capsule().stroke(Color(hex: group.colorHex).opacity(0.55), lineWidth: 1)
                        )
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }

                Button {
                    viewModel.assignSelectedOrActive(to: nil)
                } label: {
                    Label("Clear Label", systemImage: "tag.slash")
                        .font(.system(size: 11))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.white.opacity(0.08))
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)

                Divider().frame(height: 16)

                Button("All") { viewModel.selectAllVisible() }
                    .buttonStyle(.borderless)
                    .font(.system(size: 11.5))

                Button("Deselect") { viewModel.clearSelection() }
                    .buttonStyle(.borderless)
                    .font(.system(size: 11.5))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
        }
        .background(Color(red: 0.12, green: 0.14, blue: 0.18))
    }

    private var flatContent: some View {
        ScrollView {
            if viewModel.listStyle == .mediumRows {
                LazyVStack(spacing: 8) {
                    ForEach(viewModel.filteredPhotos) { photo in
                        photoRow(for: photo)
                    }
                }
                .padding(14)
            } else {
                let columns = [GridItem(.adaptive(minimum: viewModel.previewSize + 24, maximum: viewModel.previewSize + 80), spacing: 12)]
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(viewModel.filteredPhotos) { photo in
                        photoCard(for: photo)
                    }
                }
                .padding(14)
            }
        }
    }

    private var groupedContent: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                ForEach(viewModel.sectionedPhotos) { section in
                    let isCollapsed = viewModel.collapsedSectionIDs.contains(section.id)
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 10) {
                            Button {
                                if isCollapsed {
                                    viewModel.collapsedSectionIDs.remove(section.id)
                                } else {
                                    viewModel.collapsedSectionIDs.insert(section.id)
                                }
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundStyle(StudioTheme.textSecondary)
                                    Circle()
                                        .fill(Color(hex: section.colorHex))
                                        .frame(width: 10, height: 10)
                                    Text(section.title)
                                        .font(.system(size: 13.5, weight: .semibold))
                                        .foregroundStyle(.white)
                                    Text("(\(section.photos.count))")
                                        .font(.system(size: 12, design: .monospaced))
                                        .foregroundStyle(StudioTheme.textSecondary)
                                }
                            }
                            .buttonStyle(.plain)

                            if let grp = section.group, grp.recipe.hasAdjustments {
                                HStack(spacing: 4) {
                                    ForEach(grp.recipe.summaryBadges, id: \.self) { badge in
                                        Text(badge)
                                            .font(.system(size: 10, weight: .medium))
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(Color(hex: section.colorHex).opacity(0.22))
                                            .clipShape(Capsule())
                                    }
                                }
                            }

                            Spacer()

                            Button("Select Section") {
                                viewModel.selectedPhotoIDs = Set(section.photos.map { $0.id })
                                if let grp = section.group {
                                    viewModel.focusedGroupID = grp.id
                                }
                            }
                            .buttonStyle(.borderless)
                            .font(.system(size: 11))
                            .foregroundStyle(StudioTheme.accentBlue)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(StudioTheme.elevatedBg)
                        .clipShape(RoundedRectangle(cornerRadius: 8))

                        if !isCollapsed {
                            if viewModel.listStyle == .mediumRows {
                                ForEach(section.photos) { photo in
                                    photoRow(for: photo)
                                }
                            } else {
                                let columns = [GridItem(.adaptive(minimum: viewModel.previewSize + 24, maximum: viewModel.previewSize + 80), spacing: 12)]
                                LazyVGrid(columns: columns, spacing: 12) {
                                    ForEach(section.photos) { photo in
                                        photoCard(for: photo)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .padding(14)
        }
    }

    private func photoRow(for photo: PhotoItem) -> some View {
        let assignedGroup = viewModel.group(for: photo.id)
        let isSelected = viewModel.selectedPhotoIDs.contains(photo.id)
        let isActive = viewModel.activePhoto?.id == photo.id

        return HStack(spacing: 12) {
            // Checkbox for rapid mass selection without holding Cmd
            Button {
                viewModel.toggleCheckbox(for: photo.id)
            } label: {
                Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                    .font(.system(size: 16))
                    .foregroundStyle(isSelected ? StudioTheme.accentBlue : StudioTheme.textSecondary)
            }
            .buttonStyle(.plain)

            // Medium Preview Thumbnail
            ZStack {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.black.opacity(0.45))

                if let cg = viewModel.thumbnails[photo.id] {
                    CGImageView(cgImage: cg)
                        .aspectRatio(contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 5))
                } else {
                    ProgressView()
                        .controlSize(.small)
                }
            }
            .frame(width: viewModel.previewSize, height: viewModel.previewSize * 0.68)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(
                        assignedGroup.map { Color(hex: $0.colorHex).opacity(0.8) } ?? Color.white.opacity(0.08),
                        lineWidth: assignedGroup != nil ? 2 : 1
                    )
            )

            // Metadata & Camera Summary
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(photo.filename)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)

                    Text(photo.fileExtension.uppercased())
                        .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1.5)
                        .background(photo.isRaw ? Color.orange.opacity(0.25) : Color.gray.opacity(0.25))
                        .foregroundStyle(photo.isRaw ? Color.orange : Color.white.opacity(0.8))
                        .clipShape(RoundedRectangle(cornerRadius: 4))

                    if photo.hasGPS {
                        Image(systemName: "location.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(StudioTheme.textSecondary)
                            .help("Contains GPS coordinates (can be stripped in Settings)")
                    }
                }

                Text("\(photo.cameraMakeModel) · \(photo.formattedDimensions) · \(photo.formattedFileSize)")
                    .font(.system(size: 11.5))
                    .foregroundStyle(StudioTheme.textSecondary)
                    .lineLimit(1)

                if !photo.exposureSummary.isEmpty {
                    Text(photo.exposureSummary)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(StudioTheme.textSecondary.opacity(0.85))
                }
            }

            Spacer()

            // Quick Label Dropdown + Preview button
            HStack(spacing: 8) {
                Menu {
                    ForEach(viewModel.groups) { grp in
                        Button {
                            viewModel.assignPhoto(photo.id, to: grp.id)
                        } label: {
                            Text(grp.name)
                        }
                    }
                    Divider()
                    Button("Unlabeled") {
                        viewModel.assignPhoto(photo.id, to: nil)
                    }
                } label: {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(assignedGroup.map { Color(hex: $0.colorHex) } ?? Color.gray.opacity(0.5))
                            .frame(width: 8, height: 8)
                        Text(assignedGroup?.name ?? "Unlabeled")
                            .font(.system(size: 11.5, weight: .medium))
                            .foregroundStyle(.white)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 9))
                            .foregroundStyle(StudioTheme.textSecondary)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(assignedGroup.map { Color(hex: $0.colorHex).opacity(0.22) } ?? Color.white.opacity(0.06))
                    .overlay(
                        Capsule().stroke(
                            assignedGroup.map { Color(hex: $0.colorHex).opacity(0.6) } ?? Color.white.opacity(0.12),
                            lineWidth: 1
                        )
                    )
                    .clipShape(Capsule())
                }
                .menuStyle(.borderlessButton)
                .fixedSize()

                Button {
                    viewModel.setActivePhoto(photo.id)
                    viewModel.workspaceMode = .loupe
                } label: {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.system(size: 12))
                        .padding(6)
                        .background(Color.white.opacity(0.07))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
                .help("Open in Big Preview (Mode 2)")
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(isSelected ? StudioTheme.accentBlue.opacity(0.16) : StudioTheme.surfaceBg)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(
                            isActive ? StudioTheme.accentBlue : (isSelected ? StudioTheme.accentBlue.opacity(0.5) : StudioTheme.borderSubtle),
                            lineWidth: isActive ? 1.5 : 1
                        )
                )
        )
        .contentShape(Rectangle())
        .onAppear {
            viewModel.requestThumbnail(for: photo)
        }
        .onTapGesture(count: 2) {
            viewModel.handlePhotoClick(photo, modifiers: [])
            viewModel.workspaceMode = .loupe
        }
        .onTapGesture {
            let mods = NSApp.currentEvent?.modifierFlags ?? []
            viewModel.handlePhotoClick(photo, modifiers: mods)
        }
    }

    private func photoCard(for photo: PhotoItem) -> some View {
        let assignedGroup = viewModel.group(for: photo.id)
        let isSelected = viewModel.selectedPhotoIDs.contains(photo.id)
        let isActive = viewModel.activePhoto?.id == photo.id

        return VStack(alignment: .leading, spacing: 6) {
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 7)
                    .fill(Color.black.opacity(0.5))

                if let cg = viewModel.thumbnails[photo.id] {
                    CGImageView(cgImage: cg)
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                } else {
                    ProgressView().controlSize(.small)
                }

                HStack {
                    Button {
                        viewModel.toggleCheckbox(for: photo.id)
                    } label: {
                        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 16))
                            .foregroundStyle(isSelected ? StudioTheme.accentBlue : .white.opacity(0.8))
                            .shadow(radius: 2)
                    }
                    .buttonStyle(.plain)
                    Spacer()
                    Text(photo.fileExtension.uppercased())
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Color.black.opacity(0.65))
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }
                .padding(6)
            }
            .frame(height: viewModel.previewSize * 0.78)

            HStack(spacing: 6) {
                Circle()
                    .fill(assignedGroup.map { Color(hex: $0.colorHex) } ?? Color.gray.opacity(0.45))
                    .frame(width: 8, height: 8)
                Text(photo.filename)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Spacer()
            }

            Text(assignedGroup?.name ?? "Unlabeled")
                .font(.system(size: 10.5))
                .foregroundStyle(assignedGroup.map { Color(hex: $0.colorHex) } ?? StudioTheme.textSecondary)
                .lineLimit(1)
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(isSelected ? StudioTheme.accentBlue.opacity(0.18) : StudioTheme.surfaceBg)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(
                            isActive ? StudioTheme.accentBlue : (isSelected ? StudioTheme.accentBlue.opacity(0.55) : StudioTheme.borderSubtle),
                            lineWidth: isActive ? 1.5 : 1
                        )
                )
        )
        .contentShape(Rectangle())
        .onAppear {
            viewModel.requestThumbnail(for: photo)
        }
        .onTapGesture(count: 2) {
            viewModel.handlePhotoClick(photo, modifiers: [])
            viewModel.workspaceMode = .loupe
        }
        .onTapGesture {
            let mods = NSApp.currentEvent?.modifierFlags ?? []
            viewModel.handlePhotoClick(photo, modifiers: mods)
        }
    }

    private var emptyFilteredState: some View {
        VStack(spacing: 10) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 34))
                .foregroundStyle(StudioTheme.textSecondary)
            Text("No photos match the current filter")
                .font(.headline)
            Button("Show All Photos") {
                viewModel.sidebarFilter = .all
                viewModel.searchQuery = ""
            }
            .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
