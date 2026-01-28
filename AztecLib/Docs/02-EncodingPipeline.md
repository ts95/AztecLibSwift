# The Encoding Pipeline

This document explains the complete journey from your input data to a finished Aztec barcode.

## Overview

```
Input Text/Data
      │
      ▼
┌─────────────────┐
│  Data Encoding  │  Convert text to bits using modes
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│  Configuration  │  Choose symbol size based on data length
│    Selection    │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│    Codeword     │  Pack bits into fixed-width codewords
│    Packing      │  with "stuff bits"
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│  Reed-Solomon   │  Calculate error correction codewords
│    Encoding     │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│ Matrix Building │  Arrange everything into the symbol
└────────┬────────┘
         │
         ▼
    AztecSymbol
```

## Step 1: Data Encoding

The first step converts your input into a stream of bits.

### For Text

Text is encoded using "modes" that assign short bit patterns to common characters. For example:

- Uppercase letters (A-Z): 5 bits each in "Upper" mode
- Lowercase letters (a-z): 5 bits each in "Lower" mode
- Digits (0-9): 4 bits each in "Digit" mode

The encoder automatically switches between modes to minimize the total bits. See [Mode Encoding](03-ModeEncoding.md) for details.

**Example**: "ABC" in Upper mode
```
A = 2  → 00010 (5 bits)
B = 3  → 00011 (5 bits)
C = 4  → 00100 (5 bits)
─────────────────────
Total: 15 bits
```

### For Binary Data

Raw bytes are encoded in "Byte" mode:
```
[Byte mode switch] + [length] + [raw bytes]
     5 bits          5 or 16    8 bits each
```

## Step 2: Configuration Selection

Based on how many bits your data needs, the library picks the smallest symbol that will fit.

The selection considers:

1. **Payload size** - How many bits of data you have
2. **Error correction level** - How much redundancy you want
3. **Symbol preference** - Compact vs. full symbols

### Symbol Capacity

Each symbol size has a fixed total capacity in codewords. Those codewords are split between:
- **Data codewords**: Your actual information
- **Parity codewords**: Error correction

**Example**: Compact 1-layer symbol
```
Total capacity: 17 codewords × 6 bits = 102 bits
With 23% EC:    ~13 data + ~4 parity codewords
```

If your data doesn't fit, the next larger symbol is tried.

## Step 3: Codeword Packing

The bit stream is divided into fixed-width codewords (6, 8, 10, or 12 bits depending on symbol size).

### The "Stuff Bit" Rule

Here's a clever trick: Aztec codes add an extra bit to each codeword to avoid problematic patterns.

**Why?** A codeword of all 0s or all 1s could be confused with empty space or a solid block. So:

- If the data bits are all 0s → add a 1 at the end
- If the data bits are all 1s → add a 0 at the end
- Otherwise → add the next data bit

**Example** with 6-bit codewords (5 data bits + 1 stuff bit):

```
Data bits: 00000 → Codeword: 000001 (stuffed 1)
Data bits: 11111 → Codeword: 111110 (stuffed 0)
Data bits: 10101 + next bit 1 → Codeword: 101011 (normal)
```

This means each codeword carries `width - 1` bits of actual data.

## Step 4: Reed-Solomon Encoding

Now comes the "magic" part—adding error correction.

Reed-Solomon encoding takes your data codewords and calculates additional "parity" codewords. If any codewords get damaged later, the math lets us reconstruct the originals.

**Example**:
```
Data codewords:   [D1, D2, D3, D4, D5, D6, D7, D8, D9, D10]
                                  +
                   Reed-Solomon calculation
                                  ↓
Parity codewords: [P1, P2, P3]

Final codewords:  [D1, D2, D3, D4, D5, D6, D7, D8, D9, D10, P1, P2, P3]
```

The number of parity codewords determines how many errors can be corrected:
- Can correct up to `floor(parity_count / 2)` codeword errors
- Can detect up to `parity_count` errors

See [Reed-Solomon](05-ReedSolomon.md) for the mathematical details.

## Step 5: Matrix Building

The final step assembles all the pieces into the 2D symbol.

### Components Built

1. **Finder Pattern**: The central bull's eye
2. **Orientation Marks**: Direction indicators
3. **Mode Message**: Symbol metadata with its own error correction
4. **Reference Grid**: Alignment lines (full symbols only)
5. **Data Layers**: The codewords in a spiral pattern

### Mode Message Encoding

The mode message tells scanners about the symbol structure:

**Compact** (28 bits total):
```
[2 bits: layers-1] [6 bits: data_codewords-1] [20 bits: RS parity]
```

**Full** (40 bits total):
```
[5 bits: layers-1] [11 bits: data_codewords-1] [24 bits: RS parity]
```

### Data Placement

Codewords are placed in a counter-clockwise spiral pattern starting just outside the mode message ring:

```
        ← ← ← ← ←
        ↓       ↑
    → → ┌───────┐ ↑
    ↑   │Finder │ ↑
    ↑   │Pattern│ ↑
    ↑   └───────┘ →
    ↑       → → →
```

Each "layer" of the spiral is 2 modules wide, with codeword bits placed MSB-first (most significant bit first).

## Step 6: Export

The completed matrix is a grid of boolean values (true = black, false = white).

For output, rows are packed into bytes:

**LSB-first** (default):
```
Modules: [0][1][2][3][4][5][6][7]
Byte:     bit0 bit1 bit2 bit3 bit4 bit5 bit6 bit7
```

**MSB-first** (PNG-compatible):
```
Modules: [0][1][2][3][4][5][6][7]
Byte:     bit7 bit6 bit5 bit4 bit3 bit2 bit1 bit0
```

## Complete Example

Let's trace "Hi" through the pipeline:

```
Input: "Hi"

Step 1 - Data Encoding:
  H in Upper mode = 9  → 01001 (5 bits)
  Switch to Lower mode → 11100 (5 bits)
  i in Lower mode = 10 → 01010 (5 bits)
  Total: 15 bits

Step 2 - Configuration:
  15 bits + error correction → Compact 1-layer (15×15)
  Codeword width: 6 bits

Step 3 - Codeword Packing:
  Bits: 010011110001010
  Groups of 5 + stuff bit:
    01001 + 1 → 010011
    11100 + 0 → 111000
    01010 + padding → stuffed

Step 4 - Reed-Solomon:
  Data codewords + parity codewords calculated

Step 5 - Matrix Building:
  Place finder (9×9 bull's eye)
  Place mode message (28 bits around finder)
  Place data in layer 1

Step 6 - Export:
  15×15 matrix → 2 bytes per row × 15 rows = 30 bytes
```

## Next

- [Mode Encoding](03-ModeEncoding.md) - Deep dive into text compression
- [Galois Fields](04-GaloisFields.md) - The math foundation
- [Reed-Solomon](05-ReedSolomon.md) - Error correction details
- [Symbol Layout](06-SymbolLayout.md) - Matrix structure
