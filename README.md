# RawForge

[![CI & Verification](https://github.com/maddal17/raw-forge/actions/workflows/ci.yml/badge.svg)](https://github.com/maddal17/raw-forge/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-7C3AED.svg)](./LICENSE)
[![Platform: macOS 14+](https://img.shields.io/badge/macOS-14%2B%20(Swift%206%20%C2%B7%20Apple%20Silicon)-000000.svg)](#quick-start)

Native macOS RAW photo studio built in Swift 6, SwiftUI, CoreImage (`CIRAWFilter`), and Metal to **group shoots by lighting condition, apply shared color/tone edits once per label group, burn in author watermarks, add or strip EXIF/IPTC/GPS metadata, and batch-convert RAW albums at Apple Silicon speed**.

---

## Why This Exists

Shooting an event or session across changing light leaves hundreds of RAW files split between sunlit frames, warm indoor rooms, cool shade, and golden hour. Editing every file individually—or importing into a heavyweight catalog database—turns a 5-minute album turnaround into hours of repetitive work.

**RawForge** organizes shoots around **Label Groups**:
1. Browse a folder directly with zero catalog import lock-in.
2. Tag photos with similar lighting/color into shared **Lighting Label Groups** (`Daylight`, `Golden Hour`, `Indoor Warm`, `Shade`, `Night`, or custom groups).
3. Dial exposure, white balance (*As Shot ± Offset* or *Match Fixed Kelvin*), tone, detail, and lens correction once per group so every photo in that scene feels cohesive when viewed as an album.
4. Batch-convert the entire shoot in parallel across Apple Silicon Performance cores and Metal GPU queues.

---

## Workspace Modes

- **Mode 1 — List & Label**: Medium-preview rows or card grid with resizable thumbnails, checkboxes, `Cmd+Click` / `Shift+Click` range selection, a contextual mass-labeling bar, and a **Group by Labels** toggle that collapses/expands sections by group.
- **Mode 2 — Big Preview & Filmstrip**: Lightroom-style large interactive Metal preview with `Before / After (\)` toggle, watermark preview, `Fit / 100%`, live 64-bin RGB histogram, `1–9` / `0` keyboard labeling shortcuts (with optional auto-advance), and a horizontally scrollable medium-preview filmstrip.

---

## Architecture

```
┌─────────────────────────────────────────────────────────────────────────────┐
│ Dark-Studio macOS Interface (SwiftUI + AppKit)                              │
│                                                                             │
│  [Mode 1: List & Label]          [Mode 2: Big Preview + Filmstrip]          │
│   • Mass select & Group-by-Label  • Interactive Loupe + 64-bin RGB Hist.    │
│   • Medium preview rows/cards     • Before/After (\) & 1–9 quick labeling   │
└──────────────────┬───────────────────────────────────┬──────────────────────┘
                   │                                   │
                   ▼                                   ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│ Label-Group Shared Recipe Domain & Per-Folder Persistence                   │
│  • Lighting Groups own EditRecipe (EV, Fixed Kelvin/Offset WB, Highlights,  │
│    Shadows, Whites, Blacks, Contrast, Vibrance, Saturation, NR, Optics)     │
│  • Optional per-photo micro-trim layered cleanly on top of group recipe     │
│  • Global Settings: Author Watermark + Metadata Add/Subtract rules          │
└──────────────────────────────────┬──────────────────────────────────────────┘
                                   │
                                   ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│ Apple Silicon Hardware Pipeline (RawForgeCore)                              │
│                                                                             │
│  1. Interactive Loupe Actor                                                 │
│     • Caches active CIRAWFilter on Metal CIContext (RGBAh linear P3)        │
│     • ~5 ms warm draft preview on slider drag + settled full-quality pass   │
│                                                                             │
│  2. Parallel Batch Conversion Engine                                        │
│     • Auto-tunes workers to P-cores & Unified Memory (capped at 12 workers) │
│     • Pools Metal CIContexts (cacheIntermediates: false) + autoreleasepool  │
│     • Composites CoreText/logo watermark -> normalizes Orientation = 1      │
│     • Transforms EXIF/TIFF/IPTC/GPS -> atomic ImageIO hardware encode       │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## Key Restraints & Failure Modes Addressed

- **Unified Memory Pressure in Parallel RAW Batches**: Processing dozens of 20–60 MP RAWs concurrently can inflate unified memory through retained GPU intermediates. Batch worker contexts disable intermediate caching, cap concurrency against both P-core count and physical RAM, and wrap each photo render-and-encode cycle in an explicit `autoreleasepool` with atomic temp-file writes.
- **Non-Image `.raw` Rejection & Symlink Support**: Disk dumps or non-photo files carrying `.raw` are rejected by validating ImageIO image-source frame counts during scanning, while symlinked RAW assets resolve cleanly to their target size without losing link filenames on export.
- **Portrait Double-Rotation Prevention**: Because `CIRAWFilter` and CoreImage output pixels already rotated upright, metadata processing forces exported top-level and TIFF orientation tags to `1` so viewers never rotate portraits a second time.
- **Input-Safe Keyboard Shortcuts**: Global number/arrow/mode hotkeys check first-responder text controls and active modal sheets so typing inside search fields, group names, or watermark/metadata settings is never intercepted.

---

## Supported Formats

| Direction | Formats |
| :--- | :--- |
| **Input RAW** | `.dng`, `.cr2`, `.cr3`, `.crw`, `.nef`, `.nrw`, `.arw`, `.srf`, `.sr2`, `.raf`, `.rw2`, `.raw`, `.orf`, `.pef`, `.rwl`, `.3fr`, `.fff`, `.iiq`, `.mos`, `.srw`, `.erf`, `.mef`, `.mrw`, `.dcr`, `.kdc` *(plus optional `.jpg`, `.heic`, `.png`, `.tiff`)* |
| **Output Export** | **JPEG** (`.jpg`), **HEIC** (`.heic`), **PNG** (8/16-bit `.png`), **TIFF** (8/16-bit `.tiff`), **AVIF** (`.avif`), **JPEG 2000** (`.jp2`) |
| **Color Spaces** | `sRGB IEC61966-2.1`, `Display P3`, `Adobe RGB (1998)` |

---

## Watermark & Metadata Controls

- **Author Watermark** (Settings → *Author Watermark*): Text (with `{year}` and `{camera}` tokens) and/or PNG logo overlay, 9-point placement or `-30°` diagonal tiling, configurable font style, size %, opacity, margin %, drop shadow, or backing pill, plus live preview.
- **Metadata Subtract**: Strip all original camera metadata, or selectively strip GPS coordinates, camera/lens serial numbers (`BodySerialNumber`, `SerialNumber`, MakerNotes), capture EXIF, or original artist/copyright attribution.
- **Metadata Add**: Inject Author/Artist, Copyright Notice, Album Title, Image Description, Creator Credit, and CSV keywords (optionally appending each photo's Label Group name as an IPTC keyword).

---

## Quick Start

Requires **macOS 14+** and Apple Command Line Tools (`xcode-select --install`) or Xcode.

```bash
git clone https://github.com/maddal17/raw-forge.git
cd raw-forge

# Compile RawForgeCore, RawForgeApp, generate AppIcon.icns, sign dist/RawForge.app, and run RawForgeVerify
make build

# Launch the app
make run

# Or install to /Applications (or ~/Applications)
make install
```

To benchmark against a specific local RAW file during verification:

```bash
RAWFORGE_SAMPLE_RAW=/path/to/photo.RW2 .build/bin/RawForgeVerify
```

### Keyboard Shortcuts

| Shortcut | Action |
| :--- | :--- |
| `1` – `9` | Assign selected/active photo(s) to Label Group 1–9 |
| `0` | Clear label assignment |
| `\` | Toggle Before / After original preview |
| `←` / `→` | Previous / Next photo |
| `Cmd+1` / `G` | Switch to Mode 1 (List & Label) |
| `Cmd+2` / `D` | Switch to Mode 2 (Big Preview & Filmstrip) |
| `Cmd+E` | Open Batch Convert & Export |
| `Cmd+,` | Open Settings (Watermark, Metadata, Engine) |

---

## License

MIT — see [LICENSE](./LICENSE).
