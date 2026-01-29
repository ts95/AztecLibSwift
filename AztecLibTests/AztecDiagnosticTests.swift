//
//  AztecDiagnosticTests.swift
//  AztecLibTests
//
//  Diagnostic tests to help identify Aztec code issues.
//

import Foundation
import Testing
@testable import AztecLib

// MARK: - Visual Diagnostic Tests

struct AztecDiagnosticTests {

    /// Prints an Aztec symbol as ASCII art for visual inspection.
    private func printSymbol(_ symbol: AztecSymbol, label: String = "") {
        if !label.isEmpty {
            print("\n=== \(label) ===")
        }
        print("Size: \(symbol.size)x\(symbol.size)")

        for y in 0..<symbol.size {
            var row = ""
            for x in 0..<symbol.size {
                row += symbol[x: x, y: y] ? "██" : "  "
            }
            print(row)
        }
        print("")
    }

    /// Prints the matrix bits for debugging.
    private func printMatrix(_ matrix: BitBuffer, size: Int, label: String = "") {
        if !label.isEmpty {
            print("\n=== \(label) ===")
        }
        for y in 0..<size {
            var row = ""
            for x in 0..<size {
                let bitIndex = y * size + x
                let bit = matrix.leastSignificantBits(atBitPosition: bitIndex, bitCount: 1) != 0
                row += bit ? "██" : "  "
            }
            print(row)
        }
        print("")
    }

    @Test
    func diagnose_simple_aztec_code() throws {
        // Encode a simple message
        let symbol = try AztecEncoder.encode("A")
        let result = try AztecEncoder.encodeWithDetails("A")

        print("\n========== DIAGNOSTIC OUTPUT ==========")
        print("Input: \"A\"")
        print("Configuration:")
        print("  - Compact: \(result.configuration.isCompact)")
        print("  - Layers: \(result.configuration.layerCount)")
        print("  - Word size: \(result.configuration.wordSizeInBits) bits")
        print("  - Data codewords: \(result.configuration.dataCodewordCount)")
        print("  - Parity codewords: \(result.configuration.parityCodewordCount)")
        print("  - Total codewords: \(result.configuration.totalCodewordCount)")

        printSymbol(symbol, label: "Aztec Code for 'A'")

        #expect(symbol.size > 0)
    }

    @Test
    func diagnose_hello_world() throws {
        let symbol = try AztecEncoder.encode("Hello World")
        let result = try AztecEncoder.encodeWithDetails("Hello World")

        print("\n========== DIAGNOSTIC OUTPUT ==========")
        print("Input: \"Hello World\"")
        print("Configuration:")
        print("  - Compact: \(result.configuration.isCompact)")
        print("  - Layers: \(result.configuration.layerCount)")
        print("  - Word size: \(result.configuration.wordSizeInBits) bits")
        print("  - Symbol size: \(symbol.size)x\(symbol.size)")

        printSymbol(symbol, label: "Aztec Code for 'Hello World'")

        #expect(symbol.size > 0)
    }

    @Test
    func verify_orientation_marks_compact() throws {
        // Create a minimal symbol and verify orientation marks
        let config = AztecConfiguration(
            isCompact: true,
            layerCount: 1,
            wordSizeInBits: 6,
            totalCodewordCount: 17,
            dataCodewordCount: 12,
            parityCodewordCount: 5,
            primitivePolynomial: 0x43,
            rsStartExponent: 1
        )
        let builder = AztecMatrixBuilder(configuration: config)
        let modeMessage = builder.encodeModeMessage()
        let matrix = builder.buildMatrix(dataCodewords: [], modeMessageBits: modeMessage)

        let size = builder.symbolSize
        let center = size / 2

        print("\n========== ORIENTATION MARKS DIAGNOSTIC ==========")
        print("Symbol size: \(size)x\(size), center: \(center)")

        // Per ISO 24778, compact symbols should have orientation marks forming
        // a distinctive pattern in the corners:
        // - Upper-left corner: 1 black module
        // - Upper-right corner: 2 black modules (forming an "L" shape)
        // - Lower-right corner: 3 black modules

        // Check the corners of the mode message area (just outside the finder at radius 5)
        let r = 5

        // Print the corner areas
        print("\nCorner analysis at radius \(r) from center:")

        // Upper-left corner area
        let ulCorner = (x: center - r, y: center - r)
        let ulModule = matrix.leastSignificantBits(atBitPosition: ulCorner.y * size + ulCorner.x, bitCount: 1) != 0
        print("Upper-left (\(ulCorner.x), \(ulCorner.y)): \(ulModule ? "BLACK" : "white")")

        // Upper-right corner area
        let urCorner = (x: center + r, y: center - r)
        let urModule = matrix.leastSignificantBits(atBitPosition: urCorner.y * size + urCorner.x, bitCount: 1) != 0
        let urModule2 = matrix.leastSignificantBits(atBitPosition: urCorner.y * size + urCorner.x - 1, bitCount: 1) != 0
        let urModule3 = matrix.leastSignificantBits(atBitPosition: (urCorner.y + 1) * size + urCorner.x, bitCount: 1) != 0
        print("Upper-right (\(urCorner.x), \(urCorner.y)): \(urModule ? "BLACK" : "white")")
        print("Upper-right (\(urCorner.x - 1), \(urCorner.y)): \(urModule2 ? "BLACK" : "white")")
        print("Upper-right (\(urCorner.x), \(urCorner.y + 1)): \(urModule3 ? "BLACK" : "white")")

        // Lower-right corner area
        let lrCorner = (x: center + r, y: center + r)
        let lrModule = matrix.leastSignificantBits(atBitPosition: lrCorner.y * size + lrCorner.x, bitCount: 1) != 0
        print("Lower-right (\(lrCorner.x), \(lrCorner.y)): \(lrModule ? "BLACK" : "white")")

        // Lower-left corner area
        let llCorner = (x: center - r, y: center + r)
        let llModule = matrix.leastSignificantBits(atBitPosition: llCorner.y * size + llCorner.x, bitCount: 1) != 0
        print("Lower-left (\(llCorner.x), \(llCorner.y)): \(llModule ? "BLACK" : "white")")

        printMatrix(matrix, size: size, label: "Full matrix")

        #expect(true)
    }

    @Test
    func verify_finder_pattern_details() throws {
        let config = AztecConfiguration(
            isCompact: true,
            layerCount: 1,
            wordSizeInBits: 6,
            totalCodewordCount: 17,
            dataCodewordCount: 12,
            parityCodewordCount: 5,
            primitivePolynomial: 0x43,
            rsStartExponent: 1
        )
        let builder = AztecMatrixBuilder(configuration: config)
        let modeMessage = builder.encodeModeMessage()
        let matrix = builder.buildMatrix(dataCodewords: [], modeMessageBits: modeMessage)

        let size = builder.symbolSize
        let center = size / 2

        print("\n========== FINDER PATTERN DIAGNOSTIC ==========")
        print("Size: \(size), center: \(center)")

        // Print a cross-section through the center
        print("\nHorizontal cross-section through center (y=\(center)):")
        for x in 0..<size {
            let bit = matrix.leastSignificantBits(atBitPosition: center * size + x, bitCount: 1) != 0
            print("x=\(x): \(bit ? "█" : "·")", terminator: " ")
        }
        print("")

        // Expected pattern for compact (9x9 finder):
        // Radius 0: BLACK (center)
        // Radius 1: WHITE
        // Radius 2: BLACK
        // Radius 3: WHITE
        // Radius 4: BLACK (outer edge of finder)

        print("\nFinder rings from center:")
        for radius in 0...5 {
            let x = center + radius
            let bit = matrix.leastSignificantBits(atBitPosition: center * size + x, bitCount: 1) != 0
            let expected = radius <= 4 && (radius % 2 == 0)
            let status = (bit == expected) ? "OK" : "WRONG"
            print("Radius \(radius): \(bit ? "BLACK" : "WHITE") (expected: \(expected ? "BLACK" : "WHITE")) - \(status)")
        }

        #expect(true)
    }

    @Test
    func verify_mode_message_placement() throws {
        // Test mode message bit placement
        let config = AztecConfiguration(
            isCompact: true,
            layerCount: 2,
            wordSizeInBits: 6,
            totalCodewordCount: 40,
            dataCodewordCount: 35,
            parityCodewordCount: 5,
            primitivePolynomial: 0x43,
            rsStartExponent: 1
        )
        let builder = AztecMatrixBuilder(configuration: config)
        let modeMessage = builder.encodeModeMessage()

        print("\n========== MODE MESSAGE DIAGNOSTIC ==========")
        print("Mode message bit count: \(modeMessage.bitCount)")

        // Print the mode message bits
        print("Mode message bits (MSB first):")
        for i in 0..<modeMessage.bitCount {
            let bit = modeMessage.leastSignificantBits(atBitPosition: i, bitCount: 1)
            print(bit, terminator: "")
            if (i + 1) % 4 == 0 { print(" ", terminator: "") }
        }
        print("")

        // Decode what the mode message should contain
        // Compact: 2 bits layers-1, 6 bits data-1, then RS parity
        print("\nExpected mode message content:")
        print("  layers - 1 = \(config.layerCount - 1) (2 bits)")
        print("  dataCodewords - 1 = \(config.dataCodewordCount - 1) (6 bits)")

        #expect(modeMessage.bitCount == 28)
    }

    @Test
    func compare_data_encoding() throws {
        // Compare encoding of "A" which should be straightforward
        let buffer = AztecDataEncoder.encode("A")

        print("\n========== DATA ENCODING DIAGNOSTIC ==========")
        print("Input: \"A\"")
        print("Encoded bit count: \(buffer.bitCount)")

        // A in Upper mode should be code 2 (5 bits: 00010)
        print("Expected: A = code 2 = 00010 (5 bits)")

        print("Actual bits:")
        for i in 0..<buffer.bitCount {
            let bit = buffer.leastSignificantBits(atBitPosition: i, bitCount: 1)
            print(bit, terminator: "")
        }
        print("")

        // Read back as 5-bit value
        if buffer.bitCount >= 5 {
            let value = buffer.leastSignificantBits(atBitPosition: 0, bitCount: 5)
            print("First 5 bits as value: \(value) (expected: 2)")
        }

        #expect(buffer.bitCount == 5)
    }

    @Test
    func verify_codeword_stuffing() throws {
        // Test codeword stuffing for various patterns
        print("\n========== CODEWORD STUFFING DIAGNOSTIC ==========")

        // Test all zeros
        var buf1 = BitBuffer()
        buf1.appendLeastSignificantBits(0b00000, bitCount: 5)
        let cw1 = buf1.makeCodewords(codewordBitWidth: 6)
        print("Input: 00000 -> Codeword: \(cw1[0]) (binary: \(String(cw1[0], radix: 2).padding(toLength: 6, withPad: "0", startingAt: 0)))")
        print("  Expected: 000001 (stuffed 1)")

        // Test all ones
        var buf2 = BitBuffer()
        buf2.appendLeastSignificantBits(0b11111, bitCount: 5)
        let cw2 = buf2.makeCodewords(codewordBitWidth: 6)
        print("Input: 11111 -> Codeword: \(cw2[0]) (binary: \(String(cw2[0], radix: 2).padding(toLength: 6, withPad: "0", startingAt: 0)))")
        print("  Expected: 111110 (stuffed 0)")

        // Test mixed pattern
        var buf3 = BitBuffer()
        buf3.appendLeastSignificantBits(0b10101, bitCount: 5)
        buf3.appendLeastSignificantBits(0b1, bitCount: 1)
        let cw3 = buf3.makeCodewords(codewordBitWidth: 6)
        print("Input: 10101 + 1 -> Codeword: \(cw3[0]) (binary: \(String(cw3[0], radix: 2).padding(toLength: 6, withPad: "0", startingAt: 0)))")
        print("  Expected: 101011 (uses next bit)")

        #expect(true)
    }

    @Test
    func full_encoding_trace() throws {
        // Trace through the complete encoding pipeline
        print("\n========== FULL ENCODING TRACE ==========")

        let input = "A"
        print("Input: \"\(input)\"")

        // Step 1: Data encoding
        let dataBits = AztecDataEncoder.encode(input)
        print("\n1. Data encoding:")
        print("   Bit count: \(dataBits.bitCount)")
        print("   Bits: ", terminator: "")
        for i in 0..<dataBits.bitCount {
            print(dataBits.leastSignificantBits(atBitPosition: i, bitCount: 1), terminator: "")
        }
        print("")

        // Step 2: Configuration
        let config = try pickConfiguration(
            forPayloadBitCount: dataBits.bitCount,
            errorCorrectionPercentage: 23,
            preferCompact: true
        )
        print("\n2. Configuration:")
        print("   Compact: \(config.isCompact)")
        print("   Layers: \(config.layerCount)")
        print("   Word size: \(config.wordSizeInBits)")
        print("   Data codewords: \(config.dataCodewordCount)")
        print("   Parity codewords: \(config.parityCodewordCount)")

        // Step 3: Codeword packing
        let codewords = dataBits.makeCodewords(codewordBitWidth: config.wordSizeInBits)
        print("\n3. Codeword packing:")
        print("   Codeword count: \(codewords.count)")
        for (i, cw) in codewords.enumerated() {
            print("   Codeword \(i): \(cw) (\(String(cw, radix: 2)))")
        }

        // Step 4: RS parity
        let gf = GaloisField(wordSizeInBits: config.wordSizeInBits, primitivePolynomial: config.primitivePolynomial)
        let rs = ReedSolomonEncoder(field: gf, startExponent: config.rsStartExponent)

        // Pad codewords
        var paddedCodewords = codewords
        while paddedCodewords.count < config.dataCodewordCount {
            paddedCodewords.append(0)
        }

        let withParity = rs.appendingParity(to: paddedCodewords, parityCodewordCount: config.parityCodewordCount)
        print("\n4. Reed-Solomon encoding:")
        print("   Total codewords: \(withParity.count)")
        print("   Data: \(Array(withParity.prefix(config.dataCodewordCount)))")
        print("   Parity: \(Array(withParity.suffix(config.parityCodewordCount)))")

        // Step 5: Matrix building
        let builder = AztecMatrixBuilder(configuration: config)
        print("\n5. Matrix building:")
        print("   Symbol size: \(builder.symbolSize)x\(builder.symbolSize)")

        let symbol = try AztecEncoder.encode(input)
        print("\n6. Final symbol:")
        print("   Size: \(symbol.size)")
        print("   Row stride: \(symbol.rowStride)")
        print("   Total bytes: \(symbol.bytes.count)")

        #expect(symbol.size > 0)
    }
}
