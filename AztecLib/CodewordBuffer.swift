//
//  CodewordBuffer.swift
//  AztecLib
//
//  Created by Toni Sucic on 13/10/2025.
//

// MARK: - CodewordBuffer

/// A thin, type-safe container for Aztec codewords prior to parity generation.
public struct CodewordBuffer {
    /// Underlying storage of fixed-width codewords.
    public private(set) var words = [UInt16]()

    /// Creates an empty buffer.
    public init() {}

    /// Reserves capacity for at least `count` codewords.
    ///
    /// - Parameter count: Target capacity in elements.
    public mutating func reserveCapacity(codewordCount count: Int) {
        words.reserveCapacity(count)
    }

    /// Appends a single codeword value.
    ///
    /// - Parameter codeword: The codeword to append. Must fit the current word size.
    public mutating func append(_ codeword: UInt16) {
        words.append(codeword)
    }

    /// Sets the logical count. New slots are zero-initialized if growing.
    ///
    /// - Parameter newCount: The new logical element count.
    public mutating func setLogicalCount(_ newCount: Int) {
        if newCount > words.count {
            words.append(contentsOf: repeatElement(0, count: newCount - words.count))
        } else {
            words.removeLast(words.count - newCount)
        }
    }
}
