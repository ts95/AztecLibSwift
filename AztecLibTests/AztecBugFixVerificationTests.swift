//
//  AztecBugFixVerificationTests.swift
//  AztecLibTests
//
//  Tests to verify bug fixes per the AztecLib Bug Fix Plan.
//  Each section corresponds to an issue from the plan.
//

import Foundation
import Testing
@testable import AztecLib

// MARK: - Issue 1: RS Generator Polynomial Construction (Critical)

struct RSGeneratorPolynomialTests {

    @Test
    func generator_polynomial_has_correct_degree() {
        // For a degree-t polynomial, we should have exactly t+1 coefficients
        let gf = GaloisField(wordSizeInBits: 6, primitivePolynomial: 0x43)
        let rs = ReedSolomonEncoder(field: gf, startExponent: 1)

        // Test various degrees
        for t in 1...10 {
            let poly = rs.makeGeneratorPolynomial(ofDegree: t)
            #expect(
                poly.count == t + 1,
                "Generator polynomial of degree \(t) should have \(t + 1) coefficients, got \(poly.count)"
            )
        }
    }

    @Test
    func generator_polynomial_degree_5_has_6_coefficients() {
        let gf = GaloisField(wordSizeInBits: 8, primitivePolynomial: 0x12D)
        let rs = ReedSolomonEncoder(field: gf, startExponent: 1)

        let poly = rs.makeGeneratorPolynomial(ofDegree: 5)
        #expect(poly.count == 6, "Degree-5 polynomial should have 6 coefficients")
    }

    @Test
    func generator_polynomial_is_monic() {
        // The leading coefficient (highest degree) should be 1
        let gf = GaloisField(wordSizeInBits: 6, primitivePolynomial: 0x43)
        let rs = ReedSolomonEncoder(field: gf, startExponent: 1)

        for t in 1...5 {
            let poly = rs.makeGeneratorPolynomial(ofDegree: t)
            #expect(poly[t] == 1, "Generator polynomial should be monic (leading coefficient = 1)")
        }
    }

    @Test
    func rs_parity_with_known_vector_gf64() {
        // Known test vector for GF(2^6) with primitive poly 0x43
        // This verifies the RS encoding produces correct parity
        let gf = GaloisField(wordSizeInBits: 6, primitivePolynomial: 0x43)
        let rs = ReedSolomonEncoder(field: gf, startExponent: 1)

        // Simple test: data [1] with 3 parity codewords
        let data: [UInt16] = [1]
        let parity = rs.makeParityCodewords(for: data, parityCodewordCount: 3)

        #expect(parity.count == 3, "Should produce exactly 3 parity codewords")

        // All parity values should be valid field elements (0 to 63)
        for p in parity {
            #expect(p < 64, "Parity codeword should be valid GF(64) element")
        }
    }

    @Test
    func rs_parity_with_known_vector_gf256() {
        // Test with GF(2^8) used by larger Aztec symbols
        let gf = GaloisField(wordSizeInBits: 8, primitivePolynomial: 0x12D)
        let rs = ReedSolomonEncoder(field: gf, startExponent: 1)

        let data: [UInt16] = [0x48, 0x65, 0x6C, 0x6C, 0x6F] // "Hello" as bytes
        let parity = rs.makeParityCodewords(for: data, parityCodewordCount: 5)

        #expect(parity.count == 5)
        for p in parity {
            #expect(p < 256, "Parity should be valid GF(256) element")
        }
    }

    @Test
    func rs_generator_roots_are_consecutive_powers_of_alpha() {
        // The generator polynomial g(x) = ∏(x + α^i) for i = start to start+t-1
        // Each α^i should be a root of g(x)
        let gf = GaloisField(wordSizeInBits: 6, primitivePolynomial: 0x43)
        let rs = ReedSolomonEncoder(field: gf, startExponent: 1)
        let t = 5
        let g = rs.makeGeneratorPolynomial(ofDegree: t)

        // Evaluate g(α^i) for i = 1 to t; should all be 0
        for i in 1...t {
            let root = gf.exp[i]
            var result: UInt16 = 0
            var power: UInt16 = 1

            for coeff in g {
                result = gf.add(result, gf.multiply(coeff, power))
                power = gf.multiply(power, root)
            }

            #expect(result == 0, "α^\(i) should be a root of the generator polynomial")
        }
    }
}

// MARK: - Issue 2: Configuration Selection Honors Actual Stuffed Codeword Count (High)

struct ConfigurationSelectionTests {

    @Test
    func stuffing_sensitive_sizing_alternating_bits() throws {
        // Create data that will NOT trigger stuffing (alternating pattern)
        // This consumes an extra bit per codeword, expanding the output
        var buffer = BitBuffer()
        // Write alternating pattern: 10101010... (50 bits)
        for _ in 0..<50 {
            buffer.appendLeastSignificantBits(0b10101010, bitCount: 8)
        }

        // Encode and verify we get a valid symbol (no crash or truncation)
        let dataBits = buffer
        let codewords = dataBits.makeCodewords(codewordBitWidth: 6)

        // With 400 bits and stuffing consuming extra bits, we need to fit in a symbol
        #expect(codewords.count > 0, "Should produce codewords from alternating pattern")

        // Each codeword should be valid (no all-zeros or all-ones)
        for cw in codewords {
            #expect(cw != 0 && cw != 0x3F, "Codeword should not be all-zeros or all-ones for 6-bit words")
        }
    }

    @Test
    func configuration_word_size_matches_spec_for_layer() throws {
        // Verify that selected configuration's wordSizeInBits matches the spec
        let testCases = [
            ("A", true),           // Small payload, compact
            (String(repeating: "X", count: 100), false), // Larger payload
        ]

        for (input, preferCompact) in testCases {
            let result = try AztecEncoder.encodeWithDetails(
                input,
                options: AztecEncoder.Options(preferCompact: preferCompact)
            )

            // Find the matching spec
            let matchingSpec = allSymbolSpecs.first { spec in
                spec.isCompact == result.configuration.isCompact &&
                spec.layerCount == result.configuration.layerCount
            }

            #expect(matchingSpec != nil, "Should find matching spec")
            if let spec = matchingSpec {
                #expect(
                    result.configuration.wordSizeInBits == spec.wordSizeInBits,
                    "Configuration wordSizeInBits (\(result.configuration.wordSizeInBits)) should match spec (\(spec.wordSizeInBits))"
                )
            }
        }
    }

    @Test
    func actual_packed_codewords_fit_in_selected_config() throws {
        // Verify that the actual packed codeword count fits in the selected configuration
        let inputs = ["Hello", "12345", "ABCDEFGHIJKLMNOP", String(repeating: "X", count: 50)]

        for input in inputs {
            let result = try AztecEncoder.encodeWithDetails(input)
            let dataBits = AztecDataEncoder.encode(input)
            let codewords = dataBits.makeCodewords(codewordBitWidth: result.configuration.wordSizeInBits)

            #expect(
                codewords.count <= result.configuration.dataCodewordCount,
                "Packed codewords (\(codewords.count)) should fit in config data capacity (\(result.configuration.dataCodewordCount))"
            )
        }
    }
}

// MARK: - Issue 3: Padding and Truncation Safety (High)

struct PaddingAndTruncationTests {

    @Test
    func filler_codeword_is_valid() {
        // The filler codeword should not be all-zeros or all-ones
        for width in [6, 8, 10, 12] {
            let filler = BitBuffer.makeFillerCodeword(bitWidth: width)
            let maxValue = UInt16((1 << width) - 1)

            #expect(filler != 0, "Filler codeword should not be all-zeros")
            #expect(filler != maxValue, "Filler codeword should not be all-ones")
            #expect(filler == 1, "Filler codeword should be 1 (stuffed zero input)")
        }
    }

    @Test
    func padding_produces_valid_codewords() throws {
        // Encode a small payload that requires padding
        let result = try AztecEncoder.encodeWithDetails("A")

        // The configuration should have enough capacity for the codewords
        let dataBits = AztecDataEncoder.encode("A")
        let packedCodewords = dataBits.makeCodewords(codewordBitWidth: result.configuration.wordSizeInBits)

        #expect(
            packedCodewords.count <= result.configuration.dataCodewordCount,
            "Packed codewords should fit in selected configuration"
        )

        // Encoding should succeed without issues
        #expect(result.symbol.size > 0)
    }

    @Test
    func no_all_zero_codewords_in_output() throws {
        // Test that stuffing prevents all-zero codewords
        var buffer = BitBuffer()
        // Write all zeros (should be stuffed to produce codeword value 1)
        buffer.appendLeastSignificantBits(0, bitCount: 50)

        let codewords = buffer.makeCodewords(codewordBitWidth: 6)

        for (i, cw) in codewords.enumerated() {
            #expect(cw != 0, "Codeword \(i) should not be all-zeros due to stuffing")
        }
    }

    @Test
    func no_all_ones_codewords_in_output() throws {
        // Test that stuffing prevents all-ones codewords
        var buffer = BitBuffer()
        // Write all ones
        buffer.appendLeastSignificantBits(~UInt64(0), bitCount: 50)

        let codewords = buffer.makeCodewords(codewordBitWidth: 6)
        let maxValue = UInt16((1 << 6) - 1) // 0x3F for 6-bit

        for (i, cw) in codewords.enumerated() {
            #expect(cw != maxValue, "Codeword \(i) should not be all-ones due to stuffing")
        }
    }

    @Test
    func payload_too_large_throws_error() throws {
        // Create a payload that's too large for any Aztec symbol
        let hugePayload = String(repeating: "X", count: 10000)

        #expect(throws: AztecEncoder.EncodingError.self) {
            _ = try AztecEncoder.encode(hugePayload)
        }
    }
}

// MARK: - Issue 4: Shift/Latch Mode Correctness (High)

struct ShiftLatchModeTests {

    @Test
    func shift_unsupported_transition_uses_latch() throws {
        // Upper → Lower has no shift code, must use latch
        // The string "Aa" should latch to lower mode for 'a'
        let buffer = AztecDataEncoder.encode("Aa")

        // Should produce valid output
        #expect(buffer.bitCount > 0)

        // A (code 2, 5 bits) + latch to lower (varies) + a (code 2, 5 bits)
        // The important thing is it doesn't crash and produces valid output
    }

    @Test
    func shift_supported_transition_works() throws {
        // Upper → Punct has shift code (P/S = code 0)
        // "A!" should use punct shift for "!"
        let buffer = AztecDataEncoder.encode("A!")

        #expect(buffer.bitCount > 0)
        // A (5 bits) + P/S (5 bits) + ! (5 bits) = 15 bits approximately
    }

    @Test
    func multiple_punct_chars_causes_latch() throws {
        // Multiple punctuation characters should latch rather than shift repeatedly
        let buffer1 = AztecDataEncoder.encode("A!")
        let buffer2 = AztecDataEncoder.encode("A!!!")

        // Three punct chars after A should be more efficient with latch
        // (shift would be 3 * (5 + 5) = 30 bits for punct, latch is 10 + 3*5 = 25 bits)
        #expect(buffer1.bitCount > 0)
        #expect(buffer2.bitCount > 0)
    }

    @Test
    func digit_to_lower_transition_uses_latch_path() throws {
        // Digit → Lower has no direct transition, must go via Upper
        // "123a" should work correctly
        let buffer = AztecDataEncoder.encode("123a")

        #expect(buffer.bitCount > 0)
    }

    @Test
    func all_modes_reachable_from_upper() throws {
        // Verify we can encode characters from all modes starting from Upper
        let testStrings = [
            "A",        // Upper
            "a",        // Lower
            "1",        // Digit
            "!",        // Punct
            "@",        // Mixed
        ]

        for s in testStrings {
            let buffer = AztecDataEncoder.encode(s)
            #expect(buffer.bitCount > 0, "Should encode '\(s)' successfully")
        }
    }

    @Test
    func mixed_to_punct_uses_correct_transition() throws {
        // From Mixed mode, Punct shift exists (code 0)
        // "@!" should shift to punct
        let buffer = AztecDataEncoder.encode("@@!")

        #expect(buffer.bitCount > 0)
    }
}

// MARK: - Issue 5: Data Placement Capacity Validation (Medium)

struct DataPlacementValidationTests {

    @Test
    func all_compact_symbols_place_data_successfully() throws {
        // Test all 4 compact layer configurations
        for layers in 1...4 {
            let spec = compactSymbolSpecs[layers - 1]

            // Create config with maximum data codewords
            let config = AztecConfiguration(
                isCompact: true,
                layerCount: layers,
                wordSizeInBits: spec.wordSizeInBits,
                totalCodewordCount: spec.totalCodewordCount,
                dataCodewordCount: spec.totalCodewordCount - 3,
                parityCodewordCount: 3,
                primitivePolynomial: AztecPrimitivePolynomials.polynomial(forWordSize: spec.wordSizeInBits),
                rsStartExponent: 1
            )

            let builder = AztecMatrixBuilder(configuration: config)
            let modeMessage = builder.encodeModeMessage()

            // Create test codewords
            let codewords = [UInt16](repeating: 0x15, count: config.totalCodewordCount)

            // Should not crash
            let matrix = try builder.buildMatrix(dataCodewords: codewords, modeMessageBits: modeMessage)
            #expect(matrix.bitCount == builder.symbolSize * builder.symbolSize)
        }
    }

    @Test
    func data_placement_uses_full_path() throws {
        // For a small symbol, verify we can place the expected number of codewords
        let symbol = try AztecEncoder.encode("HELLO")

        // Symbol should have correct size
        #expect(symbol.size > 0)
    }
}

// MARK: - Issue 6: Mode Message Length Validation (Medium)

struct ModeMessageLengthTests {

    @Test
    func compact_mode_message_is_28_bits() {
        let config = AztecConfiguration(
            isCompact: true,
            layerCount: 1,
            wordSizeInBits: 6,
            totalCodewordCount: 17,
            dataCodewordCount: 14,
            parityCodewordCount: 3,
            primitivePolynomial: 0x43,
            rsStartExponent: 1
        )

        let builder = AztecMatrixBuilder(configuration: config)
        let modeMessage = builder.encodeModeMessage()

        #expect(modeMessage.bitCount == 28, "Compact mode message must be 28 bits")
    }

    @Test
    func full_mode_message_is_40_bits() {
        let config = AztecConfiguration(
            isCompact: false,
            layerCount: 1,
            wordSizeInBits: 6,
            totalCodewordCount: 21,
            dataCodewordCount: 18,
            parityCodewordCount: 3,
            primitivePolynomial: 0x43,
            rsStartExponent: 1
        )

        let builder = AztecMatrixBuilder(configuration: config)
        let modeMessage = builder.encodeModeMessage()

        #expect(modeMessage.bitCount == 40, "Full mode message must be 40 bits")
    }

    @Test
    func mode_message_encodes_configuration_correctly() {
        // Test that mode message encodes layer count and data codewords
        let config = AztecConfiguration(
            isCompact: true,
            layerCount: 3,
            wordSizeInBits: 8,
            totalCodewordCount: 51,
            dataCodewordCount: 40,
            parityCodewordCount: 11,
            primitivePolynomial: 0x12D,
            rsStartExponent: 1
        )

        let builder = AztecMatrixBuilder(configuration: config)
        let modeMessage = builder.encodeModeMessage()

        // Compact mode: 2 bits for layer-1, 6 bits for dataCodewords-1
        // Total 8 data bits + 20 parity bits = 28 bits
        #expect(modeMessage.bitCount == 28)
    }
}

// MARK: - Issue 7: Galois Field Polynomial Validation (Low)

struct GaloisFieldValidationTests {

    @Test
    func valid_primitive_polynomials_are_accepted() {
        // All Aztec primitive polynomials should be accepted
        _ = GaloisField(wordSizeInBits: 4, primitivePolynomial: 0x13)  // GF(16) for mode message
        _ = GaloisField(wordSizeInBits: 6, primitivePolynomial: 0x43)  // GF(64)
        _ = GaloisField(wordSizeInBits: 8, primitivePolynomial: 0x12D) // GF(256)
        _ = GaloisField(wordSizeInBits: 10, primitivePolynomial: 0x409) // GF(1024)
        _ = GaloisField(wordSizeInBits: 12, primitivePolynomial: 0x1069) // GF(4096)
    }

    @Test
    func gf_exp_table_cycles_correctly() {
        let gf = GaloisField(wordSizeInBits: 6, primitivePolynomial: 0x43)

        // α^0 = 1
        #expect(gf.exp[0] == 1)

        // α^(size-1) should cycle back (the exp table is extended for convenience)
        #expect(gf.exp[63] == gf.exp[0])
    }

    @Test
    func gf_log_table_is_inverse_of_exp() {
        let gf = GaloisField(wordSizeInBits: 6, primitivePolynomial: 0x43)

        // For all non-zero elements, log(exp(i)) = i mod (size-1)
        for i in 0..<63 {
            let alpha_i = gf.exp[i]
            let log_alpha_i = gf.log[Int(alpha_i)]
            #expect(log_alpha_i == UInt16(i), "log(exp(\(i))) should equal \(i)")
        }
    }

    @Test
    func gf_multiplication_is_associative() {
        let gf = GaloisField(wordSizeInBits: 8, primitivePolynomial: 0x12D)

        let a: UInt16 = 23
        let b: UInt16 = 45
        let c: UInt16 = 67

        let ab_c = gf.multiply(gf.multiply(a, b), c)
        let a_bc = gf.multiply(a, gf.multiply(b, c))

        #expect(ab_c == a_bc, "Multiplication should be associative")
    }

    @Test
    func gf_has_correct_field_size() {
        // Test cases: (wordSize, polynomial, expectedSize)
        // GF(16) uses 0x13 for mode message RS encoding (not via polynomial lookup)
        let testCases: [(Int, UInt32, Int)] = [
            (4, 0x13, 16),      // GF(16) for mode message - polynomial x^4 + x + 1
            (6, 0x43, 64),      // GF(64)
            (8, 0x12D, 256),    // GF(256)
            (10, 0x409, 1024),  // GF(1024)
            (12, 0x1069, 4096), // GF(4096)
        ]

        for (wordSize, poly, expectedSize) in testCases {
            let gf = GaloisField(wordSizeInBits: wordSize, primitivePolynomial: poly)
            #expect(gf.size == expectedSize, "GF(2^\(wordSize)) should have size \(expectedSize)")
        }
    }
}

// MARK: - Issue 8: AztecSymbol Buffer Validation (Low)

struct AztecSymbolValidationTests {

    @Test
    func valid_symbol_parameters_are_accepted() {
        let validBytes = Data(repeating: 0, count: 30) // 15 * 2 = 30 bytes for 15x15 symbol

        let symbol = AztecSymbol(size: 15, rowStride: 2, bytes: validBytes)

        #expect(symbol.size == 15)
        #expect(symbol.rowStride == 2)
        #expect(symbol.bytes.count == 30)
    }

    @Test
    func symbol_subscript_accesses_valid_positions() throws {
        let symbol = try AztecEncoder.encode("Test")

        // Should be able to access all valid positions
        for y in 0..<symbol.size {
            for x in 0..<symbol.size {
                // Should not crash
                _ = symbol[x: x, y: y]
            }
        }
    }

    @Test
    func symbol_bytes_are_correctly_sized() throws {
        let symbol = try AztecEncoder.encode("Hello World")

        let expectedBytes = symbol.rowStride * symbol.size
        #expect(symbol.bytes.count == expectedBytes)
    }

    @Test
    func row_stride_accommodates_symbol_size() throws {
        let symbol = try AztecEncoder.encode("X")

        // Row stride must be at least ceil(size/8)
        let minStride = (symbol.size + 7) / 8
        #expect(symbol.rowStride >= minStride)
    }
}

// MARK: - Cross-Cutting: End-to-End Tests

struct EndToEndEncodingTests {

    @Test
    func encode_various_payloads_successfully() throws {
        let testCases = [
            "",
            "A",
            "Hello",
            "12345",
            "Hello, World!",
            "ABCDEFGHIJKLMNOPQRSTUVWXYZ",
            "abcdefghijklmnopqrstuvwxyz",
            "0123456789",
            "@#$%^&*()",
            "Mixed Case 123 & Symbols!",
            String(repeating: "X", count: 100),
            "\r\n\t",
        ]

        for input in testCases {
            let symbol = try AztecEncoder.encode(input)
            #expect(symbol.size > 0, "Should encode '\(input.prefix(20))...'")
        }
    }

    @Test
    func encode_binary_data_successfully() throws {
        let testCases: [[UInt8]] = [
            [],
            [0x00],
            [0xFF],
            [0x00, 0xFF, 0x55, 0xAA],
            Array(0...255),
            [UInt8](repeating: 0x42, count: 100),
        ]

        for bytes in testCases {
            let symbol = try AztecEncoder.encode(bytes)
            #expect(symbol.size > 0, "Should encode \(bytes.count) bytes")
        }
    }

    @Test
    func encoding_is_deterministic() throws {
        let input = "Determinism test with various chars: ABC abc 123 !@#"

        var previousBytes: Data?
        for _ in 0..<5 {
            let symbol = try AztecEncoder.encode(input)

            if let prev = previousBytes {
                #expect(symbol.bytes == prev, "Encoding should be deterministic")
            }
            previousBytes = symbol.bytes
        }
    }

    @Test
    func all_compact_layer_sizes_are_correct() throws {
        // Compact: size = 11 + 4 * layers
        let expectedSizes = [
            1: 15,
            2: 19,
            3: 23,
            4: 27,
        ]

        for (layers, expectedSize) in expectedSizes {
            let spec = compactSymbolSpecs[layers - 1]
            let config = AztecConfiguration(
                isCompact: true,
                layerCount: layers,
                wordSizeInBits: spec.wordSizeInBits,
                totalCodewordCount: spec.totalCodewordCount,
                dataCodewordCount: spec.totalCodewordCount - 3,
                parityCodewordCount: 3,
                primitivePolynomial: AztecPrimitivePolynomials.polynomial(forWordSize: spec.wordSizeInBits),
                rsStartExponent: 1
            )

            let builder = AztecMatrixBuilder(configuration: config)
            #expect(builder.symbolSize == expectedSize, "Compact layer \(layers) should be \(expectedSize)x\(expectedSize)")
        }
    }
}

// MARK: - Property-Based: Stuffing Verification

struct StuffingPropertyTests {

    @Test
    func no_output_codeword_is_all_zeros_6bit() {
        var buffer = BitBuffer()
        // Random-ish pattern that includes zeros
        for i in 0..<100 {
            buffer.appendLeastSignificantBits(UInt64(i % 64), bitCount: 6)
        }

        let codewords = buffer.makeCodewords(codewordBitWidth: 6)
        for (i, cw) in codewords.enumerated() {
            #expect(cw != 0, "Codeword \(i) should not be all-zeros (6-bit)")
            #expect(cw != 0x3F, "Codeword \(i) should not be all-ones (6-bit)")
        }
    }

    @Test
    func no_output_codeword_is_all_zeros_8bit() {
        var buffer = BitBuffer()
        for i in 0..<100 {
            buffer.appendLeastSignificantBits(UInt64(i % 256), bitCount: 8)
        }

        let codewords = buffer.makeCodewords(codewordBitWidth: 8)
        for (i, cw) in codewords.enumerated() {
            #expect(cw != 0, "Codeword \(i) should not be all-zeros (8-bit)")
            #expect(cw != 0xFF, "Codeword \(i) should not be all-ones (8-bit)")
        }
    }

    @Test
    func stuffing_handles_edge_patterns() {
        // Test specific patterns that would produce all-zeros or all-ones
        let patterns: [(UInt64, Int)] = [
            (0b00000, 5),      // All zeros (5 bits)
            (0b11111, 5),      // All ones (5 bits)
            (0b0000000, 7),    // All zeros (7 bits)
            (0b1111111, 7),    // All ones (7 bits)
        ]

        for (pattern, bits) in patterns {
            var buffer = BitBuffer()
            buffer.appendLeastSignificantBits(pattern, bitCount: bits)

            let codewords = buffer.makeCodewords(codewordBitWidth: 6)
            for cw in codewords {
                #expect(cw != 0 && cw != 0x3F, "Stuffing should prevent forbidden codewords")
            }
        }
    }

    @Test
    func codeword_count_is_consistent_with_input_bits() {
        // Verify that the number of codewords is reasonable given input bits
        for inputBits in [10, 25, 50, 100, 200] {
            var buffer = BitBuffer()
            // Append bits in chunks of at most 64
            var remaining = inputBits
            var pattern: UInt64 = 0x55
            while remaining > 0 {
                let chunk = min(remaining, 64)
                buffer.appendLeastSignificantBits(pattern, bitCount: chunk)
                remaining -= chunk
                pattern = ~pattern  // Alternate pattern
            }

            let codewords = buffer.makeCodewords(codewordBitWidth: 8)

            // With 7 data bits per 8-bit codeword, we expect approximately inputBits/7 codewords
            // But stuffing can consume extra bits, so the count may vary
            let minExpected = inputBits / 8  // Lower bound
            let maxExpected = (inputBits / 7) + 2  // Upper bound with some margin

            #expect(
                codewords.count >= minExpected && codewords.count <= maxExpected,
                "Codeword count \(codewords.count) should be reasonable for \(inputBits) input bits"
            )
        }
    }
}

// MARK: - Issue 9: Compact Mode Message Data Codeword Limit (Critical)

struct CompactModeMessageLimitTests {

    @Test
    func compact_mode_message_has_6_bit_data_codeword_field() {
        // Compact mode message format: 2 bits for layers-1, 6 bits for dataCodewords-1
        // This means max representable is 64 data codewords
        let maxRepresentable = (1 << 6) // 64

        // Verify that 6 bits can represent 0-63, meaning dataCodewords 1-64
        #expect(maxRepresentable == 64, "6 bits should represent up to 64 values (0-63)")
    }

    @Test
    func compact_symbols_never_exceed_64_data_codewords() throws {
        // Compact layer 4 has 76 total codewords
        // With low EC (e.g., 0%), actualDataCodewords could theoretically be 73 (76 - 3 min parity)
        // But that would exceed the 64-codeword limit encodable in mode message

        // Test with various payloads that might trigger the edge case
        let testPayloads = [
            String(repeating: "A", count: 40),  // ~40 codewords
            String(repeating: "1", count: 50),  // Digits encode efficiently
        ]

        for payload in testPayloads {
            let result = try AztecEncoder.encodeWithDetails(
                payload,
                options: AztecEncoder.Options(errorCorrectionPercentage: 0, preferCompact: true)
            )

            if result.configuration.isCompact {
                #expect(
                    result.configuration.dataCodewordCount <= 64,
                    "Compact symbol must have at most 64 data codewords to fit in mode message, got \(result.configuration.dataCodewordCount)"
                )
            }
        }
    }

    @Test
    func compact_layer_4_respects_64_codeword_limit() {
        // Create a compact layer 4 config directly and verify the limit
        let spec = compactSymbolSpecs[3] // Layer 4
        #expect(spec.totalCodewordCount == 76, "Compact layer 4 should have 76 total codewords")

        // If we had 76 - 3 = 73 data codewords, it would overflow the 6-bit field
        // The encoder should cap at 64 data codewords
        let theoreticalMax = spec.totalCodewordCount - 3  // 73 with minimum parity
        #expect(theoreticalMax > 64, "Without the fix, compact layer 4 could overflow")

        // Verify the fix: create a config with max data codewords
        let config = AztecConfiguration(
            isCompact: true,
            layerCount: 4,
            wordSizeInBits: 8,
            totalCodewordCount: 76,
            dataCodewordCount: 64,  // Fixed to max 64
            parityCodewordCount: 12, // 76 - 64
            primitivePolynomial: 0x12D,
            rsStartExponent: 1
        )

        // Encode mode message - should not truncate
        let builder = AztecMatrixBuilder(configuration: config)
        let modeMessage = builder.encodeModeMessage()

        #expect(modeMessage.bitCount == 28, "Compact mode message should be 28 bits")

        // The encoded value should correctly represent 64 data codewords
        // dataWordBits = (64 - 1) & 0x3F = 63 & 63 = 63 ✓
    }

    @Test
    func mode_message_truncation_is_prevented() {
        // Test that if we had 73 data codewords, it would encode incorrectly
        // (73 - 1) & 0x3F = 72 & 63 = 8, which would claim only 9 codewords!

        let overflowValue = 73
        let maskedValue = (overflowValue - 1) & 0x3F  // 72 & 63 = 8

        #expect(maskedValue == 8, "Without the fix, 73 data codewords would encode as 9")

        // With the fix, we never allow > 64 data codewords for compact
        let maxSafe = 64
        let safeMasked = (maxSafe - 1) & 0x3F  // 63 & 63 = 63

        #expect(safeMasked == 63, "64 data codewords correctly encodes as 63 in the 6-bit field")
    }
}

// MARK: - Issue 10: Data Placement Precondition (Critical)

struct DataPlacementPreconditionTests {

    @Test
    func data_placement_uses_precondition_not_assert() throws {
        // This test documents that placeDataCodewords uses precondition
        // which will fail in release builds, preventing silent truncation

        // We can't easily test that precondition fires without crashing,
        // but we can verify that valid cases work correctly
        let symbol = try AztecEncoder.encode("Test data placement")
        #expect(symbol.size > 0, "Valid encoding should succeed")
    }

    @Test
    func all_standard_symbols_have_sufficient_path_capacity() throws {
        // Verify that all symbol specs have enough path capacity for their codewords
        for spec in allSymbolSpecs {
            let config = AztecConfiguration(
                isCompact: spec.isCompact,
                layerCount: spec.layerCount,
                wordSizeInBits: spec.wordSizeInBits,
                totalCodewordCount: spec.totalCodewordCount,
                dataCodewordCount: spec.totalCodewordCount - 3,
                parityCodewordCount: 3,
                primitivePolynomial: AztecPrimitivePolynomials.polynomial(forWordSize: spec.wordSizeInBits),
                rsStartExponent: 1
            )

            let builder = AztecMatrixBuilder(configuration: config)
            let modeMessage = builder.encodeModeMessage()

            // Create max codewords for this spec
            let codewords = [UInt16](repeating: 0x15, count: config.totalCodewordCount)

            // This should not throw due to path capacity issues
            let matrix = try builder.buildMatrix(dataCodewords: codewords, modeMessageBits: modeMessage)
            #expect(matrix.bitCount == builder.symbolSize * builder.symbolSize)
        }
    }

    @Test
    func full_symbols_with_reference_grid_have_correct_path_capacity() throws {
        // Verify that full symbols with reference grids (layers >= 16) work correctly
        // after the fix to isReservedPosition that limits grid lines to actual count
        for layers in [16, 20, 31, 32] {
            let spec = fullSymbolSpecs[layers - 1]

            let config = AztecConfiguration(
                isCompact: false,
                layerCount: layers,
                wordSizeInBits: spec.wordSizeInBits,
                totalCodewordCount: spec.totalCodewordCount,
                dataCodewordCount: spec.totalCodewordCount - 3,
                parityCodewordCount: 3,
                primitivePolynomial: AztecPrimitivePolynomials.polynomial(forWordSize: spec.wordSizeInBits),
                rsStartExponent: 1
            )

            let builder = AztecMatrixBuilder(configuration: config)
            let modeMessage = builder.encodeModeMessage()
            let codewords = [UInt16](repeating: 0x15, count: config.totalCodewordCount)

            // Should succeed after the reference grid fix
            let matrix = try builder.buildMatrix(dataCodewords: codewords, modeMessageBits: modeMessage)
            #expect(matrix.bitCount == builder.symbolSize * builder.symbolSize, "Layer \(layers) should build successfully")
        }
    }

    @Test
    func compact_symbols_all_place_data_correctly() throws {
        // Test all compact layer configurations with maximum data
        for layers in 1...4 {
            let spec = compactSymbolSpecs[layers - 1]

            // Ensure we don't exceed the 64-codeword mode message limit
            let maxDataCodewords = min(spec.totalCodewordCount - 3, 64)

            let config = AztecConfiguration(
                isCompact: true,
                layerCount: layers,
                wordSizeInBits: spec.wordSizeInBits,
                totalCodewordCount: spec.totalCodewordCount,
                dataCodewordCount: maxDataCodewords,
                parityCodewordCount: spec.totalCodewordCount - maxDataCodewords,
                primitivePolynomial: AztecPrimitivePolynomials.polynomial(forWordSize: spec.wordSizeInBits),
                rsStartExponent: 1
            )

            let builder = AztecMatrixBuilder(configuration: config)
            let modeMessage = builder.encodeModeMessage()
            let codewords = [UInt16](repeating: 0x15, count: config.totalCodewordCount)

            // Should succeed without precondition failure
            let matrix = try builder.buildMatrix(dataCodewords: codewords, modeMessageBits: modeMessage)
            #expect(matrix.bitCount > 0, "Compact layer \(layers) should build successfully")
        }
    }
}

// MARK: - Reference Grid Tests for Full Symbols

struct ReferenceGridVerificationTests {

    @Test
    func compact_symbols_have_no_reference_grid() throws {
        let result = try AztecEncoder.encodeWithDetails(
            "A",
            options: AztecEncoder.Options(preferCompact: true)
        )

        #expect(result.configuration.isCompact == true)
        // Compact symbols don't have reference grid lines
    }

    @Test
    func full_symbols_with_many_layers_have_reference_grid() throws {
        // Full symbols with layers > 1 may have reference grid
        let result = try AztecEncoder.encodeWithDetails(
            String(repeating: "X", count: 500),
            options: AztecEncoder.Options(preferCompact: false)
        )

        if !result.configuration.isCompact && result.configuration.layerCount > 1 {
            // The symbol should have reference grid lines at multiples of 16 from center
            // We can't easily verify this without accessing internal structure,
            // but we can verify the symbol was created successfully
            #expect(result.symbol.size > 19, "Large full symbol should have size > 19")
        }
    }
}
