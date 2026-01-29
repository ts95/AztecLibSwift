# Changelog

## v1.0.1 — January 2026

**Bug Fix Release**

### Fixed

- **Full symbol alignment map**: Fixed data placement for full (non-compact) symbols by implementing ZXing's alignment map algorithm that correctly skips the center coordinate.

- **Mode transition Digit→Punct**: Fixed the latch table entry for Digit→Punct mode transition. Previously used shift code 0 (P/S) instead of the correct 3-step path: U/L → M/L → P/L (14 bits total).

- **Symbol size formula for reference grids**: Fixed the reference grid line count calculation from `(layers - 1) / 15` to `(baseMatrixSize / 2 - 1) / 15` per ZXing's algorithm. This affects full symbols with 15+ layers.

- **Test array indexing**: Fixed test helper functions that incorrectly indexed into `fullSymbolSpecs` using `layers - 1` instead of `layers - 4` (since the array starts at layer 4).

### Verified

All fixes verified against ZXing decoder:
- Compact symbols (15x15 to 27x27): ✓
- Full symbols (31x31 and larger): ✓
- Payloads up to 500+ characters: ✓
- Mode transitions including Digit→Punct: ✓

---

## v1.0.0 — January 2026

**Initial Release**

AztecLib is a pure Swift library for generating Aztec 2D barcodes per ISO/IEC 24778.

### Features

- **Full Aztec Symbol Support**
  - Compact symbols (1-4 layers): 15x15 to 27x27 modules
  - Full symbols (1-32 layers): 19x19 to 151x151 modules

- **Complete Text Encoding**
  - All five text modes: Upper, Lower, Mixed, Punct, Digit
  - Cost-based mode optimization for efficient encoding
  - Binary/Byte mode with short (1-31 bytes) and long (32+ bytes) forms

- **Reed-Solomon Error Correction**
  - GF(2^6), GF(2^8), GF(2^10), and GF(2^12) field arithmetic
  - Configurable error correction (5-95%)

- **SwiftUI Integration**
  - `AztecSymbolView` for rendering symbols
  - `AztecCodeView` for one-step encode and display

- **Platform Support**
  - iOS 15.0+, macOS 12.0+, tvOS 15.0+, watchOS 8.0+, visionOS 1.0+

### ISO/IEC 24778 Compliance

Fully compliant with all major specification sections including symbol structure, finder patterns, mode message encoding, reference grid, codeword stuffing, and Reed-Solomon encoding.

### Validation

Verified compatible with:
- Apple Vision framework
- ZXing / zxing-cpp
