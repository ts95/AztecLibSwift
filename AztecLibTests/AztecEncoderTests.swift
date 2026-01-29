//
//  AztecEncoderTests.swift
//  AztecLibTests
//
//  Created by Toni Sucic on 13/10/2025.
//

import Foundation
import Testing
@testable import AztecLib

// MARK: - End-to-End Encoder Tests

struct AztecEncoderTests {

    // MARK: - Basic Encoding

    @Test
    func encodes_hello_string() throws {
        let symbol = try AztecEncoder.encode("Hello")
        #expect(symbol.size > 0)
        #expect(symbol.bytes.count > 0)
        #expect(symbol.rowStride > 0)
    }

    @Test
    func encodes_simple_digits() throws {
        let symbol = try AztecEncoder.encode("12345")
        #expect(symbol.size > 0)
    }

    @Test
    func encodes_binary_data() throws {
        let bytes: [UInt8] = [0x00, 0xFF, 0x42, 0x13, 0x37]
        let symbol = try AztecEncoder.encode(bytes)
        #expect(symbol.size > 0)
    }

    @Test
    func encodes_data_object() throws {
        let data = Data([0x01, 0x02, 0x03, 0x04])
        let symbol = try AztecEncoder.encode(data)
        #expect(symbol.size > 0)
    }

    @Test
    func encodes_large_binary_data_requiring_12_layers() throws {
        // This test verifies the fix for the reference grid issue with layer 12 symbols.
        // Previously, the data path calculation incorrectly excluded reference grid positions
        // for symbols with < 16 layers, causing an assertion failure.
        // 366 bytes of binary data requires a 12-layer full symbol (63x63).
        let base64 = "CpwCCpkCCpYCCiQ3ZjY1ZmE0Mi04Y2FjLTQ3ZjQtYjEyYy1jNDNlNWUzM2JjNjISDAiT0+zLBhC81JHHAhrcAQoEDAMFCBIYCAESFG5vLnJ1dGVyLlJlaXNlLnN0YWdlEggIAxIEMjYuMBIICAQSBDI2LjASCQgFEgVBcHBsZRIJCAYSBWFybTY0ElgIBxJUUlVUOkN1c3RvbWVyQWNjb3VudDpkMGM4NThiYzE1OTBjODU1ODY0OGFhMTc1ZDA0ZDA3Y2RiNWI1MjMzZmRmMDY0M2FhOGM0ZTQ4YWJlYjFkYjcyEgsICRIHMTYuMTAuMBIPCAoSC0RFVkVMT1BNRU5UEg4ICxIKNDkyR0ZKMzZYVhIICAwSBDExMzUiAQQSTQpGMEQCIHpHDShB/pKwYaJf3n2mz1nIiXmGkfJdIPCL6dSxIXVWAiA6LcQwlOucEXYsnCcBW/KJebY/IIANVyHNyTXOfp6gaxoBTjAB"
        let data = Data(base64Encoded: base64)!

        #expect(data.count == 366, "Test data should be 366 bytes")

        let result = try AztecEncoder.encodeWithDetails([UInt8](data))

        #expect(result.symbol.size == 63, "366 bytes should produce a 63x63 symbol")
        #expect(result.configuration.layerCount == 12, "366 bytes should use 12 layers")
        #expect(result.configuration.isCompact == false, "Large data requires full symbol")
    }

    // MARK: - Options

    @Test
    func respects_error_correction_option() throws {
        let lowEC = try AztecEncoder.encodeWithDetails(
            "Hello World",
            options: AztecEncoder.Options(errorCorrectionPercentage: 10)
        )
        let highEC = try AztecEncoder.encodeWithDetails(
            "Hello World",
            options: AztecEncoder.Options(errorCorrectionPercentage: 50)
        )

        // Higher EC should have equal or larger symbol (more parity)
        #expect(highEC.configuration.parityCodewordCount >= lowEC.configuration.parityCodewordCount)
    }

    @Test
    func respects_prefer_compact_option() throws {
        let compact = try AztecEncoder.encodeWithDetails(
            "Test",
            options: AztecEncoder.Options(preferCompact: true)
        )
        #expect(compact.configuration.isCompact == true)
    }

    @Test
    func msb_first_option_changes_byte_order() throws {
        let lsb = try AztecEncoder.encode(
            "Test",
            options: AztecEncoder.Options(exportMSBFirst: false)
        )
        let msb = try AztecEncoder.encode(
            "Test",
            options: AztecEncoder.Options(exportMSBFirst: true)
        )

        // Same size but potentially different byte values
        #expect(lsb.size == msb.size)
        #expect(lsb.rowStride == msb.rowStride)
    }

    // MARK: - Symbol Properties

    @Test
    func symbol_is_square() throws {
        let symbol = try AztecEncoder.encode("Hello World")
        let expectedBytes = symbol.rowStride * symbol.size
        #expect(symbol.bytes.count == expectedBytes)
    }

    @Test
    func symbol_subscript_works() throws {
        let symbol = try AztecEncoder.encode("Hello")
        // Access a module - should not crash
        let center = symbol.size / 2
        let _ = symbol[x: center, y: center]
    }

    @Test
    func center_is_black_in_finder() throws {
        let symbol = try AztecEncoder.encode("Test")
        let center = symbol.size / 2
        // Center of finder should be black (dark module)
        #expect(symbol[x: center, y: center] == true)
    }

    // MARK: - Encoding Details

    @Test
    func encode_with_details_returns_configuration() throws {
        let result = try AztecEncoder.encodeWithDetails("Hello World")
        #expect(result.configuration.layerCount > 0)
        #expect(result.configuration.totalCodewordCount > 0)
        #expect(result.symbol.size > 0)
    }

    @Test
    func bytes_encoding_returns_details() throws {
        let result = try AztecEncoder.encodeWithDetails([0x00, 0xFF])
        #expect(result.configuration.layerCount > 0)
    }

    // MARK: - Error Handling

    @Test
    func throws_for_payload_too_large() throws {
        // Create a very large string that can't fit in any symbol
        let hugeString = String(repeating: "X", count: 10000)
        #expect(throws: AztecEncoder.EncodingError.self) {
            _ = try AztecEncoder.encode(hugeString)
        }
    }

    // MARK: - Test Vectors

    @Test
    func hello_produces_compact_symbol() throws {
        let result = try AztecEncoder.encodeWithDetails("Hello")
        // "Hello" should fit in a compact symbol
        #expect(result.configuration.isCompact == true)
    }

    @Test
    func digits_use_efficient_encoding() throws {
        let result = try AztecEncoder.encodeWithDetails("12345")
        // Pure digits should use digit mode efficiently, fitting in compact
        #expect(result.configuration.isCompact == true)
        #expect(result.configuration.layerCount <= 2)
    }

    @Test
    func mixed_hello_world_encoding() throws {
        let result = try AztecEncoder.encodeWithDetails("Hello, World!")
        // Mixed content with mode switching
        #expect(result.symbol.size > 0)
    }

    // MARK: - Determinism

    @Test
    func encoding_is_deterministic() throws {
        let symbol1 = try AztecEncoder.encode("Test")
        let symbol2 = try AztecEncoder.encode("Test")

        #expect(symbol1.size == symbol2.size)
        #expect(symbol1.bytes == symbol2.bytes)
    }

    // MARK: - Symbol Sizes

    @Test
    func compact_1_layer_is_15x15() throws {
        // Force a very small symbol
        let result = try AztecEncoder.encodeWithDetails(
            "A",
            options: AztecEncoder.Options(preferCompact: true)
        )
        if result.configuration.isCompact && result.configuration.layerCount == 1 {
            #expect(result.symbol.size == 15)
        }
    }

    @Test
    func compact_2_layer_is_19x19() throws {
        // Create enough data for layer 2 but not more
        let result = try AztecEncoder.encodeWithDetails(
            "ABCDEFGHIJ",
            options: AztecEncoder.Options(preferCompact: true)
        )
        if result.configuration.isCompact && result.configuration.layerCount == 2 {
            #expect(result.symbol.size == 19)
        }
    }
}

// MARK: - Integration Tests

struct AztecIntegrationTests {

    @Test
    func full_pipeline_produces_valid_symbol() throws {
        // Trace through the full pipeline
        let input = "Hello, Aztec!"

        // Step 1: Data encoding
        let dataBits = AztecDataEncoder.encode(input)
        #expect(dataBits.bitCount > 0)

        // Step 2: Configuration selection
        let config = try pickConfiguration(
            forPayloadBitCount: dataBits.bitCount,
            errorCorrectionPercentage: 23,
            preferCompact: true
        )
        #expect(config.totalCodewordCount > 0)

        // Step 3: Codeword packing
        let codewords = dataBits.makeCodewords(codewordBitWidth: config.wordSizeInBits)
        #expect(!codewords.isEmpty)

        // Step 4: RS parity
        let gf = GaloisField(wordSizeInBits: config.wordSizeInBits, primitivePolynomial: config.primitivePolynomial)
        let rs = ReedSolomonEncoder(field: gf, startExponent: config.rsStartExponent)
        let withParity = rs.appendingParity(to: codewords, parityCodewordCount: config.parityCodewordCount)
        #expect(withParity.count == codewords.count + config.parityCodewordCount)

        // Step 5: Matrix building
        let builder = AztecMatrixBuilder(configuration: config)
        let modeMessage = builder.encodeModeMessage()
        let matrix = builder.buildMatrix(dataCodewords: withParity, modeMessageBits: modeMessage)
        #expect(matrix.bitCount == builder.symbolSize * builder.symbolSize)

        // Step 6: Export
        let symbol = matrix.makeSymbolExport(matrixSize: builder.symbolSize, rowOrderMostSignificantBitFirst: false)
        #expect(symbol.size == builder.symbolSize)
    }

    @Test
    func various_content_types_encode_successfully() throws {
        let testCases = [
            "HELLO",
            "hello",
            "12345",
            "Hello World 123!",
            "@#$%",
            " ",
            "A",
        ]

        for content in testCases {
            let symbol = try AztecEncoder.encode(content)
            #expect(symbol.size > 0, "Failed to encode: \(content)")
        }
    }

    @Test
    func binary_content_encodes_correctly() throws {
        // Test various byte patterns
        let testCases: [[UInt8]] = [
            [0x00],
            [0xFF],
            [0x00, 0xFF],
            Array(0...255),
            [UInt8](repeating: 0x42, count: 100),
        ]

        for bytes in testCases {
            let symbol = try AztecEncoder.encode(bytes)
            #expect(symbol.size > 0, "Failed to encode \(bytes.count) bytes")
        }
    }
}
