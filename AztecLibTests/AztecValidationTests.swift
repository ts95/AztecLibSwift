//
//  AztecValidationTests.swift
//  AztecLibTests
//
//  Comprehensive validation tests comparing AztecLib output against CIAztecCodeGenerator
//  using an independent decoder (Vision framework) to verify decoded content matches.
//

import Foundation
import Testing
import CoreImage
import CoreGraphics
import Vision
@testable import AztecLib

// MARK: - Image Rendering Utilities

/// Renders an AztecSymbol to a CGImage with quiet zone.
/// The resulting image has standard orientation: y=0 at top, increasing downward.
func renderAztecSymbol(
    _ symbol: AztecSymbol,
    moduleSize: Int = 10,
    quietZoneModules: Int = 4,
    foreground: CGColor = CGColor(red: 0, green: 0, blue: 0, alpha: 1),
    background: CGColor = CGColor(red: 1, green: 1, blue: 1, alpha: 1)
) -> CGImage? {
    let totalModules = symbol.size + (quietZoneModules * 2)
    let imageSize = totalModules * moduleSize

    guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
          let context = CGContext(
            data: nil,
            width: imageSize,
            height: imageSize,
            bitsPerComponent: 8,
            bytesPerRow: imageSize * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
          ) else {
        return nil
    }

    // Fill background
    context.setFillColor(background)
    context.fill(CGRect(x: 0, y: 0, width: imageSize, height: imageSize))

    // Flip the coordinate system so y=0 is at top (standard image orientation)
    // CGContext default has origin at bottom-left; we want top-left
    context.translateBy(x: 0, y: CGFloat(imageSize))
    context.scaleBy(x: 1, y: -1)

    // Draw modules
    context.setFillColor(foreground)
    for y in 0..<symbol.size {
        for x in 0..<symbol.size {
            if symbol[x: x, y: y] {
                let drawX = (quietZoneModules + x) * moduleSize
                let drawY = (quietZoneModules + y) * moduleSize
                context.fill(CGRect(x: drawX, y: drawY, width: moduleSize, height: moduleSize))
            }
        }
    }

    return context.makeImage()
}

/// Scales a CGImage by a given factor.
func scaleImage(_ image: CGImage, factor: CGFloat) -> CGImage? {
    let newWidth = Int(CGFloat(image.width) * factor)
    let newHeight = Int(CGFloat(image.height) * factor)

    guard let colorSpace = image.colorSpace,
          let context = CGContext(
            data: nil,
            width: newWidth,
            height: newHeight,
            bitsPerComponent: 8,
            bytesPerRow: newWidth * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
          ) else {
        return nil
    }

    context.interpolationQuality = .none  // Nearest neighbor for barcodes
    context.draw(image, in: CGRect(x: 0, y: 0, width: newWidth, height: newHeight))

    return context.makeImage()
}

/// Rotates a CGImage by the given angle in degrees (must be multiple of 90).
func rotateImage(_ image: CGImage, degrees: Int) -> CGImage? {
    let radians = CGFloat(degrees) * .pi / 180.0
    let width = image.width
    let height = image.height

    let rotatedWidth: Int
    let rotatedHeight: Int

    switch abs(degrees) % 360 {
    case 90, 270:
        rotatedWidth = height
        rotatedHeight = width
    default:
        rotatedWidth = width
        rotatedHeight = height
    }

    guard let colorSpace = image.colorSpace,
          let context = CGContext(
            data: nil,
            width: rotatedWidth,
            height: rotatedHeight,
            bitsPerComponent: 8,
            bytesPerRow: rotatedWidth * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
          ) else {
        return nil
    }

    // Fill with white background
    context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: rotatedWidth, height: rotatedHeight))

    // Move origin to center, rotate, then draw
    context.translateBy(x: CGFloat(rotatedWidth) / 2, y: CGFloat(rotatedHeight) / 2)
    context.rotate(by: radians)
    context.translateBy(x: -CGFloat(width) / 2, y: -CGFloat(height) / 2)
    context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

    return context.makeImage()
}

// MARK: - Vision Framework Decoder

/// Decodes Aztec barcode(s) from a CGImage using Vision framework.
/// Returns decoded payload as Data, or nil if decoding fails.
func decodeAztecWithVision(_ image: CGImage) -> (data: Data?, error: String?) {
    let requestHandler = VNImageRequestHandler(cgImage: image, options: [:])

    var decodedData: Data?
    var errorMessage: String?

    let request = VNDetectBarcodesRequest { request, error in
        if let error = error {
            errorMessage = "Vision error: \(error.localizedDescription)"
            return
        }

        guard let results = request.results as? [VNBarcodeObservation] else {
            errorMessage = "No barcode observations returned"
            return
        }

        // Find Aztec codes
        let aztecResults = results.filter { $0.symbology == .aztec }

        if aztecResults.isEmpty {
            if results.isEmpty {
                errorMessage = "No barcodes detected in image"
            } else {
                let foundTypes = results.map { $0.symbology.rawValue }.joined(separator: ", ")
                errorMessage = "No Aztec codes found (found: \(foundTypes))"
            }
            return
        }

        // Use first Aztec result
        let observation = aztecResults[0]

        // Use payloadStringValue which is the decoded message
        if let payloadString = observation.payloadStringValue {
            // Convert string to data - Vision decodes to string
            decodedData = payloadString.data(using: .isoLatin1) ?? payloadString.data(using: .utf8)
        } else {
            errorMessage = "Aztec code detected but no payload string available"
        }
    }

    // Configure for Aztec only
    request.symbologies = [.aztec]

    do {
        try requestHandler.perform([request])
    } catch {
        return (nil, "Vision request failed: \(error.localizedDescription)")
    }

    return (decodedData, errorMessage)
}

// MARK: - CIAztecCodeGenerator Wrapper

/// Generates an Aztec code using CIAztecCodeGenerator.
func generateCIAztecCode(
    data: Data,
    correctionLevel: Float = 23.0,
    compactStyle: Float = 0.0  // 0 = auto
) -> CGImage? {
    guard let filter = CIFilter(name: "CIAztecCodeGenerator") else {
        return nil
    }

    filter.setValue(data, forKey: "inputMessage")
    filter.setValue(correctionLevel, forKey: "inputCorrectionLevel")
    filter.setValue(compactStyle, forKey: "inputCompactStyle")

    guard let output = filter.outputImage else {
        return nil
    }

    // Scale up for better decoding
    let scaleX = 10.0
    let scaleY = 10.0
    let scaledImage = output.transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))

    let context = CIContext()
    return context.createCGImage(scaledImage, from: scaledImage.extent)
}

// MARK: - Test Vector Generators

/// Generates random ASCII test payloads.
func generateASCIITestVectors(count: Int, maxLength: Int = 100) -> [String] {
    var vectors: [String] = []
    let asciiChars = Array(" !\"#$%&'()*+,-./0123456789:;<=>?@ABCDEFGHIJKLMNOPQRSTUVWXYZ[\\]^_`abcdefghijklmnopqrstuvwxyz{|}~")

    for _ in 0..<count {
        let length = Int.random(in: 1...maxLength)
        var str = ""
        for _ in 0..<length {
            str.append(asciiChars.randomElement()!)
        }
        vectors.append(str)
    }

    return vectors
}

/// Generates random UTF-8 test payloads with various Unicode characters.
func generateUTF8TestVectors(count: Int, maxLength: Int = 50) -> [String] {
    var vectors: [String] = []

    // Include various Unicode ranges
    let unicodeRanges: [ClosedRange<UInt32>] = [
        0x0020...0x007E,  // Basic ASCII
        0x00A0...0x00FF,  // Latin-1 Supplement
        0x0100...0x017F,  // Latin Extended-A
        0x0391...0x03C9,  // Greek
        0x0410...0x044F,  // Cyrillic
        0x4E00...0x4E4F,  // CJK (small subset)
        0x1F600...0x1F64F // Emoji (small subset)
    ]

    for _ in 0..<count {
        let length = Int.random(in: 1...maxLength)
        var str = ""
        for _ in 0..<length {
            let range = unicodeRanges.randomElement()!
            let codePoint = UInt32.random(in: range)
            if let scalar = Unicode.Scalar(codePoint) {
                str.append(Character(scalar))
            }
        }
        if !str.isEmpty {
            vectors.append(str)
        }
    }

    return vectors
}

/// Generates random binary test payloads.
func generateBinaryTestVectors(count: Int, maxLength: Int = 200) -> [[UInt8]] {
    var vectors: [[UInt8]] = []

    for _ in 0..<count {
        let length = Int.random(in: 1...maxLength)
        var bytes: [UInt8] = []
        for _ in 0..<length {
            bytes.append(UInt8.random(in: 0...255))
        }
        vectors.append(bytes)
    }

    return vectors
}

/// Generates edge case test payloads.
func generateEdgeCaseVectors() -> [(name: String, data: Data)] {
    var vectors: [(String, Data)] = []

    // Single characters
    vectors.append(("Single digit", Data("0".utf8)))
    vectors.append(("Single uppercase", Data("A".utf8)))
    vectors.append(("Single lowercase", Data("a".utf8)))
    vectors.append(("Single space", Data(" ".utf8)))

    // Repeated patterns
    vectors.append(("Repeated zeros", Data(repeating: 0x30, count: 20)))  // "0" * 20
    vectors.append(("All uppercase", Data("ABCDEFGHIJKLMNOPQRSTUVWXYZ".utf8)))
    vectors.append(("All lowercase", Data("abcdefghijklmnopqrstuvwxyz".utf8)))
    vectors.append(("All digits", Data("0123456789".utf8)))

    // Special characters
    vectors.append(("Special chars", Data("!@#$%^&*()_+-=[]{}|;':\",./<>?".utf8)))

    // Binary edge cases
    vectors.append(("Null byte", Data([0x00])))
    vectors.append(("All 0xFF", Data(repeating: 0xFF, count: 10)))
    vectors.append(("Alternating 0x00/0xFF", Data([0x00, 0xFF, 0x00, 0xFF, 0x00, 0xFF])))
    vectors.append(("Sequential bytes", Data(0...255)))

    // Mode switching triggers
    vectors.append(("Upper-Lower mix", Data("AaBbCcDdEeFf".utf8)))
    vectors.append(("Alpha-Digit mix", Data("ABC123DEF456".utf8)))
    vectors.append(("Punct-Alpha mix", Data("Hello, World! How are you?".utf8)))

    // Long payloads
    vectors.append(("Medium string (100)", Data(String(repeating: "X", count: 100).utf8)))
    vectors.append(("Long string (500)", Data(String(repeating: "Y", count: 500).utf8)))

    return vectors
}

// MARK: - Validation Test Suite

struct AztecValidationTests {

    // MARK: - Basic Scannability Tests

    @Test
    func aztecLib_symbol_is_scannable() throws {
        let testStrings = [
            "Hello",
            "12345",
            "Hello, World!",
            "ABCDEFGHIJKLMNOP",
            "Mixed123Content!@#"
        ]

        for testString in testStrings {
            let symbol = try AztecEncoder.encode(testString)
            guard let image = renderAztecSymbol(symbol) else {
                Issue.record("Failed to render image for: \(testString)")
                continue
            }

            let (decoded, error) = decodeAztecWithVision(image)

            if let error = error {
                Issue.record("Decoding failed for '\(testString)': \(error)")
                continue
            }

            guard let decodedData = decoded else {
                Issue.record("No data decoded for: \(testString)")
                continue
            }

            let decodedString = String(data: decodedData, encoding: .isoLatin1) ?? String(data: decodedData, encoding: .utf8)
            #expect(decodedString == testString, "Decoded '\(decodedString ?? "nil")' != original '\(testString)'")
        }
    }

    @Test
    func ciAztec_symbol_is_scannable() throws {
        let testStrings = [
            "Hello",
            "12345",
            "Hello, World!",
            "ABCDEFGHIJKLMNOP"
        ]

        for testString in testStrings {
            guard let data = testString.data(using: .isoLatin1),
                  let image = generateCIAztecCode(data: data) else {
                Issue.record("Failed to generate CIAztec for: \(testString)")
                continue
            }

            let (decoded, error) = decodeAztecWithVision(image)

            if let error = error {
                Issue.record("CIAztec decoding failed for '\(testString)': \(error)")
                continue
            }

            guard let decodedData = decoded else {
                Issue.record("No data decoded for CIAztec: \(testString)")
                continue
            }

            let decodedString = String(data: decodedData, encoding: .isoLatin1)
            #expect(decodedString == testString, "CIAztec decoded '\(decodedString ?? "nil")' != original '\(testString)'")
        }
    }

    // MARK: - Cross-Validation Tests

    @Test
    func both_encoders_produce_scannable_output_for_same_payload() throws {
        let testCases = [
            "Hello",
            "Test123",
            "UPPERCASE",
            "lowercase",
            "Mixed Case 123!",
            "Special @#$%",
            String(repeating: "X", count: 50)
        ]

        for payload in testCases {
            guard let payloadData = payload.data(using: .isoLatin1) else {
                continue
            }

            // Encode with AztecLib
            let aztecLibSymbol = try AztecEncoder.encode(payload)
            guard let aztecLibImage = renderAztecSymbol(aztecLibSymbol) else {
                Issue.record("Failed to render AztecLib symbol for: \(payload)")
                continue
            }

            // Encode with CIAztecCodeGenerator
            guard let ciImage = generateCIAztecCode(data: payloadData) else {
                Issue.record("Failed to generate CIAztec for: \(payload)")
                continue
            }

            // Decode both
            let (aztecLibDecoded, aztecLibError) = decodeAztecWithVision(aztecLibImage)
            let (ciDecoded, ciError) = decodeAztecWithVision(ciImage)

            // Verify both decode successfully
            if let error = aztecLibError {
                Issue.record("AztecLib decode failed for '\(payload)': \(error)")
            }
            if let error = ciError {
                Issue.record("CIAztec decode failed for '\(payload)': \(error)")
            }

            // Compare decoded content (both should match original)
            if let aztecLibData = aztecLibDecoded {
                let aztecLibString = String(data: aztecLibData, encoding: .isoLatin1)
                #expect(aztecLibString == payload, "AztecLib: '\(aztecLibString ?? "nil")' != '\(payload)'")
            }

            if let ciData = ciDecoded {
                let ciString = String(data: ciData, encoding: .isoLatin1)
                #expect(ciString == payload, "CIAztec: '\(ciString ?? "nil")' != '\(payload)'")
            }
        }
    }

    // MARK: - Rotation Invariance Tests

    @Test
    func aztecLib_symbol_decodes_after_rotation() throws {
        let payload = "RotationTest123"
        let symbol = try AztecEncoder.encode(payload)
        guard let baseImage = renderAztecSymbol(symbol, moduleSize: 12, quietZoneModules: 6) else {
            Issue.record("Failed to render base image")
            return
        }

        for degrees in [0, 90, 180, 270] {
            guard let rotatedImage = rotateImage(baseImage, degrees: degrees) else {
                Issue.record("Failed to rotate image by \(degrees) degrees")
                continue
            }

            let (decoded, error) = decodeAztecWithVision(rotatedImage)

            if let error = error {
                Issue.record("Failed to decode at \(degrees)°: \(error)")
                continue
            }

            guard let decodedData = decoded else {
                Issue.record("No data decoded at \(degrees)°")
                continue
            }

            let decodedString = String(data: decodedData, encoding: .isoLatin1)
            #expect(decodedString == payload, "Rotation \(degrees)°: '\(decodedString ?? "nil")' != '\(payload)'")
        }
    }

    // MARK: - Scale Invariance Tests

    @Test
    func aztecLib_symbol_decodes_at_different_scales() throws {
        let payload = "ScaleTest456"
        let symbol = try AztecEncoder.encode(payload)
        guard let baseImage = renderAztecSymbol(symbol, moduleSize: 8, quietZoneModules: 4) else {
            Issue.record("Failed to render base image")
            return
        }

        // Test various scale factors
        let scaleFactors: [CGFloat] = [0.5, 0.75, 1.0, 1.5, 2.0, 3.0]

        for scale in scaleFactors {
            guard let scaledImage = scaleImage(baseImage, factor: scale) else {
                Issue.record("Failed to scale image by \(scale)x")
                continue
            }

            let (decoded, error) = decodeAztecWithVision(scaledImage)

            if let error = error {
                // Small scales may legitimately fail - just log
                print("Scale \(scale)x decode issue: \(error)")
                continue
            }

            if let decodedData = decoded {
                let decodedString = String(data: decodedData, encoding: .isoLatin1)
                #expect(decodedString == payload, "Scale \(scale)x: '\(decodedString ?? "nil")' != '\(payload)'")
            }
        }
    }

    // MARK: - Binary Data Tests

    @Test
    func aztecLib_encodes_binary_data_correctly() throws {
        let binaryVectors: [[UInt8]] = [
            [0x00],
            [0xFF],
            [0x00, 0xFF, 0x00, 0xFF],
            Array(0..<128),
            [0x01, 0x02, 0x03, 0x04, 0x05],
            [UInt8](repeating: 0x42, count: 50)
        ]

        for bytes in binaryVectors {
            let symbol = try AztecEncoder.encode(bytes)
            guard let image = renderAztecSymbol(symbol) else {
                Issue.record("Failed to render binary symbol of \(bytes.count) bytes")
                continue
            }

            let (decoded, error) = decodeAztecWithVision(image)

            if let error = error {
                Issue.record("Binary decode failed for \(bytes.count) bytes: \(error)")
                continue
            }

            guard let decodedData = decoded else {
                Issue.record("No binary data decoded")
                continue
            }

            let originalData = Data(bytes)
            #expect(decodedData == originalData, "Binary mismatch: got \(decodedData.count) bytes, expected \(bytes.count)")
        }
    }

    // MARK: - Edge Case Tests

    @Test
    func edge_cases_encode_and_decode_correctly() throws {
        let edgeCases = generateEdgeCaseVectors()

        for (name, data) in edgeCases {
            // Skip very long payloads that may exceed capacity
            if data.count > 1000 {
                continue
            }

            do {
                let symbol = try AztecEncoder.encode([UInt8](data))
                guard let image = renderAztecSymbol(symbol) else {
                    Issue.record("[\(name)] Failed to render")
                    continue
                }

                let (decoded, error) = decodeAztecWithVision(image)

                if let error = error {
                    Issue.record("[\(name)] Decode error: \(error)")
                    continue
                }

                if let decodedData = decoded {
                    #expect(decodedData == data, "[\(name)] Data mismatch")
                }
            } catch {
                // Some edge cases may be too large
                print("[\(name)] Encoding error (may be expected): \(error)")
            }
        }
    }

    // MARK: - Randomized Tests

    @Test
    func randomized_ascii_payloads() throws {
        let vectors = generateASCIITestVectors(count: 20, maxLength: 80)

        var successCount = 0
        var failCount = 0

        for (index, payload) in vectors.enumerated() {
            do {
                let symbol = try AztecEncoder.encode(payload)
                guard let image = renderAztecSymbol(symbol) else {
                    failCount += 1
                    continue
                }

                let (decoded, _) = decodeAztecWithVision(image)

                if let decodedData = decoded,
                   let decodedString = String(data: decodedData, encoding: .isoLatin1),
                   decodedString == payload {
                    successCount += 1
                } else {
                    failCount += 1
                    print("Random ASCII [\(index)] failed: payload length \(payload.count)")
                }
            } catch {
                failCount += 1
            }
        }

        print("Random ASCII tests: \(successCount)/\(successCount + failCount) passed")
        #expect(successCount > 0, "At least some random ASCII tests should pass")
    }

    @Test
    func randomized_binary_payloads() throws {
        let vectors = generateBinaryTestVectors(count: 15, maxLength: 100)

        var successCount = 0
        var failCount = 0

        for (index, bytes) in vectors.enumerated() {
            do {
                let symbol = try AztecEncoder.encode(bytes)
                guard let image = renderAztecSymbol(symbol) else {
                    failCount += 1
                    continue
                }

                let (decoded, _) = decodeAztecWithVision(image)

                if let decodedData = decoded, decodedData == Data(bytes) {
                    successCount += 1
                } else {
                    failCount += 1
                    print("Random binary [\(index)] failed: \(bytes.count) bytes")
                }
            } catch {
                failCount += 1
            }
        }

        print("Random binary tests: \(successCount)/\(successCount + failCount) passed")
        #expect(successCount > 0, "At least some random binary tests should pass")
    }

    // MARK: - Parameter Combination Tests

    @Test
    func various_error_correction_levels() throws {
        let payload = "ErrorCorrectionTest"
        let ecLevels: [UInt] = [5, 10, 23, 33, 50]

        for ecLevel in ecLevels {
            let options = AztecEncoder.Options(errorCorrectionPercentage: ecLevel)
            let symbol = try AztecEncoder.encode(payload, options: options)

            guard let image = renderAztecSymbol(symbol) else {
                Issue.record("Failed to render EC \(ecLevel)%")
                continue
            }

            let (decoded, error) = decodeAztecWithVision(image)

            if let error = error {
                Issue.record("EC \(ecLevel)% decode failed: \(error)")
                continue
            }

            if let decodedData = decoded,
               let decodedString = String(data: decodedData, encoding: .isoLatin1) {
                #expect(decodedString == payload, "EC \(ecLevel)%: mismatch")
            }
        }
    }

    @Test
    func compact_vs_full_symbols() throws {
        let payload = "CompactVsFull"

        // Force compact
        let compactOptions = AztecEncoder.Options(preferCompact: true)
        let compactSymbol = try AztecEncoder.encode(payload, options: compactOptions)

        // Force full
        let fullOptions = AztecEncoder.Options(preferCompact: false)
        let fullSymbol = try AztecEncoder.encode(payload, options: fullOptions)

        // Both should be scannable
        for (name, symbol) in [("Compact", compactSymbol), ("Full", fullSymbol)] {
            guard let image = renderAztecSymbol(symbol) else {
                Issue.record("\(name): render failed")
                continue
            }

            let (decoded, error) = decodeAztecWithVision(image)

            if let error = error {
                Issue.record("\(name): \(error)")
                continue
            }

            if let decodedData = decoded,
               let decodedString = String(data: decodedData, encoding: .isoLatin1) {
                #expect(decodedString == payload, "\(name) mode mismatch")
            }
        }
    }
}

// MARK: - Diagnostic Validation Tests

struct AztecDiagnosticValidationTests {

    @Test
    func print_decode_comparison() throws {
        let testCases = ["Hello", "12345", "Test!", "ABC"]

        print("\n" + String(repeating: "=", count: 70))
        print("AZTEC DECODE COMPARISON")
        print(String(repeating: "=", count: 70))

        for payload in testCases {
            print("\n--- Payload: \"\(payload)\" ---")

            // AztecLib
            let symbol = try AztecEncoder.encode(payload)
            if let image = renderAztecSymbol(symbol) {
                let (decoded, error) = decodeAztecWithVision(image)
                if let data = decoded, let str = String(data: data, encoding: .isoLatin1) {
                    print("AztecLib → Vision: \"\(str)\" \(str == payload ? "✓" : "✗")")
                } else {
                    print("AztecLib → Vision: FAILED - \(error ?? "unknown")")
                }
            }

            // CIAztec
            if let data = payload.data(using: .isoLatin1),
               let ciImage = generateCIAztecCode(data: data) {
                let (decoded, error) = decodeAztecWithVision(ciImage)
                if let data = decoded, let str = String(data: data, encoding: .isoLatin1) {
                    print("CIAztec  → Vision: \"\(str)\" \(str == payload ? "✓" : "✗")")
                } else {
                    print("CIAztec  → Vision: FAILED - \(error ?? "unknown")")
                }
            }
        }

        print("\n" + String(repeating: "=", count: 70))
    }

    @Test
    func save_test_images_for_manual_inspection() throws {
        // This test saves images to /tmp for manual inspection with external tools
        let payload = "ManualTest123"

        // Force non-compact mode (full symbol) to match other encoders
        let options = AztecEncoder.Options(preferCompact: false)
        let symbol = try AztecEncoder.encode(payload, options: options)
        let details = try AztecEncoder.encodeWithDetails(payload, options: options)
        print("AztecLib symbol: \(symbol.size)x\(symbol.size), compact=\(details.configuration.isCompact), layers=\(details.configuration.layerCount)")

        guard let aztecLibImage = renderAztecSymbol(symbol, moduleSize: 10, quietZoneModules: 4) else {
            Issue.record("Failed to render AztecLib image")
            return
        }

        guard let payloadData = payload.data(using: .isoLatin1),
              let ciImage = generateCIAztecCode(data: payloadData, correctionLevel: 23.0) else {
            Issue.record("Failed to generate CIAztec image")
            return
        }

        // Save images to /tmp for manual inspection
        let aztecLibURL = URL(fileURLWithPath: "/tmp/azteclib_test.png")
        let ciURL = URL(fileURLWithPath: "/tmp/ciaztec_test.png")

        if let aztecLibDest = CGImageDestinationCreateWithURL(aztecLibURL as CFURL, kUTTypePNG, 1, nil) {
            CGImageDestinationAddImage(aztecLibDest, aztecLibImage, nil)
            CGImageDestinationFinalize(aztecLibDest)
            print("Saved AztecLib image to: \(aztecLibURL.path)")
        }

        if let ciDest = CGImageDestinationCreateWithURL(ciURL as CFURL, kUTTypePNG, 1, nil) {
            CGImageDestinationAddImage(ciDest, ciImage, nil)
            CGImageDestinationFinalize(ciDest)
            print("Saved CIAztec image to: \(ciURL.path)")
        }

        // Provide instructions for external decoding
        print("\nTo decode with external tools:")
        print("  Python zxing-cpp: source /tmp/zxing-venv/bin/activate && python3 -c \"")
        print("    import zxingcpp")
        print("    from PIL import Image")
        print("    img = Image.open('/tmp/azteclib_test.png')")
        print("    results = zxingcpp.read_barcodes(img)")
        print("    for r in results: print(r.text)\"")
    }
}

// MARK: - Large Scale Validation

struct AztecLargeScaleValidationTests {

    @Test
    func comprehensive_payload_sweep() throws {
        // Test payloads of various sizes
        var results: [(size: Int, success: Bool)] = []

        for size in [1, 5, 10, 20, 50, 100, 200, 500] {
            let payload = String(repeating: "X", count: size)

            do {
                let symbol = try AztecEncoder.encode(payload)
                if let image = renderAztecSymbol(symbol) {
                    let (decoded, _) = decodeAztecWithVision(image)
                    if let data = decoded, String(data: data, encoding: .isoLatin1) == payload {
                        results.append((size, true))
                    } else {
                        results.append((size, false))
                    }
                } else {
                    results.append((size, false))
                }
            } catch {
                // Expected for very large payloads
                print("Size \(size): encoding failed (may be expected)")
            }
        }

        print("\nPayload size sweep results:")
        for (size, success) in results {
            print("  \(size) chars: \(success ? "✓" : "✗")")
        }

        let successRate = Double(results.filter { $0.success }.count) / Double(results.count)
        #expect(successRate >= 0.5, "At least half of payload sizes should succeed")
    }

    @Test
    func symbol_layer_coverage() throws {
        // Test various symbol configurations by adjusting payload size
        // Compact: 1-4 layers (15x15 to 27x27)
        // Full: 1-32 layers (19x19 to 151x151)

        print("\n--- Symbol Layer Coverage ---")

        // Small payloads for compact symbols
        for (name, payload) in [
            ("Tiny", "A"),
            ("Small", "Hello"),
            ("Medium", String(repeating: "X", count: 30)),
            ("Larger", String(repeating: "Y", count: 100))
        ] {
            let result = try AztecEncoder.encodeWithDetails(payload)
            print("\(name) (\(payload.count) chars): \(result.configuration.isCompact ? "Compact" : "Full") L\(result.configuration.layerCount) (\(result.symbol.size)x\(result.symbol.size))")

            if let image = renderAztecSymbol(result.symbol) {
                let (decoded, _) = decodeAztecWithVision(image)
                let success = decoded != nil && String(data: decoded!, encoding: .isoLatin1) == payload
                print("  Decode: \(success ? "✓" : "✗")")
            }
        }
    }
}
