import RawForgeCore
import SwiftUI

struct LoupeDevelopModeView: View {
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        VStack(spacing: 0) {
            topInfoAndControlsBar
            Divider().background(StudioTheme.borderSubtle)

            bigPreviewStage
            Divider().background(StudioTheme.borderSubtle)

            quickLabelBar
            Divider().background(StudioTheme.borderSubtle)

            mediumFilmstrip
        }
        .background(StudioTheme.canvasBg)
    }

    private var topInfoAndControlsBar: some View {
        HStack(spacing: 12) {
            if let photo = viewModel.activePhoto {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(photo.filename)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.white)
                        Text(photo.formattedDimensions)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(StudioTheme.textSecondary)
                        if viewModel.lastRenderMilliseconds > 0 {
                            Text(String(format: "Metal %.0f ms", viewModel.lastRenderMilliseconds))
                                .font(.system(size: 10, design: .monospaced))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.green.opacity(0.18))
                                .foregroundStyle(Color.green.opacity(0.9))
                                .clipShape(Capsule())
                        }
                    }
                    if !photo.exposureSummary.isEmpty {
                        Text("\(photo.cameraMakeModel) · \(photo.exposureSummary)")
                            .font(.system(size: 11))
                            .foregroundStyle(StudioTheme.textSecondary)
                    }
                }
            }

            Spacer()

            Toggle(isOn: Binding(
                get: { viewModel.showBeforeOriginal },
                set: { val in
                    viewModel.showBeforeOriginal = val
                    viewModel.scheduleLoupeRender(draft: false)
                }
            )) {
                Label("Before (\\)", systemImage: "rectangle.lefthalf.inset.filled.arrow.left")
                    .font(.system(size: 11.5))
            }
            .toggleStyle(.button)
            .tint(viewModel.showBeforeOriginal ? .orange : .secondary)

            if viewModel.globalSettings.watermark.isEnabled {
                Toggle(isOn: Binding(
                    get: { viewModel.previewWatermarkInLoupe },
                    set: { val in
                        viewModel.previewWatermarkInLoupe = val
                        viewModel.scheduleLoupeRender(draft: false)
                    }
                )) {
                    Label("Watermark", systemImage: "signature")
                        .font(.system(size: 11.5))
                }
                .toggleStyle(.button)
            }

            Toggle(isOn: $viewModel.zoomTo100) {
                Label(viewModel.zoomTo100 ? "100%" : "Fit", systemImage: "magnifyingglass")
                    .font(.system(size: 11.5))
            }
            .toggleStyle(.button)

            Toggle(isOn: $viewModel.autoAdvanceOnLabel) {
                Label("Auto-Next", systemImage: "forward.end")
                    .font(.system(size: 11.5))
            }
            .toggleStyle(.button)
            .help("Advance to the next photo automatically when assigning a label")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(StudioTheme.surfaceBg)
    }

    private var bigPreviewStage: some View {
        ZStack {
            Color(red: 0.055, green: 0.058, blue: 0.068)

            if let cg = viewModel.activeLoupeImage {
                if viewModel.zoomTo100 {
                    ScrollView([.horizontal, .vertical]) {
                        CGImageView(cgImage: cg)
                            .frame(width: CGFloat(cg.width), height: CGFloat(cg.height))
                            .padding(20)
                    }
                } else {
                    CGImageView(cgImage: cg)
                        .aspectRatio(contentMode: .fit)
                        .padding(16)
                }
            } else if viewModel.activePhoto != nil {
                VStack(spacing: 10) {
                    ProgressView()
                    Text("Decoding RAW on Metal GPU...")
                        .font(.caption)
                        .foregroundStyle(StudioTheme.textSecondary)
                }
            } else {
                Text("No photo selected")
                    .foregroundStyle(StudioTheme.textSecondary)
            }

            // Overlay status pill for Before / Active Group
            VStack {
                HStack {
                    if viewModel.showBeforeOriginal {
                        Text("BEFORE — ORIGINAL AS SHOT")
                            .font(.system(size: 10.5, weight: .bold, design: .monospaced))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(Color.orange.opacity(0.9))
                            .foregroundStyle(.black)
                            .clipShape(Capsule())
                    } else if let photo = viewModel.activePhoto, let grp = viewModel.group(for: photo.id) {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(Color(hex: grp.colorHex))
                                .frame(width: 8, height: 8)
                            Text(grp.name)
                                .font(.system(size: 11, weight: .semibold))
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Color.black.opacity(0.68))
                        .overlay(Capsule().stroke(Color(hex: grp.colorHex).opacity(0.75), lineWidth: 1))
                        .clipShape(Capsule())
                    }
                    Spacer()
                }
                Spacer()
            }
            .padding(16)

            // Left / Right hover navigation arrows
            HStack {
                Button {
                    viewModel.stepActivePhoto(delta: -1)
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.85))
                        .frame(width: 36, height: 54)
                        .background(Color.black.opacity(0.45))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)

                Spacer()

                Button {
                    viewModel.stepActivePhoto(delta: 1)
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.85))
                        .frame(width: 36, height: 54)
                        .background(Color.black.opacity(0.45))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var quickLabelBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                Text("Label Group:")
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(StudioTheme.textSecondary)

                let activeGroupID = viewModel.activePhoto.flatMap { viewModel.assignments[$0.id] }

                ForEach(viewModel.groups) { group in
                    let isAssigned = activeGroupID == group.id
                    Button {
                        viewModel.assignSelectedOrActive(to: group.id, advanceInLoupe: true)
                    } label: {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(Color(hex: group.colorHex))
                                .frame(width: 8, height: 8)
                            Text(group.name)
                                .font(.system(size: 11.5, weight: isAssigned ? .bold : .medium))
                            if let shortcut = group.shortcutNumber {
                                Text("[\(shortcut)]")
                                    .font(.system(size: 10, design: .monospaced))
                                    .opacity(0.75)
                            }
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(
                            isAssigned
                                ? Color(hex: group.colorHex).opacity(0.32)
                                : Color.white.opacity(0.06)
                        )
                        .overlay(
                            Capsule().stroke(
                                isAssigned ? Color(hex: group.colorHex) : Color.white.opacity(0.14),
                                lineWidth: isAssigned ? 1.5 : 1
                            )
                        )
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }

                Button {
                    viewModel.assignSelectedOrActive(to: nil, advanceInLoupe: true)
                } label: {
                    Text("Unlabeled [0]")
                        .font(.system(size: 11))
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(Color.white.opacity(0.05))
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
        }
        .background(StudioTheme.surfaceBg)
    }

    private var mediumFilmstrip: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: true) {
                LazyHStack(spacing: 10) {
                    ForEach(viewModel.visibleOrderedPhotos) { photo in
                        FilmstripTile(
                            photo: photo,
                            thumbnail: viewModel.thumbnails[photo.id],
                            group: viewModel.group(for: photo.id),
                            isActive: viewModel.activePhoto?.id == photo.id,
                            onAppearLoad: { viewModel.requestThumbnail(for: photo) },
                            onSelect: {
                                viewModel.selectedPhotoIDs = [photo.id]
                                viewModel.selectionAnchorID = photo.id
                                viewModel.setActivePhoto(photo.id)
                            }
                        )
                        .id(photo.id)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
            }
            .frame(height: 126)
            .background(Color(red: 0.07, green: 0.075, blue: 0.088))
            .onChange(of: viewModel.activePhotoID) { _, newID in
                if let newID {
                    withAnimation(.easeOut(duration: 0.18)) {
                        proxy.scrollTo(newID, anchor: .center)
                    }
                }
            }
        }
    }
}

private struct FilmstripTile: View {
    let photo: PhotoItem
    let thumbnail: CGImage?
    let group: LabelGroup?
    let isActive: Bool
    let onAppearLoad: () -> Void
    let onSelect: () -> Void

    var body: some View {
        VStack(spacing: 4) {
            ZStack(alignment: .bottomLeading) {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.black.opacity(0.55))

                if let thumbnail {
                    CGImageView(cgImage: thumbnail)
                        .aspectRatio(contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 5))
                } else {
                    ProgressView().controlSize(.small)
                }

                if let group {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color(hex: group.colorHex))
                        .frame(height: 4)
                        .padding(.horizontal, 4)
                        .padding(.bottom, 3)
                }
            }
            .frame(width: 122, height: 82)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(
                        isActive ? StudioTheme.accentBlue : Color.white.opacity(0.12),
                        lineWidth: isActive ? 2.5 : 1
                    )
            )

            Text(photo.filename)
                .font(.system(size: 10, weight: isActive ? .semibold : .regular))
                .foregroundStyle(isActive ? .white : StudioTheme.textSecondary)
                .lineLimit(1)
                .frame(width: 122)
        }
        .contentShape(Rectangle())
        .onAppear(perform: onAppearLoad)
        .onTapGesture(perform: onSelect)
    }
}
