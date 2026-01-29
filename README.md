# AztecLib

[![Version](https://img.shields.io/badge/version-1.0.1-blue.svg)](https://github.com/ts95/AztecLibSwift/releases/tag/1.0.1)
[![Swift 5.9+](https://img.shields.io/badge/Swift-5.9+-orange.svg)](https://swift.org)
[![Platforms](https://img.shields.io/badge/Platforms-iOS%20|%20macOS%20|%20tvOS%20|%20watchOS%20|%20visionOS-lightgray.svg)](https://developer.apple.com)

A pure Swift library for generating Aztec 2D barcodes. This library implements the ISO/IEC 24778 standard for Aztec Code symbology.

## Features

- Encode strings, byte arrays, and `Data` objects into Aztec symbols
- Automatic mode selection for optimal encoding (Upper, Lower, Digit, Punct, Mixed, Byte)
- Configurable error correction levels
- Support for both compact and full-range symbols
- Thread-safe: all types conform to `Sendable`
- No unsafe memory operations

## Requirements

- Swift 5.9+
- iOS 15.0+ / macOS 12.0+ / tvOS 15.0+ / watchOS 8.0+ / visionOS 1.0+

## Installation

### Swift Package Manager

Add AztecLib to your `Package.swift` dependencies:

```swift
dependencies: [
    .package(url: "https://github.com/ts95/AztecLibSwift.git", from: "1.0.1")
]
```

Then add it to your target dependencies:

```swift
.target(
    name: "YourApp",
    dependencies: ["AztecLib"]
)
```

### Xcode

1. File → Add Package Dependencies
2. Enter the repository URL
3. Select latest version

## Quick Start

```swift
import AztecLib

// Encode a string
let symbol = try AztecEncoder.encode("Hello, World!")

// Access the symbol data
print("Symbol size: \(symbol.size)x\(symbol.size) modules")
print("Bytes per row: \(symbol.rowStride)")

// Check individual modules (pixels)
let isDark = symbol[x: 0, y: 0]  // true = dark module, false = light
```

## SwiftUI Integration

AztecLib includes SwiftUI views for easy barcode display:

```swift
import AztecLib
import SwiftUI

struct ContentView: View {
    var body: some View {
        // Simple usage - encode and display in one step
        AztecCodeView("Hello, World!")
            .frame(width: 200, height: 200)

        // Or use a pre-encoded symbol
        let symbol = try! AztecEncoder.encode("Hello")
        AztecSymbolView(symbol: symbol)
            .frame(width: 200, height: 200)
    }
}
```

## Public API

### AztecEncoder

The main entry point for encoding data into Aztec symbols.

#### Encoding Strings

```swift
// Simple encoding with defaults
let symbol = try AztecEncoder.encode("Your text here")

// With custom options
let options = AztecEncoder.Options(
    errorCorrectionPercentage: 33,  // 33% error correction
    preferCompact: true,             // Prefer smaller symbols
    exportMSBFirst: false            // LSB-first bit ordering
)
let symbol = try AztecEncoder.encode("Your text here", options: options)
```

#### Encoding Binary Data

```swift
// Encode a byte array
let bytes: [UInt8] = [0x48, 0x65, 0x6C, 0x6C, 0x6F]
let symbol = try AztecEncoder.encode(bytes)

// Encode Foundation Data
let data = Data([0x01, 0x02, 0x03])
let symbol = try AztecEncoder.encode(data)
```

#### Getting Encoding Details

```swift
// Get both the symbol and configuration details
let result = try AztecEncoder.encodeWithDetails("Hello")

print("Compact symbol: \(result.configuration.isCompact)")
print("Layers: \(result.configuration.layerCount)")
print("Data codewords: \(result.configuration.dataCodewordCount)")
print("Parity codewords: \(result.configuration.parityCodewordCount)")
```

### AztecEncoder.Options

Configuration options for encoding.

| Property | Type | Default | Description |
|----------|------|---------|-------------|
| `errorCorrectionPercentage` | `UInt` | 23 | Percentage of codewords dedicated to error correction (higher = more resilient, larger symbol) |
| `preferCompact` | `Bool` | true | Prefer compact symbols over full symbols when both would fit |
| `exportMSBFirst` | `Bool` | false | Bit ordering: `false` = LSB-first, `true` = MSB-first (for PNG compatibility) |

### AztecSymbol

The output of encoding, representing the 2D barcode matrix.

```swift
let symbol = try AztecEncoder.encode("Test")

// Properties
symbol.size       // Int: side length in modules (e.g., 15 for 15x15)
symbol.rowStride  // Int: bytes per row in the packed data
symbol.bytes      // Data: the packed bitmap data

// Subscript access to individual modules
let isDark = symbol[x: 5, y: 5]  // Returns Bool
```

#### Rendering the Symbol

The `bytes` property contains row-major packed bitmap data. Each row is `rowStride` bytes long, with modules packed into bits.

**LSB-first (default):** Bit 0 of each byte is the leftmost module.

```swift
// Example: Render to a simple ASCII representation
func renderASCII(_ symbol: AztecSymbol) -> String {
    var result = ""
    for y in 0..<symbol.size {
        for x in 0..<symbol.size {
            result += symbol[x: x, y: y] ? "██" : "  "
        }
        result += "\n"
    }
    return result
}
```

**MSB-first (PNG compatible):** Use `exportMSBFirst: true` when the renderer expects bit 7 to be the leftmost pixel.

### AztecConfiguration

Returned by `encodeWithDetails()`, contains the selected symbol parameters.

| Property | Type | Description |
|----------|------|-------------|
| `isCompact` | `Bool` | `true` for compact symbols (1-4 layers), `false` for full |
| `layerCount` | `Int` | Number of data layers (1-4 compact, 4-32 full) |
| `wordSizeInBits` | `Int` | Codeword size: 6, 8, 10, or 12 bits |
| `totalCodewordCount` | `Int` | Total codewords in the symbol |
| `dataCodewordCount` | `Int` | Codewords available for data |
| `parityCodewordCount` | `Int` | Codewords used for error correction |

### Error Handling

```swift
do {
    let symbol = try AztecEncoder.encode(veryLongString)
} catch AztecEncoder.EncodingError.payloadTooLarge(let bitCount) {
    print("Data too large: \(bitCount) bits exceeds maximum capacity")
} catch {
    print("Encoding failed: \(error)")
}
```

## Symbol Sizes

### Compact Symbols (1-4 layers)

| Layers | Size | Max Data Bits |
|--------|------|---------------|
| 1 | 15×15 | ~50 |
| 2 | 19×19 | ~170 |
| 3 | 23×23 | ~300 |
| 4 | 27×27 | ~470 |

### Full Symbols (4-32 layers)

Full symbols range from 31×31 (layer 4) to 151×151 (layer 32), supporting up to ~12,000 bits of data.

## Thread Safety

All types in AztecLib conform to `Sendable` and can be safely used from any thread:

```swift
Task.detached {
    let symbol = try AztecEncoder.encode("Background encoding")
    // Safe to use symbol here
}
```

## Advanced Usage

### Lower-Level APIs

For advanced use cases, you can access the encoding pipeline components directly:

```swift
import AztecLib

// Step 1: Encode data to bits
let dataBits = AztecDataEncoder.encode("Hello")

// Step 2: Select configuration
let config = try pickConfiguration(
    forPayloadBitCount: dataBits.bitCount,
    errorCorrectionPercentage: 23,
    preferCompact: true
)

// Step 3: Pack into codewords
let codewords = dataBits.makeCodewords(codewordBitWidth: config.wordSizeInBits)

// Step 4: Add Reed-Solomon parity
let gf = GaloisField(
    wordSizeInBits: config.wordSizeInBits,
    primitivePolynomial: config.primitivePolynomial
)
let rs = ReedSolomonEncoder(field: gf, startExponent: config.rsStartExponent)
let allCodewords = rs.appendingParity(
    to: codewords,
    parityCodewordCount: config.parityCodewordCount
)

// Step 5: Build the matrix
let builder = AztecMatrixBuilder(configuration: config)
let modeMessage = builder.encodeModeMessage()
let matrix = builder.buildMatrix(dataCodewords: allCodewords, modeMessageBits: modeMessage)

// Step 6: Export
let symbol = matrix.makeSymbolExport(
    matrixSize: builder.symbolSize,
    rowOrderMostSignificantBitFirst: false
)
```

## Documentation

For detailed explanations of the algorithms and mathematics used in this library, see the [AztecLib/Docs/](AztecLib/Docs/) directory:

- [Overview](AztecLib/Docs/01-Overview.md) - What Aztec codes are and how they work
- [Encoding Pipeline](AztecLib/Docs/02-EncodingPipeline.md) - How data becomes a barcode
- [Mode Encoding](AztecLib/Docs/03-ModeEncoding.md) - Text compression using modes
- [Galois Fields](AztecLib/Docs/04-GaloisFields.md) - The math behind error correction
- [Reed-Solomon](AztecLib/Docs/05-ReedSolomon.md) - How error correction works
- [Symbol Layout](AztecLib/Docs/06-SymbolLayout.md) - Structure of an Aztec barcode

## Acknowledgments

This library was primarily developed with the assistance of [Claude Code](https://claude.ai/code) (Claude Opus 4.5), Anthropic's AI coding assistant. The implementation draws inspiration from [ZXing](https://github.com/zxing/zxing) ("Zebra Crossing"), the open-source barcode processing library.

## License

MIT License

## References

- ISO/IEC 24778:2008 - Information technology — Automatic identification and data capture techniques — Aztec Code bar code symbology specification
