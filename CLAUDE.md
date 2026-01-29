# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

AztecLib is a pure Swift library for generating Aztec 2D barcodes per ISO/IEC 24778. It encodes strings, byte arrays, and Data objects into Aztec symbols with configurable error correction.

## Build & Test Commands

```bash
# Build
swift build

# Run all tests
swift test

# Run a single test file
swift test --filter AztecEncoderTests

# Run a specific test
swift test --filter AztecEncoderTests.encodes_hello_string

# Build and test via Xcode
xcodebuild -scheme AztecLib test
```

## Architecture

### Encoding Pipeline

The library follows a 6-step pipeline (see `AztecEncoder.swift:93-143`):

1. **Data Encoding** (`AztecDataEncoder`) - Converts input to bits using modes (Upper, Lower, Digit, Punct, Mixed, Byte)
2. **Configuration Selection** (`pickConfiguration()` in `AztecConfiguration.swift`) - Selects smallest symbol that fits payload + error correction
3. **Codeword Packing** (`BitBuffer.makeCodewords()`) - Packs bits into codewords with "stuff bits" to avoid all-0 or all-1 patterns
4. **Reed-Solomon Encoding** (`ReedSolomonEncoder`) - Adds parity codewords for error correction using Galois field arithmetic
5. **Matrix Building** (`AztecMatrixBuilder`) - Assembles finder pattern, mode message, reference grid, and data layers
6. **Export** (`AztecSymbol`) - Outputs packed bitmap with configurable bit ordering (LSB/MSB-first)

### Key Components

- **`AztecEncoder`** - Public API entry point with `encode()` and `encodeWithDetails()` methods
- **`AztecSymbol`** - Output container with size, rowStride, bytes, and subscript access to individual modules
- **`AztecSymbolView`** - SwiftUI view for rendering symbols (iOS 15+, macOS 12+, tvOS 15+, watchOS 8+, visionOS 1+)
- **`AztecCodeView`** - Convenience SwiftUI view that encodes and renders in one step
- **`AztecConfiguration`** - Symbol parameters (compact/full, layers, codeword sizes, parity counts)
- **`GaloisField`** - GF(2^m) arithmetic for m = 6, 8, 10, or 12 bits
- **`ReedSolomonEncoder`** - Generates parity codewords using generator polynomials
- **`BitBuffer` / `CodewordBuffer`** - Bit-level packing utilities

### Symbol Types

- **Compact symbols**: 1-4 layers, 15x15 to 27x27 modules, 9x9 finder pattern
- **Full symbols**: 1-32 layers, 19x19 to 151x151 modules, 13x13 finder pattern

### Primitive Polynomials (AztecConfiguration.swift:50-68)

- GF(2^6): 0x43
- GF(2^8): 0x12D
- GF(2^10): 0x409
- GF(2^12): 0x1069

## Platform Support

The library supports all Apple platforms:
- iOS 15.0+
- macOS 12.0+
- tvOS 15.0+
- watchOS 8.0+
- visionOS 1.0+

The SwiftUI views (`AztecSymbolView`, `AztecCodeView`) are available when SwiftUI is available.

## Testing

Tests use Swift Testing framework (`@Test` macro). Test files mirror source structure in `AztecLibTests/`.

Key test files:
- `AztecComprehensiveTests.swift` - Full coverage of encoding pipeline
- `AztecDiagnosticTests.swift` - Visual inspection helpers for debugging
