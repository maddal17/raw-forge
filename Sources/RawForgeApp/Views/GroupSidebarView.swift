import RawForgeCore
import SwiftUI

struct GroupSidebarView: View {
    @ObservedObject var viewModel: AppViewModel
    @State private var isAddingGroup = false
    @State private var editingGroup: LabelGroup?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Library Filters
            VStack(alignment: .leading, spacing: 4) {
                Text("ALBUM LIBRARY")
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(StudioTheme.textSecondary)
                    .padding(.horizontal, 12)
                    .padding(.top, 12)
                    .padding(.bottom, 4)

                filterRow(
                    title: "All Photos",
                    icon: "photo.stack",
                    count: viewModel.photos.count,
                    isSelected: viewModel.sidebarFilter == .all
                ) {
                    viewModel.sidebarFilter = .all
                }

                filterRow(
                    title: "Unlabeled",
                    icon: "tray",
                    count: viewModel.unlabeledCount,
                    isSelected: viewModel.sidebarFilter == .unlabeled
                ) {
                    viewModel.sidebarFilter = .unlabeled
                }
            }

            Divider()
                .background(StudioTheme.borderSubtle)
                .padding(.vertical, 10)

            // Lighting Label Groups Header
            HStack {
                Text("LIGHTING GROUPS")
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(StudioTheme.textSecondary)
                Spacer()
                Button {
                    isAddingGroup = true
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(StudioTheme.accentBlue)
                }
                .buttonStyle(.plain)
                .help("Add a new lighting / color label group")
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 6)

            ScrollView {
                LazyVStack(spacing: 4) {
                    ForEach(viewModel.groups) { group in
                        GroupSidebarRow(
                            group: group,
                            count: viewModel.photoCount(in: group.id),
                            isFilterSelected: viewModel.sidebarFilter == .group(group.id),
                            isEditingRecipeTarget: viewModel.inspectorTargetGroup?.id == group.id,
                            hasPhotoSelection: !viewModel.selectedPhotoIDs.isEmpty,
                            onSelectFilter: {
                                if viewModel.sidebarFilter == .group(group.id) {
                                    viewModel.sidebarFilter = .all
                                } else {
                                    viewModel.sidebarFilter = .group(group.id)
                                    viewModel.focusedGroupID = group.id
                                }
                            },
                            onFocusRecipe: {
                                viewModel.focusedGroupID = group.id
                            },
                            onAssignSelected: {
                                viewModel.assignSelectedOrActive(to: group.id, advanceInLoupe: false)
                            },
                            onSelectGroupPhotos: {
                                viewModel.selectAllInGroup(group.id)
                            },
                            onRenameAndColor: {
                                editingGroup = group
                            },
                            onDuplicate: {
                                viewModel.duplicateGroup(id: group.id)
                            },
                            onCopyRecipe: {
                                viewModel.copyRecipe(from: group.id)
                            },
                            onPasteRecipe: viewModel.clipboardRecipe != nil ? {
                                viewModel.pasteRecipe(to: group.id)
                            } : nil,
                            onDelete: {
                                viewModel.deleteGroup(id: group.id)
                            }
                        )
                    }
                }
                .padding(.horizontal, 8)
            }

            Spacer(minLength: 8)

            // Bottom quick summary
            VStack(alignment: .leading, spacing: 6) {
                Divider().background(StudioTheme.borderSubtle)
                HStack(spacing: 6) {
                    Image(systemName: "keyboard")
                        .font(.system(size: 11))
                        .foregroundStyle(StudioTheme.textSecondary)
                    Text("Keys 1–9 assign group · 0 clears")
                        .font(.system(size: 10.5))
                        .foregroundStyle(StudioTheme.textSecondary)
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 10)
                .padding(.top, 4)
            }
        }
        .background(StudioTheme.surfaceBg)
        .sheet(isPresented: $isAddingGroup) {
            GroupEditorSheet(
                title: "New Lighting Group",
                name: "",
                selectedHex: LabelGroup.paletteHexes[viewModel.groups.count % LabelGroup.paletteHexes.count]
            ) { name, hex in
                _ = viewModel.addGroup(name: name, colorHex: hex)
            }
        }
        .sheet(item: $editingGroup) { group in
            GroupEditorSheet(
                title: "Edit Lighting Group",
                name: group.name,
                selectedHex: group.colorHex
            ) { name, hex in
                viewModel.updateGroupMetadata(id: group.id, name: name, colorHex: hex)
            }
        }
    }

    private func filterRow(
        title: String,
        icon: String,
        count: Int,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 12))
                    .foregroundStyle(isSelected ? .white : StudioTheme.textSecondary)
                    .frame(width: 16)
                Text(title)
                    .font(.system(size: 12.5, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(StudioTheme.textPrimary)
                Spacer()
                Text("\(count)")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(StudioTheme.textSecondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.white.opacity(isSelected ? 0.16 : 0.06))
                    .clipShape(Capsule())
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 7)
                    .fill(isSelected ? StudioTheme.accentBlue.opacity(0.28) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 8)
    }
}

private struct GroupSidebarRow: View {
    let group: LabelGroup
    let count: Int
    let isFilterSelected: Bool
    let isEditingRecipeTarget: Bool
    let hasPhotoSelection: Bool
    let onSelectFilter: () -> Void
    let onFocusRecipe: () -> Void
    let onAssignSelected: () -> Void
    let onSelectGroupPhotos: () -> Void
    let onRenameAndColor: () -> Void
    let onDuplicate: () -> Void
    let onCopyRecipe: () -> Void
    let onPasteRecipe: (() -> Void)?
    let onDelete: () -> Void

    @State private var isHovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Circle()
                    .fill(Color(hex: group.colorHex))
                    .frame(width: 10, height: 10)
                    .overlay(
                        Circle().stroke(Color.white.opacity(0.35), lineWidth: 0.75)
                    )

                VStack(alignment: .leading, spacing: 1) {
                    Text(group.name)
                        .font(.system(size: 12.5, weight: isFilterSelected || isEditingRecipeTarget ? .semibold : .medium))
                        .foregroundStyle(StudioTheme.textPrimary)
                        .lineLimit(1)

                    if group.recipe.hasAdjustments {
                        Text(group.recipe.summaryBadges.joined(separator: " · "))
                            .font(.system(size: 10))
                            .foregroundStyle(Color(hex: group.colorHex).opacity(0.9))
                            .lineLimit(1)
                    } else {
                        Text("As Shot (No Edits)")
                            .font(.system(size: 10))
                            .foregroundStyle(StudioTheme.textSecondary.opacity(0.75))
                    }
                }

                Spacer(minLength: 4)

                if hasPhotoSelection && isHovering {
                    Button {
                        onAssignSelected()
                    } label: {
                        Text("Assign")
                            .font(.system(size: 10, weight: .semibold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color(hex: group.colorHex).opacity(0.85))
                            .foregroundStyle(.white)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .help("Assign selected photos to \(group.name)")
                } else {
                    HStack(spacing: 4) {
                        if let shortcut = group.shortcutNumber {
                            Text("\(shortcut)")
                                .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                                .foregroundStyle(StudioTheme.textSecondary)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(Color.white.opacity(0.08))
                                .clipShape(RoundedRectangle(cornerRadius: 3))
                        }
                        Text("\(count)")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(StudioTheme.textSecondary)
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(
                        isFilterSelected
                            ? Color(hex: group.colorHex).opacity(0.22)
                            : (isEditingRecipeTarget ? Color.white.opacity(0.06) : Color.clear)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(
                                isEditingRecipeTarget ? Color(hex: group.colorHex).opacity(0.55) : Color.clear,
                                lineWidth: 1
                            )
                    )
            )
            .contentShape(Rectangle())
            .onTapGesture {
                onSelectFilter()
            }
            .onHover { hovering in
                isHovering = hovering
            }
            .contextMenu {
                Button("Assign Selected Photos to \"\(group.name)\"") {
                    onAssignSelected()
                }
                .disabled(!hasPhotoSelection)

                Button("Select All Photos in Group") {
                    onSelectGroupPhotos()
                }

                Button("Edit Group Recipe in Inspector") {
                    onFocusRecipe()
                }

                Divider()

                Button("Copy Recipe") {
                    onCopyRecipe()
                }
                if let onPasteRecipe {
                    Button("Paste Recipe") {
                        onPasteRecipe()
                    }
                }

                Divider()

                Button("Rename & Change Color...") {
                    onRenameAndColor()
                }
                Button("Duplicate Group") {
                    onDuplicate()
                }
                Button("Delete Group", role: .destructive) {
                    onDelete()
                }
            }
        }
    }
}
