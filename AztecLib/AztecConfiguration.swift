//
//  AztecConfiguration.swift
//  AztecLib
//
//  Created by Toni Sucic on 13/10/2025.
//

// MARK: - Configuration

/// Selected Aztec symbol parameters derived from payload size and requested EC.
public struct AztecConfiguration {
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

/// Chooses the smallest symbol that fits the payload at the requested EC level.
///
/// - Parameters:
///   - payloadBitCount: Number of data bits before codeword packing.
///   - errorCorrectionPercentage: Desired ECC percentage (e.g., 23 means 23%).
/// - Returns: The chosen `AztecConfiguration`.
/// - Throws: An error if no symbol can accommodate the payload.
public func pickConfiguration(
    forPayloadBitCount payloadBitCount: Int,
    errorCorrectionPercentage: UInt
) throws -> AztecConfiguration {
    // Stub: fill using the library’s lookup tables.
    fatalError("Unimplemented")
}
