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
    /// Per ISO/IEC 24778 Table 5
    static let mixedCharToCode: [Character: Int] = {
        var map: [Character: Int] = [:]
        // Control characters (codes 1-14)
        map[Character(UnicodeScalar(1)!)] = 1   // ^A
        map[Character(UnicodeScalar(2)!)] = 2   // ^B
        map[Character(UnicodeScalar(3)!)] = 3   // ^C
        map[Character(UnicodeScalar(4)!)] = 4   // ^D
        map[Character(UnicodeScalar(5)!)] = 5   // ^E
        map[Character(UnicodeScalar(6)!)] = 6   // ^F
        map[Character(UnicodeScalar(7)!)] = 7   // ^G
        map[Character(UnicodeScalar(8)!)] = 8   // ^H (BS)
        map[Character(UnicodeScalar(9)!)] = 9   // ^I (HT)
        map[Character(UnicodeScalar(10)!)] = 10 // ^J (LF)
        map[Character(UnicodeScalar(11)!)] = 11 // ^K
        map[Character(UnicodeScalar(12)!)] = 12 // ^L (FF)
        map[Character(UnicodeScalar(13)!)] = 13 // ^M (CR)
        map[Character(UnicodeScalar(27)!)] = 14 // ^[ (ESC)
        map[Character(UnicodeScalar(28)!)] = 15 // ^\
        map[Character(UnicodeScalar(29)!)] = 16 // ^]
        map[Character(UnicodeScalar(30)!)] = 17 // ^^
        map[Character(UnicodeScalar(31)!)] = 18 // ^_
        // Printable characters
        map["@"] = 19
        map["\\"] = 20
        map["^"] = 21
        map["_"] = 22
        map["`"] = 23
        map["|"] = 24
        map["~"] = 25
        map[Character(UnicodeScalar(127)!)] = 26 // DEL
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
    /// Per ISO/IEC 24778 Table 7
    static let digitCharToCode: [Character: Int] = {
        var map: [Character: Int] = [:]
        // Codes 0-1 are control codes
        map[" "] = 2
        map[","] = 3
        map["."] = 4
        for i in 0...9 {
            map[Character("\(i)")] = i + 5
        }
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
                    buffer.appendLeastSignificantBits(UInt64(punctCode), bitCount: 5)
                    i += 2
                    continue
                }
            }

            // Check if current mode can encode this character
            if let code = AztecModeTables.code(for: char, in: currentMode) {
                let bits = AztecModeTables.bitWidth(for: currentMode)
                buffer.appendLeastSignificantBits(UInt64(code), bitCount: bits)
                i += 1
                continue
            }

            // Find best mode for this character
            if let (targetMode, code) = findBestMode(for: char, from: currentMode, lookahead: Array(chars[i...])) {
                let shouldLatch = shouldLatchToMode(targetMode, from: currentMode, remaining: Array(chars[i...]))

                if shouldLatch {
                    appendModeSwitch(from: currentMode, to: targetMode, buffer: &buffer, latch: true)
                    currentMode = targetMode
                } else {
                    appendModeSwitch(from: currentMode, to: targetMode, buffer: &buffer, latch: false)
                }

                let bits = AztecModeTables.bitWidth(for: targetMode)
                buffer.appendLeastSignificantBits(UInt64(code), bitCount: bits)
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

    /// Determines whether to latch (permanent switch) or shift (temporary) to a mode.
    private static func shouldLatchToMode(
        _ targetMode: AztecMode,
        from currentMode: AztecMode,
        remaining: [Character]
    ) -> Bool {
        // Use lookahead to decide: if multiple upcoming characters need the target mode, latch
        var countInTarget = 0
        let lookaheadLength = min(8, remaining.count)

        for i in 0..<lookaheadLength {
            if AztecModeTables.code(for: remaining[i], in: targetMode) != nil {
                countInTarget += 1
            } else if AztecModeTables.code(for: remaining[i], in: currentMode) != nil {
                // Can return to current mode
                break
            }
        }

        // Latch if we'll use the target mode for 2+ characters
        return countInTarget >= 2
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
                buffer.appendLeastSignificantBits(UInt64(transition.code), bitCount: transition.bits)
            } else {
                // Need intermediate mode
                switch (source, target) {
                case (.upper, .punct):
                    // U -> M/L -> P/L
                    buffer.appendLeastSignificantBits(29, bitCount: 5) // M/L
                    buffer.appendLeastSignificantBits(30, bitCount: 5) // P/L
                case (.lower, .upper):
                    // L -> D/L -> U/L
                    buffer.appendLeastSignificantBits(30, bitCount: 5) // D/L
                    buffer.appendLeastSignificantBits(14, bitCount: 4) // U/L
                case (.lower, .punct):
                    // L -> M/L -> P/L
                    buffer.appendLeastSignificantBits(29, bitCount: 5) // M/L
                    buffer.appendLeastSignificantBits(30, bitCount: 5) // P/L
                case (.mixed, .digit):
                    // M -> U/L -> D/L
                    buffer.appendLeastSignificantBits(29, bitCount: 5) // U/L
                    buffer.appendLeastSignificantBits(30, bitCount: 5) // D/L
                case (.punct, .lower):
                    // P -> U/L -> L/L
                    buffer.appendLeastSignificantBits(31, bitCount: 5) // U/L
                    buffer.appendLeastSignificantBits(28, bitCount: 5) // L/L
                case (.punct, .mixed):
                    // P -> U/L -> M/L
                    buffer.appendLeastSignificantBits(31, bitCount: 5) // U/L
                    buffer.appendLeastSignificantBits(29, bitCount: 5) // M/L
                case (.punct, .digit):
                    // P -> U/L -> D/L
                    buffer.appendLeastSignificantBits(31, bitCount: 5) // U/L
                    buffer.appendLeastSignificantBits(30, bitCount: 5) // D/L
                case (.digit, .lower):
                    // D -> U/L -> L/L
                    buffer.appendLeastSignificantBits(14, bitCount: 4) // U/L
                    buffer.appendLeastSignificantBits(28, bitCount: 5) // L/L
                case (.digit, .mixed):
                    // D -> U/L -> M/L
                    buffer.appendLeastSignificantBits(14, bitCount: 4) // U/L
                    buffer.appendLeastSignificantBits(29, bitCount: 5) // M/L
                default:
                    break
                }
            }
        } else {
            // Shift (temporary switch)
            if let transition = AztecModeTransitions.shiftCodes[source]?[target] {
                buffer.appendLeastSignificantBits(UInt64(transition.code), bitCount: transition.bits)
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
            buffer.appendLeastSignificantBits(31, bitCount: 5) // U/L
            buffer.appendLeastSignificantBits(31, bitCount: 5) // B/S
        case .digit:
            // D -> U/L -> B/S (via upper)
            buffer.appendLeastSignificantBits(14, bitCount: 4) // U/L
            buffer.appendLeastSignificantBits(31, bitCount: 5) // B/S
        default:
            // U, L, M can use B/S directly
            buffer.appendLeastSignificantBits(31, bitCount: 5) // B/S
        }

        // Length encoding
        if bytes.count < 32 {
            // Short form: 5-bit length
            buffer.appendLeastSignificantBits(UInt64(bytes.count), bitCount: 5)
        } else {
            // Long form: 0 + 11-bit length
            buffer.appendLeastSignificantBits(0, bitCount: 5)
            buffer.appendLeastSignificantBits(UInt64(bytes.count - 31), bitCount: 11)
        }

        // Raw bytes
        for byte in bytes {
            buffer.appendLeastSignificantBits(UInt64(byte), bitCount: 8)
        }
    }
}
