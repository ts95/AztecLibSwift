# Symbol Layout

This document explains how all the pieces fit together to form an Aztec barcode.

## Overview

An Aztec symbol is built from the center outward:

```
┌─────────────────────────────────┐
│                                 │
│    ┌─────────────────────┐      │
│    │                     │      │
│    │   ┌─────────────┐   │      │
│    │   │             │   │      │
│    │   │   ┌─────┐   │   │      │
│    │   │   │█████│   │   │      │   Layer 2
│    │   │   │█ █ █│   │   │      │
│    │   │   │█████│   │   │      │      │
│    │   │   │█ █ █│ ← │ ← │ ←────┼── Layer 1
│    │   │   │█████│   │   │      │
│    │   │   └─────┘   │   │      │
│    │   │  Mode Msg   │   │      │
│    │   └─────────────┘   │      │
│    │    Finder Pattern   │      │
│    └─────────────────────┘      │
│         Data Layers             │
└─────────────────────────────────┘
```

## The Finder Pattern (Bull's Eye)

The center of every Aztec symbol has a distinctive pattern of alternating black and white concentric squares.

### Compact Symbols: 9×9 Finder

```
█████████
█       █
█ █████ █
█ █   █ █
█ █ █ █ █   ← Center module (always black)
█ █   █ █
█ █████ █
█       █
█████████
```

The pattern follows a simple rule: distance from center determines color.
- Distance 0 (center): Black
- Distance 1: White
- Distance 2: Black
- Distance 3: White
- Distance 4: Black

### Full Symbols: 13×13 Finder

```
█████████████
█           █
█ █████████ █
█ █       █ █
█ █ █████ █ █
█ █ █   █ █ █
█ █ █ █ █ █ █   ← Center
█ █ █   █ █ █
█ █ █████ █ █
█ █       █ █
█ █████████ █
█           █
█████████████
```

Same alternating pattern, extended to distance 6.

## Orientation Marks

Near the finder pattern, small marks indicate which way is "up." This lets scanners read the code from any angle.

For compact symbols, orientation marks are at the corners of the mode message ring:
```
        ██
      ██
    █████████
    █       █
    █ █████ █
    █ █   █ █
    █ █ █ █ █
    █ █   █ █
    █ █████ █
    █       █
    █████████
```

The marks break the rotational symmetry so there's only one correct orientation.

## The Mode Message

A ring of modules around the finder pattern encodes metadata about the symbol.

### Compact Mode Message: 28 bits

```
Layout: [2 bits: layers-1] [6 bits: data_codewords-1] [20 bits: RS parity]
```

The 28 bits are arranged in 4 segments of 7 bits each, placed on the 4 sides of the finder:

```
          ←←←←←←←
         ↑       ↓
      ███████████████
      ██         ↓ ██
      ██ ███████ ↓ ██
      ██ ██   ██ ↓ ██
    ↑ ██ ██ █ ██   ██ ↓
    ↑ ██ ██   ██ ████
    ↑ ██ ███████ ██
    ↑ ██         ██
      ███████████████
         →→→→→→→
```

### Full Mode Message: 40 bits

```
Layout: [5 bits: layers-1] [11 bits: data_codewords-1] [24 bits: RS parity]
```

The 40 bits are arranged in 4 segments of 10 bits each.

### Error Protection

The mode message has its own Reed-Solomon protection over GF(16):
- Compact: 2 data nibbles + 5 parity nibbles
- Full: 4 data nibbles + 6 parity nibbles

This heavy redundancy ensures scanners can decode the symbol structure even if the center is damaged.

## Data Layers

Data is arranged in layers that spiral outward from the mode message.

### Layer Structure

Each layer is a ring 2 modules wide. The spiral goes counter-clockwise:

```
    ← ← ← ← ← ← ←
    ↓             ↑
    ↓  ┌───────┐  ↑
    ↓  │       │  ↑
    ↓  │ Finder│  ↑
    ↓  │       │  ↑
    ↓  └───────┘  ↑
    ↓             ↑
    → → → → → → →
```

Within each layer, bits are read in a specific pattern, two modules at a time.

### Bit Placement

Codewords are placed MSB-first (most significant bit first). For a 6-bit codeword like `101011`:

```
Position: [1][0][1][0][1][1]
              ↓
First bit placed is '1' (MSB)
Last bit placed is '1' (LSB)
```

## Reference Grid (Full Symbols Only)

For full symbols with many layers, alignment can be tricky. The reference grid helps scanners stay on track.

### Grid Lines

Every 16 modules from the center, horizontal and vertical lines of alternating black/white modules are drawn:

```
█ █ █ █ █ █ █ █ █ █ █ █ █



█                       █


█         ███████       █
          ██   ██
█         ██ █ ██       █
          ██   ██
█         ███████       █

█                       █



█ █ █ █ █ █ █ █ █ █ █ █ █
```

### When Reference Grid Appears

- Layers 1-15: No reference grid
- Layers 16-30: 1 reference grid line each direction
- Layers 31-32: 2 reference grid lines each direction

The grid lines interrupt data placement—codeword bits skip over grid positions.

## Symbol Sizes

### Compact Symbol Sizes

| Layers | Size | Formula |
|--------|------|---------|
| 1 | 15×15 | 11 + 4×1 |
| 2 | 19×19 | 11 + 4×2 |
| 3 | 23×23 | 11 + 4×3 |
| 4 | 27×27 | 11 + 4×4 |

**Formula:** size = 11 + 4 × layers

### Full Symbol Sizes

| Layers | Size | Ref Grid Lines |
|--------|------|----------------|
| 1 | 19×19 | 0 |
| 5 | 35×35 | 0 |
| 10 | 55×55 | 0 |
| 15 | 75×75 | 0 |
| 16 | 81×81 | 1 |
| 20 | 97×97 | 1 |
| 31 | 143×143 | 2 |
| 32 | 151×151 | 2 |

**Formula:** size = 15 + 4 × layers + 2 × ⌊(layers-1)/15⌋

The extra term accounts for reference grid lines.

## Putting It All Together

Here's the complete rendering sequence:

### Step 1: Create Empty Matrix

```swift
let size = symbolSize  // e.g., 15 for compact 1-layer
var matrix = Array(repeating: Array(repeating: false, count: size), count: size)
```

### Step 2: Draw Finder Pattern

```swift
let center = size / 2
for y in (center-radius)...(center+radius) {
    for x in (center-radius)...(center+radius) {
        let distance = max(abs(x-center), abs(y-center))
        matrix[y][x] = (distance % 2 == 0)  // Even distance = black
    }
}
```

### Step 3: Draw Orientation Marks

Place distinctive patterns to break rotational symmetry.

### Step 4: Place Mode Message

Encode layers and data codeword count, add RS parity, place around finder.

### Step 5: Draw Reference Grid (Full Only)

```swift
for gridLine in gridPositions {
    // Horizontal line
    for x in 0..<size {
        if !isInFinder(x, gridLine) {
            matrix[gridLine][x] = (x % 2 == 0)
        }
    }
    // Vertical line (same pattern)
}
```

### Step 6: Place Data Codewords

```swift
var path = buildSpiralPath()  // Counter-clockwise from center out
var pathIndex = 0

for codeword in allCodewords {
    for bit in codeword.bits(msbFirst: true) {
        let (x, y) = path[pathIndex]
        matrix[y][x] = bit
        pathIndex += 1
    }
}
```

## Coordinate System

The symbol uses a standard coordinate system:
- Origin (0, 0) is top-left
- X increases rightward
- Y increases downward

```
(0,0) → → → (size-1, 0)
  ↓
  ↓
  ↓
(0, size-1) → → → (size-1, size-1)
```

## Export Formats

### LSB-First (Default)

Each row is packed into bytes with bit 0 being the leftmost module:

```
Modules: [M0][M1][M2][M3][M4][M5][M6][M7]
Byte:     b0  b1  b2  b3  b4  b5  b6  b7

To check module x: (byte[x/8] >> (x%8)) & 1
```

### MSB-First (PNG Compatible)

Bit 7 is the leftmost module:

```
Modules: [M0][M1][M2][M3][M4][M5][M6][M7]
Byte:     b7  b6  b5  b4  b3  b2  b1  b0

To check module x: (byte[x/8] >> (7 - x%8)) & 1
```

Use MSB-first when generating PNG images, as most image formats expect this ordering.

## Summary

1. **Finder pattern** at center identifies and orients the symbol
2. **Orientation marks** break symmetry for rotation detection
3. **Mode message** encodes symbol metadata with heavy error protection
4. **Reference grid** (full symbols) helps scanner alignment
5. **Data layers** spiral counter-clockwise from center outward
6. **Codewords** are placed MSB-first within the spiral path

The result is a robust 2D barcode that can be read from any angle, even when partially damaged!
