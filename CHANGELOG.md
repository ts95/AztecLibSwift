# Changelog

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
