//
//  AztecDataEncodingDiagnosticTests.swift
//  AztecLib
//
//  Diagnostic tests to trace through the data encoding pipeline.
//

import Testing
import Foundation
@testable import AztecLib

@Suite("Aztec Data Encoding Diagnostics")
struct AztecDataEncodingDiagnosticTests {

    @Test("Trace encoding of 'A'")
    func traceEncodingOfA() throws {
        // Step 1: High-level encoding
        let dataBits = AztecDataEncoder.encode("A")
        print("\n=== Encoding 'A' ===")
        print("Data bits count: \(dataBits.bitCount)")
        print("Data bits (binary): ", terminator: "")
        for i in 0..<dataBits.bitCount {
            let bit = dataBits.leastSignificantBits(atBitPosition: i, bitCount: 1)
            print(bit, terminator: "")
        }
        print()

        // Step 2: Codeword packing with stuff bits (6-bit codewords for compact L1)
        let codewords = dataBits.makeCodewords(codewordBitWidth: 6)
        print("\nCodewords (6-bit with stuff bits):")
        for (i, cw) in codewords.enumerated() {
            let binary = String(cw, radix: 2)
            let padded = String(repeating: "0", count: 6 - binary.count) + binary
            print("  [\(i)] = \(cw) (0b\(padded))")
        }

        // Step 3: Configuration selection
        let options = AztecEncoder.Options(errorCorrectionPercentage: 23, preferCompact: true)
        let result = try AztecEncoder.encodeWithDetails("A", options: options)
        let config = result.configuration

        print("\nConfiguration:")
        print("  isCompact: \(config.isCompact)")
        print("  layerCount: \(config.layerCount)")
        print("  wordSizeInBits: \(config.wordSizeInBits)")
        print("  totalCodewordCount: \(config.totalCodewordCount)")
        print("  dataCodewordCount: \(config.dataCodewordCount)")
        print("  parityCodewordCount: \(config.parityCodewordCount)")

        // Step 4: RS encoding
        let gf = GaloisField(wordSizeInBits: config.wordSizeInBits, primitivePolynomial: config.primitivePolynomial)
        let rsEncoder = ReedSolomonEncoder(field: gf, startExponent: config.rsStartExponent)

        // Pad to dataCodewordCount with filler
        var dataCodewords = codewords
        let filler = BitBuffer.makeFillerCodeword(bitWidth: config.wordSizeInBits)
        while dataCodewords.count < config.dataCodewordCount {
            dataCodewords.append(filler)
        }

        let allCodewords = rsEncoder.appendingParity(to: dataCodewords, parityCodewordCount: config.parityCodewordCount)

        print("\nAll codewords (data + parity):")
        for (i, cw) in allCodewords.enumerated() {
            let isData = i < config.dataCodewordCount
            let label = isData ? "DATA" : "PARITY"
            let binary = String(cw, radix: 2)
            let padded = String(repeating: "0", count: config.wordSizeInBits - binary.count) + binary
            print("  [\(i)] \(label) = \(cw) (0b\(padded))")
        }

        // Step 5: Mode message
        let builder = AztecMatrixBuilder(configuration: config)
        let modeMessage = builder.encodeModeMessage()
        print("\nMode message (\(modeMessage.bitCount) bits):")
        print("  ", terminator: "")
        for i in 0..<modeMessage.bitCount {
            let bit = modeMessage.leastSignificantBits(atBitPosition: i, bitCount: 1)
            print(bit, terminator: "")
        }
        print()

        // Step 6: Symbol
        let symbol = result.symbol
        print("\nSymbol size: \(symbol.size)x\(symbol.size)")
        print("\nSymbol matrix:")
        for y in 0..<symbol.size {
            for x in 0..<symbol.size {
                print(symbol[x: x, y: y] ? "█" : "░", terminator: "")
            }
            print()
        }
    }

    @Test("Verify codeword value for 'A'")
    func verifyCodewordForA() {
        // Upper mode, code for 'A' = 2
        // With MSB-first encoding: binary 00010 outputs as 0,0,0,1,0
        // When read as LSB-first value: 0*1 + 0*2 + 0*4 + 1*8 + 0*16 = 8

        let dataBits = AztecDataEncoder.encode("A")
        #expect(dataBits.bitCount == 5)

        // Check the bits when read LSB-first give value 8 (MSB-first 00010 = 2)
        let value = dataBits.leastSignificantBits(atBitPosition: 0, bitCount: 5)
        #expect(value == 8, "Expected bits for 'A' = 8 (00010 read LSB-first), got \(value)")

        // makeCodewords reads 6 bits: 00010 + 1 (pad) = 000101 = 5 (MSB-first)
        let codewords = dataBits.makeCodewords(codewordBitWidth: 6)
        #expect(codewords.count == 1, "Expected 1 codeword, got \(codewords.count)")
        #expect(codewords[0] == 5, "Expected codeword 5, got \(codewords[0])")
    }

    @Test("Compare spiral path with expected positions")
    func compareSpiralPath() throws {
        // For compact L1 (15x15), center = 7
        // Data starts at radius 6 from center (just outside mode message ring at radius 5)

        let config = AztecConfiguration(
            isCompact: true,
            layerCount: 1,
            wordSizeInBits: 6,
            totalCodewordCount: 17,
            dataCodewordCount: 1,
            parityCodewordCount: 16,
            primitivePolynomial: 0x43,
            rsStartExponent: 1
        )

        let builder = AztecMatrixBuilder(configuration: config)
        let size = builder.symbolSize
        let center = size / 2

        print("\n=== Data Path Analysis ===")
        print("Symbol size: \(size)x\(size)")
        print("Center: (\(center), \(center))")

        // Build a test matrix with just the data path numbered
        var pathMatrix = [[String]](repeating: [String](repeating: ".", count: size), count: size)

        // Mark the finder pattern
        for y in (center - 4)...(center + 4) {
            for x in (center - 4)...(center + 4) {
                pathMatrix[y][x] = "F"
            }
        }

        // Mark mode message ring
        for i in 0..<7 {
            let offset = center - 3 + i
            pathMatrix[center - 5][offset] = "M"
            pathMatrix[center + 5][offset] = "M"
            pathMatrix[offset][center - 5] = "M"
            pathMatrix[offset][center + 5] = "M"
        }

        // Build the actual data path
        let modeMessage = builder.encodeModeMessage()
        let gf = GaloisField(wordSizeInBits: 6, primitivePolynomial: 0x43)
        let rs = ReedSolomonEncoder(field: gf, startExponent: 1)
        let dataCodewords: [UInt16] = [4]
        let allCodewords = rs.appendingParity(to: dataCodewords, parityCodewordCount: 16)

        let matrix = try builder.buildMatrix(dataCodewords: allCodewords, modeMessageBits: modeMessage)

        // Print the path positions for first 12 positions (2 codewords worth)
        print("\nFirst 12 data path positions (2 codewords):")

        // To get the path, we need to trace where bits differ from the base pattern
        // Actually, let's just print the full matrix and compare with a reference
        print("\nGenerated matrix:")
        for y in 0..<size {
            for x in 0..<size {
                let bitIndex = y * size + x
                let bit = matrix.leastSignificantBits(atBitPosition: bitIndex, bitCount: 1) != 0
                print(bit ? "█" : "░", terminator: "")
            }
            print(" | y=\(y)")
        }
    }
}
