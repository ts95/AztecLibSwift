//
//  AztecLibTests.swift
//  AztecLibTests
//
//  Created by Toni Sucic on 10/10/2025.
//

import Foundation
import Testing
@testable import AztecLib

struct AztecLibTests {

}

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
