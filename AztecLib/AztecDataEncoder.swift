//
//  AztecDataEncoder.swift
//  AztecLib
//
//  Created by Toni Sucic on 13/10/2025.
//

import Foundation

// MARK: - Aztec Encoding Modes

/// The encoding modes defined by ISO/IEC 24778.
public enum AztecMode: Int, CaseIterable, Sendable {
    case upper = 0   // A-Z, space (5 bits)
    case lower = 1   // a-z, space (5 bits)
    case mixed = 2   // Control chars, punctuation subset (5 bits)
    case punct = 3   // Punctuation (5 bits)
    case digit = 4   // 0-9, comma, period (4 bits)
    case byte = 5    // Raw bytes (8 bits per byte after length)
}

// MARK: - Mode Tables

/// Character encoding tables per ISO/IEC 24778.
internal struct AztecModeTables: Sendable {
    /// Upper mode: A-Z (1-26), space (1)
    /// Code 0 is reserved, codes 1-26 are A-Z, code 27 is special
    static let upperCharToCode: [Character: Int] = {
        var map: [Character: Int] = [" ": 1]
        for (i, c) in "ABCDEFGHIJKLMNOPQRSTUVWXYZ".enumerated() {
            map[c] = i + 2
        }
        return map
    }()

    /// Lower mode: a-z (1-26), space (1)
    static let lowerCharToCode: [Character: Int] = {
        var map: [Character: Int] = [" ": 1]
        for (i, c) in "abcdefghijklmnopqrstuvwxyz".enumerated() {
            map[c] = i + 2
        }
        return map
    }()

    /// Mixed mode: Control characters and some punctuation (5 bits)
    /// Per ZXing: NUL=0, Space=1, ^A-CR=2-14, ESC=15, FS-US=16-19, @=20, etc.
    static let mixedCharToCode: [Character: Int] = {
        var map: [Character: Int] = [:]
        // Code 0: NUL
        map[Character(UnicodeScalar(0)!)] = 0
        // Code 1: Space
        map[" "] = 1
        // Codes 2-14: Control characters ^A through CR
        map[Character(UnicodeScalar(1)!)] = 2   // ^A (SOH)
        map[Character(UnicodeScalar(2)!)] = 3   // ^B (STX)
        map[Character(UnicodeScalar(3)!)] = 4   // ^C (ETX)
        map[Character(UnicodeScalar(4)!)] = 5   // ^D (EOT)
        map[Character(UnicodeScalar(5)!)] = 6   // ^E (ENQ)
        map[Character(UnicodeScalar(6)!)] = 7   // ^F (ACK)
        map[Character(UnicodeScalar(7)!)] = 8   // ^G (BEL)
        map[Character(UnicodeScalar(8)!)] = 9   // ^H (BS)
        map[Character(UnicodeScalar(9)!)] = 10  // ^I (HT)
        map[Character(UnicodeScalar(10)!)] = 11 // ^J (LF)
        map[Character(UnicodeScalar(11)!)] = 12 // ^K (VT)
        map[Character(UnicodeScalar(12)!)] = 13 // ^L (FF)
        map[Character(UnicodeScalar(13)!)] = 14 // ^M (CR)
        // Code 15: ESC
        map[Character(UnicodeScalar(27)!)] = 15 // ESC
        // Codes 16-19: FS, GS, RS, US
        map[Character(UnicodeScalar(28)!)] = 16 // FS
        map[Character(UnicodeScalar(29)!)] = 17 // GS
        map[Character(UnicodeScalar(30)!)] = 18 // RS
        map[Character(UnicodeScalar(31)!)] = 19 // US
        // Codes 20-26: Printable characters
        map["@"] = 20
        map["\\"] = 21
        map["^"] = 22
        map["_"] = 23
        map["`"] = 24
        map["|"] = 25
        map["~"] = 26
        // Code 27: DEL
        map[Character(UnicodeScalar(127)!)] = 27
        return map
    }()

    /// Punct mode: Punctuation characters (5 bits)
    /// Per ISO/IEC 24778 Table 6
    /// Note: Two-character sequences like CR LF, ". ", ", ", ": " are handled separately.
    static let punctCharToCode: [Character: Int] = {
        var map: [Character: Int] = [:]
        // FLG(n) is code 0 - handled separately
        map[Character(UnicodeScalar(13)!)] = 1  // CR
        // Codes 2-5 are two-character sequences handled in punctTwoCharCode()
        map["!"] = 6
        map["\""] = 7
        map["#"] = 8
        map["$"] = 9
        map["%"] = 10
        map["&"] = 11
        map["'"] = 12
        map["("] = 13
        map[")"] = 14
        map["*"] = 15
        map["+"] = 16
        map[","] = 17
        map["-"] = 18
        map["."] = 19
        map["/"] = 20
        map[":"] = 21
        map[";"] = 22
        map["<"] = 23
        map["="] = 24
        map[">"] = 25
        map["?"] = 26
        map["["] = 27
        map["]"] = 28
        map["{"] = 29
        map["}"] = 30
        return map
    }()

    /// Digit mode: digits and some punctuation (4 bits)
    /// Per ZXing/ISO - Codes: 0=P/L, 1=space, 2-11='0'-'9', 12=',', 13='.'
    static let digitCharToCode: [Character: Int] = {
        var map: [Character: Int] = [:]
        // Code 0 is P/L (latch to Punct), handled separately
        map[" "] = 1
        for i in 0...9 {
            map[Character("\(i)")] = i + 2  // '0'=2, '1'=3, ..., '9'=11
        }
        map[","] = 12
        map["."] = 13
        return map
    }()

    /// Returns the code for a character in a given mode, or nil if not representable.
    static func code(for char: Character, in mode: AztecMode) -> Int? {
        switch mode {
        case .upper: return upperCharToCode[char]
        case .lower: return lowerCharToCode[char]
        case .mixed: return mixedCharToCode[char]
        case .punct: return punctCharToCode[char]
        case .digit: return digitCharToCode[char]
        case .byte: return nil // Handled separately
        }
    }

    /// Bit width for each mode's codewords.
    static func bitWidth(for mode: AztecMode) -> Int {
        switch mode {
        case .upper, .lower, .mixed, .punct: return 5
        case .digit: return 4
        case .byte: return 8
        }
    }
}

// MARK: - Mode Transition Codes

/// Latch and shift codes for mode transitions per ISO/IEC 24778.
internal struct AztecModeTransitions: Sendable {
    /// Latch codes: permanent mode switch
    /// Format: (code, bitWidth)
    static let latchCodes: [AztecMode: [AztecMode: (code: Int, bits: Int)]] = [
        .upper: [
            .lower: (28, 5),  // L/L
            .mixed: (29, 5),  // M/L
            .punct: (29, 5),  // M/L then P/L from mixed (handled separately)
            .digit: (30, 5),  // D/L
        ],
        .lower: [
            .upper: (30, 5),  // D/L then U/L (handled via digit then shift)
            .mixed: (29, 5),  // M/L
            .punct: (29, 5),  // M/L then P/L
            .digit: (30, 5),  // D/L
        ],
        .mixed: [
            .upper: (29, 5),  // U/L
            .lower: (28, 5),  // L/L
            .punct: (30, 5),  // P/L
            .digit: (29, 5),  // U/L then D/L (handled separately)
        ],
        .punct: [
            .upper: (31, 5),  // U/L
        ],
        .digit: [
            .upper: (14, 4),  // U/L
            .punct: (15, 4),  // U/S then P/L (special handling)
        ],
    ]

    /// Shift codes: temporary mode switch (one character only)
    /// Format: (code, bitWidth)
    static let shiftCodes: [AztecMode: [AztecMode: (code: Int, bits: Int)]] = [
        .upper: [
            .punct: (0, 5),  // P/S (code 0 followed by punct)
        ],
        .lower: [
            .upper: (28, 5), // U/S
            .punct: (0, 5),  // P/S
        ],
        .mixed: [
            .punct: (0, 5),  // P/S
        ],
        .digit: [
            .upper: (15, 4), // U/S
            .punct: (0, 4),  // P/S
        ],
    ]

    /// Byte mode switch codes
    static let byteShift: (code: Int, bits: Int) = (31, 5)  // B/S in upper/lower/mixed
    static let byteShiftFromPunct: (code: Int, bits: Int) = (31, 5)  // U/L then B/S
}

// MARK: - Aztec Data Encoder

/// Encodes strings and byte arrays into Aztec bit streams with automatic mode selection.
public struct AztecDataEncoder: Sendable {

    /// Encodes a string into a bit buffer using optimal mode selection.
    ///
    /// - Parameter string: The string to encode.
    /// - Returns: A `BitBuffer` containing the encoded data bits.
    public static func encode(_ string: String) -> BitBuffer {
        var buffer = BitBuffer()
        var currentMode: AztecMode = .upper
        let chars = Array(string)
        var i = 0

        while i < chars.count {
            let char = chars[i]

            // Try two-character sequences in punct mode
            if i + 1 < chars.count {
                let twoChar = String(chars[i...i+1])
                if let punctCode = punctTwoCharCode(twoChar) {
                    appendModeSwitch(from: currentMode, to: .punct, buffer: &buffer, latch: false)
                    buffer.appendBitsMSBFirst(UInt64(punctCode), bitCount: 5)
                    i += 2
                    continue
                }
            }

            // Check if current mode can encode this character
            if let code = AztecModeTables.code(for: char, in: currentMode) {
                let bits = AztecModeTables.bitWidth(for: currentMode)
                buffer.appendBitsMSBFirst(UInt64(code), bitCount: bits)
                i += 1
                continue
            }

            // Find best mode for this character
            if let (targetMode, code) = findBestMode(for: char, from: currentMode, lookahead: Array(chars[i...])) {
                // Check if a shift code exists for this transition
                let shiftExists = AztecModeTransitions.shiftCodes[currentMode]?[targetMode] != nil

                // If no shift code exists, always latch; otherwise use cost-based heuristic
                let shouldLatch = shiftExists ? shouldLatchToMode(targetMode, from: currentMode, remaining: Array(chars[i...])) : true

                if shouldLatch {
                    appendModeSwitch(from: currentMode, to: targetMode, buffer: &buffer, latch: true)
                    currentMode = targetMode
                } else {
                    appendModeSwitch(from: currentMode, to: targetMode, buffer: &buffer, latch: false)
                }

                let bits = AztecModeTables.bitWidth(for: targetMode)
                buffer.appendBitsMSBFirst(UInt64(code), bitCount: bits)
                i += 1
                continue
            }

            // Fall back to byte mode
            let utf8 = Array(String(char).utf8)
            appendByteMode(bytes: utf8, from: currentMode, buffer: &buffer)
            i += 1
        }

        return buffer
    }

    /// Encodes raw bytes into a bit buffer using byte mode.
    ///
    /// - Parameter bytes: The bytes to encode.
    /// - Returns: A `BitBuffer` containing the encoded data bits.
    public static func encode(_ bytes: [UInt8]) -> BitBuffer {
        var buffer = BitBuffer()
        appendByteMode(bytes: bytes, from: .upper, buffer: &buffer)
        return buffer
    }

    /// Encodes raw data into a bit buffer using byte mode.
    ///
    /// - Parameter data: The data to encode.
    /// - Returns: A `BitBuffer` containing the encoded data bits.
    public static func encode(_ data: Data) -> BitBuffer {
        return encode(Array(data))
    }

    // MARK: - Private Helpers

    /// Returns the punct code for a two-character sequence, or nil.
    private static func punctTwoCharCode(_ twoChar: String) -> Int? {
        switch twoChar {
        case "\r\n": return 2
        case ". ": return 3
        case ", ": return 4
        case ": ": return 5
        default: return nil
        }
    }

    /// Finds the best mode to encode a character and returns the mode and code.
    private static func findBestMode(
        for char: Character,
        from currentMode: AztecMode,
        lookahead: [Character]
    ) -> (AztecMode, Int)? {
        // Priority order based on bit efficiency
        let modeOrder: [AztecMode] = [.digit, .upper, .lower, .punct, .mixed]

        for mode in modeOrder {
            if let code = AztecModeTables.code(for: char, in: mode) {
                return (mode, code)
            }
        }
        return nil
    }

    /// Latch costs in bits between modes (from ZXing LATCH_TABLE)
    private static let latchCostBits: [AztecMode: [AztecMode: Int]] = [
        .upper: [.upper: 0, .lower: 5, .digit: 5, .mixed: 5, .punct: 10],
        .lower: [.upper: 9, .lower: 0, .digit: 5, .mixed: 5, .punct: 10],
        .digit: [.upper: 4, .lower: 9, .digit: 0, .mixed: 9, .punct: 14],
        .mixed: [.upper: 5, .lower: 5, .digit: 10, .mixed: 0, .punct: 5],
        .punct: [.upper: 5, .lower: 10, .digit: 10, .mixed: 10, .punct: 0],
    ]

    /// Determines whether to latch (permanent switch) or shift (temporary) to a mode.
    private static func shouldLatchToMode(
        _ targetMode: AztecMode,
        from currentMode: AztecMode,
        remaining: [Character]
    ) -> Bool {
        // If only one character left, shift is fine
        guard remaining.count >= 2 else { return false }

        // Count how many consecutive characters work in the target mode
        var countInTarget = 0
        for char in remaining {
            if AztecModeTables.code(for: char, in: targetMode) != nil {
                countInTarget += 1
            } else {
                break
            }
        }

        // Latch if 2+ consecutive characters use the target mode
        if countInTarget >= 2 {
            return true
        }

        // For single character followed by a different mode:
        // Compare the cost of being in currentMode vs targetMode for encoding remaining chars
        let nextChar = remaining[1]

        // Find what mode the next character needs
        guard let (nextCharMode, _) = findBestMode(for: nextChar, from: currentMode, lookahead: Array(remaining.dropFirst())) else {
            // Next char needs byte mode, doesn't matter much
            return false
        }

        // Compare costs:
        // SHIFT path: shift (5 bits) + char + latch from currentMode to nextCharMode
        // LATCH path: latch (varies) + char + latch from targetMode to nextCharMode

        let shiftBits = AztecModeTables.bitWidth(for: currentMode) == 4 ? 4 : 5  // U/S or P/S
        let currentToNextCost = latchCostBits[currentMode]?[nextCharMode] ?? 10
        let targetToNextCost = latchCostBits[targetMode]?[nextCharMode] ?? 10
        let currentToTargetCost = latchCostBits[currentMode]?[targetMode] ?? 10

        // SHIFT total: shiftBits + targetModeBits + currentToNextCost
        // LATCH total: currentToTargetCost + targetModeBits + targetToNextCost
        let targetBits = AztecModeTables.bitWidth(for: targetMode)

        let shiftPathCost = shiftBits + targetBits + currentToNextCost
        let latchPathCost = currentToTargetCost + targetBits + targetToNextCost

        // Latch if it's cheaper or equal (prefer latch for stability)
        return latchPathCost <= shiftPathCost
    }

    /// Appends mode switch codes to the buffer.
    private static func appendModeSwitch(
        from source: AztecMode,
        to target: AztecMode,
        buffer: inout BitBuffer,
        latch: Bool
    ) {
        if source == target { return }

        if latch {
            // Latch (permanent switch)
            if let transition = AztecModeTransitions.latchCodes[source]?[target] {
                buffer.appendBitsMSBFirst(UInt64(transition.code), bitCount: transition.bits)
            } else {
                // Need intermediate mode
                switch (source, target) {
                case (.upper, .punct):
                    // U -> M/L -> P/L
                    buffer.appendBitsMSBFirst(29, bitCount: 5) // M/L
                    buffer.appendBitsMSBFirst(30, bitCount: 5) // P/L
                case (.lower, .upper):
                    // L -> D/L -> U/L
                    buffer.appendBitsMSBFirst(30, bitCount: 5) // D/L
                    buffer.appendBitsMSBFirst(14, bitCount: 4) // U/L
                case (.lower, .punct):
                    // L -> M/L -> P/L
                    buffer.appendBitsMSBFirst(29, bitCount: 5) // M/L
                    buffer.appendBitsMSBFirst(30, bitCount: 5) // P/L
                case (.mixed, .digit):
                    // M -> U/L -> D/L
                    buffer.appendBitsMSBFirst(29, bitCount: 5) // U/L
                    buffer.appendBitsMSBFirst(30, bitCount: 5) // D/L
                case (.punct, .lower):
                    // P -> U/L -> L/L
                    buffer.appendBitsMSBFirst(31, bitCount: 5) // U/L
                    buffer.appendBitsMSBFirst(28, bitCount: 5) // L/L
                case (.punct, .mixed):
                    // P -> U/L -> M/L
                    buffer.appendBitsMSBFirst(31, bitCount: 5) // U/L
                    buffer.appendBitsMSBFirst(29, bitCount: 5) // M/L
                case (.punct, .digit):
                    // P -> U/L -> D/L
                    buffer.appendBitsMSBFirst(31, bitCount: 5) // U/L
                    buffer.appendBitsMSBFirst(30, bitCount: 5) // D/L
                case (.digit, .lower):
                    // D -> U/L -> L/L
                    buffer.appendBitsMSBFirst(14, bitCount: 4) // U/L
                    buffer.appendBitsMSBFirst(28, bitCount: 5) // L/L
                case (.digit, .mixed):
                    // D -> U/L -> M/L
                    buffer.appendBitsMSBFirst(14, bitCount: 4) // U/L
                    buffer.appendBitsMSBFirst(29, bitCount: 5) // M/L
                default:
                    break
                }
            }
        } else {
            // Shift (temporary switch)
            if let transition = AztecModeTransitions.shiftCodes[source]?[target] {
                buffer.appendBitsMSBFirst(UInt64(transition.code), bitCount: transition.bits)
            }
        }
    }

    /// Appends byte mode encoding.
    private static func appendByteMode(bytes: [UInt8], from mode: AztecMode, buffer: inout BitBuffer) {
        guard !bytes.isEmpty else { return }

        // Switch to byte mode
        switch mode {
        case .punct:
            // P -> U/L -> B/S
            buffer.appendBitsMSBFirst(31, bitCount: 5) // U/L
            buffer.appendBitsMSBFirst(31, bitCount: 5) // B/S
        case .digit:
            // D -> U/L -> B/S (via upper)
            buffer.appendBitsMSBFirst(14, bitCount: 4) // U/L
            buffer.appendBitsMSBFirst(31, bitCount: 5) // B/S
        default:
            // U, L, M can use B/S directly
            buffer.appendBitsMSBFirst(31, bitCount: 5) // B/S
        }

        // Length encoding
        if bytes.count < 32 {
            // Short form: 5-bit length
            buffer.appendBitsMSBFirst(UInt64(bytes.count), bitCount: 5)
        } else {
            // Long form: 0 + 11-bit length
            buffer.appendBitsMSBFirst(0, bitCount: 5)
            buffer.appendBitsMSBFirst(UInt64(bytes.count - 31), bitCount: 11)
        }

        // Raw bytes (MSB-first per byte)
        for byte in bytes {
            buffer.appendBitsMSBFirst(UInt64(byte), bitCount: 8)
        }
    }
}
