import AppKit
import CoreImage
import RawForgeCore
import SwiftUI
import UniformTypeIdentifiers

struct SettingsSheetView: View {
    @ObservedObject var viewModel: AppViewModel
    let returnToExport: Bool
    @State private var selectedTab: SettingsTab

    init(viewModel: AppViewModel, initialTab: SettingsTab = .watermark, returnToExport: Bool = false) {
        self.viewModel = viewModel
        self.returnToExport = returnToExport
        _selectedTab = State(initialValue: initialTab)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("RawForge Settings")
                    .font(.headline)
                Spacer()
                Picker("", selection: $selectedTab) {
                    ForEach(SettingsTab.allCases) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 470)
                Spacer()
                Button(returnToExport ? "Done (Back to Export)" : "Done") {
                    viewModel.dismissSettingsAndReturnToExportIfNeeded(returnToExport)
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            }
            .padding(16)
            .background(StudioTheme.surfaceBg)

            Divider().background(StudioTheme.borderSubtle)

            Group {
                switch selectedTab {
                case .watermark:
                    watermarkTab
                case .metadata:
                    metadataTab
                case .engine:
                    engineTab
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: 780, height: 590)
        .background(StudioTheme.canvasBg)
    }

    private var watermarkTab: some View {
        HStack(spacing: 18) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 10) {
                        Image(systemName: viewModel.globalSettings.watermark.isEnabled ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                            .foregroundStyle(viewModel.globalSettings.watermark.isEnabled ? Color.green : Color.orange)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(viewModel.globalSettings.watermark.isEnabled
                                 ? "Author Watermark Enabled"
                                 : "Watermark Currently OFF — Toggle ON or edit any control")
                                .font(.system(size: 12.5, weight: .semibold))
                            Text("Applied consistently to Big Preview and exported files.")
                                .font(.caption2)
                                .foregroundStyle(StudioTheme.textSecondary)
                        }
                        Spacer()
                        Toggle("", isOn: $viewModel.globalSettings.watermark.isEnabled)
                            .labelsHidden()
                            .toggleStyle(.switch)
                    }
                    .padding(10)
                    .background((viewModel.globalSettings.watermark.isEnabled ? Color.green : Color.orange).opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke((viewModel.globalSettings.watermark.isEnabled ? Color.green : Color.orange).opacity(0.35), lineWidth: 1)
                    )

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Author Text (supports {year} and {camera})")
                            .font(.caption)
                            .foregroundStyle(StudioTheme.textSecondary)
                        TextField("© {year} Studio Name", text: watermarkBinding(\.authorText))
                            .textFieldStyle(.roundedBorder)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Optional PNG/SVG/PDF Logo Overlay")
                            .font(.caption)
                            .foregroundStyle(StudioTheme.textSecondary)
                        HStack {
                            TextField("No logo selected", text: watermarkBinding(\.logoImagePath))
                                .textFieldStyle(.roundedBorder)
                            Button("Browse…") {
                                chooseLogoFile()
                            }
                            if !viewModel.globalSettings.watermark.logoImagePath.isEmpty {
                                Button("Clear") {
                                    viewModel.globalSettings.watermark.logoImagePath = ""
                                }
                            }
                        }
                    }

                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Placement")
                                .font(.caption)
                                .foregroundStyle(StudioTheme.textSecondary)
                            Picker("", selection: watermarkBinding(\.position)) {
                                ForEach(WatermarkPosition.allCases) { pos in
                                    Text(pos.displayName).tag(pos)
                                }
                            }
                            .labelsHidden()
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            Text("Typography")
                                .font(.caption)
                                .foregroundStyle(StudioTheme.textSecondary)
                            Picker("", selection: watermarkBinding(\.fontStyle)) {
                                ForEach(WatermarkFontStyle.allCases) { style in
                                    Text(style.displayName).tag(style)
                                }
                            }
                            .labelsHidden()
                        }
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        sliderRow("Size (% of short edge)", value: watermarkBinding(\.sizePercent), range: 1.0...12.0, fmt: "%.1f%%")
                        sliderRow("Opacity", value: watermarkBinding(\.opacity), range: 0.05...1.0, fmt: "%.2f")
                        sliderRow("Edge Margin", value: watermarkBinding(\.marginPercent), range: 0.5...10.0, fmt: "%.1f%%")
                    }

                    HStack(spacing: 16) {
                        Toggle("Drop Shadow", isOn: watermarkBinding(\.dropShadow))
                        Toggle("Dark Backing Pill", isOn: watermarkBinding(\.backgroundPill))
                    }

                    HStack(spacing: 10) {
                        Text("Text Color:")
                            .font(.caption)
                            .foregroundStyle(StudioTheme.textSecondary)
                        ForEach(["#FFFFFF", "#000000", "#F59E0B", "#E5E7EB"], id: \.self) { hex in
                            Circle()
                                .fill(Color(hex: hex))
                                .frame(width: 20, height: 20)
                                .overlay(
                                    Circle().stroke(
                                        viewModel.globalSettings.watermark.textColorHex == hex ? StudioTheme.accentBlue : Color.white.opacity(0.3),
                                        lineWidth: viewModel.globalSettings.watermark.textColorHex == hex ? 2.5 : 1
                                    )
                                )
                                .onTapGesture {
                                    var updated = viewModel.globalSettings.watermark
                                    updated.textColorHex = hex
                                    updated.isEnabled = true
                                    viewModel.globalSettings.watermark = updated
                                }
                        }
                    }
                }
                .padding(16)
            }

            // Live Watermark Preview Canvas
            VStack(alignment: .leading, spacing: 8) {
                Text("LIVE WATERMARK PREVIEW")
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(StudioTheme.textSecondary)

                WatermarkLivePreview(settings: viewModel.globalSettings.watermark)
                    .frame(width: 310, height: 230)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(StudioTheme.borderSubtle, lineWidth: 1))

                Text("Preview renders the exact CoreText + CoreImage compositing engine used on full-resolution exports.")
                    .font(.caption)
                    .foregroundStyle(StudioTheme.textSecondary)
                    .frame(width: 310, alignment: .leading)

                Spacer()
            }
            .padding(.top, 16)
            .padding(.trailing, 16)
        }
    }

    private var metadataTab: some View {
        ScrollView {
            HStack(alignment: .top, spacing: 20) {
                // Subtract Column
                VStack(alignment: .leading, spacing: 12) {
                    Label("SUBTRACT / PRIVACY STRIPPING", systemImage: "minus.circle.fill")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.orange)

                    Text("Choose which original camera fields are removed from exported photos.")
                        .font(.caption)
                        .foregroundStyle(StudioTheme.textSecondary)

                    Toggle("Strip ALL Original Camera Metadata", isOn: $viewModel.globalSettings.metadata.stripAllOriginalMetadata)
                        .font(.system(size: 12.5, weight: .semibold))

                    Divider().background(StudioTheme.borderSubtle)

                    Group {
                        Toggle("Remove GPS Coordinates & Location", isOn: $viewModel.globalSettings.metadata.removeGPS)
                        Toggle("Remove Camera Body/Lens Serials & MakerNotes", isOn: $viewModel.globalSettings.metadata.removeCameraSerialAndMakerNotes)
                        Toggle("Remove Capture EXIF (ISO, Shutter, Aperture, Date)", isOn: $viewModel.globalSettings.metadata.removeCaptureExif)
                        Toggle("Remove Original Author / Copyright Attribution", isOn: $viewModel.globalSettings.metadata.removeOriginalAttribution)
                    }
                    .disabled(viewModel.globalSettings.metadata.stripAllOriginalMetadata)
                    .font(.system(size: 12))
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(StudioTheme.surfaceBg)
                .clipShape(RoundedRectangle(cornerRadius: 10))

                // Add Column
                VStack(alignment: .leading, spacing: 10) {
                    Label("ADD / AUTHOR & ALBUM TAGS", systemImage: "plus.circle.fill")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(StudioTheme.accentBlue)

                    Text("Non-empty fields are injected into EXIF/TIFF/IPTC headers of exported files.")
                        .font(.caption)
                        .foregroundStyle(StudioTheme.textSecondary)

                    metadataField("Author / Artist", placeholder: "e.g., Jane Doe", text: $viewModel.globalSettings.metadata.authorName)
                    metadataField("Copyright Notice", placeholder: "e.g., © 2026 Jane Doe Photography", text: $viewModel.globalSettings.metadata.copyrightNotice)
                    metadataField("Album / Project Title", placeholder: "e.g., Autumn Wedding Set", text: $viewModel.globalSettings.metadata.albumTitle)
                    metadataField("Description / Caption", placeholder: "Editorial description...", text: $viewModel.globalSettings.metadata.imageDescription)
                    metadataField("Creator Credit", placeholder: "Studio / Agency credit", text: $viewModel.globalSettings.metadata.creatorCredit)
                    metadataField("Keywords (comma-separated)", placeholder: "portrait, outdoor, film", text: $viewModel.globalSettings.metadata.keywordsCSV)

                    Toggle("Also tag each photo's Label Group name as an IPTC keyword", isOn: $viewModel.globalSettings.metadata.includeGroupNameAsKeyword)
                        .font(.system(size: 11.5))
                        .padding(.top, 4)
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(StudioTheme.surfaceBg)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            .padding(16)
        }
    }

    private var engineTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Apple Silicon Hardware Acceleration", systemImage: "cpu.fill")
                        .font(.headline)

                    Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 8) {
                        GridRow {
                            Text("Processor:").foregroundStyle(StudioTheme.textSecondary)
                            Text(viewModel.hardware.chipName).fontWeight(.semibold)
                        }
                        GridRow {
                            Text("Core Topology:").foregroundStyle(StudioTheme.textSecondary)
                            Text("\(viewModel.hardware.performanceCores) Performance + \(viewModel.hardware.efficiencyCores) Efficiency (\(viewModel.hardware.totalLogicalCores) total)")
                        }
                        GridRow {
                            Text("Metal GPU:").foregroundStyle(StudioTheme.textSecondary)
                            Text("\(viewModel.hardware.metalDeviceName) · Unified Memory: \(viewModel.hardware.hasUnifiedMemory ? "Yes (Zero-Copy)" : "Discrete")")
                        }
                        GridRow {
                            Text("System Memory:").foregroundStyle(StudioTheme.textSecondary)
                            Text(String(format: "%.0f GB", viewModel.hardware.physicalMemoryGB))
                        }
                        GridRow {
                            Text("Auto Batch Concurrency:").foregroundStyle(StudioTheme.textSecondary)
                            Text("\(viewModel.hardware.optimalBatchConcurrency) parallel Metal + P-core workers")
                        }
                    }
                    .font(.system(size: 12.5))
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(StudioTheme.surfaceBg)
                .clipShape(RoundedRectangle(cornerRadius: 10))

                VStack(alignment: .leading, spacing: 10) {
                    Text("BATCH WORKER OVERRIDE & SCANNING")
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(StudioTheme.textSecondary)

                    HStack {
                        Text("Batch Workers:")
                        Picker("", selection: $viewModel.globalSettings.exportConfig.manualWorkerCount) {
                            Text("Auto (\(viewModel.hardware.optimalBatchConcurrency) workers)").tag(0)
                            ForEach([2, 4, 6, 8, 10, 12], id: \.self) { count in
                                Text("\(count) workers").tag(count)
                            }
                        }
                        .frame(width: 210)
                    }

                    Toggle("Also load standard JPG / HEIC / PNG / TIFF files when scanning folders", isOn: $viewModel.globalSettings.includeStandardImages)
                        .onChange(of: viewModel.globalSettings.includeStandardImages) { _, _ in
                            Task { await viewModel.reloadCurrentFolder() }
                        }
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(StudioTheme.surfaceBg)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            .padding(16)
        }
    }

    private func metadataField(_ title: String, placeholder: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.caption)
                .foregroundStyle(StudioTheme.textSecondary)
            TextField(placeholder, text: text)
                .textFieldStyle(.roundedBorder)
        }
    }

    private func sliderRow(_ title: String, value: Binding<Double>, range: ClosedRange<Double>, fmt: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(title).font(.caption)
                Spacer()
                Text(String(format: fmt, value.wrappedValue))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(StudioTheme.textSecondary)
            }
            Slider(value: value, in: range).controlSize(.small)
        }
    }

    private func watermarkBinding<Value>(_ keyPath: WritableKeyPath<WatermarkSettings, Value>) -> Binding<Value> {
        Binding(
            get: { viewModel.globalSettings.watermark[keyPath: keyPath] },
            set: { newValue in
                var updated = viewModel.globalSettings.watermark
                updated[keyPath: keyPath] = newValue
                if !updated.isEnabled {
                    updated.isEnabled = true
                }
                viewModel.globalSettings.watermark = updated
            }
        )
    }

    private func chooseLogoFile() {
        let panel = NSOpenPanel()
        panel.title = "Choose Watermark Logo (PNG, SVG, or PDF recommended)"
        panel.allowedContentTypes = [.png, .jpeg, .tiff, .heic, .svg, .pdf]
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            var updated = viewModel.globalSettings.watermark
            updated.logoImagePath = url.path
            updated.isEnabled = true
            viewModel.globalSettings.watermark = updated
        }
    }
}

private struct WatermarkLivePreview: View {
    let settings: WatermarkSettings

    private static let previewContext = SendableCIContext(CIContext())

    var body: some View {
        ZStack(alignment: .topLeading) {
            if let cg = renderPreview() {
                CGImageView(cgImage: cg)
                    .aspectRatio(contentMode: .fill)
            } else {
                Color.black
            }

            if !settings.isEnabled {
                Text("DISABLED — Toggle ON above or edit any control")
                    .font(.system(size: 9.5, weight: .bold))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.orange)
                    .clipShape(Capsule())
                    .padding(8)
            }
        }
    }

    private func renderPreview() -> CGImage? {
        let width = 620
        let height = 460
        let baseCI = CIImage(color: CIColor(red: 0.16, green: 0.24, blue: 0.34))
            .cropped(to: CGRect(x: 0, y: 0, width: width, height: height))

        let sun = CIFilter(name: "CIRadialGradient", parameters: [
            "inputCenter": CIVector(x: 430, y: 310),
            "inputRadius0": 15.0,
            "inputRadius1": 280.0,
            "inputColor0": CIColor(red: 0.96, green: 0.72, blue: 0.42, alpha: 0.85),
            "inputColor1": CIColor(red: 0.12, green: 0.16, blue: 0.24, alpha: 0.0)
        ])?.outputImage?.cropped(to: baseCI.extent)

        var previewSettings = settings
        previewSettings.isEnabled = true
        let composed = WatermarkRenderer.apply(
            previewSettings,
            to: sun?.composited(over: baseCI) ?? baseCI,
            cameraModel: "Lumix G95"
        )
        return Self.previewContext.rawContext.createCGImage(composed, from: composed.extent)
    }
}
