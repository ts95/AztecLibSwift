//
//  BitBuffer.swift
//  AztecLib
//
//  Created by Toni Sucic on 13/10/2025.
//

import Foundation

/// A growable, random-access buffer of individual bits with support for both
/// least-significant-bit-first (LSB) and most-significant-bit-first (MSB) appends.
///
/// Storage is chunked in machine words to minimize reallocations. Bounds are
/// checked in debug builds.
public struct BitBuffer: Sendable {
    @usableFromInline internal var words = [UInt64]()
    /// Total number of valid bits currently stored.
    public private(set) var bitCount: Int = 0

    /// Creates an empty bit buffer.
    public init() {}

    // MARK: Capacity and clearing

    /// Ensures capacity for at least `bitCount` bits without further allocation.
    ///
    /// - Parameter bitCount: The number of bits to reserve space for.
    public mutating func reserveCapacity(bitCount: Int) {
        precondition(bitCount >= 0)
        let requiredWords = (bitCount + 63) >> 6
        if words.count < requiredWords {
            words.reserveCapacity(requiredWords)
            words.append(contentsOf: repeatElement(0, count: requiredWords - words.count))
        }
    }

    /// Removes all bits from the buffer, optionally keeping the allocated storage.
    ///
    /// - Parameter keepingCapacity: If `true`, the underlying storage is retained.
    public mutating func removeAll(keepingCapacity: Bool = true) {
        bitCount = 0
        if keepingCapacity {
            for i in words.indices { words[i] = 0 }
        } else {
            words.removeAll(keepingCapacity: false)
        }
    }

    // MARK: Appending

    /// Appends `bitCount` bits from the least-significant side of `value`.
    ///
    /// - Parameters:
    ///   - value: The source value whose least-significant `bitCount` bits are appended.
    ///   - bitCount: The number of bits to append. Must be in `0...64`.
    public mutating func appendLeastSignificantBits(_ value: UInt64, bitCount: Int) {
        precondition(0...64 ~= bitCount)
        if bitCount == 0 { return }
        writeBits(atBitPosition: self.bitCount, fromLeastSignificantBits: value, bitCount: bitCount)
        self.bitCount += bitCount
    }

    /// Appends `bitCount` bits from the most-significant side of `value`.
    ///
    /// - Parameters:
    ///   - value: The source value whose most-significant `bitCount` bits are appended.
    ///   - bitCount: The number of bits to append. Must be in `0...64`.
    public mutating func appendMostSignificantBits(_ value: UInt64, bitCount: Int) {
        precondition(0...64 ~= bitCount)
        if bitCount == 0 { return }
        let lsb = value & (bitCount == 64 ? ~0 : ((1 << bitCount) &- 1) << (64 - bitCount))
        let shifted = bitCount == 64 ? value : lsb >> (64 - bitCount)
        appendLeastSignificantBits(shifted, bitCount: bitCount)
    }

    // MARK: Random write

    /// Writes `bitCount` bits taken from the least-significant side of `value` at `bitPosition`.
    ///
    /// - Parameters:
    ///   - bitPosition: Zero-based bit index where the first bit is written.
    ///   - value: Source value. The least-significant `bitCount` bits are used.
    ///   - bitCount: Number of bits to write. Must be in `0...64`.
    public mutating func setBits(
        atBitPosition bitPosition: Int,
        fromLeastSignificantBits value: UInt64,
        bitCount: Int
    ) {
        precondition(bitPosition >= 0)
        precondition(0...64 ~= bitCount)
        if bitCount == 0 { return }
        let end = bitPosition + bitCount
        if end > capacityInBits { reserveCapacity(bitCount: end) }
        writeBits(atBitPosition: bitPosition, fromLeastSignificantBits: value, bitCount: bitCount)
        if end > self.bitCount { self.bitCount = end }
    }

    // MARK: Random read

    /// Reads `bitCount` bits starting at `bitPosition` and returns them packed in the LSBs.
    ///
    /// - Parameters:
    ///   - bitPosition: Zero-based bit index to start reading.
    ///   - bitCount: Number of bits to read. Must be in `0...64`.
    /// - Returns: The bits packed into the least-significant `bitCount` bits of the result.
    public func leastSignificantBits(atBitPosition bitPosition: Int, bitCount: Int) -> UInt64 {
        precondition(0...64 ~= bitCount)
        if bitCount == 0 { return 0 }
        return readBits(atBitPosition: bitPosition, bitCount: bitCount)
    }

    /// Reads `bitCount` bits starting at `bitPosition` and returns them packed MSB-first.
    ///
    /// - Parameters:
    ///   - bitPosition: Zero-based bit index to start reading.
    ///   - bitCount: Number of bits to read. Must be in `0...64`.
    /// - Returns: The bits aligned to the most-significant side of the result.
    public func mostSignificantBits(atBitPosition bitPosition: Int, bitCount: Int) -> UInt64 {
        let lsb = leastSignificantBits(atBitPosition: bitPosition, bitCount: bitCount)
        if bitCount == 64 { return lsb }
        return lsb << (64 - bitCount)
    }

    // MARK: Internals

    @inline(__always) private var capacityInBits: Int { words.count << 6 }

    @inline(__always) private mutating func writeBits(
        atBitPosition p: Int,
        fromLeastSignificantBits v: UInt64,
        bitCount n: Int
    ) {
        // Ensure capacity and materialize target words before writing.
        let end = p + n
        if end > capacityInBits { reserveCapacity(bitCount: end) }

        var remaining = n
        var value = v
        var pos = p
        while remaining > 0 {
            let wi = pos >> 6
            let off = pos & 63
            let room = 64 - off
            let take = min(remaining, room)
            let mask: UInt64 = (take == 64) ? ~0 : ((1 &<< take) &- 1)
            let chunk = value & mask
            words[wi] &= ~(mask &<< off)
            words[wi] |= chunk &<< off
            value >>= take
            remaining -= take
            pos += take
        }
    }

    @inline(__always) private func readBits(atBitPosition p: Int, bitCount n: Int) -> UInt64 {
        var remaining = n
        var pos = p
        var out: UInt64 = 0
        var shift: UInt64 = 0
        while remaining > 0 {
            let wi = pos >> 6
            let off = pos & 63
            let room = 64 - off
            let take = min(remaining, room)
            let mask: UInt64 = (take == 64) ? ~0 : ((1 &<< take) &- 1)
            let chunk = (words.indices.contains(wi) ? words[wi] : 0) >> off
            out |= (chunk & mask) << shift
            shift += UInt64(take)
            pos += take
            remaining -= take
        }
        return out
    }
}

extension BitBuffer {

    // MARK: - MSB-First Appending (ZXing-compatible)

    /// Appends `bitCount` bits from `value` in MSB-first order within the value.
    /// This matches ZXing's BitArray.appendBits() behavior.
    ///
    /// For example, appending value=9 (binary 01001) with bitCount=5:
    /// - ZXing order: bit4, bit3, bit2, bit1, bit0 → stored as 0,1,0,0,1
    ///
    /// - Parameters:
    ///   - value: The source value to append.
    ///   - bitCount: The number of bits to append. Must be in `0...64`.
    public mutating func appendBitsMSBFirst(_ value: UInt64, bitCount: Int) {
        precondition(0...64 ~= bitCount)
        if bitCount == 0 { return }
        // Append each bit from MSB to LSB of the value
        for i in stride(from: bitCount - 1, through: 0, by: -1) {
            let bit = (value >> i) & 1
            appendLeastSignificantBits(bit, bitCount: 1)
        }
    }

    // MARK: - Filler Codeword

    /// Generates a valid filler codeword for the given bit width.
    ///
    /// The filler is equivalent to what stuffing produces for an all-zeros input:
    /// `(0 << 1) | 1 = 1` (the stuff bit prevents all-zeros).
    /// Per ISO/IEC 24778 stuffing rule: all-zeros becomes `(zeros << 1) | 1 = 1`.
    /// This is the canonical "empty" codeword that carries no payload data.
    ///
    /// - Parameter bitWidth: The codeword bit width (6, 8, 10, or 12).
    /// - Returns: A valid filler codeword value.
    public static func makeFillerCodeword(bitWidth: Int) -> UInt16 {
        return 1
    }

    // MARK: - Codeword packing

    /// Rewraps a packed bit stream into fixed-width Aztec codewords with “stuff bit”—rules
    /// per ISO/IEC 24778. Groups `codewordBitWidth - 1` data bits and inserts
    /// one extra bit so no codeword is all zeros or all ones.
    ///
    /// Stuffing rule:
    /// - If the next `w-1` bits are all `0`, emit `(bits << 1) | 1` and do **not**
    ///   consume an extra source bit.
    /// - If they are all `1`, emit `(bits << 1) | 0` and do **not** consume an extra
    ///   source bit.
    /// - Otherwise, consume one more bit from the source and emit `(bits << 1) | b`.
    ///
    /// The final, partial group is left-padded with zeros to `w-1` bits, then the
    /// same stuffing rule is applied.
    ///
    /// - Parameters:
    ///   - codewordBitWidth: The codeword width `w` in bits (6, 8, 10, or 12).
    /// - Returns: The sequence of data codewords before Reed–Solomon parity.
    public func makeCodewords(codewordBitWidth w: Int) -> [UInt16] {
        // Implementation matches ZXing's stuffBits algorithm exactly.
        // ZXing reads wordSize bits at a time, padding with 1s when past end.
        // If all upper bits (excluding LSB) are 0 or 1, stuff and don't consume last bit.
        precondition([6, 8, 10, 12].contains(w), "Invalid Aztec codeword width")
        let mask = (1 << w) - 2  // e.g., 0b111110 for w=6
        let total = bitCount
        var pos = 0
        var out: [UInt16] = []

        while pos < total {
            // Read wordSize bits, padding with 1s when past end (per ZXing)
            var word = 0
            for j in 0..<w {
                let bitValue: Int
                if pos + j >= total {
                    // Past end of input: treat as 1 (per ZXing)
                    bitValue = 1
                } else {
                    // Read bit at position pos+j, place in MSB-first order
                    bitValue = Int(leastSignificantBits(atBitPosition: pos + j, bitCount: 1))
                }
                if bitValue != 0 {
                    word |= 1 << (w - 1 - j)
                }
            }

            if (word & mask) == mask {
                // All 1s in upper bits: stuff 0, don't consume last bit
                out.append(UInt16(word & mask))
                pos += w - 1
            } else if (word & mask) == 0 {
                // All 0s in upper bits: stuff 1, don't consume last bit
                out.append(UInt16(word | 1))
                pos += w - 1
            } else {
                // Normal case: output as-is, consumed all wordSize bits
                out.append(UInt16(word))
                pos += w
            }
        }
        return out
    }

    // MARK: - Symbol export (row packing)

    /// Converts a square, row-major bit matrix into an `AztecSymbol` with byte-aligned rows.
    ///
    /// The matrix is read from `matrixBits` starting at bit index `0`, in row-major
    /// order: bit `(x, y)` is at index `y * matrixSize + x`.
    ///
    /// Row orientation:
    /// - If `rowOrderMostSignificantBitFirst` is `false`, rows are packed LSB-first
    ///   (bit 0 in the byte is the leftmost module). This matches `aztec_encode`.
    /// - If `true`, rows are packed MSB-first (bit 7 in the byte is the leftmost
    ///   module). This matches `aztec_encode_inv` for PNG writers.
    ///
    /// - Parameters:
    ///   - matrixSize: The square side length in modules.
    ///   - rowOrderMostSignificantBitFirst: `true` for MSB-first row packing.
    /// - Returns: An `AztecSymbol` with contiguous row bytes and computed stride.
    public func makeSymbolExport(
        matrixSize: Int,
        rowOrderMostSignificantBitFirst: Bool
    ) -> AztecSymbol {
        precondition(matrixSize > 0)
        let stride = (matrixSize + 7) >> 3
        var bytes = [UInt8](repeating: 0, count: stride * matrixSize)

        for y in 0..<matrixSize {
            let rowStart = y * stride
            for x in 0..<matrixSize {
                let bitIndex = y * matrixSize + x
                let bit = leastSignificantBits(atBitPosition: bitIndex, bitCount: 1) != 0
                if bit {
                    let byteIndex = rowStart + (x >> 3)
                    let bitInByte = x & 7
                    if rowOrderMostSignificantBitFirst {
                        // Leftmost module stored in bit 7, next in bit 6, etc.
                        bytes[byteIndex] |= 1 << (7 - bitInByte)
                    } else {
                        // Leftmost module stored in bit 0, next in bit 1, etc.
                        bytes[byteIndex] |= 1 << bitInByte
                    }
                }
            }
        }

        return AztecSymbol(size: matrixSize, rowStride: stride, bytes: Data(bytes))
    }

    // MARK: - Mode-message helpers (GF(16) nibbles)

    /// Packs an array of 4-bit nibbles into a bit buffer, most-significant-bit first per nibble.
    /// Example: nibble 0xA (binary 1010) → bits placed as: 1, 0, 1, 0 (MSB first).
    ///
    /// - Parameter nibbles: Values in 0x0...0xF.
    /// - Returns: A `BitBuffer` containing 4 * nibbles.count bits, MSB-first per nibble.
    public static func makeBitBufferByPackingMostSignificantNibbles(_ nibbles: [UInt8]) -> BitBuffer {
        var b = BitBuffer()
        b.reserveCapacity(bitCount: nibbles.count * 4)
        for n in nibbles {
            // Write each bit of the nibble, starting with the MSB (bit 3)
            for bitPos in stride(from: 3, through: 0, by: -1) {
                let bit = UInt64((n >> bitPos) & 1)
                b.appendLeastSignificantBits(bit, bitCount: 1)
            }
        }
        return b
    }

    /// Unpacks 4-bit nibbles from a bit buffer, reading MSB-first per nibble.
    /// The buffer should have been packed with `makeBitBufferByPackingMostSignificantNibbles`.
    ///
    /// - Parameters:
    ///   - nibbleCount: Number of nibbles to read.
    /// - Returns: Array of 4-bit values in 0x0...0xF.
    public func makeMostSignificantNibblesByUnpacking(nibbleCount: Int) -> [UInt8] {
        var out: [UInt8] = []
        out.reserveCapacity(nibbleCount)
        var pos = 0
        for _ in 0..<nibbleCount {
            // Read 4 bits where position 0 = MSB of nibble
            var nibble: UInt8 = 0
            for bitOffset in 0..<4 {
                let bit = leastSignificantBits(atBitPosition: pos + bitOffset, bitCount: 1)
                // Bit at offset 0 is MSB (value 8), offset 1 is value 4, etc.
                nibble |= UInt8(bit) << (3 - bitOffset)
            }
            out.append(nibble)
            pos += 4
        }
        return out
    }

    /// Computes RS parity over 4-bit nibbles (GF(16)) and returns data+parity nibbles.
    ///
    /// - Parameters:
    ///   - payloadNibbles: Data nibbles to protect. Values must be in 0x0...0xF.
    ///   - parityNibbleCount: Number of parity symbols to append.
    ///   - startExponent: Generator root offset (α^(start)...).
    /// - Returns: Concatenation of `payloadNibbles` and parity nibbles.
    public static func makeProtectedNibblesForModeMessage(
        payloadNibbles: [UInt8],
        parityNibbleCount: Int,
        startExponent: Int
    ) -> [UInt8] {
        precondition(parityNibbleCount >= 0)
        // GF(16) with primitive poly x^4 + x + 1 = 0x13
        let gf = GaloisField(wordSizeInBits: 4, primitivePolynomial: 0x13)
        let rs = ReedSolomonEncoder(field: gf, startExponent: startExponent)
        let data = payloadNibbles.map { UInt16($0 & 0xF) }
        let parity = rs.makeParityCodewords(for: data, parityCodewordCount: parityNibbleCount)
        return data.map { UInt8($0) } + parity.map { UInt8($0 & 0xF) }
    }
}
