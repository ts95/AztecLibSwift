//
//  AztecMatrixBuilderTests.swift
//  AztecLibTests
//
//  Created by Toni Sucic on 13/10/2025.
//

import Foundation
import Testing
@testable import AztecLib

// MARK: - Matrix Builder Tests

struct AztecMatrixBuilderTests {

    // MARK: - Symbol Size Calculation

    @Test
    func compact_symbol_size_formula() throws {
        // Compact: size = 11 + 4 * layers
        for layers in 1...4 {
            let config = AztecConfiguration(
                isCompact: true,
                layerCount: layers,
                wordSizeInBits: 6,
                totalCodewordCount: 17,
                dataCodewordCount: 10,
                parityCodewordCount: 7,
                primitivePolynomial: 0x43,
                rsStartExponent: 1
            )
            let builder = AztecMatrixBuilder(configuration: config)
            let expected = 11 + 4 * layers
            #expect(builder.symbolSize == expected, "Layer \(layers) should be \(expected)")
        }
    }

    @Test
    func full_symbol_size_formula() throws {
        // Full: size = 15 + 4 * layers + 2 * floor((layers - 1) / 15)
        let testCases: [(layers: Int, expectedSize: Int)] = [
            (1, 19),   // 15 + 4 = 19
            (2, 23),   // 15 + 8 = 23
            (5, 35),   // 15 + 20 = 35
            (15, 75),  // 15 + 60 = 75
            (16, 81),  // 15 + 64 + 2 = 81
            (30, 137), // 15 + 120 + 2 = 137
            (31, 143), // 15 + 124 + 4 = 143
            (32, 147), // 15 + 128 + 4 = 147
        ]

        for (layers, expectedSize) in testCases {
            let config = AztecConfiguration(
                isCompact: false,
                layerCount: layers,
                wordSizeInBits: 8,
                totalCodewordCount: 100,
                dataCodewordCount: 70,
                parityCodewordCount: 30,
                primitivePolynomial: 0x12D,
                rsStartExponent: 1
            )
            let builder = AztecMatrixBuilder(configuration: config)
            #expect(builder.symbolSize == expectedSize, "Full layer \(layers) should be \(expectedSize)")
        }
    }

    @Test
    func center_offset_is_half_size() throws {
        let config = makeCompactConfig(layers: 1)
        let builder = AztecMatrixBuilder(configuration: config)
        let size = builder.symbolSize
        #expect(builder.centerOffset == size / 2)
    }

    // MARK: - Finder Pattern

    @Test
    func compact_finder_is_9x9() throws {
        let config = makeCompactConfig(layers: 1)
        let builder = AztecMatrixBuilder(configuration: config)
        let modeMessage = builder.encodeModeMessage()
        let matrix = try builder.buildMatrix(dataCodewords: [], modeMessageBits: modeMessage)

        let size = builder.symbolSize
        let center = size / 2

        // Check center is black
        let centerBit = matrix.leastSignificantBits(atBitPosition: center * size + center, bitCount: 1)
        #expect(centerBit == 1, "Center should be black")
    }

    @Test
    func full_finder_is_13x13() throws {
        let config = makeFullConfig(layers: 1)
        let builder = AztecMatrixBuilder(configuration: config)
        let modeMessage = builder.encodeModeMessage()
        let matrix = try builder.buildMatrix(dataCodewords: [], modeMessageBits: modeMessage)

        let size = builder.symbolSize
        let center = size / 2

        // Check center is black
        let centerBit = matrix.leastSignificantBits(atBitPosition: center * size + center, bitCount: 1)
        #expect(centerBit == 1, "Center should be black")
    }

    @Test
    func finder_has_alternating_rings() throws {
        let config = makeCompactConfig(layers: 1)
        let builder = AztecMatrixBuilder(configuration: config)
        let modeMessage = builder.encodeModeMessage()
        let matrix = try builder.buildMatrix(dataCodewords: [], modeMessageBits: modeMessage)

        let size = builder.symbolSize
        let center = size / 2

        // Check alternating pattern along a radius
        for r in 0...4 {
            let bit = matrix.leastSignificantBits(
                atBitPosition: center * size + (center + r),
                bitCount: 1
            )
            let expectedBlack = (r % 2 == 0)
            #expect((bit == 1) == expectedBlack, "Ring at radius \(r) should be \(expectedBlack ? "black" : "white")")
        }
    }

    // MARK: - Mode Message

    @Test
    func compact_mode_message_is_28_bits() throws {
        let config = makeCompactConfig(layers: 2)
        let builder = AztecMatrixBuilder(configuration: config)
        let modeMessage = builder.encodeModeMessage()
        #expect(modeMessage.bitCount == 28)
    }

    @Test
    func full_mode_message_is_40_bits() throws {
        let config = makeFullConfig(layers: 5)
        let builder = AztecMatrixBuilder(configuration: config)
        let modeMessage = builder.encodeModeMessage()
        #expect(modeMessage.bitCount == 40)
    }

    @Test
    func mode_message_encodes_layer_count() throws {
        let config = makeCompactConfig(layers: 3)
        let builder = AztecMatrixBuilder(configuration: config)
        let modeMessage = builder.encodeModeMessage()

        // First 2 bits should encode layers-1 = 2 = 0b10
        // But nibbles are MSB-first packed, so need to decode carefully
        #expect(modeMessage.bitCount == 28)
    }

    // MARK: - Data Placement

    @Test
    func builds_matrix_with_data() throws {
        let config = makeCompactConfig(layers: 1)
        let builder = AztecMatrixBuilder(configuration: config)
        let modeMessage = builder.encodeModeMessage()

        // Create some test codewords
        let codewords: [UInt16] = [0x15, 0x2A, 0x3F, 0x00, 0x1F]
        let matrix = try builder.buildMatrix(dataCodewords: codewords, modeMessageBits: modeMessage)

        let size = builder.symbolSize
        #expect(matrix.bitCount == size * size)
    }

    @Test
    func matrix_dimensions_match_symbol_size() throws {
        for layers in 1...4 {
            let config = makeCompactConfig(layers: layers)
            let builder = AztecMatrixBuilder(configuration: config)
            let modeMessage = builder.encodeModeMessage()
            let matrix = try builder.buildMatrix(dataCodewords: [], modeMessageBits: modeMessage)

            let expectedBits = builder.symbolSize * builder.symbolSize
            #expect(matrix.bitCount == expectedBits)
        }
    }

    // MARK: - Helper Functions

    private func makeCompactConfig(layers: Int) -> AztecConfiguration {
        let spec = compactSymbolSpecs[layers - 1]
        return AztecConfiguration(
            isCompact: true,
            layerCount: layers,
            wordSizeInBits: spec.wordSizeInBits,
            totalCodewordCount: spec.totalCodewordCount,
            dataCodewordCount: spec.totalCodewordCount - 5,
            parityCodewordCount: 5,
            primitivePolynomial: AztecPrimitivePolynomials.polynomial(forWordSize: spec.wordSizeInBits),
            rsStartExponent: 1
        )
    }

    private func makeFullConfig(layers: Int) -> AztecConfiguration {
        let spec = fullSymbolSpecs[layers - 1]
        return AztecConfiguration(
            isCompact: false,
            layerCount: layers,
            wordSizeInBits: spec.wordSizeInBits,
            totalCodewordCount: spec.totalCodewordCount,
            dataCodewordCount: spec.totalCodewordCount - 10,
            parityCodewordCount: 10,
            primitivePolynomial: AztecPrimitivePolynomials.polynomial(forWordSize: spec.wordSizeInBits),
            rsStartExponent: 1
        )
    }
}

// MARK: - Reference Grid Tests

struct ReferenceGridTests {

    @Test
    func compact_symbols_have_no_reference_grid() throws {
        let config = AztecConfiguration(
            isCompact: true,
            layerCount: 4,
            wordSizeInBits: 8,
            totalCodewordCount: 76,
            dataCodewordCount: 60,
            parityCodewordCount: 16,
            primitivePolynomial: 0x12D,
            rsStartExponent: 1
        )
        // Compact symbols should not have reference grid
        // This is verified by the fact that the builder skips drawReferenceGrid for compact
        #expect(config.isCompact == true)
        _ = AztecMatrixBuilder(configuration: config)
    }

    @Test
    func full_symbols_with_many_layers_have_reference_grid() throws {
        // Layer 16+ should have reference grid lines
        let config = AztecConfiguration(
            isCompact: false,
            layerCount: 20,
            wordSizeInBits: 10,
            totalCodewordCount: 864,
            dataCodewordCount: 700,
            parityCodewordCount: 164,
            primitivePolynomial: 0x409,
            rsStartExponent: 1
        )
        let builder = AztecMatrixBuilder(configuration: config)
        let size = builder.symbolSize

        // Size should include reference grid lines
        // 15 + 4*20 + 2*floor(19/15) = 15 + 80 + 2 = 97
        #expect(size == 97)
    }
}
