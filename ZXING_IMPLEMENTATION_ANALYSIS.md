# ZXing Aztec Implementation Analysis

This document provides a detailed comparison between ZXing's Aztec encoder implementation (both Java and C++) and AztecLib's Swift implementation.

## Table of Contents
1. [Encoding Pipeline Overview](#1-encoding-pipeline-overview)
2. [High-Level Encoding](#2-high-level-encoding)
3. [Stuff Bits Transformation](#3-stuff-bits-transformation)
4. [Reed-Solomon Encoding](#4-reed-solomon-encoding)
5. [Message Bits Assembly](#5-message-bits-assembly)
6. [Data Placement Algorithm](#6-data-placement-algorithm)
7. [Known Issues](#7-known-issues)

---

## 1. Encoding Pipeline Overview

### ZXing Pipeline

```
Input bytes
    ↓
HighLevelEncoder.encode() → BitArray bits
    ↓
stuffBits(bits, wordSize) → BitArray stuffedBits
    ↓
bitsToWords(stuffedBits, wordSize, totalWords) → int[] messageWords
    ↓
ReedSolomonEncoder.encode(messageWords, ecBytes) → messageWords with parity
    ↓
generateCheckWords():
  - Add startPad = totalBits % wordSize zeros at start
  - appendBits(messageWord, wordSize) for each word
    ↓
BitArray messageBits
    ↓
Data placement loop with alignmentMap
    ↓
BitMatrix
```

### AztecLib Pipeline

```
Input bytes
    ↓
AztecDataEncoder.encode() → BitBuffer
    ↓
BitBuffer.makeCodewords(codewordBitWidth) → [UInt16]
    ↓
ReedSolomonEncoder.appendingParity() → [UInt16] with parity
    ↓
placeDataCodewords():
  - Add startPad zeros
  - Flatten codewords to bits MSB-first
    ↓
Data placement loop with alignmentMap
    ↓
BitBuffer matrix
```

---

## 2. High-Level Encoding

Both implementations encode input bytes using mode-based encoding per ISO/IEC 24778:
- Upper, Lower, Mixed, Digit, Punct, Byte modes
- Latch and shift codes for mode transitions

**Status: ✓ Equivalent**

---

## 3. Stuff Bits Transformation

### ZXing Implementation (Java)

```java
static BitArray stuffBits(BitArray bits, int wordSize) {
    BitArray out = new BitArray();
    int n = bits.getSize();
    int mask = (1 << wordSize) - 2;  // e.g., 0b111110 for wordSize=6

    for (int i = 0; i < n; i += wordSize) {
        int word = 0;
        for (int j = 0; j < wordSize; j++) {
            // KEY: Past end of input treated as 1, not 0
            if (i + j >= n || bits.get(i + j)) {
                word |= 1 << (wordSize - 1 - j);
            }
        }
        if ((word & mask) == mask) {
            // All 1s in upper bits → stuff 0 at LSB
            out.appendBits(word & mask, wordSize);
            i--;  // Don't advance, reprocess last bit
        } else if ((word & mask) == 0) {
            // All 0s in upper bits → stuff 1 at LSB
            out.appendBits(word | 1, wordSize);
            i--;
        } else {
            // Normal: already consumed wordSize bits
            out.appendBits(word, wordSize);
        }
    }
    return out;
}
```

**Critical behavior**: When reading past the end of input, ZXing treats the missing bits as `1`, not `0`.

### AztecLib Implementation (Swift)

```swift
public func makeCodewords(codewordBitWidth w: Int) -> [UInt16] {
    let dataBitsPerWord = w - 1
    let allOnesMask = (1 << dataBitsPerWord) &- 1
    // ...
    while pos < total {
        let take = min(remaining, dataBitsPerWord)
        var v = Int(leastSignificantBits(atBitPosition: pos, bitCount: take))

        // Short final group: left-pad with zeros
        if take < dataBitsPerWord {
            v <<= (dataBitsPerWord - take)
        }

        if v == 0 {
            out.append(UInt16((v << 1) | 1))
            pos += take
        } else if v == allOnesMask {
            out.append(UInt16(v << 1))
            pos += take
        } else {
            // Past end: now pads with 1 (was 0)
            let stuff = (pos + take) < total
                ? Int(leastSignificantBits(atBitPosition: pos + take, bitCount: 1))
                : 1
            out.append(UInt16((v << 1) | stuff))
            pos += take + 1
        }
    }
    return out
}
```

**Comparison**:
| Aspect | ZXing | AztecLib |
|--------|-------|----------|
| Read size | wordSize bits | wordSize-1 bits + stuff bit |
| Past-end padding | 1 | 1 (fixed) |
| Output | Same | Same |

**Status: ✓ Fixed - produces same output**

---

## 4. Reed-Solomon Encoding

### ZXing Galois Field Configuration

```java
// For 6-bit codewords (compact L1-L4)
public static final GenericGF AZTEC_DATA_6 = new GenericGF(0b1000011, 64, 1);
// primitive: x^6 + x + 1 = 0x43
// size: 64
// generatorBase: 1 (roots start at α^1)
```

### ZXing RS Encoder

```java
public void encode(int[] toEncode, int ecBytes) {
    int dataBytes = toEncode.length - ecBytes;

    // Extract data coefficients
    int[] infoCoefficients = new int[dataBytes];
    System.arraycopy(toEncode, 0, infoCoefficients, 0, dataBytes);

    // Create polynomial from data
    GenericGFPoly info = new GenericGFPoly(field, infoCoefficients);

    // Multiply by x^ecBytes to make room for parity
    info = info.multiplyByMonomial(ecBytes, 1);

    // Divide by generator, remainder is parity
    GenericGFPoly remainder = info.divide(generator)[1];

    // Copy parity to output array (after data)
    int[] coefficients = remainder.getCoefficients();
    int numZeroCoefficients = ecBytes - coefficients.length;
    for (int i = 0; i < numZeroCoefficients; i++) {
        toEncode[dataBytes + i] = 0;
    }
    System.arraycopy(coefficients, 0, toEncode,
                     dataBytes + numZeroCoefficients, coefficients.length);
}
```

**Generator polynomial construction**:
```java
private GenericGFPoly buildGenerator(int degree) {
    // g(x) = (x + α^1)(x + α^2)...(x + α^degree)
    for (int d = 1; d <= degree; d++) {
        nextGenerator = lastGenerator.multiply(
            new GenericGFPoly(field, new int[] { 1, field.exp(d - 1 + generatorBase) })
        );
        // For AZTEC_DATA_6: roots are α^1, α^2, ...
    }
}
```

### ZXing bitsToWords Function

**CRITICAL**: This function initializes the entire array to zeros, then fills only the data positions:

```java
private static int[] bitsToWords(BitArray stuffedBits, int wordSize, int totalWords) {
    int[] message = new int[totalWords];  // All zeros initially
    int n = stuffedBits.getSize() / wordSize;  // Number of actual data words

    for (int i = 0; i < n; i++) {
        int value = 0;
        for (int j = 0; j < wordSize; j++) {
            value |= stuffedBits.get(i * wordSize + j) ? (1 << wordSize - j - 1) : 0;
        }
        message[i] = value;
    }
    return message;  // [data0, data1, ..., 0, 0, 0, ...]
}
```

For compact L1 with "A":
- totalWords = 104 / 6 = 17
- stuffedBits has 6 bits (1 data word = 5)
- messageWords = [5, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]

Then RS encode fills positions 1-16 with parity.

### AztecLib RS Encoder

```swift
public func makeParityCodewords(
    for dataCodewords: [UInt16],
    parityCodewordCount: Int
) -> [UInt16] {
    let g = makeGeneratorPolynomial(ofDegree: parityCodewordCount)
    var reg = [UInt16](repeating: 0, count: parityCodewordCount)

    for d in dataCodewords {
        let fb = field.add(d, reg[parityCodewordCount - 1])

        // Shift register right
        for j in stride(from: parityCodewordCount - 1, through: 1, by: -1) {
            reg[j] = reg[j - 1]
        }
        reg[0] = 0

        // Mix feedback with generator taps
        for j in 0..<parityCodewordCount {
            let tap = g[j + 1]
            if tap != 0 {
                reg[j] = field.add(reg[j], field.multiply(fb, tap))
            }
        }
    }
    return reg
}
```

**POTENTIAL ISSUE**: ZXing passes **17 data words** (including trailing zeros) to RS encode, but AztecLib only passes **1 data word** (just [5]).

The RS encoding result depends on the NUMBER of data symbols, not just their values. Encoding [5] is different from encoding [5, 0, 0, 0, ...].

---

## 5. Message Bits Assembly

### ZXing generateCheckWords

```java
private static BitArray generateCheckWords(BitArray bitArray, int totalBits, int wordSize) {
    int messageSizeInWords = bitArray.getSize() / wordSize;
    int totalWords = totalBits / wordSize;

    // Create array sized for ALL words (data + parity)
    int[] messageWords = bitsToWords(bitArray, wordSize, totalWords);

    // RS encode in-place
    rs.encode(messageWords, totalWords - messageSizeInWords);

    // Build output with startPad
    int startPad = totalBits % wordSize;
    BitArray messageBits = new BitArray();
    messageBits.appendBits(0, startPad);  // Add padding zeros first

    for (int messageWord : messageWords) {
        messageBits.appendBits(messageWord, wordSize);
    }
    return messageBits;
}
```

For compact L1:
- totalBits = 104
- wordSize = 6
- totalWords = 17
- startPad = 104 % 6 = 2

**messageBits structure**:
```
[0,0] + [cw0 bits] + [cw1 bits] + ... + [cw16 bits]
  ^        ^
  |        |
startPad   17 codewords × 6 bits = 102 bits
Total: 2 + 102 = 104 bits
```

### AztecLib placeDataCodewords

```swift
// Calculate startPad
let totalBitsInLayer = ((isCompact ? 88 : 112) + 16 * layers) * layers
let startPad = totalBitsInLayer % wordSize

// Build messageBits
var messageBits: [Bool] = []

// Add startPad zeros
for _ in 0..<startPad {
    messageBits.append(false)
}

// Add codewords MSB-first
for codeword in codewords {
    for bitPos in stride(from: wordSize - 1, through: 0, by: -1) {
        messageBits.append(((codeword >> bitPos) & 1) != 0)
    }
}
```

**Status**: startPad is now added. ✓

---

## 6. Data Placement Algorithm

### ZXing Placement Loop

```java
for (int i = 0, rowOffset = 0; i < layers; i++) {
    int rowSize = (layers - i) * 4 + (compact ? 9 : 12);

    for (int j = 0; j < rowSize; j++) {
        int columnOffset = j * 2;

        for (int k = 0; k < 2; k++) {
            // "TOP" - actually LEFT columns
            if (messageBits.get(rowOffset + columnOffset + k)) {
                matrix.set(alignmentMap[i * 2 + k], alignmentMap[i * 2 + j]);
            }
            // "RIGHT" - actually BOTTOM rows
            if (messageBits.get(rowOffset + rowSize * 2 + columnOffset + k)) {
                matrix.set(alignmentMap[i * 2 + j], alignmentMap[baseMatrixSize - 1 - i * 2 - k]);
            }
            // "BOTTOM" - actually RIGHT columns
            if (messageBits.get(rowOffset + rowSize * 4 + columnOffset + k)) {
                matrix.set(alignmentMap[baseMatrixSize - 1 - i * 2 - k], alignmentMap[baseMatrixSize - 1 - i * 2 - j]);
            }
            // "LEFT" - actually TOP rows
            if (messageBits.get(rowOffset + rowSize * 6 + columnOffset + k)) {
                matrix.set(alignmentMap[baseMatrixSize - 1 - i * 2 - j], alignmentMap[i * 2 + k]);
            }
        }
    }
    rowOffset += rowSize * 8;
}
```

**matrix.set(x, y)** uses (column, row) ordering.

For compact L1 (layer i=0, rowSize=13):

| Code Name | Bit Range | matrix.set(x, y) | Screen Position |
|-----------|-----------|------------------|-----------------|
| "TOP"     | 0-25      | (k, j)           | x=0-1, y=0-12 (LEFT) |
| "RIGHT"   | 26-51     | (j, 14-k)        | x=0-12, y=13-14 (BOTTOM) |
| "BOTTOM"  | 52-77     | (14-k, 14-j)     | x=13-14, y=2-14 (RIGHT) |
| "LEFT"    | 78-103    | (14-j, k)        | x=2-14, y=0-1 (TOP) |

### AztecLib Placement

```swift
// Top side
if messageBits[rowOffset + columnOffset + k] {
    let x = alignmentMap[i * 2 + k]
    let y = alignmentMap[i * 2 + j]
    setModule(matrix: &matrix, size: size, x: x, y: y, value: true)
}
```

**setModule** uses `bitIndex = y * size + x` (row-major storage).

**Status**: Placement formulas match ZXing. ✓

---

## 7. Implementation Status

**All identified issues have been resolved.** AztecLib now produces valid, decodable Aztec codes that match the ZXing reference implementation.

### Key Fixes Applied

1. **Stuff bit padding**: Fixed to pad with 1 when reading past end of input (matching ZXing behavior)
2. **Bit ordering**: Changed to MSB-first when placing bits in data layers
3. **Mode selection heuristic**: Fixed to correctly select compact vs full mode

### Validation

AztecLib-generated codes successfully decode with:
- Apple Vision framework
- zxing-cpp

See `AztecValidationTests.swift` and `AztecDecodeValidationTests.swift` for comprehensive validation tests.
