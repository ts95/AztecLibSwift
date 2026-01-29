# Aztec Codes: An Overview

## What is an Aztec Code?

An Aztec code is a type of 2D barcode—a square grid of black and white squares (called "modules") that encodes information. You've probably seen similar codes like QR codes on products, tickets, or advertisements.

```
    ██████████████████
    ██              ██
    ██  ██████████  ██
    ██  ██      ██  ██
    ██  ██  ██  ██  ██
    ██  ██      ██  ██
    ██  ██████████  ██
    ██              ██
    ██████████████████
```

The name "Aztec" comes from the central pattern that resembles a top-down view of an Aztec pyramid.

## Why Use Aztec Codes?

Aztec codes have several advantages:

1. **No quiet zone required** - Unlike QR codes, Aztec codes don't need a white border around them
2. **Efficient for small data** - Very compact for short messages
3. **Built-in error correction** - Can still be read even if partially damaged
4. **Variable size** - Automatically scales to fit your data

## Anatomy of an Aztec Code

Every Aztec code has these parts:

### 1. The Finder Pattern (Bull's Eye)

The center of every Aztec code has a distinctive "bull's eye" pattern of alternating black and white squares. This helps scanners locate and orient the code.

```
Compact (9×9 finder):        Full (13×13 finder):
    █████████                  █████████████
    █       █                  █           █
    █ █████ █                  █ █████████ █
    █ █   █ █                  █ █       █ █
    █ █ █ █ █                  █ █ █████ █ █
    █ █   █ █                  █ █ █   █ █ █
    █ █████ █                  █ █ █ █ █ █ █
    █       █                  █ █ █   █ █ █
    █████████                  █ █ █████ █ █
                               █ █       █ █
                               █ █████████ █
                               █           █
                               █████████████
```

### 2. Orientation Marks

Small marks near the finder pattern tell the scanner which way is "up." This lets the code be scanned from any angle.

### 3. Mode Message

A ring of modules around the finder pattern contains the "mode message"—information about the symbol itself:
- How many layers of data the symbol has
- How many data codewords are encoded

### 4. Data Layers

The actual encoded information surrounds the center, arranged in layers that spiral outward. More data = more layers = larger symbol.

### 5. Reference Grid (Full Symbols Only)

Larger "full" symbols have a grid of alternating black and white modules every 16 rows/columns. This helps scanners stay aligned when reading large symbols.

## Two Types of Symbols

### Compact Symbols

- Smaller: 15×15 to 27×27 modules
- 1 to 4 data layers
- 9×9 finder pattern
- Best for short messages (up to ~50 characters)

### Full Symbols

- Larger: 31×31 to 151×151 modules
- 4 to 32 data layers
- 13×13 finder pattern
- Can encode thousands of characters

## How Data Gets Encoded

Here's the journey your data takes:

```
"Hello" → [text encoding] → [bit stream] → [codewords] → [+ error correction] → [symbol matrix]
```

1. **Text Encoding**: Characters are converted to numbers using different "modes" (explained in [Mode Encoding](03-ModeEncoding.md))

2. **Bit Stream**: The numbers become a stream of bits (0s and 1s)

3. **Codewords**: Bits are grouped into fixed-size chunks called "codewords"

4. **Error Correction**: Extra codewords are calculated and added to protect against damage (explained in [Reed-Solomon](05-ReedSolomon.md))

5. **Symbol Matrix**: Codewords are arranged in the spiral pattern to create the final barcode

## Error Correction

One of the most important features of Aztec codes is error correction. Using clever mathematics (Reed-Solomon codes), the barcode includes extra information that allows it to be read even if:

- Part of the code is torn or scratched
- There's dirt or smudges
- Some modules are obscured

The error correction level is configurable. Higher levels:
- Can recover from more damage
- Require a larger symbol for the same data

Typical levels range from 5% to 95% of codewords dedicated to error correction. The default in this library is 23%.

## Next Steps

- [Encoding Pipeline](02-EncodingPipeline.md) - The complete journey from text to barcode
- [Mode Encoding](03-ModeEncoding.md) - How text is compressed efficiently
- [Galois Fields](04-GaloisFields.md) - The math foundation (don't worry, it's explained simply!)
- [Reed-Solomon](05-ReedSolomon.md) - How error correction actually works
- [Symbol Layout](06-SymbolLayout.md) - How the pieces fit together
