//
//  AztecSymbol.swift
//  AztecLib
//
//  Created by Toni Sucic on 13/10/2025.
//

import Foundation

/// A contiguous, row-major representation of the rendered Aztec matrix.
public struct AztecSymbol {
    /// Side length of the square matrix in modules.
    public let size: Int
    /// Row stride in bytes for the exported raster.
    public let rowStride: Int
    /// Packed rows, either LSB-first or MSB-first per row depending on export path.
    public let bytes: Data

    /// Initializes a symbol container.
    ///
    /// - Parameters:
    ///   - size: Side length in modules.
    ///   - rowStride: Byte stride per row.
    ///   - bytes: Packed row data.
    public init(size: Int, rowStride: Int, bytes: Data) {
        self.size = size
        self.rowStride = rowStride
        self.bytes = bytes
    }

    /// Returns the bit at `(x, y)` assuming LSB-first packing per row.
    ///
    /// - Parameters:
    ///   - x: Column index in `0..<size`.
    ///   - y: Row index in `0..<size`.
    /// - Returns: `true` for a dark module, `false` for light.
    public subscript(x x: Int, y y: Int) -> Bool {
        precondition(0..<size ~= x && 0..<size ~= y)
        let offset = y * rowStride + (x >> 3)
        let mask: UInt8 = 1 << (x & 7)
        return (bytes[offset] & mask) != 0
    }
}
