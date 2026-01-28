# Reed-Solomon Error Correction

Reed-Solomon codes are the "magic" that allows damaged barcodes to still be readable. Named after Irving Reed and Gustave Solomon who invented them in 1960, they're used everywhere: CDs, DVDs, QR codes, satellite communications, and of course, Aztec codes.

## The Big Idea

Imagine you have 10 numbers to send, but you're worried some might get corrupted. Reed-Solomon lets you add extra "check" numbers that can reconstruct the originals if some get damaged.

```
Original:  [5, 12, 8, 3, 7, 22, 15, 9, 4, 11]
             ↓ Add 4 parity numbers
Protected: [5, 12, 8, 3, 7, 22, 15, 9, 4, 11, P1, P2, P3, P4]
```

If up to 2 numbers get corrupted (including their positions being unknown), all 10 originals can be recovered!

## How It Works: The Intuition

### Polynomials Through Points

Remember from algebra: a straight line (degree-1 polynomial) is defined by 2 points.

```
y = mx + b
Two points uniquely determine m and b
```

A parabola (degree-2 polynomial) needs 3 points:
```
y = ax² + bx + c
Three points uniquely determine a, b, and c
```

In general: a polynomial of degree n-1 is uniquely determined by n points.

### The Reed-Solomon Trick

Here's the key insight:

1. Treat your data as coefficients of a polynomial
2. Evaluate that polynomial at extra points
3. Send both the original data AND those evaluations
4. If some values get corrupted, you have redundant information to recover

**Example with 3 data values:**

```
Data: [5, 3, 7]
Think of this as the polynomial: D(x) = 5 + 3x + 7x²

Evaluate at extra points:
  D(1) = 5 + 3 + 7 = 15
  D(2) = 5 + 6 + 28 = 39

Send: [5, 3, 7, 15, 39]
```

Now if one value gets corrupted, you have 4 good values to reconstruct a degree-2 polynomial—more than enough!

## Systematic Encoding

Aztec uses "systematic" Reed-Solomon, meaning:
- The original data appears unchanged at the start
- Parity symbols are appended at the end

```
[Data1, Data2, ..., DataN, Parity1, Parity2, ..., ParityM]
```

This is convenient because if no errors occur, you can just read the data directly without decoding.

## The Generator Polynomial

To calculate parity, we use a special "generator polynomial" G(x).

### Building G(x)

The generator polynomial has roots at consecutive powers of α:
```
G(x) = (x - α^1)(x - α^2)(x - α^3)...(x - α^m)
```

where m is the number of parity symbols.

**For 4 parity symbols:**
```
G(x) = (x - α)(x - α²)(x - α³)(x - α⁴)
```

When expanded, this gives polynomial coefficients we can use for encoding.

### Why These Roots?

The roots are chosen so that the complete codeword (data + parity) is divisible by G(x). This means evaluating the codeword polynomial at α^1, α^2, etc., gives zero.

Any corruption changes these evaluations to non-zero values, which is how errors are detected!

## Computing Parity: The LFSR Method

Instead of polynomial division, we use an efficient method called a Linear Feedback Shift Register (LFSR).

Think of it like a pipeline:

```
Data flows in →  [Reg0][Reg1][Reg2][Reg3]  → Feedback
                   ↑      ↑      ↑      ↑
                  tap0   tap1   tap2   tap3  (from G(x) coefficients)
```

**Algorithm:**
```
Initialize registers to 0
For each data codeword d:
    feedback = d XOR last_register
    Shift all registers right
    For each register position:
        register[i] XOR= feedback × G[i+1]

After all data: registers contain parity symbols
```

## Concrete Example in GF(8)

Let's encode 3 data symbols with 2 parity symbols.

**Setup:**
- Field: GF(8) with primitive polynomial x³ + x + 1
- Data: [5, 3, 7]
- Parity count: 2

**Step 1: Build generator polynomial**
```
G(x) = (x - α)(x - α²)
     = x² - (α + α²)x + α³
     = x² + 6x + 3      (in GF(8), subtraction = addition)
```

Coefficients: [3, 6, 1] (constant term first)

**Step 2: LFSR encoding**
```
Registers: [R0, R1] = [0, 0]
G taps: G[1]=6, G[2]=1

Process data[0] = 5:
  feedback = 5 XOR R1 = 5 XOR 0 = 5
  R1 = R0 XOR (5 × G[2]) = 0 XOR 5 = 5
  R0 = 5 × G[1] = 5 × 6 = ... (Galois mult)

... (continue for each data symbol)

Final registers = parity symbols
```

## Error Correction Capability

With m parity symbols, Reed-Solomon can:
- **Detect** up to m errors
- **Correct** up to ⌊m/2⌋ errors (when positions are unknown)
- **Correct** up to m erasures (when positions are known)

**Why the difference?**

Finding an error requires determining both:
1. Which position is wrong
2. What the correct value should be

Each unknown uses up some of our redundancy. With unknown positions, each error "costs" 2 parity symbols.

## The Aztec Implementation

In AztecLib, Reed-Solomon encoding follows this pattern:

```swift
// Create the Galois field
let gf = GaloisField(wordSizeInBits: 6, primitivePolynomial: 0x43)

// Create encoder with generator starting at α^1
let encoder = ReedSolomonEncoder(field: gf, startExponent: 1)

// Compute parity for data
let parity = encoder.makeParityCodewords(
    for: dataCodewords,
    parityCodewordCount: 4
)

// Or get data + parity combined
let allCodewords = encoder.appendingParity(
    to: dataCodewords,
    parityCodewordCount: 4
)
```

## Why It Works: A Deeper Look

### The Syndrome Approach

When decoding, a scanner computes "syndromes" by evaluating the received codeword at α^1, α^2, etc.

**No errors:** All syndromes are 0 (because correct codeword is divisible by G(x))
**Errors present:** Some syndromes are non-zero

The pattern of non-zero syndromes reveals:
1. How many errors occurred
2. Where they are
3. What the correct values should be

### The Math Behind Correction

Error correction solves a system of equations:
```
S₁ = e₁·α^j₁ + e₂·α^j₂ + ...
S₂ = e₁·α^(2j₁) + e₂·α^(2j₂) + ...
...
```

Where:
- Sᵢ are the syndromes (known)
- eᵢ are error values (unknown)
- jᵢ are error positions (unknown)

Galois field math lets us solve this system efficiently using algorithms like Berlekamp-Massey or Euclidean algorithm.

## Mode Message Protection

The mode message (symbol metadata) uses its own small Reed-Solomon code over GF(16):

**Compact symbols:**
- 2 data nibbles (4 bits each)
- 5 parity nibbles
- Total: 28 bits

**Full symbols:**
- 4 data nibbles
- 6 parity nibbles
- Total: 40 bits

This heavy redundancy ensures the scanner can read the symbol structure even if the center is damaged.

## Error Correction in Practice

| EC Level | Parity Ratio | Can Correct | Use Case |
|----------|--------------|-------------|----------|
| 5% | 1:20 | ~2.5% errors | Clean environment |
| 23% | ~1:4 | ~11% errors | Default, general use |
| 50% | 1:2 | ~25% errors | Harsh conditions |
| 95% | ~19:1 | ~47% errors | Maximum protection |

Higher error correction = larger symbols for same data.

## Summary

1. **Reed-Solomon** adds redundant parity symbols to detect and correct errors
2. **Generator polynomial** G(x) defines how parity is calculated
3. **LFSR** efficiently computes parity using shift register technique
4. **m parity symbols** can correct up to m/2 errors or m erasures
5. **Galois field math** makes all the calculations work within fixed bit widths

## Next

See [Symbol Layout](06-SymbolLayout.md) to understand how the protected codewords are arranged in the final barcode!
