//
//  GaloisField.swift
//  AztecLib
//
//  Created by Toni Sucic on 13/10/2025.
//

/// A binary-extension finite field GF(2^m) with log/antilog tables.
public struct GaloisField: Sendable {
    /// m such that field size is 2^m.
    public let wordSizeInBits: Int
    /// Primitive polynomial with the x^m term set.
    public let primitivePolynomial: UInt32
    @usableFromInline internal let size: Int
    @usableFromInline internal let exp: [UInt16]
    @usableFromInline internal let log: [UInt16]

    /// Creates GF(2^m) tables for the specified primitive polynomial.
    ///
    /// - Parameters:
    ///   - wordSizeInBits: The RS symbol width `m` in bits.
    ///   - primitivePolynomial: The field’s primitive polynomial.
    public init(wordSizeInBits: Int, primitivePolynomial: UInt32) {
        precondition((1...12).contains(wordSizeInBits))
        self.wordSizeInBits = wordSizeInBits
        self.primitivePolynomial = primitivePolynomial
        self.size = 1 << wordSizeInBits

        var exp = [UInt16](repeating: 0, count: size * 2)
        var log = [UInt16](repeating: 0, count: size)
        var x: UInt32 = 1
        for i in 0..<(size - 1) {
            exp[i] = UInt16(x)
            log[Int(x)] = UInt16(i)
            x <<= 1
            if (x & UInt32(size)) != 0 { x ^= primitivePolynomial }
        }
        for i in (size - 1)..<(size * 2 - 2) { exp[i] = exp[i - (size - 1)] }
        self.exp = exp
        self.log = log
    }

    /// Multiplies two field elements.
    ///
    /// - Parameters:
    ///   - a: First operand in GF(2^m).
    ///   - b: Second operand in GF(2^m).
    /// - Returns: The product `a * b` in GF(2^m).
    @inline(__always) public func multiply(_ a: UInt16, _ b: UInt16) -> UInt16 {
        if a == 0 || b == 0 { return 0 }
        let la = Int(log[Int(a)]), lb = Int(log[Int(b)])
        return exp[la + lb]
    }

    /// Adds two field elements (bitwise XOR).
    ///
    /// - Parameters:
    ///   - a: First operand.
    ///   - b: Second operand.
    /// - Returns: The sum `a ⊕ b` in GF(2^m).
    @inline(__always) public func add(_ a: UInt16, _ b: UInt16) -> UInt16 { a ^ b }
}
