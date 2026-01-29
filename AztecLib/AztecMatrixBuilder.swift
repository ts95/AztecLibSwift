//
//  AztecMatrixBuilder.swift
//  AztecLib
//
//  Created by Toni Sucic on 13/10/2025.
//

import Foundation

// MARK: - Aztec Matrix Builder

/// Builds the Aztec symbol matrix including finder pattern, mode message, reference grid, and data.
public struct AztecMatrixBuilder: Sendable {

    /// The configuration for this symbol.
    public let configuration: AztecConfiguration

    /// Creates a matrix builder for the given configuration.
    public init(configuration: AztecConfiguration) {
        self.configuration = configuration
    }

    // MARK: - Symbol Size Calculation

    /// Calculates the symbol size in modules for the configuration.
    ///
    /// - Compact: size = 11 + 4 * layers
    /// - Full: size = 15 + 4 * layers + 2 * floor((layers - 1) / 15)
    public var symbolSize: Int {
        let layers = configuration.layerCount
        if configuration.isCompact {
            return 11 + 4 * layers
        } else {
            // Full symbols have reference grid lines every 16 modules
            let refLines = (layers - 1) / 15
            return 15 + 4 * layers + 2 * refLines
        }
    }

    /// Returns the center coordinate of the symbol (0-indexed).
    public var centerOffset: Int {
        return symbolSize / 2
    }

    // MARK: - Matrix Building

    /// Builds the complete symbol matrix with all components.
    ///
    /// - Parameters:
    ///   - dataCodewords: The data codewords (including parity).
    ///   - modeMessageBits: The encoded mode message bits.
    /// - Returns: A `BitBuffer` containing the symbol matrix in row-major order.
    public func buildMatrix(dataCodewords: [UInt16], modeMessageBits: BitBuffer) -> BitBuffer {
        let size = symbolSize
        var matrix = BitBuffer()
        matrix.reserveCapacity(bitCount: size * size)

        // Initialize all bits to 0 (white/light)
        for _ in 0..<(size * size) {
            matrix.appendLeastSignificantBits(0, bitCount: 1)
        }

        // Draw components in order
        drawFinderPattern(matrix: &matrix, size: size)
        drawModeMessage(matrix: &matrix, size: size, bits: modeMessageBits)
        if !configuration.isCompact {
            drawReferenceGrid(matrix: &matrix, size: size)
        }
        placeDataCodewords(matrix: &matrix, size: size, codewords: dataCodewords)

        return matrix
    }

    // MARK: - Finder Pattern

    /// Draws the finder pattern (bull's eye) at the center.
    ///
    /// - Compact: 5 rings (9x9 area)
    /// - Full: 7 rings (13x13 area) plus orientation marks
    private func drawFinderPattern(matrix: inout BitBuffer, size: Int) {
        let center = size / 2

        if configuration.isCompact {
            // Compact: 5 concentric rings
            // Ring radii from center: 0 (black), 1 (white), 2 (black), 3 (white), 4 (black)
            drawConcentricRings(matrix: &matrix, size: size, center: center, maxRadius: 4)
            // Orientation marks at corners of the finder
            drawCompactOrientationMarks(matrix: &matrix, size: size, center: center)
        } else {
            // Full: 7 concentric rings
            drawConcentricRings(matrix: &matrix, size: size, center: center, maxRadius: 6)
            // Orientation marks for full symbols
            drawFullOrientationMarks(matrix: &matrix, size: size, center: center)
        }
    }

    /// Draws concentric rings alternating black/white from center outward.
    private func drawConcentricRings(matrix: inout BitBuffer, size: Int, center: Int, maxRadius: Int) {
        for y in (center - maxRadius)...(center + maxRadius) {
            for x in (center - maxRadius)...(center + maxRadius) {
                // Distance from center (Chebyshev distance for square rings)
                let dist = max(abs(x - center), abs(y - center))
                // Even distance = black, odd distance = white
                let isBlack = (dist % 2 == 0)
                if isBlack {
                    setModule(matrix: &matrix, size: size, x: x, y: y, value: true)
                }
            }
        }
    }

    /// Draws orientation marks for compact symbols per ISO/IEC 24778.
    /// These marks form an asymmetric pattern so the decoder can determine orientation:
    /// - Upper-left corner: 1 black module
    /// - Upper-right corner: 2 black modules (corner + one to the left)
    /// - Lower-right corner: 3 black modules (L-shape)
    private func drawCompactOrientationMarks(matrix: inout BitBuffer, size: Int, center: Int) {
        let offset = 5 // Just outside the 9x9 finder area (radius 4) and mode message ring

        // Upper-left corner: 1 black module
        setModule(matrix: &matrix, size: size, x: center - offset, y: center - offset, value: true)

        // Upper-right corner: 2 black modules
        setModule(matrix: &matrix, size: size, x: center + offset, y: center - offset, value: true)
        setModule(matrix: &matrix, size: size, x: center + offset - 1, y: center - offset, value: true)

        // Lower-right corner: 3 black modules (L-shape)
        setModule(matrix: &matrix, size: size, x: center + offset, y: center + offset, value: true)
        setModule(matrix: &matrix, size: size, x: center + offset - 1, y: center + offset, value: true)
        setModule(matrix: &matrix, size: size, x: center + offset, y: center + offset - 1, value: true)
    }

    /// Draws orientation marks for full symbols per ISO/IEC 24778.
    /// Same pattern as compact but at a larger offset.
    private func drawFullOrientationMarks(matrix: inout BitBuffer, size: Int, center: Int) {
        let offset = 7 // Just outside the 13x13 finder area (radius 6) and mode message ring

        // Upper-left corner: 1 black module
        setModule(matrix: &matrix, size: size, x: center - offset, y: center - offset, value: true)

        // Upper-right corner: 2 black modules
        setModule(matrix: &matrix, size: size, x: center + offset, y: center - offset, value: true)
        setModule(matrix: &matrix, size: size, x: center + offset - 1, y: center - offset, value: true)

        // Lower-right corner: 3 black modules (L-shape)
        setModule(matrix: &matrix, size: size, x: center + offset, y: center + offset, value: true)
        setModule(matrix: &matrix, size: size, x: center + offset - 1, y: center + offset, value: true)
        setModule(matrix: &matrix, size: size, x: center + offset, y: center + offset - 1, value: true)
    }

    // MARK: - Mode Message

    /// Draws the mode message around the finder pattern.
    ///
    /// - Compact: 28 bits (7 nibbles) around the finder
    /// - Full: 40 bits (10 nibbles) around the finder
    private func drawModeMessage(matrix: inout BitBuffer, size: Int, bits: BitBuffer) {
        let center = size / 2

        if configuration.isCompact {
            // Compact mode message: 28 bits in 4 segments of 7 bits each
            // Placed around the 9x9 finder area
            placeCompactModeMessage(matrix: &matrix, size: size, center: center, bits: bits)
        } else {
            // Full mode message: 40 bits in 4 segments of 10 bits each
            // Placed around the 13x13 finder area
            placeFullModeMessage(matrix: &matrix, size: size, center: center, bits: bits)
        }
    }

    /// Places compact mode message bits around the finder per ISO/IEC 24778.
    /// The mode message forms a ring around the finder, placed clockwise starting from upper-left:
    /// - Top segment: right to left (bits 0-6)
    /// - Right segment: top to bottom (bits 7-13)
    /// - Bottom segment: left to right (bits 14-20)
    /// - Left segment: bottom to top (bits 21-27)
    private func placeCompactModeMessage(matrix: inout BitBuffer, size: Int, center: Int, bits: BitBuffer) {
        precondition(bits.bitCount >= 28, "Compact mode message requires 28 bits, got \(bits.bitCount)")
        let r = 5 // Offset from center for mode message ring

        var bitIndex = 0

        // Top segment: right to left, y = center - r
        // Place bits 0-6 from right to left along the top edge
        for x in stride(from: center + r - 1, through: center - r + 1, by: -1) {
            if x == center { continue } // Skip center column
            let bit = bits.leastSignificantBits(atBitPosition: bitIndex, bitCount: 1) != 0
            setModule(matrix: &matrix, size: size, x: x, y: center - r, value: bit)
            bitIndex += 1
            if bitIndex >= 7 { break }
        }

        // Right segment: top to bottom, x = center + r
        // Place bits 7-13 from top to bottom along the right edge
        bitIndex = 7
        for y in (center - r + 1)..<(center + r) {
            if y == center { continue }
            let bit = bits.leastSignificantBits(atBitPosition: bitIndex, bitCount: 1) != 0
            setModule(matrix: &matrix, size: size, x: center + r, y: y, value: bit)
            bitIndex += 1
            if bitIndex >= 14 { break }
        }

        // Bottom segment: left to right, y = center + r
        // Place bits 14-20 from left to right along the bottom edge
        bitIndex = 14
        for x in (center - r + 1)..<(center + r) {
            if x == center { continue }
            let bit = bits.leastSignificantBits(atBitPosition: bitIndex, bitCount: 1) != 0
            setModule(matrix: &matrix, size: size, x: x, y: center + r, value: bit)
            bitIndex += 1
            if bitIndex >= 21 { break }
        }

        // Left segment: bottom to top, x = center - r
        // Place bits 21-27 from bottom to top along the left edge
        bitIndex = 21
        for y in stride(from: center + r - 1, through: center - r + 1, by: -1) {
            if y == center { continue }
            let bit = bits.leastSignificantBits(atBitPosition: bitIndex, bitCount: 1) != 0
            setModule(matrix: &matrix, size: size, x: center - r, y: y, value: bit)
            bitIndex += 1
            if bitIndex >= 28 { break }
        }
    }

    /// Places full mode message bits around the finder per ISO/IEC 24778.
    /// Same pattern as compact but with 10 bits per segment (40 bits total).
    private func placeFullModeMessage(matrix: inout BitBuffer, size: Int, center: Int, bits: BitBuffer) {
        precondition(bits.bitCount >= 40, "Full mode message requires 40 bits, got \(bits.bitCount)")
        let r = 7 // Offset from center for mode message ring

        var bitIndex = 0

        // Top segment: right to left
        for x in stride(from: center + r - 1, through: center - r + 1, by: -1) {
            if x == center { continue }
            let bit = bits.leastSignificantBits(atBitPosition: bitIndex, bitCount: 1) != 0
            setModule(matrix: &matrix, size: size, x: x, y: center - r, value: bit)
            bitIndex += 1
            if bitIndex >= 10 { break }
        }

        // Right segment: top to bottom
        bitIndex = 10
        for y in (center - r + 1)..<(center + r) {
            if y == center { continue }
            let bit = bits.leastSignificantBits(atBitPosition: bitIndex, bitCount: 1) != 0
            setModule(matrix: &matrix, size: size, x: center + r, y: y, value: bit)
            bitIndex += 1
            if bitIndex >= 20 { break }
        }

        // Bottom segment: left to right
        bitIndex = 20
        for x in (center - r + 1)..<(center + r) {
            if x == center { continue }
            let bit = bits.leastSignificantBits(atBitPosition: bitIndex, bitCount: 1) != 0
            setModule(matrix: &matrix, size: size, x: x, y: center + r, value: bit)
            bitIndex += 1
            if bitIndex >= 30 { break }
        }

        // Left segment: bottom to top
        bitIndex = 30
        for y in stride(from: center + r - 1, to: center - r, by: -1) {
            if y == center { continue }
            let bit = bits.leastSignificantBits(atBitPosition: bitIndex, bitCount: 1) != 0
            setModule(matrix: &matrix, size: size, x: center - r, y: y, value: bit)
            bitIndex += 1
            if bitIndex >= 40 { break }
        }
    }

    // MARK: - Reference Grid

    /// Draws the reference grid for full symbols.
    /// Lines every 16 modules from center, alternating black/white.
    private func drawReferenceGrid(matrix: inout BitBuffer, size: Int) {
        let center = size / 2

        // Reference grid spacing is 16 modules from center
        // Lines extend from the edge of the finder to the edge of the symbol

        // Calculate grid line positions
        var gridPositions: [Int] = []
        var pos = center + 16
        while pos < size {
            gridPositions.append(pos)
            pos += 16
        }
        pos = center - 16
        while pos >= 0 {
            gridPositions.append(pos)
            pos -= 16
        }

        // Draw horizontal and vertical grid lines
        for gridPos in gridPositions {
            // Horizontal line at y = gridPos
            for x in 0..<size {
                // Skip the finder area
                if isInFinderArea(x: x, y: gridPos, center: center) { continue }
                // Alternating pattern
                let isBlack = (x % 2 == 0)
                setModule(matrix: &matrix, size: size, x: x, y: gridPos, value: isBlack)
            }
            // Vertical line at x = gridPos
            for y in 0..<size {
                if isInFinderArea(x: gridPos, y: y, center: center) { continue }
                let isBlack = (y % 2 == 0)
                setModule(matrix: &matrix, size: size, x: gridPos, y: y, value: isBlack)
            }
        }
    }

    /// Checks if a position is within the finder pattern area.
    private func isInFinderArea(x: Int, y: Int, center: Int) -> Bool {
        let radius = configuration.isCompact ? 5 : 7
        return abs(x - center) <= radius && abs(y - center) <= radius
    }

    /// Checks if a position is on a reference grid line.
    private func isOnReferenceGrid(x: Int, y: Int, center: Int) -> Bool {
        guard !configuration.isCompact else { return false }
        let dx = abs(x - center)
        let dy = abs(y - center)
        return (dx > 7 && dx % 16 == 0) || (dy > 7 && dy % 16 == 0)
    }

    // MARK: - Data Placement

    /// Places data codewords in a counter-clockwise spiral from the finder outward.
    private func placeDataCodewords(matrix: inout BitBuffer, size: Int, codewords: [UInt16]) {
        let center = size / 2
        let wordSize = configuration.wordSizeInBits

        // Build the spiral path (2 bits wide, counter-clockwise from center outward)
        let path = buildDataPath(size: size, center: center)

        // Calculate total bits needed
        let totalBitsNeeded = codewords.count * wordSize

        // Validate path has sufficient capacity (assert in debug, silent in release for backwards compatibility)
        assert(
            path.count >= totalBitsNeeded,
            "Data path has insufficient capacity: need \(totalBitsNeeded) positions, have \(path.count)"
        )

        // Place codewords along the path
        var pathIndex = 0
        for codeword in codewords {
            for bitPos in stride(from: wordSize - 1, through: 0, by: -1) {
                guard pathIndex < path.count else { return }
                let (x, y) = path[pathIndex]
                let bit = ((codeword >> bitPos) & 1) != 0
                setModule(matrix: &matrix, size: size, x: x, y: y, value: bit)
                pathIndex += 1
            }
        }
    }

    /// Builds the data placement path (counter-clockwise spiral, 2 bits wide).
    private func buildDataPath(size: Int, center: Int) -> [(Int, Int)] {
        var path: [(Int, Int)] = []

        // Start just outside the finder/mode message area
        let startRadius = configuration.isCompact ? 6 : 8
        var layer = 0

        while true {
            let radius = startRadius + layer * 2
            if radius >= size / 2 { break }

            // Each layer is a ring, 2 modules wide
            // Counter-clockwise starting from top-right, going left along top
            let layerPath = buildLayerPath(center: center, innerRadius: radius, size: size)
            path.append(contentsOf: layerPath)
            layer += 1
        }

        return path
    }

    /// Builds the path for a single layer (2-module wide ring).
    private func buildLayerPath(center: Int, innerRadius: Int, size: Int) -> [(Int, Int)] {
        var path: [(Int, Int)] = []

        let outerRadius = innerRadius + 1
        let minCoord = max(0, center - outerRadius)
        let maxCoord = min(size - 1, center + outerRadius)

        // Top edge: right to left (2 rows)
        for x in stride(from: maxCoord, through: minCoord, by: -1) {
            for rowOffset in 0...1 {
                let y = center - outerRadius + rowOffset
                if y >= 0 && y < size && !isReservedPosition(x: x, y: y, center: center, size: size) {
                    path.append((x, y))
                }
            }
        }

        // Left edge: top to bottom (2 columns)
        for y in (center - outerRadius + 2)...(center + outerRadius) {
            for colOffset in stride(from: 1, through: 0, by: -1) {
                let x = center - outerRadius + colOffset
                if x >= 0 && x < size && y < size && !isReservedPosition(x: x, y: y, center: center, size: size) {
                    path.append((x, y))
                }
            }
        }

        // Bottom edge: left to right (2 rows)
        for x in (center - outerRadius + 2)...(center + outerRadius) {
            for rowOffset in stride(from: 1, through: 0, by: -1) {
                let y = center + outerRadius - rowOffset
                if y < size && x < size && !isReservedPosition(x: x, y: y, center: center, size: size) {
                    path.append((x, y))
                }
            }
        }

        // Right edge: bottom to top (2 columns)
        for y in stride(from: center + outerRadius - 2, through: center - outerRadius, by: -1) {
            for colOffset in 0...1 {
                let x = center + outerRadius - colOffset
                if x < size && y >= 0 && !isReservedPosition(x: x, y: y, center: center, size: size) {
                    path.append((x, y))
                }
            }
        }

        return path
    }

    /// Checks if a position is reserved (finder, mode message, or reference grid).
    private func isReservedPosition(x: Int, y: Int, center: Int, size: Int) -> Bool {
        // Finder and mode message area
        let finderRadius = configuration.isCompact ? 5 : 7
        if abs(x - center) <= finderRadius && abs(y - center) <= finderRadius {
            return true
        }

        // Reference grid (full symbols only)
        if !configuration.isCompact {
            let dx = x - center
            let dy = y - center
            // Grid lines at multiples of 16 from center
            if abs(dx) > 7 && abs(dx) % 16 == 0 { return true }
            if abs(dy) > 7 && abs(dy) % 16 == 0 { return true }
        }

        return false
    }

    // MARK: - Module Access

    /// Sets a module in the matrix.
    private func setModule(matrix: inout BitBuffer, size: Int, x: Int, y: Int, value: Bool) {
        guard x >= 0 && x < size && y >= 0 && y < size else { return }
        let bitIndex = y * size + x
        matrix.setBits(atBitPosition: bitIndex, fromLeastSignificantBits: value ? 1 : 0, bitCount: 1)
    }
}

// MARK: - Mode Message Encoding

extension AztecMatrixBuilder {

    /// Encodes the mode message bits with RS parity.
    ///
    /// - Compact: 8 data bits (2 nibbles) + 20 parity bits (5 nibbles) = 28 bits total
    /// - Full: 16 data bits (4 nibbles) + 24 parity bits (6 nibbles) = 40 bits total
    ///
    /// - Returns: A `BitBuffer` containing the mode message with parity.
    public func encodeModeMessage() -> BitBuffer {
        if configuration.isCompact {
            return encodeCompactModeMessage()
        } else {
            return encodeFullModeMessage()
        }
    }

    /// Encodes compact mode message.
    private func encodeCompactModeMessage() -> BitBuffer {
        // Compact mode message: 8 data bits
        // Bits 0-1: layers - 1 (2 bits)
        // Bits 2-7: data codewords - 1 (6 bits)
        let layerBits = (configuration.layerCount - 1) & 0x03
        let dataWordBits = (configuration.dataCodewordCount - 1) & 0x3F
        let dataByte = UInt8((layerBits << 6) | dataWordBits)

        // Split into 2 nibbles
        let nibble0 = (dataByte >> 4) & 0x0F
        let nibble1 = dataByte & 0x0F

        // Generate RS parity: 5 parity nibbles in GF(16)
        let protected = BitBuffer.makeProtectedNibblesForModeMessage(
            payloadNibbles: [nibble0, nibble1],
            parityNibbleCount: 5,
            startExponent: 1
        )

        // Pack nibbles MSB-first
        return BitBuffer.makeBitBufferByPackingMostSignificantNibbles(protected)
    }

    /// Encodes full mode message.
    private func encodeFullModeMessage() -> BitBuffer {
        // Full mode message: 16 data bits
        // Bits 0-4: layers - 1 (5 bits)
        // Bits 5-15: data codewords - 1 (11 bits)
        let layerBits = (configuration.layerCount - 1) & 0x1F
        let dataWordBits = (configuration.dataCodewordCount - 1) & 0x7FF
        let dataWord = UInt16((layerBits << 11) | dataWordBits)

        // Split into 4 nibbles
        let nibble0 = UInt8((dataWord >> 12) & 0x0F)
        let nibble1 = UInt8((dataWord >> 8) & 0x0F)
        let nibble2 = UInt8((dataWord >> 4) & 0x0F)
        let nibble3 = UInt8(dataWord & 0x0F)

        // Generate RS parity: 6 parity nibbles in GF(16)
        let protected = BitBuffer.makeProtectedNibblesForModeMessage(
            payloadNibbles: [nibble0, nibble1, nibble2, nibble3],
            parityNibbleCount: 6,
            startExponent: 1
        )

        // Pack nibbles MSB-first
        return BitBuffer.makeBitBufferByPackingMostSignificantNibbles(protected)
    }
}
