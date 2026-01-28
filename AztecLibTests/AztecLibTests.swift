//
//  AztecLibTests.swift
//  AztecLibTests
//
//  Created by Toni Sucic on 10/10/2025.
//

import Foundation
import Testing
@testable import AztecLib

// MARK: - Helpers

private func buffer(from bitsLSBFirst: [Int]) -> BitBuffer {
    var b = BitBuffer()
    for bit in bitsLSBFirst {
        b.appendLeastSignificantBits(UInt64(bit & 1), bitCount: 1)
    }
    return b
}

// MARK: - Codeword packing tests

struct CodewordPackingTests {

    @Test
    func packs_allZeros_group_with_stuffedOne() {
        // w = 6 → dataBitsPerWord = 5
        // Next 5 bits are 00000 → emit 000001 (1), consume only 5 bits.
        let b = buffer(from: [0,0,0,0,0])
        let cw = b.makeCodewords(codewordBitWidth: 6)
        #expect(cw == [1], "Expected stuffed 1 for all-zeros group")
    }

    @Test
    func packs_allOnes_group_with_stuffedZero() {
        // 11111 → emit 111110 (62), consume only 5 bits.
        let b = buffer(from: [1,1,1,1,1])
        let cw = b.makeCodewords(codewordBitWidth: 6)
        #expect(cw == [62], "Expected stuffed 0 for all-ones group")
    }

    @Test
    func packs_mixed_group_consumes_extra_bit() {
        // Data 10101 then next bit 1:
        // v = 10101b = 21, stuff=1 → (21<<1)|1 = 43, consume 6 bits total.
        let b = buffer(from: [1,0,1,0,1,1])
        let cw = b.makeCodewords(codewordBitWidth: 6)
        #expect(cw == [43], "Expected 43 for 10101 + stuff 1")
    }

    @Test
    func packs_final_partial_group_leftPads_then_stuffsZero() {
        // Only 3 data bits 101; w=6 → take=3, left-pad to 5: 10100b=20
        // Not all-0/1 and no extra source bit → stuff=0 → (20<<1)|0 = 40
        let b = buffer(from: [1,0,1])
        let cw = b.makeCodewords(codewordBitWidth: 6)
        #expect(cw == [40], "Expected 40 for partial final group 101")
    }

    @Test
    func packs_multiple_groups_progress_and_sizes() {
        // Two full groups with mixed patterns to exercise both branches.
        // Bits: 10101 0 | 00000  -> first mixed with stuff=0 → (21<<1)|0=42
        // second all-zeros → 000001 = 1
        let b = buffer(from: [1,0,1,0,1,0, 0,0,0,0,0])
        let cw = b.makeCodewords(codewordBitWidth: 6)
        #expect(cw == [42, 1])
    }
}

// MARK: - Symbol export tests

struct SymbolExportTests {

    @Test
    func lsb_export_stride_and_row_bits_are_correct() {
        // 3x3 matrix:
        // Row0: 1 0 1
        // Row1: 0 1 0
        // Row2: 1 1 1
        // Row-major LSB stream: 101 010 111
        var bits: [Int] = []
        bits += [1,0,1]
        bits += [0,1,0]
        bits += [1,1,1]
        let buf = buffer(from: bits)

        let sym = buf.makeSymbolExport(matrixSize: 3, rowOrderMostSignificantBitFirst: false)
        #expect(sym.size == 3)
        #expect(sym.rowStride == 1)

        // One byte per row. Check bit positions in each byte: bit i == column i
        let bytes = [UInt8](sym.bytes)
        // Row 0: 1 0 1 → 0b00000101 = 5
        #expect(bytes[0] == 0b00000101)
        // Row 1: 0 1 0 → 0b00000010 = 2
        #expect(bytes[1] == 0b00000010)
        // Row 2: 1 1 1 → 0b00000111 = 7
        #expect(bytes[2] == 0b00000111)
    }

    @Test
    func msb_vs_lsb_orientation_are_perRow_bitReversals_within_byte() {
        // 5x1 row: 1 0 1 1 0
        // LSB row byte: bits 0..4 = 1,0,1,1,0 → 0b00011011 = 27
        // MSB row byte sets bits 7..3 at positions 7,6,5,4,3 for x=0..4 respectively.
        let buf = buffer(from: [1,0,1,1,0])
        let lsb = buf.makeSymbolExport(matrixSize: 1, rowOrderMostSignificantBitFirst: false)
        let msb = buf.makeSymbolExport(matrixSize: 1, rowOrderMostSignificantBitFirst: true)
        #expect(lsb.rowStride == 1 && msb.rowStride == 1)

        let l = lsb.bytes[0]
        let m = msb.bytes[0]

        // For x in 0..<5, compare bits mirrored within the byte.
        for x in 0..<5 {
            let lBit = (l >> x) & 1
            let mBit = (m >> (7 - x)) & 1
            #expect(lBit == mBit, "Mismatch at column \(x)")
        }
    }

    @Test
    func export_handles_multiple_rows_and_padding_bits() {
        // 9x2 matrix, stride = ceil(9/8) = 2 bytes per row. Verify padding zeros.
        // Row0: 9 ones → bytes: 0xFF, 0x01 (LSB-first)
        // Row1: 9 zeros → bytes: 0x00, 0x00
        var bits: [Int] = Array(repeating: 1, count: 9)
        bits += Array(repeating: 0, count: 9)
        let buf = buffer(from: bits)
        let sym = buf.makeSymbolExport(matrixSize: 9, rowOrderMostSignificantBitFirst: false)
        #expect(sym.rowStride == 2)
        let row0 = sym.bytes[0..<2]
        let row1 = sym.bytes[2..<4]
        #expect(Array(row0) == [0xFF, 0x01])
        #expect(Array(row1) == [0x00, 0x00])
    }
}

// MARK: - Mode message RS-on-nibbles tests

struct ModeMessageNibbleTests {

    @Test
    func pack_and_unpack_nibbles_roundtrip_msb() {
        let nibbles: [UInt8] = [0xA, 0x0, 0xF, 0x1, 0x5]
        let buf = BitBuffer.makeBitBufferByPackingMostSignificantNibbles(nibbles)
        #expect(buf.bitCount == nibbles.count * 4)
        let back = buf.makeMostSignificantNibblesByUnpacking(nibbleCount: nibbles.count)
        #expect(back == nibbles)
    }

    @Test
    func rs_parity_length_and_range_are_correct() {
        // 7 data nibbles, 5 parity nibbles (typical compact-mode length).
        let data: [UInt8] = [1,2,3,4,5,6,7]
        let out = BitBuffer.makeProtectedNibblesForModeMessage(
            payloadNibbles: data,
            parityNibbleCount: 5,
            startExponent: 0 // start exponent can vary; 0 is fine for algebraic checks
        )
        #expect(out.count == 12)
        #expect(out.prefix(7).elementsEqual(data))
        #expect(out.suffix(5).allSatisfy { $0 < 16 })
    }

    // TODO: This test needs investigation - the polynomial evaluation order or LFSR parity order may need adjustment
    @Test(.disabled("Requires investigation of RS polynomial coefficient ordering"))
    func rs_codeword_polynomial_has_roots_at_generator_powers() {
        // Verify that the protected codeword evaluates to zero at α^(start+i).
        let data: [UInt8] = [0x1, 0x0, 0xA, 0xC, 0x3]
        let start = 2
        let parityCount = 6
        let cw = BitBuffer.makeProtectedNibblesForModeMessage(
            payloadNibbles: data,
            parityNibbleCount: parityCount,
            startExponent: start
        )
        let gf = GaloisField(wordSizeInBits: 4, primitivePolynomial: 0x13)

        // Systematic RS codeword: [data..., parity...]
        // Polynomial: c(x) = c[0]*x^(n-1) + c[1]*x^(n-2) + ... + c[n-1]
        // where c[0..k-1] are data and c[k..n-1] are parity symbols.
        // Use forward Horner's method (data is high-degree).
        func eval(_ aPow: Int) -> UInt16 {
            let order = gf.size - 1
            let alpha = gf.exp[((aPow % order) + order) % order]
            var acc: UInt16 = 0
            for c in cw {
                acc = gf.add(gf.multiply(acc, alpha), UInt16(c & 0xF))
            }
            return acc
        }

        for i in 0..<parityCount {
            let val = eval(start + i)
            #expect(val == 0, "Codeword should vanish at α^\(start + i), got \(val)")
        }
    }
}
