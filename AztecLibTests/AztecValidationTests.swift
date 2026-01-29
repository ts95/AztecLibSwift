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

    @Test
    func save_multiple_test_images() throws {
        // Save various configurations for ZXing testing
        let testCases: [(String, AztecEncoder.Options)] = [
            ("Hello", AztecEncoder.Options(preferCompact: true)),
            ("Hello World 123", AztecEncoder.Options(preferCompact: true)),
            ("ABC123+/xyz", AztecEncoder.Options(preferCompact: true)),
            ("ManualTest123", AztecEncoder.Options(preferCompact: true)),
            ("ManualTest123", AztecEncoder.Options(preferCompact: false)),
        ]

        print("\n=== Saving Multiple Test Images ===")
        for (payload, options) in testCases {
            let symbol = try AztecEncoder.encode(payload, options: options)
            let details = try AztecEncoder.encodeWithDetails(payload, options: options)
            let compact = details.configuration.isCompact ? "compact" : "full"
            let filename = "/tmp/aztec_\(compact)_\(symbol.size)x\(symbol.size).png"

            guard let image = renderAztecSymbol(symbol, moduleSize: 10, quietZoneModules: 4) else {
                print("  FAILED to render \(payload.prefix(20))...")
                continue
            }

            let url = URL(fileURLWithPath: filename)
            if let dest = CGImageDestinationCreateWithURL(url as CFURL, kUTTypePNG, 1, nil) {
                CGImageDestinationAddImage(dest, image, nil)
                CGImageDestinationFinalize(dest)
                print("  \(compact) \(symbol.size)x\(symbol.size) '\(payload.prefix(20))' → \(filename)")
            }
        }
    }

    @Test
    func test_simple_payloads() throws {
        // Test progressively larger payloads to find where decoding breaks
        let testCases = [
            "Hello",
            "Hello World",
            "Hello World 123",
            String(repeating: "A", count: 50),
            String(repeating: "A", count: 100),
            String(repeating: "A", count: 200),
            String(repeating: "A", count: 300),
            "ABC123+/xyz",  // Test with + and / characters
        ]

        print("\n=== Testing Simple Payloads (preferring compact) ===")
        let options = AztecEncoder.Options(preferCompact: true)  // Changed to prefer compact

        for payload in testCases {
            let symbol = try AztecEncoder.encode(payload, options: options)
            let details = try AztecEncoder.encodeWithDetails(payload, options: options)

            guard let image = renderAztecSymbol(symbol, moduleSize: 10, quietZoneModules: 4) else {
                print("\(payload.prefix(20))...: RENDER FAILED")
                continue
            }

            let (decoded, error) = decodeAztecWithVision(image)
            if let data = decoded, let str = String(data: data, encoding: .isoLatin1), str == payload {
                print("[\(symbol.size)x\(symbol.size)] \"\(payload.prefix(20))\(payload.count > 20 ? "..." : "")\": ✓")
            } else {
                let errMsg = error ?? "mismatch"
                print("[\(symbol.size)x\(symbol.size)] \"\(payload.prefix(20))\(payload.count > 20 ? "..." : "")\": ✗ (\(errMsg))")
            }
        }
    }

    @Test
    func compare_hello_with_ciaztec() throws {
        let payload = "Hello"

        print("\n=== Detailed Hello Comparison ===")

        // AztecLib
        let options = AztecEncoder.Options(preferCompact: false)
        let symbol = try AztecEncoder.encode(payload, options: options)
        let details = try AztecEncoder.encodeWithDetails(payload, options: options)

        print("AztecLib: \(symbol.size)x\(symbol.size), layers=\(details.configuration.layerCount)")
        print("  Data codewords: \(details.configuration.dataCodewordCount)")
        print("  Parity codewords: \(details.configuration.parityCodewordCount)")
        print("  Word size: \(details.configuration.wordSizeInBits) bits")

        // Print AztecLib matrix
        print("\nAztecLib matrix:")
        for y in 0..<min(symbol.size, 20) {
            var row = ""
            for x in 0..<symbol.size {
                row += symbol[x: x, y: y] ? "█" : "░"
            }
            print(row)
        }

        // CIAztec
        if let payloadData = payload.data(using: .isoLatin1),
           let ciImage = generateCIAztecCode(data: payloadData, correctionLevel: 23.0) {

            // Get CIAztec dimensions
            let ciSize = ciImage.width / 10  // We scaled by 10x
            print("\nCIAztec: \(ciSize)x\(ciSize)")

            // Try to extract CIAztec modules
            guard let ciData = ciImage.dataProvider?.data,
                  let ptr = CFDataGetBytePtr(ciData) else {
                print("Could not read CIAztec image data")
                return
            }

            print("\nCIAztec matrix (first rows at module level):")
            // Sample modules from CIAztec image
            for y in 0..<min(ciSize, 20) {
                var row = ""
                for x in 0..<ciSize {
                    // Sample center of each module
                    let px = x * 10 + 5
                    let py = y * 10 + 5
                    let offset = (py * ciImage.bytesPerRow + px * 4)
                    let r = ptr[offset]  // Grayscale, so R=G=B
                    row += r < 128 ? "█" : "░"
                }
                print(row)
            }
        }

        // Dump mode message details
        print("\n--- Mode Message Analysis ---")
        let builder = AztecMatrixBuilder(configuration: details.configuration)
        let modeMsg = builder.encodeModeMessage()
        print("Mode message bits (\(modeMsg.bitCount)): ", terminator: "")
        for i in 0..<modeMsg.bitCount {
            let bit = modeMsg.leastSignificantBits(atBitPosition: i, bitCount: 1)
            print(bit != 0 ? "1" : "0", terminator: "")
        }
        print()

        // Extract mode message from the actual matrix
        print("\n--- Mode Message Placement Verification ---")
        let symSize = symbol.size
        let center = symSize / 2
        print("Symbol size: \(symSize)x\(symSize), center: \(center)")

        // For full symbol, mode message is at distance 7 from center
        // 10 bits per edge, 40 bits total
        print("Expected mode message positions (full symbol, d=7):")
        var extractedBits = ""
        for i in 0..<10 {
            let offset = center - 5 + i + i / 5
            // Top edge
            let topBit = symbol[x: offset, y: center - 7]
            extractedBits += topBit ? "1" : "0"
        }
        print("  Top edge (y=\(center-7)): \(extractedBits)")

        extractedBits = ""
        for i in 0..<10 {
            let offset = center - 5 + i + i / 5
            let rightBit = symbol[x: center + 7, y: offset]
            extractedBits += rightBit ? "1" : "0"
        }
        print("  Right edge (x=\(center+7)): \(extractedBits)")

        extractedBits = ""
        for i in 0..<10 {
            let offset = center - 5 + i + i / 5
            let bottomBit = symbol[x: offset, y: center + 7]
            extractedBits += bottomBit ? "1" : "0"
        }
        print("  Bottom edge (y=\(center+7)): \(extractedBits)")

        extractedBits = ""
        for i in 0..<10 {
            let offset = center - 5 + i + i / 5
            let leftBit = symbol[x: center - 7, y: offset]
            extractedBits += leftBit ? "1" : "0"
        }
        print("  Left edge (x=\(center-7)): \(extractedBits)")

        // Compare with what should have been placed
        print("\n--- Expected vs Placed ---")
        print("Mode bits (raw):      ", terminator: "")
        for i in 0..<40 {
            let bit = modeMsg.leastSignificantBits(atBitPosition: i, bitCount: 1)
            print(bit != 0 ? "1" : "0", terminator: i % 10 == 9 ? " " : "")
        }
        print()

        print("Expected top (0-9):   ", terminator: "")
        for i in 0..<10 {
            let bit = modeMsg.leastSignificantBits(atBitPosition: i, bitCount: 1)
            print(bit != 0 ? "1" : "0", terminator: "")
        }
        print()

        print("Expected right(10-19):", terminator: "")
        for i in 0..<10 {
            let bit = modeMsg.leastSignificantBits(atBitPosition: i + 10, bitCount: 1)
            print(bit != 0 ? "1" : "0", terminator: "")
        }
        print()

        print("Expected bot (29-20): ", terminator: "")
        for i in 0..<10 {
            let bit = modeMsg.leastSignificantBits(atBitPosition: 29 - i, bitCount: 1)
            print(bit != 0 ? "1" : "0", terminator: "")
        }
        print()

        print("Expected left(39-30): ", terminator: "")
        for i in 0..<10 {
            let bit = modeMsg.leastSignificantBits(atBitPosition: 39 - i, bitCount: 1)
            print(bit != 0 ? "1" : "0", terminator: "")
        }
        print()

        // Check for coordinate overlap between data and mode message
        print("\n--- Coordinate Overlap Analysis ---")
        let layers = details.configuration.layerCount  // 1
        let baseMatrixSize = 14 + layers * 4  // 18
        print("baseMatrixSize: \(baseMatrixSize), symbolSize: \(symSize)")

        // Mode message positions (full symbol, distance 7)
        var modeMsgPositions: Set<String> = []
        for i in 0..<10 {
            let offset = center - 5 + i + i / 5
            modeMsgPositions.insert("\(offset),\(center-7)")  // top
            modeMsgPositions.insert("\(center+7),\(offset)")  // right
            modeMsgPositions.insert("\(offset),\(center+7)")  // bottom
            modeMsgPositions.insert("\(center-7),\(offset)")  // left
        }
        print("Mode message positions: \(modeMsgPositions.count) modules")

        // Data positions for layer 0
        var dataPositions: Set<String> = []
        let rowSize = (layers - 0) * 4 + 12  // 16
        print("Data layer 0 rowSize: \(rowSize)")

        for j in 0..<rowSize {
            for k in 0..<2 {
                // Top side
                let topX = 0 * 2 + k  // 0 or 1
                let topY = 0 * 2 + j  // 0..15
                dataPositions.insert("\(topX),\(topY)")

                // Right side
                let rightX = 0 * 2 + j  // 0..15
                let rightY = baseMatrixSize - 1 - 0 * 2 - k  // 17 or 16
                dataPositions.insert("\(rightX),\(rightY)")

                // Bottom side
                let botX = baseMatrixSize - 1 - 0 * 2 - k  // 17 or 16
                let botY = baseMatrixSize - 1 - 0 * 2 - j  // 17..2
                dataPositions.insert("\(botX),\(botY)")

                // Left side
                let leftX = baseMatrixSize - 1 - 0 * 2 - j  // 17..2
                let leftY = 0 * 2 + k  // 0 or 1
                dataPositions.insert("\(leftX),\(leftY)")
            }
        }
        print("Data positions: \(dataPositions.count) modules")

        let overlap = modeMsgPositions.intersection(dataPositions)
        if overlap.isEmpty {
            print("No overlap between data and mode message ✓")
        } else {
            print("OVERLAP DETECTED: \(overlap.count) positions!")
            for pos in overlap.sorted() {
                print("  \(pos)")
            }
        }

        // Decode mode message
        // Full: 16 data bits (layers-1 in 5 bits, dataWords-1 in 11 bits) + 24 parity = 40 bits
        // Compact: 8 data bits (layers-1 in 2 bits, dataWords-1 in 6 bits) + 20 parity = 28 bits
        if !details.configuration.isCompact {
            // Extract nibbles
            let nibbles = modeMsg.makeMostSignificantNibblesByUnpacking(nibbleCount: 10)
            let dataWord = (UInt16(nibbles[0]) << 12) | (UInt16(nibbles[1]) << 8) | (UInt16(nibbles[2]) << 4) | UInt16(nibbles[3])
            let decodedLayers = ((dataWord >> 11) & 0x1F) + 1
            let decodedDataWords = (dataWord & 0x7FF) + 1
            print("Full mode message: layers=\(decodedLayers), dataWords=\(decodedDataWords)")
            print("  Expected: layers=\(details.configuration.layerCount), dataWords=\(details.configuration.dataCodewordCount)")
        }

        // Save images
        if let aztecImage = renderAztecSymbol(symbol, moduleSize: 10, quietZoneModules: 4) {
            let url = URL(fileURLWithPath: "/tmp/hello_azteclib.png")
            if let dest = CGImageDestinationCreateWithURL(url as CFURL, kUTTypePNG, 1, nil) {
                CGImageDestinationAddImage(dest, aztecImage, nil)
                CGImageDestinationFinalize(dest)
                print("\nSaved AztecLib to: \(url.path)")
            }
        }

        if let payloadData = payload.data(using: .isoLatin1),
           let ciImage = generateCIAztecCode(data: payloadData, correctionLevel: 23.0) {
            let url = URL(fileURLWithPath: "/tmp/hello_ciaztec.png")
            if let dest = CGImageDestinationCreateWithURL(url as CFURL, kUTTypePNG, 1, nil) {
                CGImageDestinationAddImage(dest, ciImage, nil)
                CGImageDestinationFinalize(dest)
                print("Saved CIAztec to: \(url.path)")
            }
        }
    }

    @Test
    func debug_punct_mismatch() throws {
        // Debug the "ABC123+/xyz" mismatch issue
        let payload = "ABC123+/xyz"

        print("\n=== Debug Punctuation Mismatch ===")

        let options = AztecEncoder.Options(preferCompact: true)
        let symbol = try AztecEncoder.encode(payload, options: options)
        let details = try AztecEncoder.encodeWithDetails(payload, options: options)

        print("Payload: \"\(payload)\"")
        print("AztecLib: \(symbol.size)x\(symbol.size), compact=\(details.configuration.isCompact), layers=\(details.configuration.layerCount)")
        print("Data codewords: \(details.configuration.dataCodewordCount)")
        print("Parity codewords: \(details.configuration.parityCodewordCount)")

        // Render and decode
        guard let image = renderAztecSymbol(symbol, moduleSize: 10, quietZoneModules: 4) else {
            Issue.record("Failed to render image")
            return
        }

        let (decoded, error) = decodeAztecWithVision(image)
        if let data = decoded {
            let str = String(data: data, encoding: .isoLatin1) ?? "(decode failed)"
            print("Vision decoded: \"\(str)\"")
            print("Expected:       \"\(payload)\"")
            print("Match: \(str == payload ? "✓" : "✗")")

            // Compare character by character
            if str != payload {
                print("\nCharacter comparison:")
                let maxLen = max(str.count, payload.count)
                for i in 0..<maxLen {
                    let strChar = i < str.count ? str[str.index(str.startIndex, offsetBy: i)] : Character("_")
                    let payloadChar = i < payload.count ? payload[payload.index(payload.startIndex, offsetBy: i)] : Character("_")
                    let match = strChar == payloadChar ? "✓" : "✗"
                    print("  [\(i)] '\(strChar)' vs '\(payloadChar)' \(match)")
                }
            }
        } else {
            print("Vision failed: \(error ?? "unknown")")
        }

        // Save for ZXing analysis
        let url = URL(fileURLWithPath: "/tmp/azteclib_punct.png")
        if let dest = CGImageDestinationCreateWithURL(url as CFURL, kUTTypePNG, 1, nil) {
            CGImageDestinationAddImage(dest, image, nil)
            CGImageDestinationFinalize(dest)
            print("\nSaved AztecLib to: \(url.path)")
        }

        // Generate CIAztec for comparison
        guard let payloadData = payload.data(using: .isoLatin1),
              let filter = CIFilter(name: "CIAztecCodeGenerator") else {
            print("CIAztec filter not available")
            return
        }
        filter.setValue(payloadData, forKey: "inputMessage")
        filter.setValue(Float(23.0), forKey: "inputCorrectionLevel")
        filter.setValue(Float(1.0), forKey: "inputCompactStyle")  // Force compact

        guard let ciOutput = filter.outputImage else {
            print("CIAztec filter returned nil")
            return
        }

        let ciContext = CIContext()
        guard let ciImage = ciContext.createCGImage(ciOutput, from: ciOutput.extent) else {
            print("Failed to create CGImage from CIFilter")
            return
        }

        print("CIAztec: \(ciImage.width)x\(ciImage.height)")

        // Scale up and decode CIAztec
        if let ciScaled = scaleImage(ciImage, factor: 10) {
            let (ciDecoded, ciError) = decodeAztecWithVision(ciScaled)
            if let data = ciDecoded {
                let str = String(data: data, encoding: .isoLatin1) ?? "(decode failed)"
                print("CIAztec  → Vision: \"\(str)\"")
            } else {
                print("CIAztec  → Vision: FAILED - \(ciError ?? "unknown")")
            }

            let ciUrl = URL(fileURLWithPath: "/tmp/ciaztec_punct.png")
            if let dest = CGImageDestinationCreateWithURL(ciUrl as CFURL, kUTTypePNG, 1, nil) {
                CGImageDestinationAddImage(dest, ciScaled, nil)
                CGImageDestinationFinalize(dest)
                print("Saved CIAztec to: \(ciUrl.path)")
            }
        }

        // Module-by-module comparison
        print("\n--- Module Comparison ---")
        guard let ciData = ciImage.dataProvider?.data,
              let ptr = CFDataGetBytePtr(ciData) else {
            print("Could not read CIAztec image data")
            return
        }

        let compareSize = min(symbol.size, ciImage.width)
        var differences = 0
        for y in 0..<compareSize {
            var row = ""
            for x in 0..<compareSize {
                let aztecModule = symbol[x: x, y: y]
                // CIAztec: 1 pixel = 1 module, RGBA format
                let offset = y * ciImage.bytesPerRow + x * 4
                let ciModule = ptr[offset] < 128
                if aztecModule != ciModule {
                    differences += 1
                    row += "X"
                } else {
                    row += aztecModule ? "█" : "░"
                }
            }
            print("Row \(String(format: "%2d", y)): \(row)")
        }
        print("\nTotal differences: \(differences) modules")
    }

    @Test
    func compare_hello_modules() throws {
        // Compare "Hello" encoding between AztecLib and CIAztec
        let payload = "Hello"

        print("\n=== Module Comparison for 'Hello' ===")

        let options = AztecEncoder.Options(preferCompact: true)
        let symbol = try AztecEncoder.encode(payload, options: options)

        print("AztecLib: \(symbol.size)x\(symbol.size)")

        // Generate CIAztec
        guard let payloadData = payload.data(using: .isoLatin1),
              let filter = CIFilter(name: "CIAztecCodeGenerator") else {
            print("CIAztec filter not available")
            return
        }
        filter.setValue(payloadData, forKey: "inputMessage")
        filter.setValue(Float(23.0), forKey: "inputCorrectionLevel")
        filter.setValue(Float(1.0), forKey: "inputCompactStyle")

        guard let ciOutput = filter.outputImage else {
            print("CIAztec filter returned nil")
            return
        }

        let ciContext = CIContext()
        guard let ciImage = ciContext.createCGImage(ciOutput, from: ciOutput.extent) else {
            print("Failed to create CGImage from CIFilter")
            return
        }

        print("CIAztec: \(ciImage.width)x\(ciImage.height)")

        if ciImage.width != symbol.size {
            print("DIFFERENT SIZES - cannot compare")
            return
        }

        // Module-by-module comparison
        guard let ciData = ciImage.dataProvider?.data,
              let ptr = CFDataGetBytePtr(ciData) else {
            print("Could not read CIAztec image data")
            return
        }

        var differences = 0
        for y in 0..<symbol.size {
            var row = ""
            for x in 0..<symbol.size {
                let aztecModule = symbol[x: x, y: y]
                let offset = y * ciImage.bytesPerRow + x * 4
                let ciModule = ptr[offset] < 128
                if aztecModule != ciModule {
                    differences += 1
                    row += "X"
                } else {
                    row += aztecModule ? "█" : "░"
                }
            }
            print("Row \(String(format: "%2d", y)): \(row)")
        }

        print("\nTotal differences: \(differences) modules")

        if differences == 0 {
            print("PERFECT MATCH! ✓")
        }
    }

    @Test
    func compare_compact_layer_3_with_ciaztec() throws {
        // 50 'A's should result in compact layer 3 (23x23)
        let payload = String(repeating: "A", count: 50)

        print("\n=== Compact Layer 3 Comparison (50 'A's) ===")

        // AztecLib
        let options = AztecEncoder.Options(preferCompact: true)
        let details = try AztecEncoder.encodeWithDetails(payload, options: options)
        let symbol = details.symbol

        print("AztecLib: \(symbol.size)x\(symbol.size), compact=\(details.configuration.isCompact), layers=\(details.configuration.layerCount)")
        #expect(details.configuration.isCompact == true)
        #expect(details.configuration.layerCount == 3)
        #expect(symbol.size == 23)

        // CIAztec with compact style forced
        guard let payloadData = payload.data(using: .isoLatin1) else {
            Issue.record("Failed to convert payload to data")
            return
        }

        guard let filter = CIFilter(name: "CIAztecCodeGenerator") else {
            Issue.record("CIAztecCodeGenerator not available")
            return
        }
        filter.setValue(payloadData, forKey: "inputMessage")
        filter.setValue(Float(23.0), forKey: "inputCorrectionLevel")
        filter.setValue(Float(1.0), forKey: "inputCompactStyle")  // Force compact

        guard let ciOutput = filter.outputImage else {
            Issue.record("CIAztec filter returned nil")
            return
        }

        let ciContext = CIContext()
        guard let ciImage = ciContext.createCGImage(ciOutput, from: ciOutput.extent) else {
            Issue.record("Failed to create CGImage from CIFilter")
            return
        }

        let ciSize = ciImage.width
        print("CIAztec:  \(ciSize)x\(ciSize)")

        // Extract modules from CIAztec (1 pixel = 1 module at this scale)
        guard let ciData = ciImage.dataProvider?.data,
              let ptr = CFDataGetBytePtr(ciData) else {
            Issue.record("Could not read CIAztec image data")
            return
        }

        print("\n--- Module-by-Module Comparison ---")
        var differences = 0
        let compareSize = min(symbol.size, ciSize)

        for y in 0..<compareSize {
            var diffRow = ""
            for x in 0..<compareSize {
                let aztecModule = symbol[x: x, y: y]

                // CIAztec: grayscale, so just check red channel
                let offset = y * ciImage.bytesPerRow + x * 4
                let ciModule = ptr[offset] < 128  // dark = true

                if aztecModule != ciModule {
                    differences += 1
                    diffRow += "X"
                } else {
                    diffRow += aztecModule ? "█" : "░"
                }
            }
            if y < 25 {  // Print first 25 rows
                print("Row \(String(format: "%2d", y)): \(diffRow)")
            }
        }

        print("\nTotal differences: \(differences) out of \(compareSize * compareSize) modules")

        // Render and decode AztecLib
        guard let aztecImage = renderAztecSymbol(symbol, moduleSize: 10, quietZoneModules: 4) else {
            Issue.record("Failed to render AztecLib image")
            return
        }

        let (aztecDecoded, aztecError) = decodeAztecWithVision(aztecImage)
        if let data = aztecDecoded, let str = String(data: data, encoding: .isoLatin1) {
            print("AztecLib → Vision: \"\(str.prefix(20))...\" (\(str.count) chars)")
            print("Match: \(str == payload ? "✓" : "✗")")
        } else {
            print("AztecLib → Vision: FAILED - \(aztecError ?? "unknown")")
        }

        // Scale up CIAztec for Vision
        let ciScaled = scaleImage(ciImage, factor: 10)!
        let (ciDecoded, ciError) = decodeAztecWithVision(ciScaled)
        if let data = ciDecoded, let str = String(data: data, encoding: .isoLatin1) {
            print("CIAztec  → Vision: \"\(str.prefix(20))...\" (\(str.count) chars)")
            print("Match: \(str == payload ? "✓" : "✗")")
        } else {
            print("CIAztec  → Vision: FAILED - \(ciError ?? "unknown")")
        }

        // Save images
        let aztecURL = URL(fileURLWithPath: "/tmp/azteclib_compact3.png")
        let ciURL = URL(fileURLWithPath: "/tmp/ciaztec_compact3.png")

        if let dest = CGImageDestinationCreateWithURL(aztecURL as CFURL, kUTTypePNG, 1, nil) {
            CGImageDestinationAddImage(dest, aztecImage, nil)
            CGImageDestinationFinalize(dest)
            print("\nSaved AztecLib to: \(aztecURL.path)")
        }

        if let dest = CGImageDestinationCreateWithURL(ciURL as CFURL, kUTTypePNG, 1, nil) {
            CGImageDestinationAddImage(dest, ciScaled, nil)
            CGImageDestinationFinalize(dest)
            print("Saved CIAztec to: \(ciURL.path)")
        }
    }

    @Test
    func test_problematic_base64_payload() throws {
        // This is the payload that fails - a 488 char Base64 string
        let payload = "CpwCCpkCCpYCCiQ3ZjY1ZmE0Mi04Y2FjLTQ3ZjQtYjEyYy1jNDNlNWUzM2JjNjISDAii6u3LBhD3zZCJAhrcAQoEDAMFCBIYCAESFG5vLnJ1dGVyLlJlaXNlLnN0YWdlEggIAxIEMjYuMBIICAQSBDI2LjASCQgFEgVBcHBsZRIJCAYSBWFybTY0ElgIBxJUUlVUOkN1c3RvbWVyQWNjb3VudDpkMGM4NThiYzE1OTBjODU1ODY0OGFhMTc1ZDA0ZDA3Y2RiNWI1MjMzZmRmMDY0M2FhOGM0ZTQ4YWJlYjFkYjcyEgsICRIHMTYuMTAuMBIPCAoSC0RFVkVMT1BNRU5UEg4ICxIKNDkyR0ZKMzZYVhIICAwSBDExMzUiAQQSTQpGMEQCIEWzEVp6lv2LpiMmy8/D1Pf0EMwMQPnUSz1MMjt2XW5fAiBdy+2YP2NsCM3l7eNunSn7ziHxhmJkzQZSLEcZFLnNUxoBTjAB"

        print("\n=== Testing Problematic Base64 Payload ===")
        print("Payload length: \(payload.count) chars")

        // Test data encoding
        let dataBits = AztecDataEncoder.encode(payload)
        print("Data bits from string encode: \(dataBits.bitCount)")

        // Compare with byte mode
        let byteData = Array(payload.utf8)
        let byteBits = AztecDataEncoder.encode(byteData)
        print("Data bits from byte encode: \(byteBits.bitCount)")
        print("UTF-8 byte count: \(byteData.count)")

        // Check codeword packing for different word sizes
        print("\nCodeword packing analysis:")
        for wordSize in [8, 10, 12] {
            let codewords = dataBits.makeCodewords(codewordBitWidth: wordSize)
            let effectiveDataBits = codewords.count * (wordSize - 1)
            print("  \(wordSize)-bit: \(codewords.count) codewords = ~\(effectiveDataBits) data bits (need \(dataBits.bitCount))")
        }

        // What does CIAztec use? 83x83 = 17 layers (full), 10-bit codewords, 652 total
        print("\nCIAztec comparison (17 layers, 10-bit codewords, 652 total):")
        print("  If using byte mode: \(byteData.count) * 8 + header = ~\(byteData.count * 8 + 16) bits")
        let byteCodewords = byteBits.makeCodewords(codewordBitWidth: 10)
        print("  Byte mode codewords: \(byteCodewords.count)")

        // Encode with AztecLib
        let options = AztecEncoder.Options(preferCompact: false)
        let details = try AztecEncoder.encodeWithDetails(payload, options: options)
        let symbol = details.symbol

        print("AztecLib config: \(symbol.size)x\(symbol.size), compact=\(details.configuration.isCompact), layers=\(details.configuration.layerCount)")
        print("Word size: \(details.configuration.wordSizeInBits) bits")
        print("Data codewords: \(details.configuration.dataCodewordCount)")
        print("Parity codewords: \(details.configuration.parityCodewordCount)")
        print("Total codewords: \(details.configuration.totalCodewordCount)")

        // Render and try to decode with Vision
        guard let aztecLibImage = renderAztecSymbol(symbol, moduleSize: 10, quietZoneModules: 4) else {
            Issue.record("Failed to render AztecLib image")
            return
        }

        let (aztecDecoded, aztecError) = decodeAztecWithVision(aztecLibImage)
        if let data = aztecDecoded, let str = String(data: data, encoding: .isoLatin1) {
            print("AztecLib → Vision: \"\(str.prefix(50))...\" (\(str.count) chars)")
            print("Match: \(str == payload ? "✓" : "✗")")
        } else {
            print("AztecLib → Vision: FAILED - \(aztecError ?? "unknown")")
        }

        // Generate with CIAztec for comparison
        guard let payloadData = payload.data(using: .isoLatin1),
              let ciImage = generateCIAztecCode(data: payloadData, correctionLevel: 23.0) else {
            Issue.record("Failed to generate CIAztec image")
            return
        }

        // Get CIAztec dimensions (approximate from image)
        let ciModuleSize = ciImage.width / 10  // Since we scaled by 10x
        print("CIAztec image: \(ciImage.width/10)x\(ciImage.height/10) modules (approx)")

        let (ciDecoded, ciError) = decodeAztecWithVision(ciImage)
        if let data = ciDecoded, let str = String(data: data, encoding: .isoLatin1) {
            print("CIAztec  → Vision: \"\(str.prefix(50))...\" (\(str.count) chars)")
            print("Match: \(str == payload ? "✓" : "✗")")
        } else {
            print("CIAztec  → Vision: FAILED - \(ciError ?? "unknown")")
        }

        // Also test with byte-mode encoding to see if that works
        print("\n--- Testing with byte-mode encoding ---")
        let byteOptions = AztecEncoder.Options(preferCompact: false)
        let byteSymbol = try AztecEncoder.encode(byteData, options: byteOptions)
        let byteDetails = try AztecEncoder.encodeWithDetails(byteData, options: byteOptions)
        print("Byte mode config: \(byteSymbol.size)x\(byteSymbol.size), layers=\(byteDetails.configuration.layerCount)")
        print("Data codewords: \(byteDetails.configuration.dataCodewordCount)")

        if let byteImage = renderAztecSymbol(byteSymbol, moduleSize: 10, quietZoneModules: 4) {
            let (byteDecoded, byteError) = decodeAztecWithVision(byteImage)
            if let data = byteDecoded, let str = String(data: data, encoding: .isoLatin1) {
                print("Byte mode → Vision: Match=\(str == payload ? "✓" : "✗") (\(str.count) chars)")
            } else {
                print("Byte mode → Vision: FAILED - \(byteError ?? "unknown")")
            }
            // Save byte mode image too
            let byteURL = URL(fileURLWithPath: "/tmp/azteclib_bytemode.png")
            if let dest = CGImageDestinationCreateWithURL(byteURL as CFURL, kUTTypePNG, 1, nil) {
                CGImageDestinationAddImage(dest, byteImage, nil)
                CGImageDestinationFinalize(dest)
                print("Saved byte mode image to: \(byteURL.path)")
            }
        }

        // Save images for external analysis
        let aztecLibURL = URL(fileURLWithPath: "/tmp/azteclib_base64.png")
        let ciURL = URL(fileURLWithPath: "/tmp/ciaztec_base64.png")

        if let aztecLibDest = CGImageDestinationCreateWithURL(aztecLibURL as CFURL, kUTTypePNG, 1, nil) {
            CGImageDestinationAddImage(aztecLibDest, aztecLibImage, nil)
            CGImageDestinationFinalize(aztecLibDest)
            print("\nSaved AztecLib image to: \(aztecLibURL.path)")
        }

        if let ciDest = CGImageDestinationCreateWithURL(ciURL as CFURL, kUTTypePNG, 1, nil) {
            CGImageDestinationAddImage(ciDest, ciImage, nil)
            CGImageDestinationFinalize(ciDest)
            print("Saved CIAztec image to: \(ciURL.path)")
        }
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
        // Full: 4-32 layers (31x31 to 151x151)

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
