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
public struct BitBuffer {
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
        precondition([6, 8, 10, 12].contains(w), "Invalid Aztec codeword width")
        let dataBitsPerWord = w - 1
        let allOnesMask = (1 << dataBitsPerWord) &- 1
        let total = bitCount
        var pos = 0
        var out: [UInt16] = []
        out.reserveCapacity((total + dataBitsPerWord) / dataBitsPerWord)

        while pos < total {
            let remaining = total - pos
            let take = min(remaining, dataBitsPerWord)
            var v = Int(leastSignificantBits(atBitPosition: pos, bitCount: take))

            // Left-pad a short final group to `w-1` bits.
            if take < dataBitsPerWord {
                v <<= (dataBitsPerWord - take)
            }

            if v == 0 {
                // Stuff a 1; do not consume extra bit.
                let cw = UInt16((v << 1) | 1)
                out.append(cw)
                pos += take
            } else if v == allOnesMask {
                // Stuff a 0; do not consume extra bit.
                let cw = UInt16(v << 1)
                out.append(cw)
                pos += take
            } else {
                // Consume one more source bit as the stuff bit.
                let stuff = (pos + take) < total
                ? Int(leastSignificantBits(atBitPosition: pos + take, bitCount: 1))
                : 0
                let cw = UInt16((v << 1) | stuff)
                out.append(cw)
                pos += take + 1
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
        var bytes = Data(count: stride * matrixSize)
        bytes.withUnsafeMutableBytes { raw in
            guard let ptr = raw.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return }
            for y in 0..<matrixSize {
                let rowStart = y * stride
                // Zero the whole row buffer
                for i in 0..<stride { ptr[rowStart + i] = 0 }
                for x in 0..<matrixSize {
                    let bitIndex = y * matrixSize + x
                    let bit = leastSignificantBits(atBitPosition: bitIndex, bitCount: 1) != 0
                    let byteIndex = rowStart + (x >> 3)
                    let bitInByte = x & 7
                    if rowOrderMostSignificantBitFirst {
                        // Leftmost module stored in bit 7, next in bit 6, etc.
                        let mask: UInt8 = 1 << (7 - bitInByte)
                        if bit { ptr[byteIndex] |= mask }
                    } else {
                        // Leftmost module stored in bit 0, next in bit 1, etc.
                        let mask: UInt8 = 1 << bitInByte
                        if bit { ptr[byteIndex] |= mask }
                    }
                }
            }
        }
        return AztecSymbol(size: matrixSize, rowStride: stride, bytes: bytes)
    }

    // MARK: - Mode-message helpers (GF(16) nibbles)

    /// Packs an array of 4-bit nibbles into a bit buffer, most-significant-bit first per nibble.
    /// Example: nibble 0xA → bits 1010.
    ///
    /// - Parameter nibbles: Values in 0x0...0xF.
    /// - Returns: A `BitBuffer` containing 4 * nibbles.count bits, MSB-first per nibble.
    public static func makeBitBufferByPackingMostSignificantNibbles(_ nibbles: [UInt8]) -> BitBuffer {
        var b = BitBuffer()
        b.reserveCapacity(bitCount: nibbles.count * 4)
        for n in nibbles {
            let v = UInt64(n & 0xF)
            // MSB-first within the nibble: write the top bit first
            b.appendMostSignificantBits(v << 60, bitCount: 4) // reuse MSB path; top-aligned
        }
        return b
    }

    /// Unpacks 4-bit nibbles from a bit buffer, reading MSB-first per nibble.
    ///
    /// - Parameters:
    ///   - nibbleCount: Number of nibbles to read.
    /// - Returns: Array of 4-bit values in 0x0...0xF.
    public func makeMostSignificantNibblesByUnpacking(nibbleCount: Int) -> [UInt8] {
        var out: [UInt8] = []
        out.reserveCapacity(nibbleCount)
        var pos = 0
        for _ in 0..<nibbleCount {
            let v = mostSignificantBits(atBitPosition: pos, bitCount: 4)
            out.append(UInt8((v >> 60) & 0xF))
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
