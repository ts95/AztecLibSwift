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

### Key Test Files

- `AztecComprehensiveTests.swift` - Full coverage of encoding pipeline
- `AztecDiagnosticTests.swift` - Visual inspection helpers for debugging
- `AztecValidationTests.swift` - Cross-validation against CIAztecCodeGenerator using Vision framework decoder
- `AztecComparisonTests.swift` - Module-level comparison between AztecLib and native encoders

### Validation Test Harness

The `AztecValidationTests.swift` file provides comprehensive validation by:

1. **Rendering** AztecSymbol to CGImage with configurable module size and quiet zone
2. **Decoding** using Apple's Vision framework (`VNDetectBarcodesRequest`)
3. **Comparing** against CIAztecCodeGenerator reference implementation
4. **Testing** scannability invariants (rotation, scaling)

#### Running Validation Tests

```bash
# Run all validation tests
swift test --filter AztecValidationTests

# Run diagnostic comparison (prints decode results)
swift test --filter print_decode_comparison

# Save test images for manual inspection
swift test --filter save_test_images_for_manual_inspection
# Images saved to: /tmp/azteclib_test.png and /tmp/ciaztec_test.png
```

#### External Decoder (zxing-cpp)

For detailed error messages and cross-validation, use the zxing-cpp Python decoder.

**Prerequisites:**
- Python 3.9+ (included with macOS)
- pip (Python package manager)

**Setup (one-time):**

```bash
# Create a virtual environment (recommended location)
python3 -m venv ~/.venv/zxing

# Activate the virtual environment
source ~/.venv/zxing/bin/activate

# Install required packages
pip install zxing-cpp pillow

# Verify installation
python3 -c "import zxingcpp; print('zxing-cpp ready')"
```

**Alternative: Temporary virtual environment**

```bash
# For quick testing without persistent venv
python3 -m venv /tmp/zxing-venv
source /tmp/zxing-venv/bin/activate
pip install zxing-cpp pillow
```

**Usage:**

```bash
# Activate the virtual environment first
source ~/.venv/zxing/bin/activate  # or /tmp/zxing-venv/bin/activate

# Decode an image (basic)
python3 Scripts/aztec_decode.py /tmp/azteclib_test.png

# Decode with verbose output (shows image info, format detected)
python3 Scripts/aztec_decode.py /tmp/azteclib_test.png --verbose

# Output as JSON (for scripting/automation)
python3 Scripts/aztec_decode.py /tmp/azteclib_test.png --json

# Show raw bytes as hex (for binary payloads)
python3 Scripts/aztec_decode.py /tmp/azteclib_test.png --raw
```

**Complete workflow example:**

```bash
# 1. Generate test images from Swift tests
swift test --filter save_test_images_for_manual_inspection

# 2. Decode and compare
source ~/.venv/zxing/bin/activate
python3 Scripts/aztec_decode.py /tmp/azteclib_test.png --verbose
python3 Scripts/aztec_decode.py /tmp/ciaztec_test.png --verbose
```

The `Scripts/aztec_decode.py` helper provides:
- Detailed error messages when decoding fails
- Verbose mode showing image dimensions, format, and content type
- JSON output mode for automation (`--json`)
- Raw bytes output as hex (`--raw`)
- Exit code 0 on success, 1 on failure (for CI integration)

#### Image Rendering Utilities

The test file provides these utility functions:

```swift
// Render AztecSymbol to CGImage with quiet zone
let image = renderAztecSymbol(symbol, moduleSize: 10, quietZoneModules: 4)

// Scale an image
let scaled = scaleImage(image, factor: 2.0)

// Rotate an image (90° increments)
let rotated = rotateImage(image, degrees: 90)

// Decode using Vision framework
let (data, error) = decodeAztecWithVision(image)

// Generate reference with CIAztecCodeGenerator
let ciImage = generateCIAztecCode(data: payload.data(using: .isoLatin1)!)
```

#### Test Vector Generators

```swift
// Random ASCII strings
let vectors = generateASCIITestVectors(count: 20, maxLength: 80)

// Random UTF-8 strings (various Unicode ranges)
let utf8Vectors = generateUTF8TestVectors(count: 20, maxLength: 50)

// Random binary data
let binaryVectors = generateBinaryTestVectors(count: 15, maxLength: 100)

// Edge cases (null bytes, repeated patterns, mode switching)
let edgeCases = generateEdgeCaseVectors()
```

### Known Issues

**Decoding Compatibility**: AztecLib-generated codes currently do not decode successfully with external decoders (Vision framework, zxing-cpp), while CIAztecCodeGenerator codes decode correctly. This indicates a potential encoding issue in the data layers or mode message encoding that needs investigation.
