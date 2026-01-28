# Mode Encoding

Aztec codes use "modes" to efficiently encode different types of characters. This is like having different dictionaries optimized for different kinds of text.

## Why Use Modes?

Imagine you're sending a message and you want to use as few bits as possible. You could:

1. Use 8 bits for every character (like ASCII) → 8 bits per character
2. Notice that uppercase letters only need 5 bits (26 letters < 32 = 2^5)

Aztec takes this further with specialized modes for different character types.

## The Six Modes

### 1. Upper Mode (5 bits per character)

For uppercase letters and space.

| Code | Character | Code | Character |
|------|-----------|------|-----------|
| 1 | (space) | 15 | N |
| 2 | A | 16 | O |
| 3 | B | 17 | P |
| 4 | C | 18 | Q |
| 5 | D | 19 | R |
| 6 | E | 20 | S |
| 7 | F | 21 | T |
| 8 | G | 22 | U |
| 9 | H | 23 | V |
| 10 | I | 24 | W |
| 11 | J | 25 | X |
| 12 | K | 26 | Y |
| 13 | L | 27 | Z |
| 14 | M | | |

Codes 28-31 are reserved for mode switching.

### 2. Lower Mode (5 bits per character)

For lowercase letters and space. Same structure as Upper, but with a-z instead of A-Z.

### 3. Digit Mode (4 bits per character)

For numbers and a few common characters.

| Code | Character |
|------|-----------|
| 2 | (space) |
| 3 | , (comma) |
| 4 | . (period) |
| 5-14 | 0-9 |

Codes 0, 1, and 15 are for mode switching.

**Note**: Digit mode uses only 4 bits per character, making it very efficient for numbers!

### 4. Punctuation Mode (5 bits per character)

For punctuation marks.

| Code | Character | Code | Character |
|------|-----------|------|-----------|
| 1 | CR | 17 | , |
| 2 | CR LF | 18 | - |
| 3 | . (space) | 19 | . |
| 4 | , (space) | 20 | / |
| 5 | : (space) | 21 | : |
| 6 | ! | 22 | ; |
| 7 | " | 23 | < |
| 8 | # | 24 | = |
| 9 | $ | 25 | > |
| 10 | % | 26 | ? |
| 11 | & | 27 | [ |
| 12 | ' | 28 | ] |
| 13 | ( | 29 | { |
| 14 | ) | 30 | } |
| 15 | * | 31 | U/L (switch) |
| 16 | + | | |

Notice codes 2-5 encode two-character sequences in a single code—very efficient for common patterns like ". " or ", ".

### 5. Mixed Mode (5 bits per character)

For control characters and special symbols not in other modes.

| Code | Character | Code | Character |
|------|-----------|------|-----------|
| 1-18 | Control chars (^A through ^_) | 23 | ` |
| 19 | @ | 24 | \| |
| 20 | \\ | 25 | ~ |
| 21 | ^ | 26 | DEL |
| 22 | _ | | |

### 6. Byte Mode (8 bits per byte)

For raw binary data or characters not in other modes (like emoji or non-Latin text).

```
[Mode switch] + [Length] + [Bytes...]
   5 bits       5 or 16    8 bits each
```

- Short form: length 1-31 uses 5-bit length
- Long form: length 32+ uses 0 + 11-bit length (for lengths 32-2079)

## Mode Switching

To use a character from a different mode, you need to switch. There are two types:

### Latching (Permanent Switch)

A "latch" changes your current mode until you latch again. Use this when you'll be staying in the new mode for multiple characters.

**Latch codes from Upper mode:**
| Code | Bits | Destination |
|------|------|-------------|
| 28 | 5 | Lower |
| 29 | 5 | Mixed |
| 30 | 5 | Digit |
| 31 | 5 | Byte |

### Shifting (Temporary Switch)

A "shift" changes mode for just one character, then returns. Use this for isolated characters.

**Shift codes from Upper mode:**
| Code | Bits | Destination |
|------|------|-------------|
| 0 | 5 | Punctuation (one char) |

### Multi-Step Switches

Some mode transitions require going through intermediate modes:

```
Upper → Punct: Must go through Mixed
  Upper --[29]--> Mixed --[30]--> Punct

Lower → Upper: Must go through Digit
  Lower --[30]--> Digit --[14]--> Upper
```

## Encoding Strategy

The encoder uses a simple look-ahead strategy to choose between latching and shifting:

1. Look at the next few characters
2. Count how many can use the potential target mode
3. If 2 or more → latch (permanent switch)
4. If just 1 → shift (temporary switch)

## Example: Encoding "Hello, World!"

Let's trace through this string:

```
Current mode: Upper (default start)

'H' - In Upper mode: code 9 (01001)
'e' - Not in Upper! Look ahead: "ello" all lowercase
      → Latch to Lower: code 28 (11100)
      In Lower mode: 'e' = code 6 (00110)
'l' - In Lower mode: code 13 (01101)
'l' - In Lower mode: code 13 (01101)
'o' - In Lower mode: code 16 (10000)
',' - Not in Lower! Only one punctuation
      → Shift to Punct: code 0 (00000)
      In Punct mode: ',' = code 17 (10001)
      (Back to Lower automatically)
' ' - In Lower mode: code 1 (00001)
'W' - Not in Lower! Look ahead: "World" mostly lowercase
      → Shift to Upper: code 28 (11100)
      In Upper mode: 'W' = code 24 (11000)
      (Back to Lower automatically)
'o' - In Lower mode: code 16 (10000)
'r' - In Lower mode: code 19 (10011)
'l' - In Lower mode: code 13 (01101)
'd' - In Lower mode: code 5 (00101)
'!' - Not in Lower!
      → Shift to Punct: code 0 (00000)
      In Punct mode: '!' = code 6 (00110)
```

Total encoding:
```
01001 11100 00110 01101 01101 10000 00000 10001 00001 11100 11000 10000 10011 01101 00101 00000 00110
  H   L/L    e     l     l     o    P/S    ,    space U/S    W     o     r     l     d    P/S    !
```

That's 85 bits for 13 characters, averaging about 6.5 bits per character—much better than 8 bits per character in plain ASCII!

## Efficiency Comparison

| Input | ASCII (8 bits each) | Aztec Encoded |
|-------|---------------------|---------------|
| "HELLO" | 40 bits | 25 bits (Upper mode) |
| "hello" | 40 bits | 30 bits (latch + Lower) |
| "12345" | 40 bits | 25 bits (latch + Digit) |
| "Hello" | 40 bits | 30 bits (mix of modes) |

## Two-Character Sequences

Punctuation mode has special codes for common patterns:

| Code | Sequence | Use Case |
|------|----------|----------|
| 2 | CR LF | Line endings (Windows) |
| 3 | ". " | End of sentence |
| 4 | ", " | Comma in text |
| 5 | ": " | After colons |

These encode two characters in 5 bits instead of 10+!

## Next

- [Galois Fields](04-GaloisFields.md) - The math behind error correction
- [Reed-Solomon](05-ReedSolomon.md) - How error correction works
