//
//  AztecEncoder.swift
//  AztecLib
//
//  Created by Toni Sucic on 13/10/2025.
//

import Foundation

// MARK: - Aztec Encoder

/// High-level Aztec code encoder supporting strings and byte arrays.
public struct AztecEncoder: Sendable {

    // MARK: - Options

    /// Configuration options for Aztec encoding.
    public struct Options: Sendable {
        /// Desired error correction percentage (e.g., 23 means 23%).
        /// Higher values provide more error correction at the cost of larger symbols.
        public var errorCorrectionPercentage: UInt

        /// If `true`, prefer compact symbols over full symbols when both would fit.
        public var preferCompact: Bool

        /// If `true`, export rows with MSB-first bit ordering (for PNG compatibility).
        /// If `false`, export rows with LSB-first bit ordering.
        public var exportMSBFirst: Bool

        /// Creates default encoding options.
        public init(
            errorCorrectionPercentage: UInt = 23,
            preferCompact: Bool = true,
            exportMSBFirst: Bool = false
        ) {
            self.errorCorrectionPercentage = errorCorrectionPercentage
            self.preferCompact = preferCompact
            self.exportMSBFirst = exportMSBFirst
        }
    }

    // MARK: - Encoding Errors

    /// Errors that can occur during Aztec encoding.
    public enum EncodingError: Error, Sendable {
        /// The payload is too large for any Aztec symbol.
        case payloadTooLarge(bitCount: Int)
        /// Invalid configuration.
        case invalidConfiguration(String)
    }

    // MARK: - Public API

    /// Encodes a string into an Aztec symbol.
    ///
    /// - Parameters:
    ///   - string: The string to encode.
    ///   - options: Encoding options.
    /// - Returns: An `AztecSymbol` containing the rendered barcode.
    /// - Throws: `EncodingError` if encoding fails.
    public static func encode(_ string: String, options: Options = Options()) throws(EncodingError) -> AztecSymbol {
        let dataBits = AztecDataEncoder.encode(string)
        return try encodeData(dataBits, options: options)
    }

    /// Encodes a byte array into an Aztec symbol.
    ///
    /// - Parameters:
    ///   - bytes: The bytes to encode.
    ///   - options: Encoding options.
    /// - Returns: An `AztecSymbol` containing the rendered barcode.
    /// - Throws: `EncodingError` if encoding fails.
    public static func encode(_ bytes: [UInt8], options: Options = Options()) throws(EncodingError) -> AztecSymbol {
        let dataBits = AztecDataEncoder.encode(bytes)
        return try encodeData(dataBits, options: options)
    }

    /// Encodes Data into an Aztec symbol.
    ///
    /// - Parameters:
    ///   - data: The data to encode.
    ///   - options: Encoding options.
    /// - Returns: An `AztecSymbol` containing the rendered barcode.
    /// - Throws: `EncodingError` if encoding fails.
    public static func encode(_ data: Data, options: Options = Options()) throws(EncodingError) -> AztecSymbol {
        let dataBits = AztecDataEncoder.encode(data)
        return try encodeData(dataBits, options: options)
    }

    // MARK: - Internal Pipeline

    /// Core encoding pipeline: data bits -> pack with each spec -> select smallest fitting -> RS parity -> matrix -> symbol.
    private static func encodeData(_ dataBits: BitBuffer, options: Options) throws(EncodingError) -> AztecSymbol {
        let ecFraction = Double(options.errorCorrectionPercentage) / 100.0

        // Cache packed codewords per word size (avoid redundant packing)
        var packedCache: [Int: [UInt16]] = [:]

        // Step 1: Find smallest fitting spec by iterating allSymbolSpecs
        var bestSpec: SymbolSpec? = nil
        var bestCodewords: [UInt16]? = nil
        var bestParityCount: Int = 0

        for spec in allSymbolSpecs {
            // Skip compact symbols if preferCompact is false (force full symbols)
            if !options.preferCompact && spec.isCompact {
                continue
            }

            // Skip full symbols if we prefer compact and a compact option could fit
            if options.preferCompact && !spec.isCompact && bestSpec != nil && bestSpec!.isCompact {
                continue
            }

            // Pack using this spec's word size (cache to avoid re-packing)
            let codewords: [UInt16]
            if let cached = packedCache[spec.wordSizeInBits] {
                codewords = cached
            } else {
                codewords = dataBits.makeCodewords(codewordBitWidth: spec.wordSizeInBits)
                packedCache[spec.wordSizeInBits] = codewords
            }

            // Compute required parity count (at least 3, or ecFraction of data codewords)
            let minParity = max(3, Int(ceil(Double(codewords.count) * ecFraction)))

            // Check if it fits
            if codewords.count + minParity <= spec.totalCodewordCount {
                // Found a fitting spec - allSymbolSpecs is sorted smallest-first
                // But keep looking if we prefer compact and haven't found a compact yet
                if options.preferCompact && bestSpec == nil && !spec.isCompact {
                    // Check if any later compact symbol could fit
                    var compactFits = false
                    for laterSpec in allSymbolSpecs where laterSpec.isCompact {
                        let laterCodewords: [UInt16]
                        if let cached = packedCache[laterSpec.wordSizeInBits] {
                            laterCodewords = cached
                        } else {
                            let packed = dataBits.makeCodewords(codewordBitWidth: laterSpec.wordSizeInBits)
                            packedCache[laterSpec.wordSizeInBits] = packed
                            laterCodewords = packed
                        }
                        let laterMinParity = max(3, Int(ceil(Double(laterCodewords.count) * ecFraction)))
                        if laterCodewords.count + laterMinParity <= laterSpec.totalCodewordCount {
                            compactFits = true
                            break
                        }
                    }
                    if compactFits {
                        continue
                    }
                }

                bestSpec = spec
                bestCodewords = codewords
                bestParityCount = minParity
                break
            }
        }

        guard let spec = bestSpec, var dataCodewords = bestCodewords else {
            throw EncodingError.payloadTooLarge(bitCount: dataBits.bitCount)
        }

        // Build configuration from spec
        let availableForParity = spec.totalCodewordCount - dataCodewords.count
        let actualParity = min(availableForParity, max(bestParityCount, Int(ceil(Double(dataCodewords.count) * ecFraction))))
        let actualDataCodewordCount = spec.totalCodewordCount - actualParity

        let configuration = AztecConfiguration(
            isCompact: spec.isCompact,
            layerCount: spec.layerCount,
            wordSizeInBits: spec.wordSizeInBits,
            totalCodewordCount: spec.totalCodewordCount,
            dataCodewordCount: actualDataCodewordCount,
            parityCodewordCount: actualParity,
            primitivePolynomial: AztecPrimitivePolynomials.polynomial(forWordSize: spec.wordSizeInBits),
            rsStartExponent: 1
        )

        // Safety check: truncation should never happen with proper config selection
        precondition(
            dataCodewords.count <= configuration.dataCodewordCount,
            "Internal error: packed codewords (\(dataCodewords.count)) exceed config capacity (\(configuration.dataCodewordCount))"
        )

        // Step 2: Pad with valid filler codewords (not raw zeros which are forbidden)
        let filler = BitBuffer.makeFillerCodeword(bitWidth: configuration.wordSizeInBits)
        while dataCodewords.count < configuration.dataCodewordCount {
            dataCodewords.append(filler)
        }

        // Step 3: Generate RS parity codewords
        let gf = GaloisField(
            wordSizeInBits: configuration.wordSizeInBits,
            primitivePolynomial: configuration.primitivePolynomial
        )
        let rsEncoder = ReedSolomonEncoder(field: gf, startExponent: configuration.rsStartExponent)
        let allCodewords = rsEncoder.appendingParity(
            to: dataCodewords,
            parityCodewordCount: configuration.parityCodewordCount
        )

        // Step 4: Build the matrix
        let builder = AztecMatrixBuilder(configuration: configuration)
        let modeMessage = builder.encodeModeMessage()
        let matrixBits = builder.buildMatrix(dataCodewords: allCodewords, modeMessageBits: modeMessage)

        // Step 5: Export to symbol
        let symbol = matrixBits.makeSymbolExport(
            matrixSize: builder.symbolSize,
            rowOrderMostSignificantBitFirst: options.exportMSBFirst
        )

        return symbol
    }
}

// MARK: - Convenience Extensions

extension AztecEncoder {

    /// Result containing both the symbol and its configuration.
    public struct EncodingResult: Sendable {
        /// The rendered Aztec symbol.
        public let symbol: AztecSymbol
        /// The configuration used for encoding.
        public let configuration: AztecConfiguration
    }

    /// Encodes a string and returns both the symbol and configuration.
    ///
    /// - Parameters:
    ///   - string: The string to encode.
    ///   - options: Encoding options.
    /// - Returns: An `EncodingResult` containing the symbol and configuration.
    /// - Throws: `EncodingError` if encoding fails.
    public static func encodeWithDetails(_ string: String, options: Options = Options()) throws(EncodingError) -> EncodingResult {
        let dataBits = AztecDataEncoder.encode(string)
        return try encodeDataWithDetails(dataBits, options: options)
    }

    /// Encodes bytes and returns both the symbol and configuration.
    ///
    /// - Parameters:
    ///   - bytes: The bytes to encode.
    ///   - options: Encoding options.
    /// - Returns: An `EncodingResult` containing the symbol and configuration.
    /// - Throws: `EncodingError` if encoding fails.
    public static func encodeWithDetails(_ bytes: [UInt8], options: Options = Options()) throws(EncodingError) -> EncodingResult {
        let dataBits = AztecDataEncoder.encode(bytes)
        return try encodeDataWithDetails(dataBits, options: options)
    }

    /// Core encoding pipeline that returns configuration details.
    private static func encodeDataWithDetails(_ dataBits: BitBuffer, options: Options) throws(EncodingError) -> EncodingResult {
        let ecFraction = Double(options.errorCorrectionPercentage) / 100.0

        // Cache packed codewords per word size (avoid redundant packing)
        var packedCache: [Int: [UInt16]] = [:]

        // Find smallest fitting spec by iterating allSymbolSpecs
        var bestSpec: SymbolSpec? = nil
        var bestCodewords: [UInt16]? = nil
        var bestParityCount: Int = 0

        for spec in allSymbolSpecs {
            // Skip compact symbols if preferCompact is false (force full symbols)
            if !options.preferCompact && spec.isCompact {
                continue
            }

            // Skip full symbols if we prefer compact and a compact option could fit
            if options.preferCompact && !spec.isCompact && bestSpec != nil && bestSpec!.isCompact {
                continue
            }

            // Pack using this spec's word size (cache to avoid re-packing)
            let codewords: [UInt16]
            if let cached = packedCache[spec.wordSizeInBits] {
                codewords = cached
            } else {
                codewords = dataBits.makeCodewords(codewordBitWidth: spec.wordSizeInBits)
                packedCache[spec.wordSizeInBits] = codewords
            }

            // Compute required parity count
            let minParity = max(3, Int(ceil(Double(codewords.count) * ecFraction)))

            // Check if it fits
            if codewords.count + minParity <= spec.totalCodewordCount {
                if options.preferCompact && bestSpec == nil && !spec.isCompact {
                    var compactFits = false
                    for laterSpec in allSymbolSpecs where laterSpec.isCompact {
                        let laterCodewords: [UInt16]
                        if let cached = packedCache[laterSpec.wordSizeInBits] {
                            laterCodewords = cached
                        } else {
                            let packed = dataBits.makeCodewords(codewordBitWidth: laterSpec.wordSizeInBits)
                            packedCache[laterSpec.wordSizeInBits] = packed
                            laterCodewords = packed
                        }
                        let laterMinParity = max(3, Int(ceil(Double(laterCodewords.count) * ecFraction)))
                        if laterCodewords.count + laterMinParity <= laterSpec.totalCodewordCount {
                            compactFits = true
                            break
                        }
                    }
                    if compactFits {
                        continue
                    }
                }

                bestSpec = spec
                bestCodewords = codewords
                bestParityCount = minParity
                break
            }
        }

        guard let spec = bestSpec, var dataCodewords = bestCodewords else {
            throw EncodingError.payloadTooLarge(bitCount: dataBits.bitCount)
        }

        // Build configuration from spec
        let availableForParity = spec.totalCodewordCount - dataCodewords.count
        let actualParity = min(availableForParity, max(bestParityCount, Int(ceil(Double(dataCodewords.count) * ecFraction))))
        let actualDataCodewordCount = spec.totalCodewordCount - actualParity

        let configuration = AztecConfiguration(
            isCompact: spec.isCompact,
            layerCount: spec.layerCount,
            wordSizeInBits: spec.wordSizeInBits,
            totalCodewordCount: spec.totalCodewordCount,
            dataCodewordCount: actualDataCodewordCount,
            parityCodewordCount: actualParity,
            primitivePolynomial: AztecPrimitivePolynomials.polynomial(forWordSize: spec.wordSizeInBits),
            rsStartExponent: 1
        )

        // Safety check: truncation should never happen
        precondition(
            dataCodewords.count <= configuration.dataCodewordCount,
            "Internal error: packed codewords (\(dataCodewords.count)) exceed config capacity (\(configuration.dataCodewordCount))"
        )

        // Pad with valid filler codewords
        let filler = BitBuffer.makeFillerCodeword(bitWidth: configuration.wordSizeInBits)
        while dataCodewords.count < configuration.dataCodewordCount {
            dataCodewords.append(filler)
        }

        let gf = GaloisField(
            wordSizeInBits: configuration.wordSizeInBits,
            primitivePolynomial: configuration.primitivePolynomial
        )
        let rsEncoder = ReedSolomonEncoder(field: gf, startExponent: configuration.rsStartExponent)
        let allCodewords = rsEncoder.appendingParity(
            to: dataCodewords,
            parityCodewordCount: configuration.parityCodewordCount
        )

        let builder = AztecMatrixBuilder(configuration: configuration)
        let modeMessage = builder.encodeModeMessage()
        let matrixBits = builder.buildMatrix(dataCodewords: allCodewords, modeMessageBits: modeMessage)

        let symbol = matrixBits.makeSymbolExport(
            matrixSize: builder.symbolSize,
            rowOrderMostSignificantBitFirst: options.exportMSBFirst
        )

        return EncodingResult(symbol: symbol, configuration: configuration)
    }
}
