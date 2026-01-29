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

        let input = "Hello"
        let options = AztecEncoder.Options(preferCompact: true)
        let details = try AztecEncoder.encodeWithDetails(input, options: options)
        let config = details.configuration

        let dataBits = AztecDataEncoder.encode(input)
        print("Data bits count: \(dataBits.bitCount)")

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

        // Verify RS syndromes
        print("\nRS Verification:")
        var syndromeOK = true
        for i in 0..<config.parityCodewordCount {
            var syndrome: UInt16 = 0
            for (j, cw) in allCodewords.enumerated() {
                let power = (config.rsStartExponent + i) * j
                let alpha_power = gf.exp[power % (gf.exp.count / 2)]
                syndrome = gf.add(syndrome, gf.multiply(cw, alpha_power))
            }
            if syndrome != 0 {
                print("  Syndrome[\(i)] = \(syndrome) (should be 0) ✗")
                syndromeOK = false
            }
        }
        if syndromeOK {
            print("  All syndromes are zero ✓")
        }

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

    @Test
    func full_trace_punct_encoding() throws {
        // Full pipeline trace for "ABC123+/xyz"
        let input = "ABC123+/xyz"
        print("\n========== FULL PIPELINE TRACE ==========")
        print("Input: \"\(input)\"")

        // Use the actual encoder to get all details
        let options = AztecEncoder.Options(preferCompact: true)
        let details = try AztecEncoder.encodeWithDetails(input, options: options)
        let symbol = details.symbol
        let config = details.configuration

        print("\n1. Configuration:")
        print("  compact: \(config.isCompact)")
        print("  layers: \(config.layerCount)")
        print("  wordSize: \(config.wordSizeInBits)")
        print("  dataCodewords: \(config.dataCodewordCount)")
        print("  parityCodewords: \(config.parityCodewordCount)")
        print("  totalCodewords: \(config.totalCodewordCount)")
        print("  symbolSize: \(symbol.size)x\(symbol.size)")

        // Trace mode message
        let builder = AztecMatrixBuilder(configuration: config)
        let modeMsg = builder.encodeModeMessage()
        print("\n2. Mode message (\(modeMsg.bitCount) bits):")
        var modeBits = ""
        for i in 0..<modeMsg.bitCount {
            modeBits += modeMsg.leastSignificantBits(atBitPosition: i, bitCount: 1) != 0 ? "1" : "0"
        }
        print("  Bits: \(modeBits)")
        // Decode mode message
        let layers = (modeMsg.leastSignificantBits(atBitPosition: 0, bitCount: 2) + 1)
        let dataWords = modeMsg.leastSignificantBits(atBitPosition: 2, bitCount: 6) + 1
        print("  Decoded: layers=\(layers), dataWords=\(dataWords)")
        print("  Expected: layers=\(config.layerCount), dataWords=\(config.dataCodewordCount)")

        // Get the actual data bits
        let dataBits = AztecDataEncoder.encode(input)
        print("\n3. Data encoding:")
        print("  Data bits: \(dataBits.bitCount)")

        // Get the packed codewords
        let packedCodewords = dataBits.makeCodewords(codewordBitWidth: config.wordSizeInBits)
        print("\n4. Codewords (before RS):")
        print("  Count: \(packedCodewords.count)")
        for (i, cw) in packedCodewords.enumerated() {
            let binary = String(cw, radix: 2)
            let padded = String(repeating: "0", count: config.wordSizeInBits - binary.count) + binary
            print("  [\(i)] \(cw) = \(padded)")
        }

        // RS encoding
        let gf = GaloisField(wordSizeInBits: config.wordSizeInBits, primitivePolynomial: config.primitivePolynomial)
        let rs = ReedSolomonEncoder(field: gf, startExponent: config.rsStartExponent)
        let allCodewords = rs.appendingParity(to: packedCodewords, parityCodewordCount: config.parityCodewordCount)
        print("\n5. All codewords (with RS parity):")
        print("  Count: \(allCodewords.count)")
        for (i, cw) in allCodewords.enumerated() {
            let binary = String(cw, radix: 2)
            let padded = String(repeating: "0", count: config.wordSizeInBits - binary.count) + binary
            let label = i < packedCodewords.count ? "data" : "parity"
            print("  [\(i)] \(cw) = \(padded) (\(label))")
        }

        // Print symbol
        print("\n6. Generated symbol:")
        for y in 0..<symbol.size {
            var row = "  "
            for x in 0..<symbol.size {
                row += symbol[x: x, y: y] ? "█" : "░"
            }
            print(row)
        }

        // Extract first few bits from symbol using ZXing's inverse algorithm
        print("\n7. Verify data placement:")
        let size = symbol.size
        let numLayers = config.layerCount
        let baseMatrixSize = 11 + numLayers * 4  // 15 for layer 1

        // Build alignment map (identity for compact)
        let alignmentMap = Array(0..<size)

        // Extract first bits from layer 0 TOP side
        print("  Extracting first 12 bits from TOP side of layer 0:")
        let rowSize = numLayers * 4 + 9  // 13 for layer 1
        var extractedBits: [Bool] = []
        for j in 0..<6 {  // First 6 positions
            for k in 0..<2 {
                let x = alignmentMap[0 * 2 + k]
                let y = alignmentMap[0 * 2 + j]
                let bit = symbol[x: x, y: y]
                extractedBits.append(bit)
                print("    j=\(j) k=\(k): (\(x),\(y)) = \(bit ? "1" : "0")")
            }
        }

        // Compare with expected message bits
        print("\n  Expected message bits (first 12):")
        var messageBits: [Bool] = []
        // startPad zeros
        let totalBitsInLayer = ((config.isCompact ? 88 : 112) + 16 * numLayers) * numLayers
        let startPad = totalBitsInLayer % config.wordSizeInBits
        for _ in 0..<startPad {
            messageBits.append(false)
        }
        // Codeword bits MSB first
        for cw in allCodewords {
            for bitPos in stride(from: config.wordSizeInBits - 1, through: 0, by: -1) {
                messageBits.append(((cw >> bitPos) & 1) != 0)
            }
        }
        for i in 0..<12 {
            print("    [\(i)]: \(messageBits[i] ? "1" : "0")")
        }

        // Compare
        print("\n  Comparison:")
        var matches = 0
        for i in 0..<min(extractedBits.count, 12) {
            let match = extractedBits[i] == messageBits[i]
            print("    [\(i)]: extracted=\(extractedBits[i] ? "1" : "0"), expected=\(messageBits[i] ? "1" : "0") \(match ? "✓" : "✗")")
            if match { matches += 1 }
        }
        print("  Matches: \(matches)/12")

        #expect(symbol.size > 0)
    }

    @Test
    func trace_punct_encoding() throws {
        // Detailed trace of "ABC123+/xyz" encoding
        let input = "ABC123+/xyz"
        print("\n========== PUNCT ENCODING TRACE ==========")
        print("Input: \"\(input)\"")

        // Show what modes each character should use
        print("\nCharacter modes:")
        for char in input {
            var modes: [(mode: AztecMode, code: Int)] = []
            for mode in [AztecMode.upper, .lower, .mixed, .punct, .digit] {
                if let code = AztecModeTables.code(for: char, in: mode) {
                    modes.append((mode, code))
                }
            }
            print("  '\(char)': \(modes.map { "\($0.mode): \($0.code)" }.joined(separator: ", "))")
        }

        // Encode
        let dataBits = AztecDataEncoder.encode(input)
        print("\nData bits count: \(dataBits.bitCount)")

        // Print bits with groupings
        print("Data bits (binary):")
        var bitString = ""
        for i in 0..<dataBits.bitCount {
            let bit = dataBits.leastSignificantBits(atBitPosition: i, bitCount: 1)
            bitString += bit != 0 ? "1" : "0"
        }
        print(bitString)

        // Expected encoding:
        // A=2(5b), B=3(5b), C=4(5b): 00010 00011 00100 = 15 bits
        // D/L=30(5b): 11110 = 5 bits
        // 1=3(4b), 2=4(4b), 3=5(4b): 0011 0100 0101 = 12 bits
        // P/L=0(4b): 0000 = 4 bits
        // +=16(5b): 10000 = 5 bits
        // /=20(5b): 10100 = 5 bits
        // Then Lower: U/L=31(5b), L/L=28(5b): 11111 11100 = 10 bits
        // x=25(5b), y=26(5b), z=27(5b): 11001 11010 11011 = 15 bits
        // Total: 15+5+12+4+5+5+10+15 = 71 bits

        print("\nExpected encoding breakdown:")
        print("  A=2, B=3, C=4 in Upper (5-bit each): 00010 00011 00100 (15 bits)")
        print("  D/L from Upper to Digit = 30: 11110 (5 bits)")
        print("  1=3, 2=4, 3=5 in Digit (4-bit each): 0011 0100 0101 (12 bits)")
        print("  P/L from Digit to Punct = 0: 0000 (4 bits)")
        print("  +=16 in Punct (5-bit): 10000 (5 bits)")
        print("  /=20 in Punct (5-bit): 10100 (5 bits)")
        print("  U/L from Punct to Upper = 31: 11111 (5 bits)")
        print("  L/L from Upper to Lower = 28: 11100 (5 bits)")
        print("  x=25, y=26, z=27 in Lower (5-bit each): 11001 11010 11011 (15 bits)")
        print("  Expected total: 71 bits")

        print("\nActual vs expected:")
        let expected = "000100001100100" + "11110" + "001101000101" + "0000" + "10000" + "10100" + "11111" + "11100" + "110011101011011"
        print("Expected: \(expected) (\(expected.count) bits)")
        print("Actual:   \(bitString) (\(bitString.count) bits)")

        if bitString == expected {
            print("MATCH ✓")
        } else {
            print("MISMATCH ✗")
            // Find first difference
            for (i, (e, a)) in zip(expected, bitString).enumerated() {
                if e != a {
                    print("First difference at bit \(i): expected '\(e)', got '\(a)'")
                    break
                }
            }
        }

        // Now trace through codeword stuffing
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
        print("\nCodewords (with stuff bits): \(codewords.count) codewords")
        for (i, cw) in codewords.enumerated() {
            let binary = String(cw, radix: 2)
            let padded = String(repeating: "0", count: config.wordSizeInBits - binary.count) + binary
            print("  [\(i)] \(cw) = \(padded)")
        }

        // Check if we can reconstruct the original bits from codewords
        print("\nReconstruct from codewords (accounting for stuff bits):")
        let mask = (1 << config.wordSizeInBits) - 2  // e.g., 0b111110 for w=6
        var reconstructed = ""
        for cw in codewords {
            let upperBits = Int(cw) & mask
            let isStuffed = (upperBits == 0) || (upperBits == mask)
            // For stuffed codewords, LSB is the stuff bit - skip it
            // For normal codewords, all bits are data
            let minBit = isStuffed ? 1 : 0
            for bitPos in stride(from: config.wordSizeInBits - 1, through: minBit, by: -1) {
                let bit = (Int(cw) >> bitPos) & 1
                reconstructed += bit == 1 ? "1" : "0"
            }
        }
        print("  Reconstructed: \(reconstructed.prefix(dataBits.bitCount))")
        print("  Original:      \(bitString)")
        if String(reconstructed.prefix(dataBits.bitCount)) == bitString {
            print("  MATCH ✓")
        } else {
            print("  MISMATCH ✗")
            // Find first difference
            let orig = Array(bitString)
            let recon = Array(reconstructed.prefix(dataBits.bitCount))
            for (i, (o, r)) in zip(orig, recon).enumerated() {
                if o != r {
                    print("  First diff at bit \(i): expected '\(o)', got '\(r)'")
                    break
                }
            }
        }

        #expect(dataBits.bitCount > 0)
    }

    @Test
    func diagnose_compact_layer_3() throws {
        // Diagnose why compact layer 3 (23x23) fails
        let input = String(repeating: "A", count: 50)
        print("\n========== COMPACT LAYER 3 DIAGNOSTIC ==========")
        print("Input: 50 'A's")

        // Step 1: Data encoding
        let dataBits = AztecDataEncoder.encode(input)
        print("\n1. Data encoding:")
        print("   Bit count: \(dataBits.bitCount)")
        print("   Expected: 50 * 5 = 250 bits")

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
        print("   Total codewords: \(config.totalCodewordCount)")

        // Verify we get compact layer 3
        #expect(config.isCompact == true)
        #expect(config.layerCount == 3)

        // Step 3: Calculate expected symbol geometry
        let symbolSize = 11 + 4 * config.layerCount  // 23 for layer 3
        let center = symbolSize / 2  // 11
        print("\n3. Symbol geometry:")
        print("   Symbol size: \(symbolSize)x\(symbolSize)")
        print("   Center: \(center)")
        print("   Finder pattern: 9x9 (radius 4)")
        print("   Mode message at radius 5")
        print("   Data starts at radius 6")

        // Step 4: Check data placement coordinates
        let baseMatrixSize = 11 + config.layerCount * 4  // 23
        print("\n4. Data placement analysis:")
        print("   baseMatrixSize: \(baseMatrixSize)")

        // Trace innermost layer placement (layer index 2, closest to center)
        // For compact layer 3, layer i=2 is the innermost
        // rowSize = (3-2)*4 + 9 = 13
        let innerRowSize = (config.layerCount - (config.layerCount - 1)) * 4 + 9
        print("   Innermost layer (i=\(config.layerCount-1)): rowSize = \(innerRowSize)")

        // Calculate x and y coordinates for innermost layer's TOP side
        print("\n   Innermost layer TOP side coordinates:")
        let i = config.layerCount - 1  // 2 for layer 3
        for j in 0..<min(innerRowSize, 5) {
            for k in 0..<2 {
                let x = i * 2 + k  // alignmentMap[i*2+k]
                let y = i * 2 + j  // alignmentMap[i*2+j]
                print("     j=\(j) k=\(k): x=\(x), y=\(y)")
            }
        }

        // Check if any data positions overlap with finder/mode message
        print("\n   Checking for overlaps:")
        print("     Finder area: (\(center-4), \(center-4)) to (\(center+4), \(center+4)) = (7,7) to (15,15)")
        print("     Mode message at y=\(center-5)=\(center-5) and y=\(center+5)=\(center+5)")

        // Check innermost layer positions
        let innermostX = [i*2, i*2+1]  // x=4,5 for layer 3
        let innermostY = (0..<innerRowSize).map { i*2 + $0 }  // y=4 to 4+12=16
        print("     Innermost layer x values: \(innermostX)")
        print("     Innermost layer y values (TOP side): \(innermostY)")
        print("     Does innermost layer TOP overlap finder (y from 7-15)? \(innermostY.contains(where: { $0 >= 7 && $0 <= 15 }) ? "YES" : "NO")")

        // Step 5: Encode and output the symbol
        let symbol = try AztecEncoder.encode(input)
        print("\n5. Generated symbol (\(symbol.size)x\(symbol.size)):")
        for y in 0..<symbol.size {
            var row = "Row \(String(format: "%2d", y)): "
            for x in 0..<symbol.size {
                row += symbol[x: x, y: y] ? "█" : "░"
            }
            print(row)
        }

        // Step 6: Highlight specific areas
        print("\n6. Region analysis:")
        print("   Center row (y=\(center)):")
        var centerRow = "   "
        for x in 0..<symbol.size {
            centerRow += symbol[x: x, y: center] ? "█" : "░"
        }
        print(centerRow)

        // Check the mode message area
        print("\n   Mode message top (y=\(center-5)=\(center-5)):")
        var modeTop = "   "
        for x in 0..<symbol.size {
            modeTop += symbol[x: x, y: center-5] ? "█" : "░"
        }
        print(modeTop)

        #expect(symbol.size == 23)
    }

    @Test
    func diagnose_full_symbol_structure() throws {
        // Diagnose full (non-compact) symbol to find why ZXing can't decode it
        let input = "Test"
        print("\n========== FULL SYMBOL DIAGNOSIS ==========")
        print("Input: \"\(input)\"")

        // Force non-compact mode
        let options = AztecEncoder.Options(preferCompact: false)
        let symbol = try AztecEncoder.encode(input, options: options)
        let details = try AztecEncoder.encodeWithDetails(input, options: options)

        print("\nConfiguration:")
        print("  compact: \(details.configuration.isCompact)")
        print("  layers: \(details.configuration.layerCount)")
        print("  wordSize: \(details.configuration.wordSizeInBits)")
        print("  dataCodewords: \(details.configuration.dataCodewordCount)")
        print("  parityCodewords: \(details.configuration.parityCodewordCount)")
        print("  symbol size: \(symbol.size)x\(symbol.size)")

        let center = symbol.size / 2
        print("\nFinder pattern (center=\(center), radius=6 for full):")
        print("  Expected bulls-eye with 7 concentric rings (radius 0-6)")

        // Print center area
        print("\n  Center 15x15 area:")
        for y in (center - 7)...(center + 7) {
            var row = "  "
            for x in (center - 7)...(center + 7) {
                row += symbol[x: x, y: y] ? "█" : "░"
            }
            print(row)
        }

        // Verify bulls-eye pattern
        print("\n  Verifying bulls-eye (Chebyshev distance from center):")
        var finderOK = true
        for dist in 0...6 {
            // Check modules at this distance
            let expectedBlack = (dist % 2 == 0)
            // Check all modules at exactly this Chebyshev distance
            for y in (center - dist)...(center + dist) {
                for x in (center - dist)...(center + dist) {
                    let actualDist = max(abs(x - center), abs(y - center))
                    if actualDist == dist {
                        let actual = symbol[x: x, y: y]
                        if actual != expectedBlack {
                            print("  ✗ Module (\(x), \(y)) at dist \(dist): expected \(expectedBlack), got \(actual)")
                            finderOK = false
                        }
                    }
                }
            }
        }
        if finderOK {
            print("  Bulls-eye pattern verified ✓")
        }

        // Check orientation marks (distance 7 from center)
        print("\n  Orientation marks (at distance 7 from center):")
        let d = 7
        let orientationMarks = [
            // Top-left corner: 3 marks forming an L
            (center - d, center - d),
            (center - d + 1, center - d),
            (center - d, center - d + 1),
            // Top-right corner: 2 vertical marks
            (center + d, center - d),
            (center + d, center - d + 1),
            // Bottom-right corner: 1 mark
            (center + d, center + d - 1),
        ]
        for (x, y) in orientationMarks {
            let actual = symbol[x: x, y: y]
            print("  (\(x), \(y)): \(actual ? "█" : "░") (should be █)")
        }

        // Check mode message area (at distance 7 from center)
        print("\n  Mode message row (y = center-7 = \(center - 7)):")
        var modeRow = "  "
        for x in 0..<symbol.size {
            modeRow += symbol[x: x, y: center - 7] ? "█" : "░"
        }
        print(modeRow)

        // Print entire symbol
        print("\n  Full symbol:")
        for y in 0..<symbol.size {
            var row = "  Row \(String(format: "%2d", y)): "
            for x in 0..<symbol.size {
                row += symbol[x: x, y: y] ? "█" : "░"
            }
            print(row)
        }

        #expect(details.configuration.isCompact == false)
    }
}
