//
//  AztecConfiguration.swift
//  AztecLib
//
//  Created by Toni Sucic on 13/10/2025.
//

import Foundation

// MARK: - Configuration

/// Selected Aztec symbol parameters derived from payload size and requested EC.
public struct AztecConfiguration: Sendable {
    /// `true` for compact symbols, `false` for full symbols.
    public let isCompact: Bool
    /// Number of concentric data layers.
    public let layerCount: Int
    /// Codeword bit width `m` (6, 8, 10, or 12).
    public let wordSizeInBits: Int
    /// Total codewords (data + parity).
    public let totalCodewordCount: Int
    /// Data codewords only.
    public let dataCodewordCount: Int
    /// Parity codewords only.
    public let parityCodewordCount: Int
    /// Primitive polynomial used for GF(2^m) arithmetic.
    public let primitivePolynomial: UInt32
    /// RS generator starting exponent.
    public let rsStartExponent: Int
}

/// Error thrown when no symbol can accommodate the payload.
public enum AztecConfigurationError: Error, Sendable {
    case payloadTooLarge(payloadBitCount: Int)
}

// MARK: - Symbol Specification

/// Internal specification for a single Aztec symbol size.
internal struct SymbolSpec: Sendable {
    let isCompact: Bool
    let layerCount: Int
    let wordSizeInBits: Int
    let totalCodewordCount: Int
}

// MARK: - Primitive Polynomials

/// Primitive polynomials for Galois fields used in Aztec codes.
/// - GF(2^6):  x^6 + x + 1 = 0x43
/// - GF(2^8):  x^8 + x^5 + x^3 + x^2 + 1 = 0x12D
/// - GF(2^10): x^10 + x^3 + 1 = 0x409
/// - GF(2^12): x^12 + x^6 + x^5 + x^3 + 1 = 0x1069
internal enum AztecPrimitivePolynomials: Sendable {
    static let gf6: UInt32 = 0x43
    static let gf8: UInt32 = 0x12D
    static let gf10: UInt32 = 0x409
    static let gf12: UInt32 = 0x1069

    static func polynomial(forWordSize wordSize: Int) -> UInt32 {
        switch wordSize {
        case 6: return gf6
        case 8: return gf8
        case 10: return gf10
        case 12: return gf12
        default: fatalError("Invalid word size \(wordSize)")
        }
    }
}

// MARK: - Symbol Lookup Tables

/// Compact symbol specifications (layers 1-4).
/// Total codewords per ISO/IEC 24778 Table 2.
internal let compactSymbolSpecs: [SymbolSpec] = [
    SymbolSpec(isCompact: true, layerCount: 1, wordSizeInBits: 6, totalCodewordCount: 17),
    SymbolSpec(isCompact: true, layerCount: 2, wordSizeInBits: 6, totalCodewordCount: 40),
    SymbolSpec(isCompact: true, layerCount: 3, wordSizeInBits: 8, totalCodewordCount: 51),
    SymbolSpec(isCompact: true, layerCount: 4, wordSizeInBits: 8, totalCodewordCount: 76),
]

/// Full symbol specifications (layers 1-32).
/// Total codewords per ISO/IEC 24778 Table 2.
internal let fullSymbolSpecs: [SymbolSpec] = [
    SymbolSpec(isCompact: false, layerCount: 1, wordSizeInBits: 6, totalCodewordCount: 21),
    SymbolSpec(isCompact: false, layerCount: 2, wordSizeInBits: 6, totalCodewordCount: 48),
    SymbolSpec(isCompact: false, layerCount: 3, wordSizeInBits: 8, totalCodewordCount: 60),
    SymbolSpec(isCompact: false, layerCount: 4, wordSizeInBits: 8, totalCodewordCount: 88),
    SymbolSpec(isCompact: false, layerCount: 5, wordSizeInBits: 8, totalCodewordCount: 120),
    SymbolSpec(isCompact: false, layerCount: 6, wordSizeInBits: 8, totalCodewordCount: 156),
    SymbolSpec(isCompact: false, layerCount: 7, wordSizeInBits: 8, totalCodewordCount: 196),
    SymbolSpec(isCompact: false, layerCount: 8, wordSizeInBits: 8, totalCodewordCount: 240),
    SymbolSpec(isCompact: false, layerCount: 9, wordSizeInBits: 10, totalCodewordCount: 230),
    SymbolSpec(isCompact: false, layerCount: 10, wordSizeInBits: 10, totalCodewordCount: 272),
    SymbolSpec(isCompact: false, layerCount: 11, wordSizeInBits: 10, totalCodewordCount: 316),
    SymbolSpec(isCompact: false, layerCount: 12, wordSizeInBits: 10, totalCodewordCount: 364),
    SymbolSpec(isCompact: false, layerCount: 13, wordSizeInBits: 10, totalCodewordCount: 416),
    SymbolSpec(isCompact: false, layerCount: 14, wordSizeInBits: 10, totalCodewordCount: 470),
    SymbolSpec(isCompact: false, layerCount: 15, wordSizeInBits: 10, totalCodewordCount: 528),
    SymbolSpec(isCompact: false, layerCount: 16, wordSizeInBits: 10, totalCodewordCount: 588),
    SymbolSpec(isCompact: false, layerCount: 17, wordSizeInBits: 10, totalCodewordCount: 652),
    SymbolSpec(isCompact: false, layerCount: 18, wordSizeInBits: 10, totalCodewordCount: 720),
    SymbolSpec(isCompact: false, layerCount: 19, wordSizeInBits: 10, totalCodewordCount: 790),
    SymbolSpec(isCompact: false, layerCount: 20, wordSizeInBits: 10, totalCodewordCount: 864),
    SymbolSpec(isCompact: false, layerCount: 21, wordSizeInBits: 10, totalCodewordCount: 940),
    SymbolSpec(isCompact: false, layerCount: 22, wordSizeInBits: 10, totalCodewordCount: 1020),
    SymbolSpec(isCompact: false, layerCount: 23, wordSizeInBits: 12, totalCodewordCount: 920),
    SymbolSpec(isCompact: false, layerCount: 24, wordSizeInBits: 12, totalCodewordCount: 992),
    SymbolSpec(isCompact: false, layerCount: 25, wordSizeInBits: 12, totalCodewordCount: 1066),
    SymbolSpec(isCompact: false, layerCount: 26, wordSizeInBits: 12, totalCodewordCount: 1144),
    SymbolSpec(isCompact: false, layerCount: 27, wordSizeInBits: 12, totalCodewordCount: 1224),
    SymbolSpec(isCompact: false, layerCount: 28, wordSizeInBits: 12, totalCodewordCount: 1306),
    SymbolSpec(isCompact: false, layerCount: 29, wordSizeInBits: 12, totalCodewordCount: 1392),
    SymbolSpec(isCompact: false, layerCount: 30, wordSizeInBits: 12, totalCodewordCount: 1480),
    SymbolSpec(isCompact: false, layerCount: 31, wordSizeInBits: 12, totalCodewordCount: 1570),
    SymbolSpec(isCompact: false, layerCount: 32, wordSizeInBits: 12, totalCodewordCount: 1664),
]

/// All symbol specs sorted by total capacity (smallest first).
internal let allSymbolSpecs: [SymbolSpec] = {
    (compactSymbolSpecs + fullSymbolSpecs).sorted { a, b in
        let aBits = a.totalCodewordCount * a.wordSizeInBits
        let bBits = b.totalCodewordCount * b.wordSizeInBits
        if aBits != bBits { return aBits < bBits }
        // Prefer compact for same capacity
        if a.isCompact != b.isCompact { return a.isCompact }
        return a.layerCount < b.layerCount
    }
}()

// MARK: - Configuration Selection

/// Chooses the smallest symbol that fits the payload at the requested EC level.
///
/// - Parameters:
///   - payloadBitCount: Number of data bits before codeword packing.
///   - errorCorrectionPercentage: Desired ECC percentage (e.g., 23 means 23%).
///   - preferCompact: If `true`, prefer compact symbols when both fit.
/// - Returns: The chosen `AztecConfiguration`.
/// - Throws: `AztecConfigurationError.payloadTooLarge` if no symbol can accommodate the payload.
public func pickConfiguration(
    forPayloadBitCount payloadBitCount: Int,
    errorCorrectionPercentage: UInt,
    preferCompact: Bool = true
) throws -> AztecConfiguration {
    let ecFraction = Double(errorCorrectionPercentage) / 100.0

    for spec in allSymbolSpecs {
        // Skip full symbols if we prefer compact and haven't exhausted compact options
        if preferCompact && !spec.isCompact {
            // Check if any compact symbol could fit
            let compactFits = compactSymbolSpecs.contains { compact in
                canFit(spec: compact, payloadBitCount: payloadBitCount, ecFraction: ecFraction)
            }
            if compactFits { continue }
        }

        if let config = tryConfiguration(spec: spec, payloadBitCount: payloadBitCount, ecFraction: ecFraction) {
            return config
        }
    }

    throw AztecConfigurationError.payloadTooLarge(payloadBitCount: payloadBitCount)
}

/// Checks if a symbol spec can fit the payload with the given EC fraction.
private func canFit(spec: SymbolSpec, payloadBitCount: Int, ecFraction: Double) -> Bool {
    return tryConfiguration(spec: spec, payloadBitCount: payloadBitCount, ecFraction: ecFraction) != nil
}

/// Attempts to create a configuration from a spec. Returns nil if payload doesn't fit.
private func tryConfiguration(spec: SymbolSpec, payloadBitCount: Int, ecFraction: Double) -> AztecConfiguration? {
    let wordSize = spec.wordSizeInBits
    let totalCodewords = spec.totalCodewordCount

    // Calculate data codewords needed for payload
    // Each codeword has (wordSize - 1) data bits due to stuff bit
    let dataBitsPerCodeword = wordSize - 1
    let dataCodewordsNeeded = (payloadBitCount + dataBitsPerCodeword - 1) / dataBitsPerCodeword

    // Calculate minimum parity codewords based on EC percentage
    // parityCount >= ceil(dataCodewords * ecFraction)
    let minParityCodewords = Int(ceil(Double(dataCodewordsNeeded) * ecFraction))

    // Ensure at least 3 parity codewords for any meaningful error correction
    let parityCodewords = max(minParityCodewords, 3)

    // Check if we have enough total codewords
    let requiredCodewords = dataCodewordsNeeded + parityCodewords
    guard requiredCodewords <= totalCodewords else { return nil }

    // Allocate remaining capacity to parity (up to the requested EC level)
    let availableForParity = totalCodewords - dataCodewordsNeeded
    let actualParityCodewords = min(availableForParity, max(parityCodewords, minParityCodewords))
    let actualDataCodewords = totalCodewords - actualParityCodewords

    return AztecConfiguration(
        isCompact: spec.isCompact,
        layerCount: spec.layerCount,
        wordSizeInBits: wordSize,
        totalCodewordCount: totalCodewords,
        dataCodewordCount: actualDataCodewords,
        parityCodewordCount: actualParityCodewords,
        primitivePolynomial: AztecPrimitivePolynomials.polynomial(forWordSize: wordSize),
        rsStartExponent: 1
    )
}
