//
//  ReedSolomonEncoder.swift
//  AztecLib
//
//  Created by Toni Sucic on 13/10/2025.
//

/// Reed–Solomon encoder producing systematic parity codewords over GF(2^m).
public struct ReedSolomonEncoder: Sendable {
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
        // Generator polynomial g(x) = ∏_{i=0..t-1} (x + α^(start+i))
        // Coefficients g[0..t], with g[0] == 1 and g[t] == 1 (monic).
        let g = makeGeneratorPolynomial(ofDegree: parityCodewordCount)

        // LFSR register of length t; systematic parity will be the remainder of D(x) x^t mod g(x).
        var reg = [UInt16](repeating: 0, count: parityCodewordCount)

        for d in dataCodewords {
            // Feedback from the last register cell (right-shift form)
            let fb = field.add(d, reg[parityCodewordCount - 1])

            // Shift right by one: reg[j] = reg[j-1]
            if parityCodewordCount > 1 {
                for j in stride(from: parityCodewordCount - 1, through: 1, by: -1) {
                    reg[j] = reg[j - 1]
                }
            }
            reg[0] = 0

            // Mix feedback using taps g[1..t] (skip g[0], the constant term; include g[t] which is 1 for monic g)
            for j in 0..<parityCodewordCount {
                let tap = g[j + 1]
                if tap != 0 {
                    reg[j] = field.add(reg[j], field.multiply(fb, tap))
                }
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
        // Build g(x) = ∏_{i=0}^{t-1} (x + α^(startExponent+i))
        // Represented as coefficients g[0] + g[1] x + ... + g[t] x^t.
        // Start with g(x) = 1 (degree-0 polynomial with single element).
        var g: [UInt16] = [1]
        for i in 0..<t {
            let root = field.exp[(startExponent + i) % (field.size - 1)]
            var next = [UInt16](repeating: 0, count: g.count + 1)
            for j in 0..<g.count {
                // Multiply by x: shift coefficients up by one
                next[j + 1] = field.add(next[j + 1], g[j])
                // Add constant term for (x + root): g[j] * root
                next[j] = field.add(next[j], field.multiply(g[j], root))
            }
            g = next
        }
        return g
    }
}
