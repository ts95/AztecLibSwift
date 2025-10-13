//
//  ReedSolomonEncoder.swift
//  AztecLib
//
//  Created by Toni Sucic on 13/10/2025.
//

/// Reed–Solomon encoder producing systematic parity codewords over GF(2^m).
public struct ReedSolomonEncoder {
    public let field: GaloisField
    public let startExponent: Int

    /// Creates an encoder with a field and generator-root start exponent.
    ///
    /// - Parameters:
    ///   - field: The finite field GF(2^m) to operate in.
    ///   - startExponent: Root offset; generator uses α^(start ... start+ecc-1).
    public init(field: GaloisField, startExponent: Int) {
        self.field = field
        self.startExponent = startExponent
    }

    /// Computes parity codewords for the given data sequence.
    ///
    /// - Parameters:
    ///   - dataCodewords: The input sequence of data symbols in `0 ..< 2^m`.
    ///   - parityCodewordCount: The number of parity codewords to produce.
    /// - Returns: An array of parity codewords of length `parityCodewordCount`.
    public func makeParityCodewords(
        for dataCodewords: [UInt16],
        parityCodewordCount: Int
    ) -> [UInt16] {
        guard parityCodewordCount > 0 else { return [] }
        let gen = makeGeneratorPolynomial(ofDegree: parityCodewordCount)
        var reg = [UInt16](repeating: 0, count: parityCodewordCount)
        for d in dataCodewords {
            let fb = field.add(d, reg[0])
            if parityCodewordCount > 1 {
                reg.replaceSubrange(0..<(parityCodewordCount - 1), with: reg[1...])
            }
            reg[parityCodewordCount - 1] = 0
            for j in 0..<parityCodewordCount {
                let tap = gen[j]
                if tap != 0 { reg[j] = field.add(reg[j], field.multiply(fb, tap)) }
            }
        }
        return reg
    }

    /// Returns data+parity in a single array.
    ///
    /// - Parameters:
    ///   - dataCodewords: The data portion.
    ///   - parityCodewordCount: The number of parity symbols to append.
    /// - Returns: Concatenation of `dataCodewords` and computed parity.
    public func appendingParity(
        to dataCodewords: [UInt16],
        parityCodewordCount: Int
    ) -> [UInt16] {
        dataCodewords + makeParityCodewords(for: dataCodewords, parityCodewordCount: parityCodewordCount)
    }

    // MARK: Internals

    @usableFromInline internal func makeGeneratorPolynomial(ofDegree t: Int) -> [UInt16] {
        var g = [UInt16](repeating: 0, count: t + 1)
        g[0] = 1
        for i in 0..<t {
            let root = field.exp[(startExponent + i) % (field.size - 1)]
            var next = [UInt16](repeating: 0, count: g.count + 1)
            for j in 0..<g.count {
                next[j + 1] = field.add(next[j + 1], g[j])              // x * g
                next[j] = field.add(next[j], field.multiply(g[j], root)) // (x - root)
            }
            g = next
        }
        return g
    }
}
