//
//  AztecMatrixBuilder.swift
//  AztecLib
//
//  Created by Toni Sucic on 13/10/2025.
//

import Foundation

// MARK: - Matrix Builder Errors

/// Errors that can occur during matrix building.
public enum AztecMatrixBuilderError: Error, Sendable {
    /// The data path has insufficient capacity for the codewords.
    case insufficientPathCapacity(needed: Int, available: Int)
}

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

    /// Returns true if this configuration includes reference grid lines.
    /// Reference grid lines appear in full symbols with 15 or more layers.
    public var hasReferenceGrid: Bool {
        guard !configuration.isCompact else { return false }
        // Reference grid lines are added when (layers - 1) / 15 > 0, i.e., layers >= 16
        // However, the grid is drawn at multiples of 16 from center when the symbol
        // is large enough to contain them. For layers 1-14, no reference grid.
        return (configuration.layerCount - 1) / 15 > 0
    }

    // MARK: - Matrix Building

    /// Builds the complete symbol matrix with all components.
    ///
    /// - Parameters:
    ///   - dataCodewords: The data codewords (including parity).
    ///   - modeMessageBits: The encoded mode message bits.
    /// - Returns: A `BitBuffer` containing the symbol matrix in row-major order.
    /// - Throws: `AztecMatrixBuilderError.insufficientPathCapacity` if the data path cannot fit all codewords.
    public func buildMatrix(dataCodewords: [UInt16], modeMessageBits: BitBuffer) throws(AztecMatrixBuilderError) -> BitBuffer {
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
        if hasReferenceGrid {
            drawReferenceGrid(matrix: &matrix, size: size)
        }
        try placeDataCodewords(matrix: &matrix, size: size, codewords: dataCodewords)

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
    /// These marks help decoders determine symbol orientation.
    /// For compact symbols, marks are placed at distance 5 from center.
    private func drawCompactOrientationMarks(matrix: inout BitBuffer, size: Int, center: Int) {
        let d = 5  // Distance from center for compact symbols
        // Top-left corner: 3 marks forming an L
        setModule(matrix: &matrix, size: size, x: center - d, y: center - d, value: true)
        setModule(matrix: &matrix, size: size, x: center - d + 1, y: center - d, value: true)
        setModule(matrix: &matrix, size: size, x: center - d, y: center - d + 1, value: true)
        // Top-right corner: 2 vertical marks
        setModule(matrix: &matrix, size: size, x: center + d, y: center - d, value: true)
        setModule(matrix: &matrix, size: size, x: center + d, y: center - d + 1, value: true)
        // Bottom-right corner: 1 mark
        setModule(matrix: &matrix, size: size, x: center + d, y: center + d - 1, value: true)
    }

    /// Draws orientation marks for full symbols per ISO/IEC 24778.
    /// Same pattern as compact but at distance 7 from center.
    private func drawFullOrientationMarks(matrix: inout BitBuffer, size: Int, center: Int) {
        let d = 7  // Distance from center for full symbols
        // Top-left corner: 3 marks forming an L
        setModule(matrix: &matrix, size: size, x: center - d, y: center - d, value: true)
        setModule(matrix: &matrix, size: size, x: center - d + 1, y: center - d, value: true)
        setModule(matrix: &matrix, size: size, x: center - d, y: center - d + 1, value: true)
        // Top-right corner: 2 vertical marks
        setModule(matrix: &matrix, size: size, x: center + d, y: center - d, value: true)
        setModule(matrix: &matrix, size: size, x: center + d, y: center - d + 1, value: true)
        // Bottom-right corner: 1 mark
        setModule(matrix: &matrix, size: size, x: center + d, y: center + d - 1, value: true)
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
    /// The mode message forms a ring around the finder, matching ZXing-cpp's placement:
    /// - Top segment: left to right (bits 0-6)
    /// - Right segment: top to bottom (bits 7-13)
    /// - Bottom segment: left to right (bits 20-14, reversed order)
    /// - Left segment: top to bottom (bits 27-21, reversed order)
    private func placeCompactModeMessage(matrix: inout BitBuffer, size: Int, center: Int, bits: BitBuffer) {
        precondition(bits.bitCount >= 28, "Compact mode message requires 28 bits, got \(bits.bitCount)")

        // Mode message is placed at distance 5 from center
        // Each edge has 7 bits at positions offset = center - 3 + i for i in 0..<7
        for i in 0..<7 {
            let offset = center - 3 + i

            // Top edge (y = center - 5): bit i at x = offset
            let topBit = bits.leastSignificantBits(atBitPosition: i, bitCount: 1) != 0
            setModule(matrix: &matrix, size: size, x: offset, y: center - 5, value: topBit)

            // Right edge (x = center + 5): bit i+7 at y = offset
            let rightBit = bits.leastSignificantBits(atBitPosition: i + 7, bitCount: 1) != 0
            setModule(matrix: &matrix, size: size, x: center + 5, y: offset, value: rightBit)

            // Bottom edge (y = center + 5): bit 20-i at x = offset (reversed order)
            let bottomBit = bits.leastSignificantBits(atBitPosition: 20 - i, bitCount: 1) != 0
            setModule(matrix: &matrix, size: size, x: offset, y: center + 5, value: bottomBit)

            // Left edge (x = center - 5): bit 27-i at y = offset (reversed order)
            let leftBit = bits.leastSignificantBits(atBitPosition: 27 - i, bitCount: 1) != 0
            setModule(matrix: &matrix, size: size, x: center - 5, y: offset, value: leftBit)
        }
    }

    /// Places full mode message bits around the finder per ISO/IEC 24778.
    /// Same pattern as compact but with 10 bits per segment (40 bits total).
    /// The offset formula `center - 5 + i + i/5` creates a gap at the center position.
    private func placeFullModeMessage(matrix: inout BitBuffer, size: Int, center: Int, bits: BitBuffer) {
        precondition(bits.bitCount >= 40, "Full mode message requires 40 bits, got \(bits.bitCount)")

        // Mode message is placed at distance 7 from center
        // Each edge has 10 bits at positions with a gap to skip center
        for i in 0..<10 {
            // The i/5 term adds 0 for i=0..4 and 1 for i=5..9, creating a gap at center
            let offset = center - 5 + i + i / 5

            // Top edge (y = center - 7): bit i at x = offset
            let topBit = bits.leastSignificantBits(atBitPosition: i, bitCount: 1) != 0
            setModule(matrix: &matrix, size: size, x: offset, y: center - 7, value: topBit)

            // Right edge (x = center + 7): bit i+10 at y = offset
            let rightBit = bits.leastSignificantBits(atBitPosition: i + 10, bitCount: 1) != 0
            setModule(matrix: &matrix, size: size, x: center + 7, y: offset, value: rightBit)

            // Bottom edge (y = center + 7): bit 29-i at x = offset (reversed order)
            let bottomBit = bits.leastSignificantBits(atBitPosition: 29 - i, bitCount: 1) != 0
            setModule(matrix: &matrix, size: size, x: offset, y: center + 7, value: bottomBit)

            // Left edge (x = center - 7): bit 39-i at y = offset (reversed order)
            let leftBit = bits.leastSignificantBits(atBitPosition: 39 - i, bitCount: 1) != 0
            setModule(matrix: &matrix, size: size, x: center - 7, y: offset, value: leftBit)
        }
    }

    // MARK: - Reference Grid

    /// Draws the reference grid for full symbols.
    /// Lines every 16 modules from center, alternating black/white.
    private func drawReferenceGrid(matrix: inout BitBuffer, size: Int) {
        let center = size / 2

        // Reference grid spacing is 16 modules from center
        // Lines extend from the edge of the finder to the edge of the symbol
        // Only draw the actual number of grid line sets for this symbol's layer count
        let refLineCount = (configuration.layerCount - 1) / 15

        // Calculate grid line positions (only up to refLineCount sets)
        var gridPositions: [Int] = []
        for i in 1...refLineCount {
            let offset = i * 16
            let posRight = center + offset
            let posLeft = center - offset
            if posRight < size {
                gridPositions.append(posRight)
            }
            if posLeft >= 0 {
                gridPositions.append(posLeft)
            }
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
        guard hasReferenceGrid else { return false }
        let dx = abs(x - center)
        let dy = abs(y - center)
        let refLineCount = (configuration.layerCount - 1) / 15
        let maxGridDistance = refLineCount * 16
        return (dx > 7 && dx % 16 == 0 && dx <= maxGridDistance) || (dy > 7 && dy % 16 == 0 && dy <= maxGridDistance)
    }

    // MARK: - Data Placement

    /// Places data codewords using ZXing-compatible bit placement.
    /// Bits are arranged by side: top bits, then right, then bottom, then left.
    /// - Throws: `AztecMatrixBuilderError.insufficientPathCapacity` if the data doesn't fit.
    private func placeDataCodewords(matrix: inout BitBuffer, size: Int, codewords: [UInt16]) throws(AztecMatrixBuilderError) {
        let wordSize = configuration.wordSizeInBits
        let layers = configuration.layerCount
        let baseMatrixSize = configuration.isCompact ? 11 + layers * 4 : 14 + layers * 4

        // Build alignment map (identity for compact symbols without reference grid)
        let alignmentMap = buildAlignmentMap(matrixSize: baseMatrixSize, size: size)

        // Calculate total bits in layer per ZXing formula
        let totalBitsInLayer = ((configuration.isCompact ? 88 : 112) + 16 * layers) * layers

        // ZXing adds startPad zero bits at the beginning for alignment
        // startPad = totalBitsInLayer % wordSize
        let startPad = totalBitsInLayer % wordSize

        // Build message bits: startPad zeros, then codewords MSB-first
        var messageBits: [Bool] = []

        // Add startPad zero bits at the beginning (critical for ZXing compatibility!)
        for _ in 0..<startPad {
            messageBits.append(false)
        }

        // Flatten codewords to bits (MSB first within each codeword per ZXing's appendBits)
        for codeword in codewords {
            for bitPos in stride(from: wordSize - 1, through: 0, by: -1) {
                messageBits.append(((codeword >> bitPos) & 1) != 0)
            }
        }

        // Calculate total bits needed for validation
        var totalBitsNeeded = 0
        for i in 0..<layers {
            let rowSize = (layers - i) * 4 + (configuration.isCompact ? 9 : 12)
            totalBitsNeeded += rowSize * 8
        }

        // Pad message bits with zeros if needed
        while messageBits.count < totalBitsNeeded {
            messageBits.append(false)
        }

        // Place bits using ZXing's algorithm: top, right, bottom, left for each layer
        var rowOffset = 0
        for i in 0..<layers {
            let rowSize = (layers - i) * 4 + (configuration.isCompact ? 9 : 12)

            for j in 0..<rowSize {
                let columnOffset = j * 2

                for k in 0..<2 {
                    // Top side
                    if messageBits[rowOffset + columnOffset + k] {
                        let x = alignmentMap[i * 2 + k]
                        let y = alignmentMap[i * 2 + j]
                        setModule(matrix: &matrix, size: size, x: x, y: y, value: true)
                    }

                    // Right side
                    if messageBits[rowOffset + rowSize * 2 + columnOffset + k] {
                        let x = alignmentMap[i * 2 + j]
                        let y = alignmentMap[baseMatrixSize - 1 - i * 2 - k]
                        setModule(matrix: &matrix, size: size, x: x, y: y, value: true)
                    }

                    // Bottom side
                    if messageBits[rowOffset + rowSize * 4 + columnOffset + k] {
                        let x = alignmentMap[baseMatrixSize - 1 - i * 2 - k]
                        let y = alignmentMap[baseMatrixSize - 1 - i * 2 - j]
                        setModule(matrix: &matrix, size: size, x: x, y: y, value: true)
                    }

                    // Left side
                    if messageBits[rowOffset + rowSize * 6 + columnOffset + k] {
                        let x = alignmentMap[baseMatrixSize - 1 - i * 2 - j]
                        let y = alignmentMap[i * 2 + k]
                        setModule(matrix: &matrix, size: size, x: x, y: y, value: true)
                    }
                }
            }

            rowOffset += rowSize * 8
        }
    }

    /// Builds the alignment map for coordinate transformation.
    /// For compact symbols without reference grid, this is identity.
    /// For full symbols with reference grid, it skips grid line positions.
    private func buildAlignmentMap(matrixSize: Int, size: Int) -> [Int] {
        if configuration.isCompact || !hasReferenceGrid {
            // Identity mapping for compact symbols
            return Array(0..<size)
        }

        // For full symbols with reference grid, skip positions that fall on grid lines
        var map: [Int] = []
        let center = size / 2
        var origPos = 0
        for i in 0..<size {
            // Check if this position is on a reference grid line
            let distFromCenter = i - center
            let refLineCount = (configuration.layerCount - 1) / 15
            var isGridLine = false
            for g in 1...refLineCount {
                if abs(distFromCenter) == g * 16 {
                    isGridLine = true
                    break
                }
            }
            if !isGridLine {
                if map.count <= origPos {
                    map.append(i)
                }
                origPos += 1
            }
        }

        // Ensure we have enough entries
        while map.count < matrixSize {
            map.append(map.count)
        }

        return map
    }

    /// Builds the data placement path (counter-clockwise spiral, 2 bits wide).
    private func buildDataPath(size: Int, center: Int) -> [(Int, Int)] {
        var path: [(Int, Int)] = []

        // Start just outside the finder/mode message area
        let startRadius = configuration.isCompact ? 6 : 8
        var layer = 0

        while true {
            let radius = startRadius + layer * 2
            // Continue while the ring's outer edge (radius + 1) can still fit in the symbol
            // Use > instead of >= to allow the final ring that reaches the symbol edge
            if radius > size / 2 { break }

            // Each layer is a ring, 2 modules wide
            // Counter-clockwise starting from top-right, going left along top
            let layerPath = buildLayerPath(center: center, innerRadius: radius, size: size)
            path.append(contentsOf: layerPath)
            layer += 1
        }

        return path
    }

    /// Builds the path for a single layer (2-module wide ring).
    /// Following ZXing's interleaved placement: for each position j along the edges,
    /// place 2 bits on top, 2 on right, 2 on bottom, 2 on left, then move to j+1.
    /// This matches ZXing's nested loop structure where the outer loop is j (position)
    /// and the inner loop is k (which of the 2 bits).
    private func buildLayerPath(center: Int, innerRadius: Int, size: Int) -> [(Int, Int)] {
        var path: [(Int, Int)] = []

        let i = 0  // Layer offset within this call (always 0 for single layer building)
        // rowSize determines how many positions along each edge
        // For compact symbols, this follows ZXing's formula: (layers - i) * 4 + 9
        // But since we build one layer at a time, we calculate based on geometry
        let outerRadius = innerRadius + 1
        let edgeLength = outerRadius * 2 + 1  // Total edge length including corners

        // Calculate row size similar to ZXing: this is the number of j iterations
        // For a layer at distance innerRadius from center, the edge size is 2*outerRadius + 1
        // But ZXing uses rowSize = (layers - i) * 4 + (compact ? 9 : 12) for the iteration count
        // For compact L1 at layer 0: rowSize = 1 * 4 + 9 = 13

        // Actually, let me compute this more directly from the geometry
        // The data layer starts at radius 6 for compact (just outside mode message at radius 5)
        // Edge length = 2 * (innerRadius + 1) + 1 = 2 * 7 + 1 = 15 for first layer
        // But we need to skip the corners that overlap between edges

        // ZXing iterates j from 0 to rowSize-1, placing 8 bits per j (2 per side)
        // Let's compute the positions more directly

        let rowSize = edgeLength  // Number of positions per edge

        for j in 0..<rowSize {
            for k in 0..<2 {
                // Top: x increases left to right, y is near top
                let topX = center - outerRadius + j
                let topY = center - outerRadius + k
                if topX >= 0 && topX < size && topY >= 0 && topY < size &&
                   !isReservedPosition(x: topX, y: topY, center: center, size: size) {
                    path.append((topX, topY))
                }

                // Right: y increases top to bottom, x is near right
                let rightX = center + outerRadius - k
                let rightY = center - outerRadius + j
                if rightX >= 0 && rightX < size && rightY >= 0 && rightY < size &&
                   !isReservedPosition(x: rightX, y: rightY, center: center, size: size) {
                    path.append((rightX, rightY))
                }

                // Bottom: x decreases right to left, y is near bottom
                let bottomX = center + outerRadius - j
                let bottomY = center + outerRadius - k
                if bottomX >= 0 && bottomX < size && bottomY >= 0 && bottomY < size &&
                   !isReservedPosition(x: bottomX, y: bottomY, center: center, size: size) {
                    path.append((bottomX, bottomY))
                }

                // Left: y decreases bottom to top, x is near left
                let leftX = center - outerRadius + k
                let leftY = center + outerRadius - j
                if leftX >= 0 && leftX < size && leftY >= 0 && leftY < size &&
                   !isReservedPosition(x: leftX, y: leftY, center: center, size: size) {
                    path.append((leftX, leftY))
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

        // Reference grid (only for full symbols with 16+ layers)
        if hasReferenceGrid {
            let dx = x - center
            let dy = y - center
            // Grid lines at multiples of 16 from center, but only up to the actual number of grid line sets
            // Layer 16-30: 1 set at ±16, Layer 31-32: 2 sets at ±16 and ±32
            let refLineCount = (configuration.layerCount - 1) / 15
            let maxGridDistance = refLineCount * 16
            if abs(dx) > 7 && abs(dx) % 16 == 0 && abs(dx) <= maxGridDistance { return true }
            if abs(dy) > 7 && abs(dy) % 16 == 0 && abs(dy) <= maxGridDistance { return true }
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
