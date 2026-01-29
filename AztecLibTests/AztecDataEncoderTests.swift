//
//  AztecDataEncoderTests.swift
//  AztecLibTests
//
//  Created by Toni Sucic on 13/10/2025.
//

import Foundation
import Testing
@testable import AztecLib

// MARK: - Data Encoder Tests

struct AztecDataEncoderTests {

    // MARK: - Upper Mode

    @Test
    func encodes_uppercase_letters_in_upper_mode() {
        let buffer = AztecDataEncoder.encode("ABC")
        // A=2, B=3, C=4 in upper mode (5 bits each)
        // Total: 15 bits
        #expect(buffer.bitCount == 15)
    }

    @Test
    func encodes_space_in_upper_mode() {
        let buffer = AztecDataEncoder.encode(" ")
        // Space = 1 in upper mode (5 bits)
        #expect(buffer.bitCount == 5)
    }

    @Test
    func encodes_hello_uppercase() {
        let buffer = AztecDataEncoder.encode("HELLO")
        // H=9, E=6, L=13, L=13, O=16 (all 5 bits)
        // Total: 25 bits
        #expect(buffer.bitCount == 25)
    }

    // MARK: - Lower Mode

    @Test
    func encodes_lowercase_with_mode_switch() {
        let buffer = AztecDataEncoder.encode("hello")
        // Needs L/L (28, 5 bits) then h=9, e=6, l=13, l=13, o=16 (5 bits each)
        // Total: 5 + 25 = 30 bits
        #expect(buffer.bitCount == 30)
    }

    @Test
    func encodes_mixed_case_with_switches() {
        let buffer = AztecDataEncoder.encode("Hello")
        // H=9 (5), then L/L (5), then e=6, l=13, l=13, o=16 (5 each)
        // Total: 5 + 5 + 20 = 30 bits
        #expect(buffer.bitCount == 30)
    }

    // MARK: - Digit Mode

    @Test
    func encodes_digits_efficiently() {
        let buffer = AztecDataEncoder.encode("12345")
        // D/L (30, 5 bits) then 1=6, 2=7, 3=8, 4=9, 5=10 (4 bits each)
        // Total: 5 + 20 = 25 bits
        #expect(buffer.bitCount == 25)
    }

    @Test
    func encodes_space_comma_period_in_digit_mode() {
        let buffer = AztecDataEncoder.encode("1 2,3.4")
        // D/L then digits with space (2), comma (3), period (4) in digit mode
        #expect(buffer.bitCount > 0)
    }

    // MARK: - Punct Mode

    @Test
    func encodes_punctuation_with_shift() {
        let buffer = AztecDataEncoder.encode("!")
        // P/S (0, 5 bits) then ! (6, 5 bits) = 10 bits
        #expect(buffer.bitCount == 10)
    }

    @Test
    func encodes_two_char_sequences_efficiently() {
        let buffer = AztecDataEncoder.encode(". ")
        // ". " is code 3 in punct mode, with P/S = 5 + 5 = 10 bits
        #expect(buffer.bitCount == 10)
    }

    // MARK: - Byte Mode

    @Test
    func encodes_bytes_directly() {
        let bytes: [UInt8] = [0x00, 0xFF, 0x42]
        let buffer = AztecDataEncoder.encode(bytes)
        // B/S (31, 5 bits) + length (3, 5 bits) + 3 bytes (24 bits)
        // Total: 5 + 5 + 24 = 34 bits
        #expect(buffer.bitCount == 34)
    }

    @Test
    func encodes_data_object() {
        let data = Data([0x01, 0x02, 0x03])
        let buffer = AztecDataEncoder.encode(data)
        // Same as bytes encoding
        #expect(buffer.bitCount == 34)
    }

    @Test
    func encodes_long_byte_sequence() {
        // More than 31 bytes uses long form
        let bytes = [UInt8](repeating: 0xAB, count: 40)
        let buffer = AztecDataEncoder.encode(bytes)
        // B/S (5) + 0 (5) + length-31 (11) + 40 bytes (320)
        // Total: 5 + 5 + 11 + 320 = 341 bits
        #expect(buffer.bitCount == 341)
    }

    // MARK: - Mode Switching

    @Test
    func efficient_mode_switching_for_mixed_content() {
        let buffer = AztecDataEncoder.encode("ABC123abc")
        // ABC in upper, then D/L, 123 in digit, then back through modes for abc
        #expect(buffer.bitCount > 0)
    }

    @Test
    func handles_special_characters() {
        let buffer = AztecDataEncoder.encode("@")
        // @ is in mixed mode
        #expect(buffer.bitCount > 0)
    }

    // MARK: - Edge Cases

    @Test
    func encodes_empty_string() {
        let buffer = AztecDataEncoder.encode("")
        #expect(buffer.bitCount == 0)
    }

    @Test
    func encodes_empty_bytes() {
        let buffer = AztecDataEncoder.encode([UInt8]())
        #expect(buffer.bitCount == 0)
    }

    @Test
    func encodes_single_character() {
        let buffer = AztecDataEncoder.encode("A")
        #expect(buffer.bitCount == 5) // A=2 in upper mode
    }

    @Test
    func handles_non_ascii_via_byte_mode() {
        let buffer = AztecDataEncoder.encode("🙂")
        // Non-ASCII falls back to byte mode
        #expect(buffer.bitCount > 0)
    }
}

// MARK: - Mode Table Tests

struct ModeTableTests {

    @Test
    func upper_mode_has_26_letters_plus_space() {
        #expect(AztecModeTables.upperCharToCode.count == 27)
    }

    @Test
    func lower_mode_has_26_letters_plus_space() {
        #expect(AztecModeTables.lowerCharToCode.count == 27)
    }

    @Test
    func digit_mode_has_correct_codes() {
        // ZXing-compatible digit mode codes: space=1, 0-9=2-11, comma=12, period=13
        #expect(AztecModeTables.digitCharToCode["0"] == 2)
        #expect(AztecModeTables.digitCharToCode["9"] == 11)
        #expect(AztecModeTables.digitCharToCode[" "] == 1)
        #expect(AztecModeTables.digitCharToCode[","] == 12)
        #expect(AztecModeTables.digitCharToCode["."] == 13)
    }

    @Test
    func punct_mode_has_common_punctuation() {
        #expect(AztecModeTables.punctCharToCode["!"] == 6)
        #expect(AztecModeTables.punctCharToCode["?"] == 26)
        #expect(AztecModeTables.punctCharToCode["."] == 19)
    }

    @Test
    func bit_widths_are_correct() {
        #expect(AztecModeTables.bitWidth(for: .upper) == 5)
        #expect(AztecModeTables.bitWidth(for: .lower) == 5)
        #expect(AztecModeTables.bitWidth(for: .mixed) == 5)
        #expect(AztecModeTables.bitWidth(for: .punct) == 5)
        #expect(AztecModeTables.bitWidth(for: .digit) == 4)
        #expect(AztecModeTables.bitWidth(for: .byte) == 8)
    }
}
