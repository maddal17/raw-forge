import RawForgeCore
import SwiftUI

struct RecipeInspectorView: View {
    @ObservedObject var viewModel: AppViewModel
    @State private var showTrimSection = false

    var body: some View {
        VStack(spacing: 0) {
            histogramPanel
            Divider().background(StudioTheme.borderSubtle)

            if let targetGroup = viewModel.inspectorTargetGroup {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        groupRecipeHeader(targetGroup)
                        presetAndClipboardRow(targetGroup)
                        Divider().background(StudioTheme.borderSubtle)
                        whiteBalanceSection(targetGroup)
                        Divider().background(StudioTheme.borderSubtle)
                        lightToneSection(targetGroup)
                        Divider().background(StudioTheme.borderSubtle)
                        colorSection(targetGroup)
                        Divider().background(StudioTheme.borderSubtle)
                        detailOpticsSection(targetGroup)

                        if let active = viewModel.activePhoto {
                            Divider().background(StudioTheme.borderSubtle)
                            perPhotoTrimSection(for: active)
                        }
                    }
                    .padding(14)
                }
            } else {
                unassignedInspectorState
            }
        }
        .background(StudioTheme.surfaceBg)
    }

    private var histogramPanel: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("HISTOGRAM")
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(StudioTheme.textSecondary)
                Spacer()
                if viewModel.activePhoto != nil {
                    Text(String(format: "As Shot: %.0fK / %+.0f", viewModel.activeAsShotTemperature, viewModel.activeAsShotTint))
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(StudioTheme.textSecondary)
                }
            }

            HistogramCanvas(data: viewModel.activeHistogram)
                .frame(height: 82)
                .background(Color.black.opacity(0.45))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(StudioTheme.borderSubtle, lineWidth: 1)
                )
        }
        .padding(.horizontal, 14)
        .padding(.top, 12)
        .padding(.bottom, 10)
    }

    private func groupRecipeHeader(_ group: LabelGroup) -> some View {
        let memberCount = viewModel.photoCount(in: group.id)
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Circle()
                    .fill(Color(hex: group.colorHex))
                    .frame(width: 11, height: 11)
                Text(group.name)
                    .font(.system(size: 13.5, weight: .bold))
                    .foregroundStyle(.white)
                Spacer()
                Text("\(memberCount) photo\(memberCount == 1 ? "" : "s")")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Color(hex: group.colorHex))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(Color(hex: group.colorHex).opacity(0.18))
                    .clipShape(Capsule())
            }
            Text("Changes apply simultaneously to all photos labeled \"\(group.name)\"")
                .font(.system(size: 10.5))
                .foregroundStyle(StudioTheme.textSecondary)
        }
        .padding(10)
        .background(Color(hex: group.colorHex).opacity(0.10))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color(hex: group.colorHex).opacity(0.42), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func presetAndClipboardRow(_ group: LabelGroup) -> some View {
        HStack(spacing: 6) {
            Menu {
                ForEach(RecipePreset.allCases) { preset in
                    Button(preset.displayName) {
                        viewModel.setGroupRecipe(groupID: group.id, recipe: preset.recipe)
                    }
                }
            } label: {
                Label("Preset", systemImage: "wand.and.stars")
                    .font(.system(size: 11.5))
            }
            .menuStyle(.borderedButton)
            .controlSize(.small)

            Spacer()

            Button("Copy") {
                viewModel.copyRecipe(from: group.id)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

            Button("Paste") {
                viewModel.pasteRecipe(to: group.id)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(viewModel.clipboardRecipe == nil)

            Button("Reset") {
                viewModel.setGroupRecipe(groupID: group.id, recipe: EditRecipe())
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(!group.recipe.hasAdjustments)
        }
    }

    private func whiteBalanceSection(_ group: LabelGroup) -> some View {
        let recipe = group.recipe
        return VStack(alignment: .leading, spacing: 8) {
            Text("WHITE BALANCE")
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(StudioTheme.textSecondary)

            Picker("", selection: Binding(
                get: { recipe.whiteBalanceMode },
                set: { mode in
                    viewModel.updateGroupRecipe(groupID: group.id, isDragging: false) {
                        $0.whiteBalanceMode = mode
                    }
                }
            )) {
                ForEach(WhiteBalanceMode.allCases) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .controlSize(.small)

            if recipe.whiteBalanceMode == .asShotOffset {
                RecipeSlider(
                    "Temp Shift",
                    value: recipe.temperatureShift,
                    in: -2000...2000,
                    defaultValue: 0,
                    format: "%+.0f",
                    unit: " K"
                ) { val, dragging in
                    viewModel.updateGroupRecipe(groupID: group.id, isDragging: dragging) { $0.temperatureShift = val }
                }
            } else {
                RecipeSlider(
                    "Target Kelvin",
                    value: recipe.customKelvin,
                    in: 2200...12000,
                    defaultValue: 5500,
                    format: "%.0f",
                    unit: " K"
                ) { val, dragging in
                    viewModel.updateGroupRecipe(groupID: group.id, isDragging: dragging) { $0.customKelvin = val }
                }
            }

            RecipeSlider(
                "Tint",
                value: recipe.tint,
                in: -150...150,
                defaultValue: 0,
                format: "%+.0f"
            ) { val, dragging in
                viewModel.updateGroupRecipe(groupID: group.id, isDragging: dragging) { $0.tint = val }
            }
        }
    }

    private func lightToneSection(_ group: LabelGroup) -> some View {
        let recipe = group.recipe
        return VStack(alignment: .leading, spacing: 8) {
            Text("LIGHT & TONE")
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(StudioTheme.textSecondary)

            RecipeSlider("Exposure", value: recipe.exposure, in: -4.0...4.0, defaultValue: 0, format: "%+.2f", unit: " EV") { val, dragging in
                viewModel.updateGroupRecipe(groupID: group.id, isDragging: dragging) { $0.exposure = val }
            }
            RecipeSlider("Contrast", value: recipe.contrast, in: -100...100, defaultValue: 0, format: "%+.0f") { val, dragging in
                viewModel.updateGroupRecipe(groupID: group.id, isDragging: dragging) { $0.contrast = val }
            }
            RecipeSlider("Highlights", value: recipe.highlights, in: -100...100, defaultValue: 0, format: "%+.0f") { val, dragging in
                viewModel.updateGroupRecipe(groupID: group.id, isDragging: dragging) { $0.highlights = val }
            }
            RecipeSlider("Shadows", value: recipe.shadows, in: -100...100, defaultValue: 0, format: "%+.0f") { val, dragging in
                viewModel.updateGroupRecipe(groupID: group.id, isDragging: dragging) { $0.shadows = val }
            }
            RecipeSlider("Whites", value: recipe.whites, in: -100...100, defaultValue: 0, format: "%+.0f") { val, dragging in
                viewModel.updateGroupRecipe(groupID: group.id, isDragging: dragging) { $0.whites = val }
            }
            RecipeSlider("Blacks", value: recipe.blacks, in: -100...100, defaultValue: 0, format: "%+.0f") { val, dragging in
                viewModel.updateGroupRecipe(groupID: group.id, isDragging: dragging) { $0.blacks = val }
            }
            RecipeSlider("RAW Tone Boost", value: recipe.rawToneBoost, in: 0...100, defaultValue: 100, format: "%.0f", unit: "%") { val, dragging in
                viewModel.updateGroupRecipe(groupID: group.id, isDragging: dragging) { $0.rawToneBoost = val }
            }
        }
    }

    private func colorSection(_ group: LabelGroup) -> some View {
        let recipe = group.recipe
        return VStack(alignment: .leading, spacing: 8) {
            Text("COLOR")
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(StudioTheme.textSecondary)

            RecipeSlider("Vibrance", value: recipe.vibrance, in: -100...100, defaultValue: 0, format: "%+.0f") { val, dragging in
                viewModel.updateGroupRecipe(groupID: group.id, isDragging: dragging) { $0.vibrance = val }
            }
            RecipeSlider("Saturation", value: recipe.saturation, in: -100...100, defaultValue: 0, format: "%+.0f") { val, dragging in
                viewModel.updateGroupRecipe(groupID: group.id, isDragging: dragging) { $0.saturation = val }
            }
        }
    }

    private func detailOpticsSection(_ group: LabelGroup) -> some View {
        let recipe = group.recipe
        return VStack(alignment: .leading, spacing: 8) {
            Text("DETAIL & OPTICS")
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(StudioTheme.textSecondary)

            RecipeSlider("Sharpness", value: recipe.sharpness, in: 0...100, defaultValue: 25, format: "%.0f") { val, dragging in
                viewModel.updateGroupRecipe(groupID: group.id, isDragging: dragging) { $0.sharpness = val }
            }
            RecipeSlider("Clarity", value: recipe.clarity, in: 0...100, defaultValue: 0, format: "%.0f") { val, dragging in
                viewModel.updateGroupRecipe(groupID: group.id, isDragging: dragging) { $0.clarity = val }
            }
            RecipeSlider("Luminance NR", value: recipe.luminanceNoiseReduction, in: 0...100, defaultValue: 15, format: "%.0f") { val, dragging in
                viewModel.updateGroupRecipe(groupID: group.id, isDragging: dragging) { $0.luminanceNoiseReduction = val }
            }
            RecipeSlider("Color NR", value: recipe.colorNoiseReduction, in: 0...100, defaultValue: 35, format: "%.0f") { val, dragging in
                viewModel.updateGroupRecipe(groupID: group.id, isDragging: dragging) { $0.colorNoiseReduction = val }
            }
            RecipeSlider("Vignette", value: recipe.vignette, in: -100...100, defaultValue: 0, format: "%+.0f") { val, dragging in
                viewModel.updateGroupRecipe(groupID: group.id, isDragging: dragging) { $0.vignette = val }
            }

            Toggle("Camera Lens Correction", isOn: Binding(
                get: { recipe.lensCorrection },
                set: { val in viewModel.updateGroupRecipe(groupID: group.id, isDragging: false) { $0.lensCorrection = val } }
            ))
            .font(.system(size: 11.5))
            .controlSize(.small)

            Toggle("RAW Highlight Recovery", isOn: Binding(
                get: { recipe.highlightRecovery },
                set: { val in viewModel.updateGroupRecipe(groupID: group.id, isDragging: false) { $0.highlightRecovery = val } }
            ))
            .font(.system(size: 11.5))
            .controlSize(.small)
        }
    }

    private func perPhotoTrimSection(for photo: PhotoItem) -> some View {
        let trim = viewModel.trims[photo.id] ?? PhotoTrim()
        return DisclosureGroup(isExpanded: $showTrimSection) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Fine micro-trim layered only on \(photo.filename)")
                    .font(.system(size: 10.5))
                    .foregroundStyle(StudioTheme.textSecondary)

                RecipeSlider("Exposure Trim", value: trim.exposureTrim, in: -1.5...1.5, defaultValue: 0, format: "%+.2f", unit: " EV") { val, _ in
                    viewModel.updateActivePhotoTrim { $0.exposureTrim = val }
                }
                RecipeSlider("Temp Trim", value: trim.temperatureTrim, in: -800...800, defaultValue: 0, format: "%+.0f", unit: " K") { val, _ in
                    viewModel.updateActivePhotoTrim { $0.temperatureTrim = val }
                }
            }
            .padding(.top, 6)
        } label: {
            HStack {
                Text("PER-PHOTO FINE TRIM")
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(StudioTheme.textSecondary)
                if trim.hasTrim {
                    Circle().fill(Color.orange).frame(width: 6, height: 6)
                }
            }
        }
    }

    private var unassignedInspectorState: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    Label("Assign a Lighting Group to Edit", systemImage: "tag.circle.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                    Text("RawForge edits photos through shared Lighting Groups so every photo with similar lighting renders cohesively as an album.")
                        .font(.system(size: 11.5))
                        .foregroundStyle(StudioTheme.textSecondary)
                }
                .padding(12)
                .background(StudioTheme.elevatedBg)
                .clipShape(RoundedRectangle(cornerRadius: 8))

                if viewModel.activePhoto != nil || !viewModel.selectedPhotoIDs.isEmpty {
                    Text("QUICK ASSIGN SELECTION:")
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(StudioTheme.textSecondary)

                    ForEach(viewModel.groups) { group in
                        Button {
                            viewModel.assignSelectedOrActive(to: group.id, advanceInLoupe: false)
                        } label: {
                            HStack(spacing: 8) {
                                Circle()
                                    .fill(Color(hex: group.colorHex))
                                    .frame(width: 10, height: 10)
                                Text(group.name)
                                    .font(.system(size: 12.5, weight: .medium))
                                Spacer()
                                if let shortcut = group.shortcutNumber {
                                    Text("Key \(shortcut)")
                                        .font(.system(size: 10, design: .monospaced))
                                        .foregroundStyle(StudioTheme.textSecondary)
                                }
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .background(Color(hex: group.colorHex).opacity(0.14))
                            .overlay(
                                RoundedRectangle(cornerRadius: 7)
                                    .stroke(Color(hex: group.colorHex).opacity(0.45), lineWidth: 1)
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 7))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(14)
        }
    }
}

private struct HistogramCanvas: View {
    let data: HistogramData

    var body: some View {
        Canvas { ctx, size in
            let w = size.width
            let h = size.height
            guard w > 4 && h > 4 else { return }

            func drawChannel(_ bins: [Double], color: Color) {
                guard bins.count > 1 else { return }
                var path = Path()
                path.move(to: CGPoint(x: 0, y: h))
                let step = w / CGFloat(bins.count - 1)
                for (i, val) in bins.enumerated() {
                    let x = CGFloat(i) * step
                    let y = h - CGFloat(max(0, min(1, val))) * (h - 4)
                    path.addLine(to: CGPoint(x: x, y: y))
                }
                path.addLine(to: CGPoint(x: w, y: h))
                path.closeSubpath()
                ctx.fill(path, with: .color(color.opacity(0.28)))
                ctx.stroke(path, with: .color(color.opacity(0.85)), lineWidth: 1)
            }

            drawChannel(data.red, color: .red)
            drawChannel(data.green, color: .green)
            drawChannel(data.blue, color: .blue)
            drawChannel(data.luminance, color: .white.opacity(0.5))
        }
    }
}
