# Galois Fields: The Math Behind Error Correction

Don't worry—this sounds scarier than it is! We'll build up the concepts step by step.

## The Problem We're Solving

We want to do math on codewords (numbers) in a way that:
1. Addition and multiplication always give valid codewords
2. We can "undo" operations (like division) without getting fractions
3. Everything stays within a fixed range of numbers

Regular math doesn't work well here. For example, if our codewords are 0-63 (6 bits):
- 50 + 20 = 70 (too big!)
- 10 / 3 = 3.333... (not a whole number!)

Galois fields solve this problem.

## What is a Galois Field?

A Galois field (named after mathematician Évariste Galois) is a set of numbers with special addition and multiplication rules that always keep results within the set.

We write GF(n) for a Galois field with n elements. Aztec codes use:
- GF(64) for 6-bit codewords (0-63)
- GF(256) for 8-bit codewords (0-255)
- GF(1024) for 10-bit codewords (0-1023)
- GF(4096) for 12-bit codewords (0-4095)

## Binary Fields: GF(2)

Let's start with the simplest Galois field: GF(2), which has just {0, 1}.

### Addition in GF(2)

Addition is XOR (exclusive or):

| + | 0 | 1 |
|---|---|---|
| 0 | 0 | 1 |
| 1 | 1 | 0 |

Notice: 1 + 1 = 0, not 2! This "wraps around" to stay in {0, 1}.

### Multiplication in GF(2)

Multiplication is AND:

| × | 0 | 1 |
|---|---|---|
| 0 | 0 | 0 |
| 1 | 0 | 1 |

This is just like regular multiplication, but the results are always 0 or 1.

## Extension Fields: GF(2^m)

Now here's the clever part. We can build larger fields from GF(2) using a technique similar to how complex numbers extend real numbers.

### Think of It Like Polynomials

In GF(2^6), we represent each number as a polynomial with binary (0 or 1) coefficients:

```
The number 45 = 101101 in binary

Think of it as: 1·x^5 + 0·x^4 + 1·x^3 + 1·x^2 + 0·x^1 + 1·x^0
             = x^5 + x^3 + x^2 + 1
```

Each number 0-63 corresponds to a unique polynomial of degree ≤ 5.

### Addition in GF(2^m)

Addition is simple: XOR the binary representations (add coefficients mod 2).

```
  45 = 101101
+ 27 = 011011
  ──────────
  38 = 110110  (XOR each bit position)
```

In polynomial form:
```
(x^5 + x^3 + x^2 + 1) + (x^4 + x^3 + x + 1) = x^5 + x^4 + x^2 + x
```

Coefficients that add to 2 become 0 (because 1 + 1 = 0 in GF(2)).

### Multiplication in GF(2^m)

This is trickier. We multiply polynomials, then reduce by a special polynomial to keep the result within bounds.

**Step 1: Multiply polynomials**
```
(x^2 + 1) × (x + 1) = x^3 + x^2 + x + 1
```

**Step 2: If result is too big, reduce using the "primitive polynomial"**

The primitive polynomial acts like a modulus. For GF(64), we use:
```
p(x) = x^6 + x + 1
```

If our product has degree ≥ 6, we divide by p(x) and keep the remainder.

**Why this works**: We're essentially saying "x^6 = x + 1" (because x^6 + x + 1 = 0 means x^6 = -x - 1 = x + 1 in binary).

## The Primitive Element α

Every Galois field has a special element called the "primitive element" (usually written as α, the Greek letter alpha).

The key property: Powers of α generate every non-zero element in the field!

```
α^0 = 1
α^1 = α
α^2 = α·α
α^3 = α·α·α
...
α^62 = (some value)
α^63 = 1  (wraps back around!)
```

This is like how powers of 2 cycle in regular modular arithmetic, but it works perfectly in Galois fields.

## Log and Antilog Tables

Here's a practical trick: we can do multiplication using addition!

Remember logarithms from high school?
```
log(a × b) = log(a) + log(b)
```

We build tables for the Galois field:
- **Exp table** (antilog): exp[i] = α^i
- **Log table**: log[x] = i where α^i = x

Then multiplication becomes:
```
a × b = exp[log[a] + log[b]]
```

This is much faster than polynomial multiplication!

### Example Tables for GF(8)

Using primitive polynomial x^3 + x + 1:

| i | α^i | Binary |
|---|-----|--------|
| 0 | 1 | 001 |
| 1 | α | 010 |
| 2 | α^2 | 100 |
| 3 | α+1 | 011 |
| 4 | α^2+α | 110 |
| 5 | α^2+α+1 | 111 |
| 6 | α^2+1 | 101 |
| 7 | 1 | 001 (cycles!) |

Log table (inverse):
| x | Binary | log(x) |
|---|--------|--------|
| 1 | 001 | 0 |
| 2 | 010 | 1 |
| 3 | 011 | 3 |
| 4 | 100 | 2 |
| 5 | 101 | 6 |
| 6 | 110 | 4 |
| 7 | 111 | 5 |

### Multiplication Example

Let's compute 3 × 5 in GF(8):
```
log[3] = 3
log[5] = 6
log[3] + log[5] = 9

But 9 > 7, so we wrap: 9 mod 7 = 2

exp[2] = 4

Therefore: 3 × 5 = 4 in GF(8)
```

You can verify: (x+1) × (x^2+1) = x^3 + x^2 + x + 1. Reducing by x^3+x+1 gives x^2, which is 4.

## Primitive Polynomials Used in Aztec

| Field | Size | Primitive Polynomial | Hex |
|-------|------|---------------------|-----|
| GF(64) | 2^6 | x^6 + x + 1 | 0x43 |
| GF(256) | 2^8 | x^8 + x^5 + x^3 + x^2 + 1 | 0x12D |
| GF(1024) | 2^10 | x^10 + x^3 + 1 | 0x409 |
| GF(4096) | 2^12 | x^12 + x^6 + x^5 + x^3 + 1 | 0x1069 |

The hex values include the x^m term (e.g., 0x43 = 1000011 = x^6 + x + 1).

## Why This Matters for Error Correction

Galois field arithmetic has a crucial property: **every non-zero element has a multiplicative inverse**.

This means we can always solve equations like:
```
a × x = b  →  x = b / a = b × inverse(a)
```

Reed-Solomon error correction works by solving systems of equations over Galois fields. Without guaranteed inverses, this wouldn't be possible!

## Summary

1. **Galois fields** are number systems where +, -, ×, ÷ always stay within bounds
2. **Addition** is XOR (simple and fast)
3. **Multiplication** uses polynomial math modulo a primitive polynomial
4. **Log/exp tables** make multiplication fast
5. **Every non-zero element has an inverse**, enabling equation solving

## Code Connection

In AztecLib, the `GaloisField` struct implements all of this:

```swift
// Create a field
let gf = GaloisField(wordSizeInBits: 6, primitivePolynomial: 0x43)

// Addition is XOR
let sum = gf.add(a, b)  // Returns a ^ b

// Multiplication uses log/exp tables
let product = gf.multiply(a, b)  // Uses: exp[log[a] + log[b]]
```

## Next

Now that we understand Galois fields, we can see how they're used in [Reed-Solomon](05-ReedSolomon.md) error correction!
