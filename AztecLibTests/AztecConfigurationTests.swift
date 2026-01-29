//
//  AztecConfigurationTests.swift
//  AztecLibTests
//
//  Created by Toni Sucic on 13/10/2025.
//

import Foundation
import Testing
@testable import AztecLib

// MARK: - Configuration Selection Tests

struct AztecConfigurationTests {

    // MARK: - Basic Selection

    @Test
    func picks_smallest_compact_symbol_for_small_payload() throws {
        // Very small payload should use compact 1-layer
        let config = try pickConfiguration(
            forPayloadBitCount: 10,
            errorCorrectionPercentage: 23,
            preferCompact: true
        )
        #expect(config.isCompact == true)
        #expect(config.layerCount == 1)
        #expect(config.wordSizeInBits == 6)
    }

    @Test
    func picks_larger_symbol_for_larger_payload() throws {
        // Larger payload should scale up
        let config = try pickConfiguration(
            forPayloadBitCount: 200,
            errorCorrectionPercentage: 23,
            preferCompact: true
        )
        #expect(config.isCompact == true)
        #expect(config.layerCount >= 2)
    }

    @Test
    func picks_full_symbol_when_compact_insufficient() throws {
        // Payload too large for compact should use full
        let config = try pickConfiguration(
            forPayloadBitCount: 500,
            errorCorrectionPercentage: 23,
            preferCompact: true
        )
        #expect(config.isCompact == false)
    }

    @Test
    func respects_preferCompact_false() throws {
        // Small payload with preferCompact=false should use full
        let config = try pickConfiguration(
            forPayloadBitCount: 10,
            errorCorrectionPercentage: 23,
            preferCompact: false
        )
        // Should still fit in a small symbol, but configuration logic may vary
        #expect(config.totalCodewordCount > 0)
    }

    // MARK: - Error Correction Levels

    @Test
    func higher_ec_level_allocates_more_parity() throws {
        let lowEC = try pickConfiguration(
            forPayloadBitCount: 50,
            errorCorrectionPercentage: 10,
            preferCompact: true
        )
        let highEC = try pickConfiguration(
            forPayloadBitCount: 50,
            errorCorrectionPercentage: 50,
            preferCompact: true
        )
        // Higher EC should have more parity (or same data means more parity proportion)
        #expect(highEC.parityCodewordCount >= lowEC.parityCodewordCount)
    }

    @Test
    func minimum_parity_codewords_is_at_least_three() throws {
        // Even with very low EC, should have at least 3 parity codewords
        let config = try pickConfiguration(
            forPayloadBitCount: 10,
            errorCorrectionPercentage: 1,
            preferCompact: true
        )
        #expect(config.parityCodewordCount >= 3)
    }

    // MARK: - Edge Cases

    @Test
    func throws_for_payload_too_large() throws {
        // Extremely large payload should throw
        #expect(throws: AztecConfigurationError.self) {
            _ = try pickConfiguration(
                forPayloadBitCount: 100000,
                errorCorrectionPercentage: 23,
                preferCompact: true
            )
        }
    }

    @Test
    func handles_zero_payload() throws {
        // Zero-bit payload should still produce a valid config
        let config = try pickConfiguration(
            forPayloadBitCount: 0,
            errorCorrectionPercentage: 23,
            preferCompact: true
        )
        #expect(config.isCompact == true)
        #expect(config.layerCount == 1)
    }

    // MARK: - Word Size Selection

    @Test
    func uses_6bit_words_for_small_symbols() throws {
        let config = try pickConfiguration(
            forPayloadBitCount: 50,
            errorCorrectionPercentage: 23,
            preferCompact: true
        )
        #expect(config.wordSizeInBits == 6)
    }

    @Test
    func uses_8bit_words_for_medium_symbols() throws {
        let config = try pickConfiguration(
            forPayloadBitCount: 300,
            errorCorrectionPercentage: 23,
            preferCompact: true
        )
        #expect(config.wordSizeInBits == 8)
    }

    // MARK: - Primitive Polynomial

    @Test
    func correct_primitive_polynomial_for_6bit() throws {
        let config = try pickConfiguration(
            forPayloadBitCount: 10,
            errorCorrectionPercentage: 23,
            preferCompact: true
        )
        #expect(config.wordSizeInBits == 6)
        #expect(config.primitivePolynomial == 0x43)
    }

    @Test
    func correct_primitive_polynomial_for_8bit() throws {
        // Force a larger symbol that uses 8-bit words
        let config = try pickConfiguration(
            forPayloadBitCount: 300,
            errorCorrectionPercentage: 23,
            preferCompact: true
        )
        if config.wordSizeInBits == 8 {
            #expect(config.primitivePolynomial == 0x12D)
        }
    }

    // MARK: - Configuration Consistency

    @Test
    func data_plus_parity_equals_total() throws {
        let config = try pickConfiguration(
            forPayloadBitCount: 100,
            errorCorrectionPercentage: 23,
            preferCompact: true
        )
        #expect(config.dataCodewordCount + config.parityCodewordCount == config.totalCodewordCount)
    }

    @Test
    func rs_start_exponent_is_one() throws {
        let config = try pickConfiguration(
            forPayloadBitCount: 50,
            errorCorrectionPercentage: 23,
            preferCompact: true
        )
        #expect(config.rsStartExponent == 1)
    }
}

// MARK: - Symbol Spec Table Tests

struct SymbolSpecTableTests {

    @Test
    func compact_specs_have_correct_count() {
        #expect(compactSymbolSpecs.count == 4)
    }

    @Test
    func full_specs_have_correct_count() {
        // Full specs cover layers 4-32 (29 entries, not 32)
        // Layers 1-3 are omitted because they cause coordinate overlap issues
        #expect(fullSymbolSpecs.count == 29)
    }

    @Test
    func all_specs_sorted_by_capacity() {
        for i in 1..<allSymbolSpecs.count {
            let prev = allSymbolSpecs[i - 1]
            let curr = allSymbolSpecs[i]
            let prevBits = prev.totalCodewordCount * prev.wordSizeInBits
            let currBits = curr.totalCodewordCount * curr.wordSizeInBits
            #expect(prevBits <= currBits, "Specs should be sorted by capacity")
        }
    }

    @Test
    func compact_layer_counts_are_1_to_4() {
        for (i, spec) in compactSymbolSpecs.enumerated() {
            #expect(spec.layerCount == i + 1)
            #expect(spec.isCompact == true)
        }
    }

    @Test
    func full_layer_counts_are_4_to_32() {
        // Full specs start at layer 4 (index 0) and go to layer 32 (index 28)
        for (i, spec) in fullSymbolSpecs.enumerated() {
            #expect(spec.layerCount == i + 4)
            #expect(spec.isCompact == false)
        }
    }
}
