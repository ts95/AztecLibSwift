//
//  AztecDecodeValidationTests.swift
//  AztecLibTests
//
//  Extensive decode validation tests that save images for external decoder verification.
//

import Foundation
import Testing
import CoreImage
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
@testable import AztecLib

// MARK: - Test Image Generator

/// Generates and saves an Aztec code image for external decoder testing.
/// Returns the file path where the image was saved.
func generateTestImage(
    payload: String,
    preferCompact: Bool = true,
    ecLevel: UInt = 23,
    filename: String
) throws -> (path: String, info: String) {
    let options = AztecEncoder.Options(
        errorCorrectionPercentage: ecLevel,
        preferCompact: preferCompact
    )

    let symbol = try AztecEncoder.encode(payload, options: options)
    let details = try AztecEncoder.encodeWithDetails(payload, options: options)

    // Render to image
    let moduleSize = 10
    let quietZone = 4
    let totalModules = symbol.size + (quietZone * 2)
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
        throw NSError(domain: "TestError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to create context"])
    }

    // Fill white background
    context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: imageSize, height: imageSize))

    // Flip coordinates for standard image orientation
    context.translateBy(x: 0, y: CGFloat(imageSize))
    context.scaleBy(x: 1, y: -1)

    // Draw black modules
    context.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
    for y in 0..<symbol.size {
        for x in 0..<symbol.size {
            if symbol[x: x, y: y] {
                let drawX = (quietZone + x) * moduleSize
                let drawY = (quietZone + y) * moduleSize
                context.fill(CGRect(x: drawX, y: drawY, width: moduleSize, height: moduleSize))
            }
        }
    }

    guard let image = context.makeImage() else {
        throw NSError(domain: "TestError", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to create image"])
    }

    // Save to file
    let path = "/tmp/aztec_test_\(filename).png"
    let url = URL(fileURLWithPath: path)

    guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
        throw NSError(domain: "TestError", code: 3, userInfo: [NSLocalizedDescriptionKey: "Failed to create destination"])
    }

    CGImageDestinationAddImage(dest, image, nil)
    guard CGImageDestinationFinalize(dest) else {
        throw NSError(domain: "TestError", code: 4, userInfo: [NSLocalizedDescriptionKey: "Failed to finalize"])
    }

    let info = "\(symbol.size)x\(symbol.size) \(details.configuration.isCompact ? "compact" : "full") L\(details.configuration.layerCount)"
    return (path, info)
}

/// Generates and saves an Aztec code image for binary data.
func generateBinaryTestImage(
    bytes: [UInt8],
    preferCompact: Bool = true,
    ecLevel: UInt = 23,
    filename: String
) throws -> (path: String, info: String) {
    let options = AztecEncoder.Options(
        errorCorrectionPercentage: ecLevel,
        preferCompact: preferCompact
    )

    let symbol = try AztecEncoder.encode(bytes, options: options)
    let details = try AztecEncoder.encodeWithDetails(bytes, options: options)

    // Render to image (same as above)
    let moduleSize = 10
    let quietZone = 4
    let totalModules = symbol.size + (quietZone * 2)
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
        throw NSError(domain: "TestError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to create context"])
    }

    context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: imageSize, height: imageSize))
    context.translateBy(x: 0, y: CGFloat(imageSize))
    context.scaleBy(x: 1, y: -1)
    context.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))

    for y in 0..<symbol.size {
        for x in 0..<symbol.size {
            if symbol[x: x, y: y] {
                let drawX = (quietZone + x) * moduleSize
                let drawY = (quietZone + y) * moduleSize
                context.fill(CGRect(x: drawX, y: drawY, width: moduleSize, height: moduleSize))
            }
        }
    }

    guard let image = context.makeImage() else {
        throw NSError(domain: "TestError", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to create image"])
    }

    let path = "/tmp/aztec_test_\(filename).png"
    let url = URL(fileURLWithPath: path)

    guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
        throw NSError(domain: "TestError", code: 3, userInfo: [NSLocalizedDescriptionKey: "Failed to create destination"])
    }

    CGImageDestinationAddImage(dest, image, nil)
    guard CGImageDestinationFinalize(dest) else {
        throw NSError(domain: "TestError", code: 4, userInfo: [NSLocalizedDescriptionKey: "Failed to finalize"])
    }

    let info = "\(symbol.size)x\(symbol.size) \(details.configuration.isCompact ? "compact" : "full") L\(details.configuration.layerCount)"
    return (path, info)
}

// MARK: - Extensive Test Suite

struct AztecDecodeValidationTests {

    @Test
    func generate_all_test_images() throws {
        print("\n" + String(repeating: "=", count: 70))
        print("GENERATING TEST IMAGES FOR EXTERNAL DECODE VALIDATION")
        print(String(repeating: "=", count: 70))

        var manifest: [(name: String, payload: String, path: String, info: String)] = []

        // Simple strings
        let simpleTests: [(String, String)] = [
            ("simple_A", "A"),
            ("simple_hello", "Hello"),
            ("simple_digits", "12345"),
            ("simple_mixed", "Hello123"),
            ("simple_upper", "ABCDEFGHIJ"),
            ("simple_lower", "abcdefghij"),
        ]

        for (name, payload) in simpleTests {
            let (path, info) = try generateTestImage(payload: payload, filename: name)
            manifest.append((name, payload, path, info))
            print("Generated: \(name) -> \(info)")
        }

        // Special characters
        let specialTests: [(String, String)] = [
            ("special_space", "Hello World"),
            ("special_punct", "Hello, World!"),
            ("special_symbols", "@#$%^&*()"),
            ("special_url", "https://example.com"),
            ("special_email", "test@example.com"),
        ]

        for (name, payload) in specialTests {
            let (path, info) = try generateTestImage(payload: payload, filename: name)
            manifest.append((name, payload, path, info))
            print("Generated: \(name) -> \(info)")
        }

        // Different sizes (tests different layer configurations)
        let sizeTests: [(String, String)] = [
            ("size_5", String(repeating: "A", count: 5)),
            ("size_10", String(repeating: "B", count: 10)),
            ("size_20", String(repeating: "C", count: 20)),
            ("size_50", String(repeating: "D", count: 50)),
            ("size_100", String(repeating: "E", count: 100)),
            ("size_200", String(repeating: "F", count: 200)),
        ]

        for (name, payload) in sizeTests {
            let (path, info) = try generateTestImage(payload: payload, filename: name)
            manifest.append((name, payload, path, info))
            print("Generated: \(name) -> \(info)")
        }

        // Compact vs Full mode
        let (pathCompact, infoCompact) = try generateTestImage(payload: "CompactTest", preferCompact: true, filename: "mode_compact")
        manifest.append(("mode_compact", "CompactTest", pathCompact, infoCompact))
        print("Generated: mode_compact -> \(infoCompact)")

        let (pathFull, infoFull) = try generateTestImage(payload: "FullTest", preferCompact: false, filename: "mode_full")
        manifest.append(("mode_full", "FullTest", pathFull, infoFull))
        print("Generated: mode_full -> \(infoFull)")

        // Different EC levels
        for ec in [5, 10, 23, 33, 50] as [UInt] {
            let (path, info) = try generateTestImage(payload: "EC\(ec)Test", ecLevel: ec, filename: "ec_\(ec)")
            manifest.append(("ec_\(ec)", "EC\(ec)Test", path, info))
            print("Generated: ec_\(ec) -> \(info)")
        }

        // Edge cases
        let edgeTests: [(String, String)] = [
            ("edge_digit", "0"),
            ("edge_space", " "),
            ("edge_repeated", "AAAAAAAAAA"),
            ("edge_alldigits", "0123456789"),
            ("edge_newline", "Line1\nLine2"),
            ("edge_tab", "Col1\tCol2"),
        ]

        for (name, payload) in edgeTests {
            do {
                let (path, info) = try generateTestImage(payload: payload, filename: name)
                manifest.append((name, payload, path, info))
                print("Generated: \(name) -> \(info)")
            } catch {
                print("SKIPPED: \(name) - \(error)")
            }
        }

        // Write manifest file for Python decoder
        print("\n" + String(repeating: "-", count: 70))
        print("Writing manifest file...")

        var manifestContent = "# Test manifest for AztecLib decode validation\n"
        manifestContent += "# Format: name|payload|path|info\n"
        for (name, payload, path, info) in manifest {
            let escapedPayload = payload
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "|", with: "\\|")
                .replacingOccurrences(of: "\n", with: "\\n")
                .replacingOccurrences(of: "\t", with: "\\t")
            manifestContent += "\(name)|\(escapedPayload)|\(path)|\(info)\n"
        }

        try manifestContent.write(toFile: "/tmp/aztec_test_manifest.txt", atomically: true, encoding: .utf8)
        print("Manifest written to: /tmp/aztec_test_manifest.txt")
        print("Total images generated: \(manifest.count)")

        print("\nTo decode all images, run:")
        print("  source ~/.venv/zxing/bin/activate")
        print("  python3 Scripts/decode_all_tests.py")
    }
}
