import AppKit
import CoreGraphics
import RawForgeCore
import SwiftUI

enum StudioTheme {
    static let canvasBg = Color(red: 0.08, green: 0.085, blue: 0.098)
    static let surfaceBg = Color(red: 0.115, green: 0.122, blue: 0.14)
    static let elevatedBg = Color(red: 0.15, green: 0.16, blue: 0.185)
    static let borderSubtle = Color.white.opacity(0.08)
    static let textPrimary = Color.white.opacity(0.94)
    static let textSecondary = Color.white.opacity(0.60)
    static let accentBlue = Color(red: 0.31, green: 0.56, blue: 0.97)
}

extension Color {
    init(hex: String) {
        let rgba = RGBAColor(hex: hex)
        self.init(red: rgba.r, green: rgba.g, blue: rgba.b, opacity: rgba.a)
    }
}

/// Reusable develop slider with value readout and double-click-to-reset behavior.
struct RecipeSlider: View {
    let label: String
    let value: Double
    let range: ClosedRange<Double>
    let defaultValue: Double
    let formatString: String
    let unitSuffix: String
    let onChanged: (Double, Bool) -> Void

    @State private var isEditing: Bool = false

    init(
        _ label: String,
        value: Double,
        in range: ClosedRange<Double>,
        defaultValue: Double = 0,
        format: String = "%.0f",
        unit: String = "",
        onChanged: @escaping (Double, Bool) -> Void
    ) {
        self.label = label
        self.value = value
        self.range = range
        self.defaultValue = defaultValue
        self.formatString = format
        self.unitSuffix = unit
        self.onChanged = onChanged
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(label)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(StudioTheme.textPrimary)
                    .help("Double-click to reset \(label)")
                    .onTapGesture(count: 2) {
                        onChanged(defaultValue, false)
                    }
                Spacer()
                Text("\(String(format: formatString, value))\(unitSuffix)")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(abs(value - defaultValue) > 0.001 ? StudioTheme.accentBlue : StudioTheme.textSecondary)
                    .onTapGesture(count: 2) {
                        onChanged(defaultValue, false)
                    }
            }

            Slider(
                value: Binding(
                    get: { value },
                    set: { newValue in
                        onChanged(newValue, true)
                    }
                ),
                in: range,
                onEditingChanged: { editing in
                    isEditing = editing
                    if !editing {
                        onChanged(value, false)
                    }
                }
            )
            .controlSize(.small)
        }
    }
}

/// Renders a `CGImage` cleanly inside SwiftUI without extra wrapper conversions.
struct CGImageView: View {
    let cgImage: CGImage

    var body: some View {
        Image(decorative: cgImage, scale: 1.0, orientation: .up)
            .resizable()
    }
}

/// Modal editor for creating or updating a Lighting Label Group.
struct GroupEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    let title: String
    @State var name: String
    @State var selectedHex: String
    let onSave: (String, String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title)
                .font(.headline)

            VStack(alignment: .leading, spacing: 6) {
                Text("Group Name")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("e.g., Ceremony Shade, Reception Warm", text: $name)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Label Color")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack(spacing: 10) {
                    ForEach(LabelGroup.paletteHexes, id: \.self) { hex in
                        Circle()
                            .fill(Color(hex: hex))
                            .frame(width: 24, height: 24)
                            .overlay(
                                Circle()
                                    .stroke(Color.white, lineWidth: selectedHex == hex ? 2.5 : 0)
                            )
                            .scaleEffect(selectedHex == hex ? 1.12 : 1.0)
                            .onTapGesture {
                                selectedHex = hex
                            }
                    }
                }
            }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save") {
                    onSave(name, selectedHex)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .frame(width: 360)
    }
}
