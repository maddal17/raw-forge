import Foundation
import ImageIO

/// Applies metadata addition and subtraction rules when encoding converted images via ImageIO.
public enum MetadataProcessor {
    private static let makerNoteDictionaryKeys: [String] = [
        "{MakerCanon}",
        "{MakerNikon}",
        "{MakerSony}",
        "{MakerFuji}",
        "{MakerOlympus}",
        "{MakerPentax}",
        "{MakerPanasonic}",
        "{MakerApple}",
        "{MakerMinolta}",
        "{MakerSigma}"
    ]

    public static func buildDestinationProperties(
        sourceProperties: [String: Any],
        settings: MetadataSettings,
        groupName: String?,
        format: ExportFormat,
        quality: Double
    ) -> [String: Any] {
        var output: [String: Any] = settings.stripAllOriginalMetadata
            ? [:]
            : deepMutableDictionaryCopy(sourceProperties)

        // Strip camera-proprietary/auxiliary top-level keys that cause encoder or privacy bloat
        if settings.stripAllOriginalMetadata {
            output.removeAll()
        } else {
            if settings.removeGPS {
                output.removeValue(forKey: kCGImagePropertyGPSDictionary as String)
            }

            if settings.removeCameraSerialAndMakerNotes {
                for key in makerNoteDictionaryKeys {
                    output.removeValue(forKey: key)
                }
                if var exifAux = output[kCGImagePropertyExifAuxDictionary as String] as? [String: Any] {
                    exifAux.removeValue(forKey: kCGImagePropertyExifAuxSerialNumber as String)
                    exifAux.removeValue(forKey: kCGImagePropertyExifAuxLensSerialNumber as String)
                    output[kCGImagePropertyExifAuxDictionary as String] = exifAux
                }
                if var exif = output[kCGImagePropertyExifDictionary as String] as? [String: Any] {
                    exif.removeValue(forKey: kCGImagePropertyExifBodySerialNumber as String)
                    exif.removeValue(forKey: kCGImagePropertyExifLensSerialNumber as String)
                    exif.removeValue(forKey: kCGImagePropertyExifMakerNote as String)
                    output[kCGImagePropertyExifDictionary as String] = exif
                }
            }

            if settings.removeCaptureExif {
                output.removeValue(forKey: kCGImagePropertyExifDictionary as String)
                output.removeValue(forKey: kCGImagePropertyExifAuxDictionary as String)
                if var tiff = output[kCGImagePropertyTIFFDictionary as String] as? [String: Any] {
                    tiff.removeValue(forKey: kCGImagePropertyTIFFDateTime as String)
                    output[kCGImagePropertyTIFFDictionary as String] = tiff
                }
            }

            if settings.removeOriginalAttribution {
                if var tiff = output[kCGImagePropertyTIFFDictionary as String] as? [String: Any] {
                    tiff.removeValue(forKey: kCGImagePropertyTIFFArtist as String)
                    tiff.removeValue(forKey: kCGImagePropertyTIFFCopyright as String)
                    output[kCGImagePropertyTIFFDictionary as String] = tiff
                }
                if var iptc = output[kCGImagePropertyIPTCDictionary as String] as? [String: Any] {
                    iptc.removeValue(forKey: kCGImagePropertyIPTCByline as String)
                    iptc.removeValue(forKey: kCGImagePropertyIPTCCopyrightNotice as String)
                    iptc.removeValue(forKey: kCGImagePropertyIPTCCredit as String)
                    output[kCGImagePropertyIPTCDictionary as String] = iptc
                }
                if var exif = output[kCGImagePropertyExifDictionary as String] as? [String: Any] {
                    exif.removeValue(forKey: kCGImagePropertyExifCameraOwnerName as String)
                    output[kCGImagePropertyExifDictionary as String] = exif
                }
                if var exifAux = output[kCGImagePropertyExifAuxDictionary as String] as? [String: Any] {
                    exifAux.removeValue(forKey: kCGImagePropertyExifAuxOwnerName as String)
                    output[kCGImagePropertyExifAuxDictionary as String] = exifAux
                }
            }
        }

        // Apply Metadata Additions / Overrides
        var tiff = output[kCGImagePropertyTIFFDictionary as String] as? [String: Any] ?? [:]
        var iptc = output[kCGImagePropertyIPTCDictionary as String] as? [String: Any] ?? [:]
        var exifAux = output[kCGImagePropertyExifAuxDictionary as String] as? [String: Any] ?? [:]

        let author = settings.authorName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !author.isEmpty {
            tiff[kCGImagePropertyTIFFArtist as String] = author
            iptc[kCGImagePropertyIPTCByline as String] = [author]
            exifAux[kCGImagePropertyExifAuxOwnerName as String] = author
        }

        let copyright = settings.copyrightNotice.trimmingCharacters(in: .whitespacesAndNewlines)
        if !copyright.isEmpty {
            tiff[kCGImagePropertyTIFFCopyright as String] = copyright
            iptc[kCGImagePropertyIPTCCopyrightNotice as String] = copyright
        }

        let album = settings.albumTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        if !album.isEmpty {
            iptc[kCGImagePropertyIPTCObjectName as String] = album
        }

        let description = settings.imageDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        if !description.isEmpty {
            tiff[kCGImagePropertyTIFFImageDescription as String] = description
            iptc[kCGImagePropertyIPTCCaptionAbstract as String] = description
        }

        let credit = settings.creatorCredit.trimmingCharacters(in: .whitespacesAndNewlines)
        if !credit.isEmpty {
            iptc[kCGImagePropertyIPTCCredit as String] = credit
        }

        var keywords = settings.keywordsCSV
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        if settings.includeGroupNameAsKeyword, let groupName, !groupName.isEmpty {
            if !keywords.contains(where: { $0.caseInsensitiveCompare(groupName) == .orderedSame }) {
                keywords.append(groupName)
            }
        }
        if !keywords.isEmpty {
            iptc[kCGImagePropertyIPTCKeywords as String] = keywords
        }

        // Mandatory Orientation Normalization: exported CGImage pixels are already upright.
        output[kCGImagePropertyOrientation as String] = 1
        tiff[kCGImagePropertyTIFFOrientation as String] = 1

        if !tiff.isEmpty {
            output[kCGImagePropertyTIFFDictionary as String] = tiff
        }
        if !iptc.isEmpty {
            output[kCGImagePropertyIPTCDictionary as String] = iptc
        }
        if !exifAux.isEmpty {
            output[kCGImagePropertyExifAuxDictionary as String] = exifAux
        }

        if format.supportsQuality {
            output[kCGImageDestinationLossyCompressionQuality as String] = max(0.1, min(1.0, quality))
        }

        return output
    }

    private static func deepMutableDictionaryCopy(_ source: [String: Any]) -> [String: Any] {
        var copy: [String: Any] = [:]
        for (key, value) in source {
            if let nested = value as? [String: Any] {
                copy[key] = deepMutableDictionaryCopy(nested)
            } else {
                copy[key] = value
            }
        }
        return copy
    }
}
