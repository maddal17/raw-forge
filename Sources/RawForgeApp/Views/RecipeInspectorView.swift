import RawForgeCore
import SwiftUI

struct RecipeInspectorView: View {
    @ObservedObject var viewModel: AppViewModel
    @State private var showTrimSection = false

    var body: some View {
        VStack(spacing: 0) {
            inspectorModeHeader
            Divider().background(StudioTheme.borderSubtle)

            if viewModel.inspectorMode == .pro {
                histogramPanel
                Divider().background(StudioTheme.borderSubtle)
            }

            if let ctx = viewModel.inspectorContext {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        inspectorContextHeader(ctx)

                        if viewModel.inspectorMode == .simple {
                            simpleControls(for: ctx.group)
                        } else {
                            proControls(for: ctx.group)
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

    private var inspectorModeHeader: some View {
        HStack(spacing: 10) {
            Text("INSPECTOR")
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(StudioTheme.textSecondary)

            Spacer()

            Picker("", selection: $viewModel.inspectorMode) {
                ForEach(InspectorMode.allCases) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .controlSize(.small)
            .frame(width: 148)
            .help("Simple shows curated presets, scene white balance, and color controls. Pro adds the live histogram and full RAW tuning.")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(StudioTheme.elevatedBg.opacity(0.65))
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
        .padding(.top, 10)
        .padding(.bottom, 10)
    }

    private func inspectorContextHeader(_ ctx: AppViewModel.InspectorGroupContext) -> some View {
        let group = ctx.group
        return VStack(alignment: .leading, spacing: 6) {
            if ctx.requiresAutoAssignOnEdit {
                HStack(spacing: 6) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.orange)
                    Text("Unlabeled Photo — Adjusting assigns to:")
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(.orange)
                }
            }

            HStack(spacing: 8) {
                Menu {
                    ForEach(viewModel.groups) { grp in
                        Button {
                            if ctx.requiresAutoAssignOnEdit {
                                viewModel.focusedGroupID = grp.id
                            } else {
                                viewModel.assignSelectedOrActive(to: grp.id, advanceInLoupe: false)
                            }
                        } label: {
                            Text(grp.name)
                        }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(Color(hex: group.colorHex))
                            .frame(width: 10, height: 10)
                        Text(group.name)
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(.white)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 9))
                            .foregroundStyle(StudioTheme.textSecondary)
                    }
                }
                .menuStyle(.borderlessButton)

                Spacer()

                if ctx.requiresAutoAssignOnEdit {
                    Button("Assign") {
                        viewModel.assignSelectedOrActive(to: group.id, advanceInLoupe: false)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.mini)
                } else {
                    Text("\(ctx.targetPhotoCount) photo\(ctx.targetPhotoCount == 1 ? "" : "s")")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(Color(hex: group.colorHex))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(Color(hex: group.colorHex).opacity(0.18))
                        .clipShape(Capsule())
                }
            }

            Text(
                ctx.requiresAutoAssignOnEdit
                    ? "Moving any preset or slider automatically labels \(ctx.targetPhotoCount == 1 ? "this photo" : "\(ctx.targetPhotoCount) selected photos") as \"\(group.name)\"."
                    : "Changes apply simultaneously to all photos labeled \"\(group.name)\""
            )
            .font(.system(size: 10.5))
            .foregroundStyle(StudioTheme.textSecondary)
        }
        .padding(10)
        .background(
            ctx.requiresAutoAssignOnEdit
                ? Color.orange.opacity(0.10)
                : Color(hex: group.colorHex).opacity(0.10)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(
                    ctx.requiresAutoAssignOnEdit
                        ? Color.orange.opacity(0.45)
                        : Color(hex: group.colorHex).opacity(0.42),
                    lineWidth: 1
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder
    private func simpleControls(for group: LabelGroup) -> some View {
        clipboardActionsRow(group)
        Divider().background(StudioTheme.borderSubtle)
        simplePresetsSection(group)
        Divider().background(StudioTheme.borderSubtle)
        simpleWhiteBalanceSection(group)
        Divider().background(StudioTheme.borderSubtle)
        simpleColorAndLightSection(group)
    }

    @ViewBuilder
    private func proControls(for group: LabelGroup) -> some View {
        proPresetAndClipboardRow(group)
        Divider().background(StudioTheme.borderSubtle)
        proWhiteBalanceSection(group)
        Divider().background(StudioTheme.borderSubtle)
        lightToneSection(group)
        Divider().background(StudioTheme.borderSubtle)
        colorSection(group)
        Divider().background(StudioTheme.borderSubtle)
        detailOpticsSection(group)

        if let active = viewModel.activePhoto {
            Divider().background(StudioTheme.borderSubtle)
            perPhotoTrimSection(for: active)
        }
    }

    private func clipboardActionsRow(_ group: LabelGroup) -> some View {
        HStack(spacing: 6) {
            Text("GROUP LOOK")
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(StudioTheme.textSecondary)

            Spacer()

            Button("Copy") { viewModel.copyRecipe(from: group.id) }
                .buttonStyle(.bordered)
                .controlSize(.small)

            Button("Paste") { viewModel.pasteRecipe(to: group.id) }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(viewModel.clipboardRecipe == nil)

            Button("Reset") { viewModel.setGroupRecipe(groupID: group.id, recipe: EditRecipe()) }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(!group.recipe.hasAdjustments)
        }
    }

    private func simplePresetsSection(_ group: LabelGroup) -> some View {
        let columns = [GridItem(.flexible(), spacing: 6), GridItem(.flexible(), spacing: 6)]
        return VStack(alignment: .leading, spacing: 10) {
            Text("CURATED PRESETS (16)")
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(StudioTheme.textSecondary)

            ForEach(PresetCategory.allCases) { category in
                VStack(alignment: .leading, spacing: 5) {
                    Text(category.displayName)
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(StudioTheme.textSecondary.opacity(0.9))

                    LazyVGrid(columns: columns, spacing: 6) {
                        ForEach(category.presets) { preset in
                            let isSelected = group.recipe == preset.recipe
                            Button {
                                viewModel.setGroupRecipe(groupID: group.id, recipe: preset.recipe)
                            } label: {
                                Text(preset.displayName)
                                    .font(.system(size: 11, weight: isSelected ? .semibold : .medium))
                                    .foregroundStyle(.white)
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 6)
                                    .background(isSelected ? StudioTheme.accentBlue.opacity(0.32) : StudioTheme.elevatedBg)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 6)
                                            .stroke(
                                                isSelected ? StudioTheme.accentBlue : StudioTheme.borderSubtle,
                                                lineWidth: isSelected ? 1.5 : 1
                                            )
                                    )
                                    .clipShape(RoundedRectangle(cornerRadius: 6))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    private func simpleWhiteBalanceSection(_ group: LabelGroup) -> some View {
        let recipe = group.recipe
        let matchedScene = SimpleWhiteBalanceScene.matching(recipe: recipe)
        let columns = [GridItem(.flexible(), spacing: 6), GridItem(.flexible(), spacing: 6), GridItem(.flexible(), spacing: 6)]
        let wbReadout: String = recipe.whiteBalanceMode == .customKelvin
            ? "\(Int(recipe.customKelvin.rounded())) K"
            : String(format: "As Shot %+.0fK", recipe.temperatureShift)

        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("WHITE BALANCE (SCENE)")
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(StudioTheme.textSecondary)
                Spacer()
                Text(wbReadout)
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(StudioTheme.accentBlue)
            }

            LazyVGrid(columns: columns, spacing: 6) {
                ForEach(SimpleWhiteBalanceScene.allCases) { scene in
                    let isSelected = matchedScene == scene
                    Button {
                        viewModel.updateGroupRecipe(groupID: group.id, isDragging: false) { r in
                            scene.apply(to: &r)
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: scene.symbolName)
                                .font(.system(size: 10.5))
                                .foregroundStyle(isSelected ? StudioTheme.accentBlue : .orange.opacity(0.85))
                            Text(scene.displayName)
                                .font(.system(size: 10.5, weight: isSelected ? .semibold : .medium))
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .padding(.horizontal, 4)
                        .background(isSelected ? StudioTheme.accentBlue.opacity(0.28) : StudioTheme.elevatedBg)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(isSelected ? StudioTheme.accentBlue : StudioTheme.borderSubtle, lineWidth: isSelected ? 1.5 : 1)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(.plain)
                }
            }

            if recipe.whiteBalanceMode == .asShotOffset {
                RecipeSlider(
                    "Warmth (Cool ↔ Warm)",
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
                    "Warmth (Kelvin)",
                    value: recipe.customKelvin,
                    in: 2500...9500,
                    defaultValue: 5500,
                    format: "%.0f",
                    unit: " K"
                ) { val, dragging in
                    viewModel.updateGroupRecipe(groupID: group.id, isDragging: dragging) { $0.customKelvin = val }
                }
            }

            RecipeSlider(
                "Color Tint (Green ↔ Magenta)",
                value: recipe.tint,
                in: -150...150,
                defaultValue: 0,
                format: "%+.0f"
            ) { val, dragging in
                viewModel.updateGroupRecipe(groupID: group.id, isDragging: dragging) { $0.tint = val }
            }
        }
    }

    private func simpleColorAndLightSection(_ group: LabelGroup) -> some View {
        let recipe = group.recipe
        return VStack(alignment: .leading, spacing: 8) {
            Text("COLOR & BRIGHTNESS")
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(StudioTheme.textSecondary)

            RecipeSlider("Brightness", value: recipe.exposure, in: -3.0...3.0, defaultValue: 0, format: "%+.2f", unit: " EV") { val, dragging in
                viewModel.updateGroupRecipe(groupID: group.id, isDragging: dragging) { $0.exposure = val }
            }
            RecipeSlider("Contrast", value: recipe.contrast, in: -100...100, defaultValue: 0, format: "%+.0f") { val, dragging in
                viewModel.updateGroupRecipe(groupID: group.id, isDragging: dragging) { $0.contrast = val }
            }
            RecipeSlider("Color Pop (Vibrance)", value: recipe.vibrance, in: -100...100, defaultValue: 0, format: "%+.0f") { val, dragging in
                viewModel.updateGroupRecipe(groupID: group.id, isDragging: dragging) { $0.vibrance = val }
            }
            RecipeSlider("Saturation", value: recipe.saturation, in: -100...100, defaultValue: 0, format: "%+.0f") { val, dragging in
                viewModel.updateGroupRecipe(groupID: group.id, isDragging: dragging) { $0.saturation = val }
            }
        }
    }

    private func proPresetAndClipboardRow(_ group: LabelGroup) -> some View {
        HStack(spacing: 6) {
            Menu {
                ForEach(PresetCategory.allCases) { category in
                    Section(category.displayName) {
                        ForEach(category.presets) { preset in
                            Button(preset.displayName) {
                                viewModel.setGroupRecipe(groupID: group.id, recipe: preset.recipe)
                            }
                        }
                    }
                }
            } label: {
                Label("Presets", systemImage: "wand.and.stars")
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

    private func proWhiteBalanceSection(_ group: LabelGroup) -> some View {
        let recipe = group.recipe
        let quickKelvins = [3200, 4200, 5000, 5500, 6500, 7500]
        return VStack(alignment: .leading, spacing: 8) {
            Text("WHITE BALANCE (PRO)")
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

            HStack(spacing: 4) {
                ForEach(quickKelvins, id: \.self) { kelvin in
                    let isActive = recipe.whiteBalanceMode == .customKelvin && abs(recipe.customKelvin - Double(kelvin)) < 120
                    Button("\(kelvin)K") {
                        viewModel.updateGroupRecipe(groupID: group.id, isDragging: false) { r in
                            r.whiteBalanceMode = .customKelvin
                            r.customKelvin = Double(kelvin)
                        }
                    }
                    .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
                    .background(isActive ? StudioTheme.accentBlue.opacity(0.3) : StudioTheme.elevatedBg)
                    .overlay(
                        RoundedRectangle(cornerRadius: 5)
                            .stroke(isActive ? StudioTheme.accentBlue : StudioTheme.borderSubtle, lineWidth: 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 5))
                    .buttonStyle(.plain)
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
                    Label("Open a Folder to Develop", systemImage: "folder.badge.plus")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                    Text("Load RAW photos and create Lighting Groups so every photo with similar lighting renders cohesively as an album.")
                        .font(.system(size: 11.5))
                        .foregroundStyle(StudioTheme.textSecondary)
                }
                .padding(12)
                .background(StudioTheme.elevatedBg)
                .clipShape(RoundedRectangle(cornerRadius: 8))
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
