import AppKit
import RawForgeCore
import SwiftUI

struct ExportModalView: View {
    @ObservedObject var viewModel: AppViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let targetPhotos = viewModel.itemsForExportScope(viewModel.exportScope)

        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Batch Convert & Export")
                        .font(.headline)
                    Text("\(targetPhotos.count) photo\(targetPhotos.count == 1 ? "" : "s") queued · \(viewModel.hardware.summaryBadge)")
                        .font(.caption)
                        .foregroundStyle(StudioTheme.textSecondary)
                }
                Spacer()
                Button("Close") { dismiss() }
                    .disabled(viewModel.isExporting)
            }
            .padding(16)
            .background(StudioTheme.surfaceBg)

            Divider().background(StudioTheme.borderSubtle)

            if let result = viewModel.exportResult {
                exportResultSummary(result)
            } else if viewModel.isExporting, let progress = viewModel.exportProgress {
                exportProgressPanel(progress)
            } else {
                exportConfigurationForm(targetCount: targetPhotos.count)
            }
        }
        .frame(width: 640, height: 570)
        .background(StudioTheme.canvasBg)
    }

    private func exportConfigurationForm(targetCount: Int) -> some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Scope & Destination
                    VStack(alignment: .leading, spacing: 10) {
                        Text("SCOPE & DESTINATION")
                            .font(.system(size: 10.5, weight: .semibold))
                            .foregroundStyle(StudioTheme.textSecondary)

                        Picker("Photos to Convert", selection: $viewModel.exportScope) {
                            ForEach(ExportScope.allCases) { scope in
                                let count = viewModel.itemsForExportScope(scope).count
                                if scope == .currentPhoto, let active = viewModel.activePhoto {
                                    Text("\(scope.displayName) — \(active.filename) (\(count))").tag(scope)
                                } else {
                                    Text("\(scope.displayName) (\(count))").tag(scope)
                                }
                            }
                        }

                        if targetCount == 0 {
                            HStack(spacing: 10) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundStyle(.orange)
                                Text("No photos match this scope (empty selection will not auto-convert the whole folder).")
                                    .font(.caption)
                                    .foregroundStyle(.orange)
                                Spacer()
                                if viewModel.activePhoto != nil {
                                    Button("Use Current Photo (1)") {
                                        viewModel.exportScope = .currentPhoto
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)
                                }
                                if !viewModel.photos.isEmpty {
                                    Button("Use All Photos (\(viewModel.photos.count))") {
                                        viewModel.exportScope = .allPhotos
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)
                                }
                            }
                            .padding(8)
                            .background(Color.orange.opacity(0.12))
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                        }

                        HStack {
                            Text("Output Folder:")
                                .frame(width: 110, alignment: .leading)
                            Text(viewModel.exportDestinationURL?.path ?? "Not selected")
                                .font(.system(size: 11.5, design: .monospaced))
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .padding(6)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(StudioTheme.elevatedBg)
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                            Button("Choose…") {
                                viewModel.chooseExportDestinationPanel()
                            }
                        }

                        Toggle("Organize exported photos into subfolders named after their Label Group", isOn: $viewModel.globalSettings.exportConfig.organizeIntoGroupSubfolders)
                            .font(.system(size: 12))
                    }
                    .padding(12)
                    .background(StudioTheme.surfaceBg)
                    .clipShape(RoundedRectangle(cornerRadius: 10))

                    // Format & Image Settings
                    VStack(alignment: .leading, spacing: 10) {
                        Text("FORMAT & COLOR")
                            .font(.system(size: 10.5, weight: .semibold))
                            .foregroundStyle(StudioTheme.textSecondary)

                        HStack(spacing: 16) {
                            Picker("Target Format", selection: $viewModel.globalSettings.exportConfig.format) {
                                ForEach(ExportFormat.allCases) { fmt in
                                    Text(fmt.displayName).tag(fmt)
                                }
                            }
                            .frame(width: 260)

                            Picker("Color Space", selection: $viewModel.globalSettings.exportConfig.colorSpace) {
                                ForEach(ExportColorSpace.allCases) { cs in
                                    Text(cs.displayName).tag(cs)
                                }
                            }
                        }

                        if viewModel.globalSettings.exportConfig.format.supportsQuality {
                            HStack {
                                Text("Compression Quality:")
                                Slider(value: $viewModel.globalSettings.exportConfig.quality, in: 0.4...1.0)
                                Text("\(Int((viewModel.globalSettings.exportConfig.quality * 100).rounded()))%")
                                    .font(.system(size: 11.5, design: .monospaced))
                                    .frame(width: 44)
                            }
                        }

                        if viewModel.globalSettings.exportConfig.format.supports16Bit {
                            Toggle("16-bit Deep Color Export (PNG / TIFF)", isOn: $viewModel.globalSettings.exportConfig.bitDepth16)
                                .font(.system(size: 12))
                        }

                        HStack(spacing: 12) {
                            Picker("Resize", selection: $viewModel.globalSettings.exportConfig.resizeMode) {
                                ForEach(ResizeMode.allCases) { mode in
                                    Text(mode.displayName).tag(mode)
                                }
                            }
                            .frame(width: 260)

                            if viewModel.globalSettings.exportConfig.resizeMode == .maxLongEdge {
                                TextField("Max px", value: $viewModel.globalSettings.exportConfig.maxLongEdgePixels, format: .number)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(width: 90)
                                Text("px long edge")
                                    .font(.caption)
                                    .foregroundStyle(StudioTheme.textSecondary)
                            }
                        }
                    }
                    .padding(12)
                    .background(StudioTheme.surfaceBg)
                    .clipShape(RoundedRectangle(cornerRadius: 10))

                    // Naming, Watermark & Metadata
                    VStack(alignment: .leading, spacing: 10) {
                        Text("WATERMARK, METADATA & NAMING")
                            .font(.system(size: 10.5, weight: .semibold))
                            .foregroundStyle(StudioTheme.textSecondary)

                        HStack {
                            Toggle("Apply Author Watermark", isOn: $viewModel.globalSettings.watermark.isEnabled)
                            Spacer()
                            Button("Watermark Settings…") {
                                viewModel.openSettings(tab: .watermark, returnToExport: true)
                            }
                            .buttonStyle(.link)
                        }

                        if viewModel.globalSettings.watermark.isEnabled {
                            HStack(spacing: 10) {
                                TextField("© {year} Author Name", text: $viewModel.globalSettings.watermark.authorText)
                                    .textFieldStyle(.roundedBorder)
                                Picker("", selection: $viewModel.globalSettings.watermark.position) {
                                    ForEach(WatermarkPosition.allCases) { pos in
                                        Text(pos.displayName).tag(pos)
                                    }
                                }
                                .labelsHidden()
                                .frame(width: 155)
                            }
                        }

                        HStack {
                            Text("Metadata Rules:")
                                .font(.system(size: 12))
                            Text(metadataSummary)
                                .font(.caption)
                                .foregroundStyle(StudioTheme.textSecondary)
                            Spacer()
                            Button("Edit Metadata…") {
                                viewModel.openSettings(tab: .metadata, returnToExport: true)
                            }
                            .buttonStyle(.link)
                        }

                        HStack(spacing: 10) {
                            TextField("Filename Prefix", text: $viewModel.globalSettings.exportConfig.filenamePrefix)
                                .textFieldStyle(.roundedBorder)
                            TextField("Filename Suffix", text: $viewModel.globalSettings.exportConfig.filenameSuffix)
                                .textFieldStyle(.roundedBorder)
                            Picker("Collisions", selection: $viewModel.globalSettings.exportConfig.collisionPolicy) {
                                ForEach(FilenameCollisionPolicy.allCases) { pol in
                                    Text(pol.displayName).tag(pol)
                                }
                            }
                            .frame(width: 190)
                        }
                    }
                    .padding(12)
                    .background(StudioTheme.surfaceBg)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .padding(16)
            }

            Divider().background(StudioTheme.borderSubtle)

            HStack {
                Text("M-Chip Acceleration: \(viewModel.hardware.optimalBatchConcurrency) workers on \(viewModel.hardware.metalDeviceName)")
                    .font(.caption)
                    .foregroundStyle(StudioTheme.textSecondary)
                Spacer()
                Button("Convert \(targetCount) Photo\(targetCount == 1 ? "" : "s")") {
                    viewModel.startBatchExport()
                }
                .buttonStyle(.borderedProminent)
                .disabled(targetCount == 0)
            }
            .padding(14)
            .background(StudioTheme.surfaceBg)
        }
    }

    private func exportProgressPanel(_ progress: BatchProgressSnapshot) -> some View {
        VStack(spacing: 18) {
            Spacer()

            Image(systemName: "bolt.circle.fill")
                .font(.system(size: 44))
                .foregroundStyle(StudioTheme.accentBlue)

            Text("Converting on \(progress.gpuName)")
                .font(.title3.bold())

            ProgressView(value: progress.fractionCompleted)
                .progressViewStyle(.linear)
                .frame(width: 440)

            HStack(spacing: 28) {
                metricBlock(title: "Completed", value: "\(progress.completedCount) / \(progress.totalCount)")
                metricBlock(title: "Throughput", value: String(format: "%.2f photos/s", progress.photosPerSecond))
                metricBlock(title: "Bandwidth", value: String(format: "%.1f MP/s", progress.megapixelsPerSecond))
                metricBlock(title: "Workers", value: "\(progress.activeWorkers)")
            }

            Text(progress.recentFile)
                .font(.system(size: 11.5, design: .monospaced))
                .foregroundStyle(StudioTheme.textSecondary)

            Button("Cancel Batch", role: .destructive) {
                viewModel.cancelBatchExport()
            }
            .buttonStyle(.bordered)

            Spacer()
        }
        .padding(24)
    }

    private func exportResultSummary(_ result: BatchExportResult) -> some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: result.failedCount == 0 ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                .font(.system(size: 46))
                .foregroundStyle(result.failedCount == 0 ? .green : .orange)

            Text(result.wasCancelled ? "Batch Cancelled" : "Conversion Complete")
                .font(.title2.bold())

            HStack(spacing: 24) {
                metricBlock(title: "Exported", value: "\(result.succeededCount)")
                metricBlock(title: "Failed", value: "\(result.failedCount)")
                metricBlock(title: "Total MP", value: String(format: "%.1f MP", result.totalMegapixels))
                metricBlock(title: "Time", value: String(format: "%.2fs", result.elapsedSeconds))
            }

            if !result.errors.isEmpty {
                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(result.errors, id: \.self) { err in
                            Text("• \(err)")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                    }
                    .padding(8)
                }
                .frame(maxHeight: 110)
                .background(StudioTheme.surfaceBg)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            HStack(spacing: 12) {
                Button("Reveal in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting(
                        result.exportedFiles.first.map { [$0] } ?? [result.outputDirectory]
                    )
                }
                .buttonStyle(.borderedProminent)

                Button("Done") {
                    viewModel.exportResult = nil
                    dismiss()
                }
                .buttonStyle(.bordered)
            }

            Spacer()
        }
        .padding(24)
    }

    private func metricBlock(title: String, value: String) -> some View {
        VStack(spacing: 3) {
            Text(value)
                .font(.system(size: 16, weight: .bold, design: .monospaced))
            Text(title)
                .font(.caption)
                .foregroundStyle(StudioTheme.textSecondary)
        }
    }

    private var metadataSummary: String {
        var parts: [String] = []
        let m = viewModel.globalSettings.metadata
        if m.stripAllOriginalMetadata {
            parts.append("Strip All Original")
        } else {
            if m.removeGPS { parts.append("-GPS") }
            if m.removeCameraSerialAndMakerNotes { parts.append("-Serials") }
            if m.removeCaptureExif { parts.append("-EXIF") }
        }
        if !m.authorName.isEmpty { parts.append("+\(m.authorName)") }
        if !m.copyrightNotice.isEmpty { parts.append("+Copyright") }
        if !m.keywordsCSV.isEmpty { parts.append("+Keywords") }
        return parts.isEmpty ? "Preserve camera metadata" : parts.joined(separator: " · ")
    }
}
