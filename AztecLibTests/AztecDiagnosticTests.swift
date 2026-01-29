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
        let matrix = try builder.buildMatrix(dataCodewords: [], modeMessageBits: modeMessage)

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
        let matrix = try builder.buildMatrix(dataCodewords: [], modeMessageBits: modeMessage)

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
    func output_single_char_format() throws {
        // Output AztecLib barcode in single-character format for comparison with ZXing
        let symbol = try AztecEncoder.encode("A")

        print("\n========== SINGLE-CHAR FORMAT (for Python comparison) ==========")
        print("azteclib_rows = [")
        for y in 0..<symbol.size {
            var row = ""
            for x in 0..<symbol.size {
                row += symbol[x: x, y: y] ? "█" : "░"
            }
            print("    \"\(row)\",")
        }
        print("]")

        #expect(symbol.size > 0)
    }

    @Test
    func output_hello_format() throws {
        // Output AztecLib barcode for "Hello"
        let symbol = try AztecEncoder.encode("Hello")

        print("\n========== HELLO FORMAT (for Python comparison) ==========")
        print("AztecLib matrix (\(symbol.size)x\(symbol.size)):")
        for y in 0..<symbol.size {
            var row = ""
            for x in 0..<symbol.size {
                row += symbol[x: x, y: y] ? "█" : "░"
            }
            print(row)
        }

        #expect(symbol.size > 0)
    }

    @Test
    func output_123_format() throws {
        // Output AztecLib barcode for "123"
        let symbol = try AztecEncoder.encode("123")

        print("\n========== 123 FORMAT (for Python comparison) ==========")
        print("azteclib_123_rows = [")
        for y in 0..<symbol.size {
            var row = ""
            for x in 0..<symbol.size {
                row += symbol[x: x, y: y] ? "█" : "░"
            }
            print("    \"\(row)\",")
        }
        print("]")

        #expect(symbol.size > 0)
    }

    @Test
    func trace_123_encoding() throws {
        // Trace the encoding of "123"
        print("\n========== 123 ENCODING TRACE ==========")

        let dataBits = AztecDataEncoder.encode("123")
        print("Data bits count: \(dataBits.bitCount)")
        print("Data bits: ", terminator: "")
        for i in 0..<dataBits.bitCount {
            print(dataBits.leastSignificantBits(atBitPosition: i, bitCount: 1), terminator: "")
        }
        print()

        let config = try pickConfiguration(
            forPayloadBitCount: dataBits.bitCount,
            errorCorrectionPercentage: 23,
            preferCompact: true
        )
        print("\nConfiguration:")
        print("  compact: \(config.isCompact)")
        print("  layers: \(config.layerCount)")
        print("  wordSize: \(config.wordSizeInBits)")
        print("  dataCodewords: \(config.dataCodewordCount)")
        print("  parityCodewords: \(config.parityCodewordCount)")

        let codewords = dataBits.makeCodewords(codewordBitWidth: config.wordSizeInBits)
        print("\nData codewords: \(codewords)")

        let gf = GaloisField(wordSizeInBits: config.wordSizeInBits, primitivePolynomial: config.primitivePolynomial)
        let rs = ReedSolomonEncoder(field: gf, startExponent: config.rsStartExponent)
        let allCodewords = rs.appendingParity(to: codewords, parityCodewordCount: config.parityCodewordCount)
        print("All codewords (with RS): \(allCodewords)")

        #expect(true)
    }

    @Test
    func trace_hello_encoding() throws {
        // Trace the encoding of "Hello"
        print("\n========== HELLO ENCODING TRACE ==========")

        let dataBits = AztecDataEncoder.encode("Hello")
        print("Data bits count: \(dataBits.bitCount)")
        print("Data bits: ", terminator: "")
        for i in 0..<dataBits.bitCount {
            print(dataBits.leastSignificantBits(atBitPosition: i, bitCount: 1), terminator: "")
        }
        print()

        let config = try pickConfiguration(
            forPayloadBitCount: dataBits.bitCount,
            errorCorrectionPercentage: 23,
            preferCompact: true
        )
        print("\nConfiguration:")
        print("  compact: \(config.isCompact)")
        print("  layers: \(config.layerCount)")
        print("  wordSize: \(config.wordSizeInBits)")
        print("  dataCodewords: \(config.dataCodewordCount)")
        print("  parityCodewords: \(config.parityCodewordCount)")

        let codewords = dataBits.makeCodewords(codewordBitWidth: config.wordSizeInBits)
        print("\nData codewords: \(codewords)")

        let gf = GaloisField(wordSizeInBits: config.wordSizeInBits, primitivePolynomial: config.primitivePolynomial)
        let rs = ReedSolomonEncoder(field: gf, startExponent: config.rsStartExponent)
        let allCodewords = rs.appendingParity(to: codewords, parityCodewordCount: config.parityCodewordCount)
        print("All codewords (with RS): \(allCodewords)")

        #expect(true)
    }

    @Test
    func trace_data_placement() throws {
        // Trace the exact data placement to compare with ZXing
        print("\n========== DATA PLACEMENT TRACE ==========")

        // Encode "A"
        let dataBits = AztecDataEncoder.encode("A")
        print("Input 'A' encoded to \(dataBits.bitCount) bits")

        // Get configuration
        let config = try pickConfiguration(
            forPayloadBitCount: dataBits.bitCount,
            errorCorrectionPercentage: 23,
            preferCompact: true
        )
        print("Configuration: compact=\(config.isCompact), layers=\(config.layerCount), wordSize=\(config.wordSizeInBits)")

        // Pack into codewords
        let codewords = dataBits.makeCodewords(codewordBitWidth: config.wordSizeInBits)
        print("Data codewords (before RS): \(codewords)")

        // Pad and add RS parity
        var paddedCodewords = codewords
        while paddedCodewords.count < config.dataCodewordCount {
            paddedCodewords.append(0)
        }
        let gf = GaloisField(wordSizeInBits: config.wordSizeInBits, primitivePolynomial: config.primitivePolynomial)
        let rs = ReedSolomonEncoder(field: gf, startExponent: config.rsStartExponent)
        let allCodewords = rs.appendingParity(to: paddedCodewords, parityCodewordCount: config.parityCodewordCount)
        print("All codewords (with RS): \(allCodewords)")

        // Calculate startPad
        let totalBitsInLayer = ((config.isCompact ? 88 : 112) + 16 * config.layerCount) * config.layerCount
        let startPad = totalBitsInLayer % config.wordSizeInBits
        print("totalBitsInLayer = \(totalBitsInLayer), startPad = \(startPad)")

        // Build messageBits like ZXing
        var messageBits: [Bool] = []
        for _ in 0..<startPad {
            messageBits.append(false)
        }
        for codeword in allCodewords {
            for bitPos in stride(from: config.wordSizeInBits - 1, through: 0, by: -1) {
                messageBits.append(((codeword >> bitPos) & 1) != 0)
            }
        }
        print("messageBits count = \(messageBits.count)")

        // Print first 26 message bits (first TOP side bits)
        print("\nFirst 26 messageBits:")
        for i in 0..<min(26, messageBits.count) {
            print("  [\(String(format: "%2d", i))]: \(messageBits[i] ? "1" : "0")")
        }

        // Trace first few placements
        let layers = config.layerCount
        let baseMatrixSize = 11 + layers * 4  // 15 for L1
        let rowSize = layers * 4 + 9  // 13 for L1

        print("\nData placement trace (first 12 TOP bits):")
        print("rowSize = \(rowSize), baseMatrixSize = \(baseMatrixSize)")
        var rowOffset = 0
        for j in 0..<6 {
            let columnOffset = j * 2
            for k in 0..<2 {
                let bitIdx = rowOffset + columnOffset + k
                let x = k  // alignmentMap[0*2+k] = k for compact
                let y = j  // alignmentMap[0*2+j] = j for compact
                let bit = messageBits[bitIdx]
                print("  TOP: j=\(j) k=\(k) bitIdx=\(bitIdx) -> (\(x),\(y)) = \(bit ? "1" : "0")")
            }
        }

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

    @Test
    func trace_mixed_content_encoding() throws {
        // Trace the encoding of "Mixed123Content!@#" to debug the punctuation issue
        let input = "Mixed123Content!@#"
        print("\n========== MIXED CONTENT ENCODING TRACE ==========")
        print("Input: \"\(input)\"")

        // Trace character by character what modes are used
        print("\nCharacter analysis:")
        for char in input {
            let modes: [AztecMode] = [.upper, .lower, .mixed, .punct, .digit]
            var foundModes: [(AztecMode, Int)] = []
            for mode in modes {
                if let code = AztecModeTables.code(for: char, in: mode) {
                    foundModes.append((mode, code))
                }
            }
            print("  '\(char)': \(foundModes.map { "\($0.0): \($0.1)" }.joined(separator: ", "))")
        }

        // Encode
        let dataBits = AztecDataEncoder.encode(input)
        print("\nData bits count: \(dataBits.bitCount)")
        print("Data bits: ", terminator: "")
        for i in 0..<dataBits.bitCount {
            print(dataBits.leastSignificantBits(atBitPosition: i, bitCount: 1), terminator: "")
        }
        print()

        // Get configuration
        let config = try pickConfiguration(
            forPayloadBitCount: dataBits.bitCount,
            errorCorrectionPercentage: 23,
            preferCompact: true
        )
        print("\nConfiguration:")
        print("  compact: \(config.isCompact)")
        print("  layers: \(config.layerCount)")
        print("  wordSize: \(config.wordSizeInBits)")
        print("  dataCodewords: \(config.dataCodewordCount)")
        print("  parityCodewords: \(config.parityCodewordCount)")

        let codewords = dataBits.makeCodewords(codewordBitWidth: config.wordSizeInBits)
        print("\nData codewords count: \(codewords.count)")
        print("Data codewords: \(codewords)")

        // Also print the final symbol as binary for comparison
        let symbol = try AztecEncoder.encode(input)
        print("\nAztecLib matrix (19x19):")
        for y in 0..<symbol.size {
            var row = "Row \(String(format: "%2d", y)): "
            for x in 0..<symbol.size {
                row += symbol[x: x, y: y] ? "1" : "0"
            }
            print(row)
        }

        #expect(true)
    }

    @Test
    func trace_simple_punct() throws {
        // Test just "!" encoding
        let input = "A!"
        print("\n========== A! ENCODING TRACE ==========")
        print("Input: \"\(input)\"")

        let dataBits = AztecDataEncoder.encode(input)
        print("Data bits count: \(dataBits.bitCount)")
        print("Data bits: ", terminator: "")
        for i in 0..<dataBits.bitCount {
            print(dataBits.leastSignificantBits(atBitPosition: i, bitCount: 1), terminator: "")
        }
        print()

        // A in Upper = code 2 (5 bits: 00010)
        // P/S from Upper = code 0 (5 bits: 00000)
        // ! in Punct = code 6 (5 bits: 00110)
        // Total: 15 bits
        print("\nExpected:")
        print("  A: code 2 = 00010 (5 bits)")
        print("  P/S: code 0 = 00000 (5 bits)")
        print("  !: code 6 = 00110 (5 bits)")
        print("  Total: 15 bits")

        #expect(dataBits.bitCount == 15)
    }

    @Test
    func trace_binary_encoding() throws {
        // Test binary encoding for 5 bytes
        let bytes: [UInt8] = [0x01, 0x02, 0x03, 0x04, 0x05]
        print("\n========== BINARY ENCODING TRACE ==========")
        print("Input: \(bytes)")

        let dataBits = AztecDataEncoder.encode(bytes)
        print("Data bits count: \(dataBits.bitCount)")
        print("Data bits: ", terminator: "")
        for i in 0..<dataBits.bitCount {
            print(dataBits.leastSignificantBits(atBitPosition: i, bitCount: 1), terminator: "")
        }
        print()

        // Expected: B/S (5 bits, code 31) + length (5 bits, value 5) + 5*8 bits = 50 bits
        print("\nExpected:")
        print("  B/S: 11111 (5 bits, code 31)")
        print("  Length: 00101 (5 bits, value 5)")
        print("  Bytes: 0x01=00000001, 0x02=00000010, etc.")
        print("  Total: 50 bits")

        let config = try pickConfiguration(
            forPayloadBitCount: dataBits.bitCount,
            errorCorrectionPercentage: 23,
            preferCompact: true
        )
        print("\nConfiguration:")
        print("  compact: \(config.isCompact)")
        print("  layers: \(config.layerCount)")
        print("  wordSize: \(config.wordSizeInBits)")
        print("  dataCodewords: \(config.dataCodewordCount)")
        print("  parityCodewords: \(config.parityCodewordCount)")

        let codewords = dataBits.makeCodewords(codewordBitWidth: config.wordSizeInBits)
        print("\nCodewords (with stuff bits): \(codewords)")

        let gf = GaloisField(wordSizeInBits: config.wordSizeInBits, primitivePolynomial: config.primitivePolynomial)
        let rs = ReedSolomonEncoder(field: gf, startExponent: config.rsStartExponent)

        var paddedCodewords = codewords
        let filler = BitBuffer.makeFillerCodeword(bitWidth: config.wordSizeInBits)
        while paddedCodewords.count < config.dataCodewordCount {
            paddedCodewords.append(filler)
        }
        print("Padded codewords: \(paddedCodewords)")

        let allCodewords = rs.appendingParity(to: paddedCodewords, parityCodewordCount: config.parityCodewordCount)
        print("All codewords (with RS parity): \(allCodewords)")

        // Check mode message
        let builder = AztecMatrixBuilder(configuration: config)
        let modeMessage = builder.encodeModeMessage()
        print("\nMode message (\(modeMessage.bitCount) bits): ", terminator: "")
        for i in 0..<modeMessage.bitCount {
            print(modeMessage.leastSignificantBits(atBitPosition: i, bitCount: 1), terminator: "")
            if (i + 1) % 4 == 0 { print(" ", terminator: "") }
        }
        print()
        print("Expected: (layers-1)=0 (2 bits), (data-1)=9 (6 bits) = 00001001, then RS parity")

        let symbol = try AztecEncoder.encode(bytes)
        print("\nAztecLib matrix (\(symbol.size)x\(symbol.size)):")
        for y in 0..<symbol.size {
            var row = ""
            for x in 0..<symbol.size {
                row += symbol[x: x, y: y] ? "1" : "0"
            }
            print(row)
        }

        #expect(symbol.size == 15, "Expected 15x15 symbol for 5 bytes")
    }

    @Test
    func trace_at_encoding() throws {
        // Test just "@" encoding - should use Mixed mode
        let input = "A@"
        print("\n========== A@ ENCODING TRACE ==========")
        print("Input: \"\(input)\"")

        let dataBits = AztecDataEncoder.encode(input)
        print("Data bits count: \(dataBits.bitCount)")
        print("Data bits: ", terminator: "")
        for i in 0..<dataBits.bitCount {
            print(dataBits.leastSignificantBits(atBitPosition: i, bitCount: 1), terminator: "")
        }
        print()

        // A in Upper = code 2 (5 bits: 00010)
        // M/L from Upper = code 29 (5 bits: 11101)
        // @ in Mixed = code 20 (5 bits: 10100)
        // Total: 15 bits
        print("\nExpected:")
        print("  A: code 2 = 00010 (5 bits)")
        print("  M/L: code 29 = 11101 (5 bits)")
        print("  @: code 20 = 10100 (5 bits)")
        print("  Total: 15 bits")

        #expect(dataBits.bitCount == 15)
    }
}
