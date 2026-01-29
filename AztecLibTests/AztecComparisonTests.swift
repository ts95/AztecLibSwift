//
//  AztecComparisonTests.swift
//  AztecLibTests
//
//  Comparison tests between AztecLib and native CIFilter aztecCodeGenerator.
//

import Foundation
import Testing
import CoreImage
@testable import AztecLib

struct AztecComparisonTests {

    // MARK: - Native CIFilter Reference

    /// Generates an Aztec code using CIFilter and extracts its modules.
    private func generateNativeAztec(_ string: String) -> (modules: [[Bool]], size: Int)? {
        guard let filter = CIFilter(name: "CIAztecCodeGenerator") else {
            return nil
        }

        filter.setValue(string.data(using: .isoLatin1), forKey: "inputMessage")
        filter.setValue(23.0, forKey: "inputCorrectionLevel") // Match AztecLib default
        filter.setValue(0.0, forKey: "inputCompactStyle") // 0 = auto, not forcing compact

        guard let output = filter.outputImage else {
            return nil
        }

        let context = CIContext()
        let extent = output.extent
        let size = Int(extent.width)

        // Create bitmap context to read pixels
        var pixelData = [UInt8](repeating: 0, count: size * size * 4)
        context.render(output, toBitmap: &pixelData, rowBytes: size * 4, bounds: extent, format: .RGBA8, colorSpace: CGColorSpaceCreateDeviceRGB())

        // Extract modules (black = true, white = false)
        var modules: [[Bool]] = Array(repeating: Array(repeating: false, count: size), count: size)
        for y in 0..<size {
            for x in 0..<size {
                let offset = (y * size + x) * 4
                // Check if black (R=0, or close to it)
                modules[y][x] = pixelData[offset] < 128
            }
        }

        return (modules, size)
    }

    /// Extracts modules from an AztecSymbol.
    private func extractModules(_ symbol: AztecSymbol) -> [[Bool]] {
        var modules: [[Bool]] = Array(repeating: Array(repeating: false, count: symbol.size), count: symbol.size)
        for y in 0..<symbol.size {
            for x in 0..<symbol.size {
                modules[y][x] = symbol[x: x, y: y]
            }
        }
        return modules
    }

    /// Prints a module grid as ASCII art.
    private func printModules(_ modules: [[Bool]], label: String, highlight: Set<String> = []) {
        print("\n=== \(label) (\(modules.count)x\(modules.count)) ===")
        for y in 0..<modules.count {
            var row = ""
            for x in 0..<modules[y].count {
                let key = "\(x),\(y)"
                if highlight.contains(key) {
                    row += modules[y][x] ? "▓▓" : "░░"
                } else {
                    row += modules[y][x] ? "██" : "  "
                }
            }
            print(row)
        }
    }

    /// Compares two module grids and returns differences.
    private func compareModules(_ a: [[Bool]], _ b: [[Bool]]) -> [(x: Int, y: Int, aValue: Bool, bValue: Bool)] {
        var differences: [(x: Int, y: Int, aValue: Bool, bValue: Bool)] = []
        let size = min(a.count, b.count)
        for y in 0..<size {
            for x in 0..<size {
                if a[y][x] != b[y][x] {
                    differences.append((x: x, y: y, aValue: a[y][x], bValue: b[y][x]))
                }
            }
        }
        return differences
    }

    /// Extracts a region from a module grid.
    private func extractRegion(_ modules: [[Bool]], centerX: Int, centerY: Int, radius: Int) -> [[Bool]] {
        var region: [[Bool]] = []
        for y in (centerY - radius)...(centerY + radius) {
            var row: [Bool] = []
            for x in (centerX - radius)...(centerX + radius) {
                if y >= 0 && y < modules.count && x >= 0 && x < modules[y].count {
                    row.append(modules[y][x])
                } else {
                    row.append(false)
                }
            }
            region.append(row)
        }
        return region
    }

    // MARK: - Comparison Tests

    @Test
    func compare_forcing_full_symbol() throws {
        let input = "Hello"

        print("\n" + String(repeating: "=", count: 60))
        print("FORCING FULL SYMBOL FOR: \"\(input)\"")
        print(String(repeating: "=", count: 60))

        // Force AztecLib to use a full (non-compact) symbol
        let options = AztecEncoder.Options(preferCompact: false)
        let aztecSymbol = try AztecEncoder.encode(input, options: options)
        let aztecDetails = try AztecEncoder.encodeWithDetails(input, options: options)
        let aztecModules = extractModules(aztecSymbol)

        print("\nAztecLib configuration (forced full):")
        print("  Compact: \(aztecDetails.configuration.isCompact)")
        print("  Layers: \(aztecDetails.configuration.layerCount)")
        print("  Word size: \(aztecDetails.configuration.wordSizeInBits) bits")
        print("  Symbol size: \(aztecSymbol.size)x\(aztecSymbol.size)")

        guard let (nativeModules, nativeSize) = generateNativeAztec(input) else {
            print("ERROR: Could not generate native Aztec code")
            return
        }

        print("\nNative CIFilter:")
        print("  Symbol size: \(nativeSize)x\(nativeSize)")

        printModules(aztecModules, label: "AztecLib Output (Full)")
        printModules(nativeModules, label: "Native CIFilter Output")

        if aztecSymbol.size == nativeSize {
            let differences = compareModules(aztecModules, nativeModules)
            print("\n📊 COMPARISON RESULTS:")
            print("   Total modules: \(aztecSymbol.size * aztecSymbol.size)")
            print("   Differences: \(differences.count)")
            print("   Match rate: \(String(format: "%.1f", Double(aztecSymbol.size * aztecSymbol.size - differences.count) / Double(aztecSymbol.size * aztecSymbol.size) * 100))%")

            if differences.count > 0 {
                // Group differences by region
                let center = aztecSymbol.size / 2
                var finderDiffs = 0
                var modeMsgDiffs = 0
                var dataDiffs = 0
                for diff in differences {
                    let dist = max(abs(diff.x - center), abs(diff.y - center))
                    if dist <= 6 {
                        finderDiffs += 1
                    } else if dist == 7 {
                        modeMsgDiffs += 1
                    } else {
                        dataDiffs += 1
                    }
                }
                print("\n   Differences by region:")
                print("   - Finder pattern (center±6): \(finderDiffs)")
                print("   - Mode message ring (±7): \(modeMsgDiffs)")
                print("   - Data layers (>7): \(dataDiffs)")
            }
        } else {
            print("\n⚠️  SIZE STILL MISMATCHED: AztecLib=\(aztecSymbol.size), Native=\(nativeSize)")
        }
    }

    @Test
    func compare_simple_string() throws {
        let input = "Hello"

        print("\n" + String(repeating: "=", count: 60))
        print("COMPARING AZTEC CODES FOR: \"\(input)\"")
        print(String(repeating: "=", count: 60))

        // Generate with AztecLib
        let aztecSymbol = try AztecEncoder.encode(input)
        let aztecDetails = try AztecEncoder.encodeWithDetails(input)
        let aztecModules = extractModules(aztecSymbol)

        print("\nAztecLib configuration:")
        print("  Compact: \(aztecDetails.configuration.isCompact)")
        print("  Layers: \(aztecDetails.configuration.layerCount)")
        print("  Word size: \(aztecDetails.configuration.wordSizeInBits) bits")
        print("  Data codewords: \(aztecDetails.configuration.dataCodewordCount)")
        print("  Parity codewords: \(aztecDetails.configuration.parityCodewordCount)")
        print("  Symbol size: \(aztecSymbol.size)x\(aztecSymbol.size)")

        // Generate with native CIFilter
        guard let (nativeModules, nativeSize) = generateNativeAztec(input) else {
            print("ERROR: Could not generate native Aztec code")
            return
        }

        print("\nNative CIFilter:")
        print("  Symbol size: \(nativeSize)x\(nativeSize)")

        // Print both side by side
        printModules(aztecModules, label: "AztecLib Output")
        printModules(nativeModules, label: "Native CIFilter Output")

        // Compare sizes
        if aztecSymbol.size != nativeSize {
            print("\n⚠️  SIZE MISMATCH: AztecLib=\(aztecSymbol.size), Native=\(nativeSize)")
            print("    This may indicate a configuration selection issue.")
        }

        // If sizes match, compare modules
        if aztecSymbol.size == nativeSize {
            let differences = compareModules(aztecModules, nativeModules)
            print("\n📊 COMPARISON RESULTS:")
            print("   Total modules: \(aztecSymbol.size * aztecSymbol.size)")
            print("   Differences: \(differences.count)")
            print("   Match rate: \(String(format: "%.1f", Double(aztecSymbol.size * aztecSymbol.size - differences.count) / Double(aztecSymbol.size * aztecSymbol.size) * 100))%")

            if differences.count > 0 && differences.count <= 50 {
                print("\nFirst \(min(differences.count, 20)) differences:")
                for diff in differences.prefix(20) {
                    print("   (\(diff.x), \(diff.y)): AztecLib=\(diff.aValue ? "█" : "·") Native=\(diff.bValue ? "█" : "·")")
                }
            }
        }
    }

    @Test
    func compare_finder_pattern_only() throws {
        let input = "A"

        print("\n" + String(repeating: "=", count: 60))
        print("FINDER PATTERN COMPARISON FOR: \"\(input)\"")
        print(String(repeating: "=", count: 60))

        let aztecSymbol = try AztecEncoder.encode(input)
        let aztecModules = extractModules(aztecSymbol)

        guard let (nativeModules, _) = generateNativeAztec(input) else {
            print("ERROR: Could not generate native Aztec code")
            return
        }

        // Extract and compare finder regions only
        let aztecCenter = aztecSymbol.size / 2
        let nativeCenter = nativeModules.count / 2

        let aztecFinder = extractRegion(aztecModules, centerX: aztecCenter, centerY: aztecCenter, radius: 6)
        let nativeFinder = extractRegion(nativeModules, centerX: nativeCenter, centerY: nativeCenter, radius: 6)

        printModules(aztecFinder, label: "AztecLib Finder (center±6)")
        printModules(nativeFinder, label: "Native Finder (center±6)")

        // Check finder rings (center, outward)
        print("\nFinder ring analysis (horizontal cross-section through center):")
        print("Radius | AztecLib | Native | Expected")
        print("-------|----------|--------|----------")
        for r in 0...6 {
            let aztecBit = aztecModules[aztecCenter][aztecCenter + r]
            let nativeBit = nativeModules[nativeCenter][nativeCenter + r]
            let expected = r <= 4 && r % 2 == 0
            let aztecOK = aztecBit == expected ? "✓" : "✗"
            let nativeOK = nativeBit == expected ? "✓" : "✗"
            print("   \(r)   |    \(aztecBit ? "█" : "·") \(aztecOK)   |   \(nativeBit ? "█" : "·") \(nativeOK)   |    \(expected ? "█" : "·")")
        }
    }

    @Test
    func debug_byte_layout() throws {
        let input = "A"

        print("\n" + String(repeating: "=", count: 60))
        print("BYTE LAYOUT DEBUGGING FOR: \"\(input)\"")
        print(String(repeating: "=", count: 60))

        let symbol = try AztecEncoder.encode(input)

        print("\nSymbol properties:")
        print("  Size: \(symbol.size)")
        print("  Row stride: \(symbol.rowStride) bytes")
        print("  Total bytes: \(symbol.bytes.count)")

        print("\nRaw byte dump (first 5 rows):")
        for row in 0..<min(5, symbol.size) {
            let start = row * symbol.rowStride
            let end = start + symbol.rowStride
            let rowBytes = Array(symbol.bytes[start..<end])

            var binaryStr = ""
            for byte in rowBytes {
                binaryStr += String(byte, radix: 2).leftPadding(toLength: 8, withPad: "0") + " "
            }
            print("  Row \(row): \(binaryStr)")
        }

        print("\nModule access vs raw byte comparison (row 0):")
        let y = 0
        var subscriptRow = ""
        var rawRow = ""
        for x in 0..<min(16, symbol.size) {
            subscriptRow += symbol[x: x, y: y] ? "1" : "0"

            // Manual byte extraction
            let byteOffset = y * symbol.rowStride + (x / 8)
            let bitOffset = x % 8
            let rawBit = (symbol.bytes[byteOffset] >> bitOffset) & 1
            rawRow += rawBit == 1 ? "1" : "0"
        }
        print("  Subscript access: \(subscriptRow)")
        print("  Raw byte (LSB):   \(rawRow)")
    }

    @Test
    func debug_export_bit_ordering() throws {
        // Create a minimal test pattern to verify bit ordering
        print("\n" + String(repeating: "=", count: 60))
        print("EXPORT BIT ORDERING TEST")
        print(String(repeating: "=", count: 60))

        // Create a simple pattern: first row alternating, to test bit packing
        var testBuffer = BitBuffer()
        let testSize = 8
        for y in 0..<testSize {
            for x in 0..<testSize {
                // Create a known pattern: checkerboard
                let bit = (x + y) % 2 == 0
                testBuffer.appendLeastSignificantBits(bit ? 1 : 0, bitCount: 1)
            }
        }

        let exported = testBuffer.makeSymbolExport(matrixSize: testSize, rowOrderMostSignificantBitFirst: false)

        print("\nTest pattern (8x8 checkerboard):")
        print("  Expected row 0: 10101010")
        print("  Expected row 1: 01010101")

        print("\nExported bytes (LSB-first):")
        for row in 0..<testSize {
            let byte = exported.bytes[row]
            print("  Row \(row): \(String(byte, radix: 2).leftPadding(toLength: 8, withPad: "0")) = 0x\(String(byte, radix: 16).leftPadding(toLength: 2, withPad: "0"))")
        }

        print("\nDecoded via subscript:")
        for row in 0..<testSize {
            var rowStr = ""
            for x in 0..<testSize {
                rowStr += exported[x: x, y: row] ? "1" : "0"
            }
            print("  Row \(row): \(rowStr)")
        }
    }

    @Test
    func trace_full_pipeline() throws {
        let input = "Hi"

        print("\n" + String(repeating: "=", count: 60))
        print("FULL PIPELINE TRACE FOR: \"\(input)\"")
        print(String(repeating: "=", count: 60))

        // Step 1: Data encoding
        let dataBits = AztecDataEncoder.encode(input)
        print("\n1️⃣ DATA ENCODING")
        print("   Input: \"\(input)\"")
        print("   Bit count: \(dataBits.bitCount)")
        print("   Bits: ", terminator: "")
        for i in 0..<dataBits.bitCount {
            print(dataBits.leastSignificantBits(atBitPosition: i, bitCount: 1), terminator: "")
        }
        print("")

        // Step 2: Configuration selection
        let config = try pickConfiguration(
            forPayloadBitCount: dataBits.bitCount,
            errorCorrectionPercentage: 23,
            preferCompact: true
        )
        print("\n2️⃣ CONFIGURATION")
        print("   Compact: \(config.isCompact)")
        print("   Layers: \(config.layerCount)")
        print("   Word size: \(config.wordSizeInBits) bits")
        print("   Total codewords: \(config.totalCodewordCount)")
        print("   Data codewords: \(config.dataCodewordCount)")
        print("   Parity codewords: \(config.parityCodewordCount)")

        // Step 3: Codeword packing
        let codewords = dataBits.makeCodewords(codewordBitWidth: config.wordSizeInBits)
        print("\n3️⃣ CODEWORD PACKING")
        print("   Packed codewords: \(codewords.count)")
        for (i, cw) in codewords.enumerated() {
            print("   [\(i)]: \(cw) = \(String(cw, radix: 2).leftPadding(toLength: config.wordSizeInBits, withPad: "0"))")
        }

        // Step 4: RS encoding
        let gf = GaloisField(wordSizeInBits: config.wordSizeInBits, primitivePolynomial: config.primitivePolynomial)
        let rs = ReedSolomonEncoder(field: gf, startExponent: config.rsStartExponent)
        var paddedCodewords = codewords
        while paddedCodewords.count < config.dataCodewordCount {
            paddedCodewords.append(0)
        }
        let withParity = rs.appendingParity(to: paddedCodewords, parityCodewordCount: config.parityCodewordCount)
        print("\n4️⃣ REED-SOLOMON ENCODING")
        print("   Data codewords: \(Array(withParity.prefix(config.dataCodewordCount)))")
        print("   Parity codewords: \(Array(withParity.suffix(config.parityCodewordCount)))")

        // Step 5: Mode message
        let builder = AztecMatrixBuilder(configuration: config)
        let modeMessage = builder.encodeModeMessage()
        print("\n5️⃣ MODE MESSAGE")
        print("   Bit count: \(modeMessage.bitCount)")
        print("   Bits: ", terminator: "")
        for i in 0..<modeMessage.bitCount {
            print(modeMessage.leastSignificantBits(atBitPosition: i, bitCount: 1), terminator: "")
            if (i + 1) % 4 == 0 { print(" ", terminator: "") }
        }
        print("")

        // Step 6: Matrix
        print("\n6️⃣ MATRIX BUILDING")
        print("   Symbol size: \(builder.symbolSize)x\(builder.symbolSize)")

        // Final output
        let symbol = try AztecEncoder.encode(input)
        let modules = extractModules(symbol)
        printModules(modules, label: "Final Output")

        // Compare with native
        if let (nativeModules, _) = generateNativeAztec(input) {
            printModules(nativeModules, label: "Native Reference")

            let differences = compareModules(modules, nativeModules)
            print("\n📊 Match rate: \(String(format: "%.1f", Double(symbol.size * symbol.size - differences.count) / Double(symbol.size * symbol.size) * 100))% (\(differences.count) differences)")
        }
    }
}

// MARK: - String Extension

extension String {
    func leftPadding(toLength length: Int, withPad character: Character) -> String {
        if self.count >= length {
            return String(self.suffix(length))
        }
        return String(repeating: character, count: length - self.count) + self
    }
}
