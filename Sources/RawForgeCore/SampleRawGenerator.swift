import Foundation

/// Lighting simulation profile used when generating synthetic 16-bit LinearRaw `.dng` test albums.
public enum SampleLightingCondition: CaseIterable, Sendable {
    case daylightOutdoor
    case goldenHour
    case indoorTungsten
    case coolShade

    public var prefix: String {
        switch self {
        case .daylightOutdoor: return "DAY"
        case .goldenHour: return "GOLD"
        case .indoorTungsten: return "INDOOR"
        case .coolShade: return "SHADE"
        }
    }

    /// Simulated As-Shot white balance neutral multipliers `(R, G, B)` for DNG `AsShotNeutral`.
    public var asShotNeutral: (r: UInt32, g: UInt32, b: UInt32) {
        switch self {
        case .daylightOutdoor: return (4728, 10000, 6250)  // ~5500K neutral
        case .goldenHour: return (4200, 10000, 7800)       // Warm sunlit
        case .indoorTungsten: return (7100, 10000, 3900)   // Warm tungsten cast
        case .coolShade: return (4050, 10000, 8200)        // Cool blue shade
        }
    }

    /// Simulated scene base color tint & brightness (16-bit linear).
    public var sceneRGBScale: (r: Double, g: Double, b: Double) {
        switch self {
        case .daylightOutdoor: return (0.48, 0.56, 0.68)
        case .goldenHour: return (0.72, 0.52, 0.34)
        case .indoorTungsten: return (0.36, 0.28, 0.18)
        case .coolShade: return (0.34, 0.44, 0.62)
        }
    }
}

/// Generates genuine 16-bit LinearRaw `.dng` files with valid EXIF, GPS, and camera serial metadata for tests and demos.
public enum SampleRawGenerator {
    /// Generates a sample RAW album folder containing 12 16-bit `.dng` photos across 4 lighting conditions.
    public static func generateSampleAlbum(
        in directory: URL,
        count: Int = 12,
        width: Int = 640,
        height: Int = 426
    ) throws -> [URL] {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let conditions = SampleLightingCondition.allCases
        var created: [URL] = []

        for idx in 0..<count {
            let cond = conditions[idx % conditions.count]
            let fileURL = directory.appendingPathComponent(String(format: "%@_%03d.dng", cond.prefix, idx + 1))
            let data = makeLinearDNG(
                width: width,
                height: height,
                condition: cond,
                variant: idx,
                includeGPS: true,
                serialNumber: "RF-BODY-987654"
            )
            try data.write(to: fileURL, options: [.atomic])
            created.append(fileURL)
        }
        return created
    }

    /// Builds an uncompressed 16-bit LinearRaw DNG binary with valid TIFF/IFD0, ExifIFD, and GPSInfoIFD.
    public static func makeLinearDNG(
        width: Int = 320,
        height: Int = 240,
        condition: SampleLightingCondition = .daylightOutdoor,
        variant: Int = 0,
        includeGPS: Bool = true,
        serialNumber: String = "RF-BODY-987654"
    ) -> Data {
        func appendU16(_ buf: inout Data, _ v: UInt16) {
            var x = v.littleEndian
            withUnsafeBytes(of: &x) { buf.append(contentsOf: $0) }
        }
        func appendU32(_ buf: inout Data, _ v: UInt32) {
            var x = v.littleEndian
            withUnsafeBytes(of: &x) { buf.append(contentsOf: $0) }
        }
        func appendS32(_ buf: inout Data, _ v: Int32) {
            var x = v.littleEndian
            withUnsafeBytes(of: &x) { buf.append(contentsOf: $0) }
        }
        func appendRational(_ buf: inout Data, _ num: UInt32, _ den: UInt32) {
            appendU32(&buf, num)
            appendU32(&buf, den)
        }
        func appendSRational(_ buf: inout Data, _ num: Int32, _ den: Int32) {
            appendS32(&buf, num)
            appendS32(&buf, den)
        }

        // Generate scenic smooth gradient + architectural horizon & geometric blocks
        var pixels = Data(capacity: width * height * 6)
        let scale = condition.sceneRGBScale
        let horizon = Double(height) * (0.45 + Double(variant % 3) * 0.06)

        for y in 0..<height {
            let ny = Double(y) / Double(max(1, height - 1))
            let isSky = Double(y) < horizon
            for x in 0..<width {
                let nx = Double(x) / Double(max(1, width - 1))
                var rf: Double
                var gf: Double
                var bf: Double

                if isSky {
                    let skyFactor = 0.55 + 0.40 * (1.0 - ny)
                    rf = scale.r * skyFactor + 0.15 * nx
                    gf = scale.g * skyFactor + 0.12 * nx
                    bf = scale.b * skyFactor + 0.18 * (1.0 - nx)
                } else {
                    let groundFactor = 0.35 + 0.25 * ny
                    rf = scale.r * groundFactor + 0.10 * sin(nx * 12.0 + Double(variant))
                    gf = scale.g * groundFactor + 0.12 * cos(ny * 8.0)
                    bf = scale.b * groundFactor * 0.8
                }

                // Sun / highlight orb
                let dx = nx - (0.25 + Double(variant % 4) * 0.16)
                let dy = ny - 0.24
                let dist = sqrt(dx * dx + dy * dy)
                if dist < 0.08 {
                    let glow = (1.0 - dist / 0.08) * 0.55
                    rf += glow
                    gf += glow * 0.92
                    bf += glow * 0.72
                }

                let r16 = UInt16(max(1200, min(62000, rf * 52000.0)))
                let g16 = UInt16(max(1200, min(62000, gf * 52000.0)))
                let b16 = UInt16(max(1200, min(62000, bf * 52000.0)))
                appendU16(&pixels, r16)
                appendU16(&pixels, g16)
                appendU16(&pixels, b16)
            }
        }

        struct IFDEntry {
            let tag: UInt16
            let type: UInt16
            let count: UInt32
            let inlineVal: UInt32?
            let extraData: Data?
        }

        func serializeIFD(at startOffset: Int, entries: [IFDEntry]) -> Data {
            let sorted = entries.sorted { $0.tag < $1.tag }
            let extraStart = startOffset + 2 + sorted.count * 12 + 4
            var extra = Data()
            var out = Data()
            appendU16(&out, UInt16(sorted.count))
            for e in sorted {
                appendU16(&out, e.tag)
                appendU16(&out, e.type)
                appendU32(&out, e.count)
                if let inlineVal = e.inlineVal {
                    appendU32(&out, inlineVal)
                } else if let data = e.extraData {
                    let offset = UInt32(extraStart + extra.count)
                    extra.append(data)
                    if extra.count % 2 != 0 { extra.append(0) }
                    appendU32(&out, offset)
                }
            }
            appendU32(&out, 0) // next IFD = 0
            out.append(extra)
            return out
        }

        var bps = Data()
        appendU16(&bps, 16); appendU16(&bps, 16); appendU16(&bps, 16)

        var cm1 = Data()
        for (n, dn) in [
            (Int32(6722), Int32(10000)), (-635, 10000), (-963, 10000),
            (-4287, 10000), (12460, 10000), (2028, 10000),
            (-908, 10000), (2162, 10000), (5668, 10000)
        ] {
            appendSRational(&cm1, n, dn)
        }

        let neutral = condition.asShotNeutral
        var asn = Data()
        appendRational(&asn, neutral.r, 10000)
        appendRational(&asn, neutral.g, 10000)
        appendRational(&asn, neutral.b, 10000)

        var wl = Data()
        appendU32(&wl, 65535); appendU32(&wl, 65535); appendU32(&wl, 65535)

        let makeData = "RawForge SimCam\0".data(using: .ascii)!
        let modelData = "SimCam M1 RAW\0".data(using: .ascii)!
        let dateStr = "2026:11:10 14:32:10\0".data(using: .ascii)!
        let serialData = (serialNumber + "\0").data(using: .ascii)!

        var fNumberData = Data(); appendRational(&fNumberData, 28, 10)
        var expTimeData = Data(); appendRational(&expTimeData, 1, 250)
        var focalData = Data(); appendRational(&focalData, 50, 1)

        var latData = Data()
        appendRational(&latData, 41, 1); appendRational(&latData, 18, 1); appendRational(&latData, 3600, 100)
        var lonData = Data()
        appendRational(&lonData, 69, 1); appendRational(&lonData, 14, 1); appendRational(&lonData, 2400, 100)

        func build(exifOffset: UInt32, gpsOffset: UInt32, pixOffset: UInt32) -> (data: Data, exifOff: UInt32, gpsOff: UInt32, pixOff: UInt32) {
            var ifd0: [IFDEntry] = [
                IFDEntry(tag: 0x00FE, type: 4, count: 1, inlineVal: 0, extraData: nil),
                IFDEntry(tag: 0x0100, type: 4, count: 1, inlineVal: UInt32(width), extraData: nil),
                IFDEntry(tag: 0x0101, type: 4, count: 1, inlineVal: UInt32(height), extraData: nil),
                IFDEntry(tag: 0x0102, type: 3, count: 3, inlineVal: nil, extraData: bps),
                IFDEntry(tag: 0x0103, type: 3, count: 1, inlineVal: 1, extraData: nil),
                IFDEntry(tag: 0x0106, type: 3, count: 1, inlineVal: 34892, extraData: nil),
                IFDEntry(tag: 0x010F, type: 2, count: UInt32(makeData.count), inlineVal: nil, extraData: makeData),
                IFDEntry(tag: 0x0110, type: 2, count: UInt32(modelData.count), inlineVal: nil, extraData: modelData),
                IFDEntry(tag: 0x0111, type: 4, count: 1, inlineVal: pixOffset, extraData: nil),
                IFDEntry(tag: 0x0112, type: 3, count: 1, inlineVal: 1, extraData: nil),
                IFDEntry(tag: 0x0115, type: 3, count: 1, inlineVal: 3, extraData: nil),
                IFDEntry(tag: 0x0116, type: 4, count: 1, inlineVal: UInt32(height), extraData: nil),
                IFDEntry(tag: 0x0117, type: 4, count: 1, inlineVal: UInt32(pixels.count), extraData: nil),
                IFDEntry(tag: 0x011C, type: 3, count: 1, inlineVal: 1, extraData: nil),
                IFDEntry(tag: 0x0132, type: 2, count: UInt32(dateStr.count), inlineVal: nil, extraData: dateStr),
                IFDEntry(tag: 0x8769, type: 4, count: 1, inlineVal: exifOffset, extraData: nil),
                IFDEntry(tag: 0xC612, type: 1, count: 4, inlineVal: 0x00000401, extraData: nil),
                IFDEntry(tag: 0xC613, type: 1, count: 4, inlineVal: 0x00000101, extraData: nil),
                IFDEntry(tag: 0xC614, type: 2, count: UInt32(modelData.count), inlineVal: nil, extraData: modelData),
                IFDEntry(tag: 0xC61D, type: 4, count: 3, inlineVal: nil, extraData: wl),
                IFDEntry(tag: 0xC621, type: 10, count: 9, inlineVal: nil, extraData: cm1),
                IFDEntry(tag: 0xC628, type: 5, count: 3, inlineVal: nil, extraData: asn),
                IFDEntry(tag: 0xC65A, type: 3, count: 1, inlineVal: 21, extraData: nil)
            ]
            if includeGPS {
                ifd0.append(IFDEntry(tag: 0x8825, type: 4, count: 1, inlineVal: gpsOffset, extraData: nil))
            }

            let exifEntries: [IFDEntry] = [
                IFDEntry(tag: 0x829A, type: 5, count: 1, inlineVal: nil, extraData: expTimeData),
                IFDEntry(tag: 0x829D, type: 5, count: 1, inlineVal: nil, extraData: fNumberData),
                IFDEntry(tag: 0x8827, type: 3, count: 1, inlineVal: UInt32(100 + (variant % 4) * 100), extraData: nil),
                IFDEntry(tag: 0x9003, type: 2, count: UInt32(dateStr.count), inlineVal: nil, extraData: dateStr),
                IFDEntry(tag: 0x920A, type: 5, count: 1, inlineVal: nil, extraData: focalData),
                IFDEntry(tag: 0xA431, type: 2, count: UInt32(serialData.count), inlineVal: nil, extraData: serialData)
            ]

            let gpsEntries: [IFDEntry] = [
                IFDEntry(tag: 0x0001, type: 2, count: 2, inlineVal: 0x0000004E, extraData: nil), // "N\0"
                IFDEntry(tag: 0x0002, type: 5, count: 3, inlineVal: nil, extraData: latData),
                IFDEntry(tag: 0x0003, type: 2, count: 2, inlineVal: 0x00000045, extraData: nil), // "E\0"
                IFDEntry(tag: 0x0004, type: 5, count: 3, inlineVal: nil, extraData: lonData)
            ]

            var file = Data([0x49, 0x49])
            appendU16(&file, 42)
            appendU32(&file, 8)

            let ifd0Blob = serializeIFD(at: 8, entries: ifd0)
            file.append(ifd0Blob)

            let calcExifOff = UInt32(file.count)
            let exifBlob = serializeIFD(at: file.count, entries: exifEntries)
            file.append(exifBlob)

            let calcGpsOff = UInt32(file.count)
            if includeGPS {
                let gpsBlob = serializeIFD(at: file.count, entries: gpsEntries)
                file.append(gpsBlob)
            }

            let calcPixOff = UInt32(file.count)
            file.append(pixels)
            return (file, calcExifOff, calcGpsOff, calcPixOff)
        }

        let pass1 = build(exifOffset: 0, gpsOffset: 0, pixOffset: 0)
        return build(exifOffset: pass1.exifOff, gpsOffset: pass1.gpsOff, pixOffset: pass1.pixOff).data
    }
}
