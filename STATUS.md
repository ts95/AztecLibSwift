# AztecLib Project Status

**Version: 1.0.1**

This document describes the current implementation status, ISO compliance, and known limitations.

## Overview

AztecLib is a pure Swift implementation of Aztec 2D barcode encoding per ISO/IEC 24778. The library generates Aztec symbols that are fully compatible with standard barcode decoders including ZXing and Apple's Vision framework.

## Implementation Status

### Completed Features

| Feature | Status | Notes |
|---------|--------|-------|
| Compact symbols (1-4 layers) | ✅ Complete | 15x15 to 27x27 modules |
| Full symbols (4-32 layers) | ✅ Complete | 31x31 to 151x151 modules |
| Text encoding modes | ✅ Complete | Upper, Lower, Mixed, Punct, Digit |
| Binary/Byte mode | ✅ Complete | Short (1-31 bytes) and long (32+ bytes) forms |
| Mode transitions | ✅ Complete | Latch and shift with cost-based optimization |
| Reed-Solomon encoding | ✅ Complete | GF(2^6), GF(2^8), GF(2^10), GF(2^12) |
| Mode message encoding | ✅ Complete | RS-protected nibble encoding |
| Finder pattern | ✅ Complete | 9x9 (compact) and 13x13 (full) |
| Reference grid | ✅ Complete | For full symbols with large layer counts |
| Data placement | ✅ Complete | Clockwise spiral with layer mapping |
| Codeword stuffing | ✅ Complete | Bit stuffing to avoid all-0/all-1 patterns |
| Configurable error correction | ✅ Complete | 5-95% error correction percentage |
| SwiftUI views | ✅ Complete | `AztecSymbolView` and `AztecCodeView` |

### Encoding Pipeline

The library implements the full 6-step Aztec encoding pipeline:

1. **Data Encoding** - Converts input to bits using optimal mode selection
2. **Configuration Selection** - Picks smallest symbol fitting payload + EC
3. **Codeword Packing** - Packs bits with stuff bits per ISO spec
4. **Reed-Solomon Encoding** - Adds parity codewords for error correction
5. **Matrix Building** - Assembles finder, mode message, grid, and data
6. **Export** - Outputs packed bitmap with configurable bit ordering

## ISO/IEC 24778 Compliance

### Compliant Areas

| Specification | Compliance | Reference |
|--------------|------------|-----------|
| Symbol structure | ✅ Compliant | ISO 24778 §7.1 |
| Finder pattern | ✅ Compliant | ISO 24778 §7.2 |
| Orientation pattern | ✅ Compliant | ISO 24778 §7.3 |
| Mode message | ✅ Compliant | ISO 24778 §7.4 |
| Reference grid | ✅ Compliant | ISO 24778 §7.5 |
| Data region | ✅ Compliant | ISO 24778 §7.6 |
| Character encoding | ✅ Compliant | ISO 24778 §8 (Tables 2-6) |
| Codeword stuffing | ✅ Compliant | ISO 24778 §9 |
| Reed-Solomon codes | ✅ Compliant | ISO 24778 §10 |
| Primitive polynomials | ✅ Compliant | ISO 24778 Annex A |

### Character Encoding Tables

The library implements all five text modes per ISO 24778:

- **Upper mode** (5 bits): Space + A-Z (codes 1-27)
- **Lower mode** (5 bits): Space + a-z (codes 1-27)
- **Mixed mode** (5 bits): Control characters + special symbols (@, \, ^, _, `, |, ~)
- **Punct mode** (5 bits): Punctuation (!, ", #, $, %, etc.) + two-char sequences
- **Digit mode** (4 bits): Space + 0-9 + comma + period

### Primitive Polynomials (per ISO 24778 Annex A)

| Field | Polynomial | Usage |
|-------|------------|-------|
| GF(2^6) | 0x43 (x^6 + x + 1) | Compact symbols |
| GF(2^8) | 0x12D (x^8 + x^5 + x^3 + x^2 + 1) | Full L1-L8 |
| GF(2^10) | 0x409 (x^10 + x^3 + 1) | Full L9-L22 |
| GF(2^12) | 0x1069 (x^12 + x^6 + x^5 + x^3 + 1) | Full L23-L32 |

## Validation

### ZXing Compatibility

The library has been validated against ZXing (the reference Aztec implementation):

| Test Case | Result |
|-----------|--------|
| "Hello" encoding | ✅ Identical output |
| "123" encoding | ✅ Identical output |
| "Mixed123Content!@#" | ✅ Identical output |
| Binary data (5 bytes) | ✅ ZXing decodes correctly |
| Binary data (128 bytes) | ✅ ZXing decodes correctly |
| Large payloads (366 bytes) | ✅ ZXing decodes correctly |

### Test Suite Results

The library passes comprehensive validation testing against multiple decoders:
- Apple Vision framework
- zxing-cpp

---

## Future Enhancements

The following features are planned for future releases:

1. **Decoder implementation**: Add Aztec decoding support (currently encode-only)

2. **Structured Append**: Support for multi-symbol encoding of large payloads

3. **FNC1 support**: Add support for GS1 Aztec Code format

4. **Reader Initialization**: Add support for reader programming symbols

5. **Performance optimization**: Profile and optimize for large symbols

---

*Last updated: January 2026 (v1.0.1)*
