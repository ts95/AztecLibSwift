//
//  AztecSymbolView.swift
//  AztecLib
//
//  A SwiftUI view for rendering AztecSymbol on all Apple platforms.
//

#if canImport(SwiftUI)
import SwiftUI

/// Configuration options for rendering an Aztec symbol.
@available(iOS 15.0, macOS 12.0, tvOS 15.0, watchOS 8.0, visionOS 1.0, *)
public struct AztecSymbolRenderOptions: Sendable {
    /// Color for dark modules (default: black).
    public var foregroundColor: Color

    /// Color for light modules (default: white).
    public var backgroundColor: Color

    /// Number of quiet zone modules around the symbol (default: 1).
    /// ISO/IEC 24778 does not require a quiet zone, but some readers work better with one.
    public var quietZoneModules: Int

    /// Size of each module in points. If nil, the view sizes automatically.
    public var moduleSize: CGFloat?

    /// Creates render options with default values.
    public init(
        foregroundColor: Color = .black,
        backgroundColor: Color = .white,
        quietZoneModules: Int = 1,
        moduleSize: CGFloat? = nil
    ) {
        self.foregroundColor = foregroundColor
        self.backgroundColor = backgroundColor
        self.quietZoneModules = max(0, quietZoneModules)
        self.moduleSize = moduleSize
    }
}

/// A SwiftUI view that renders an AztecSymbol.
///
/// This view renders the Aztec barcode using Canvas for efficient drawing.
/// It automatically adapts to the available space while maintaining a square aspect ratio.
///
/// Example usage:
/// ```swift
/// let symbol = try AztecEncoder.encode("Hello, World!")
/// AztecSymbolView(symbol: symbol)
///     .frame(width: 200, height: 200)
/// ```
@available(iOS 15.0, macOS 12.0, tvOS 15.0, watchOS 8.0, visionOS 1.0, *)
public struct AztecSymbolView: View {
    /// The Aztec symbol to render.
    public let symbol: AztecSymbol

    /// Rendering options.
    public let options: AztecSymbolRenderOptions

    /// Creates an Aztec symbol view.
    ///
    /// - Parameters:
    ///   - symbol: The Aztec symbol to render.
    ///   - options: Rendering options for customization.
    public init(symbol: AztecSymbol, options: AztecSymbolRenderOptions = AztecSymbolRenderOptions()) {
        self.symbol = symbol
        self.options = options
    }

    public var body: some View {
        GeometryReader { geometry in
            let totalModules = symbol.size + 2 * options.quietZoneModules
            let moduleSize = options.moduleSize ?? min(
                geometry.size.width / CGFloat(totalModules),
                geometry.size.height / CGFloat(totalModules)
            )
            let canvasSize = moduleSize * CGFloat(totalModules)

            Canvas { context, size in
                // Fill background (including quiet zone)
                context.fill(
                    Path(CGRect(origin: .zero, size: size)),
                    with: .color(options.backgroundColor)
                )

                // Calculate offset to center the symbol
                let offsetX = (size.width - canvasSize) / 2 + moduleSize * CGFloat(options.quietZoneModules)
                let offsetY = (size.height - canvasSize) / 2 + moduleSize * CGFloat(options.quietZoneModules)

                // Draw dark modules
                for y in 0..<symbol.size {
                    for x in 0..<symbol.size {
                        if symbol[x: x, y: y] {
                            let rect = CGRect(
                                x: offsetX + CGFloat(x) * moduleSize,
                                y: offsetY + CGFloat(y) * moduleSize,
                                width: moduleSize,
                                height: moduleSize
                            )
                            context.fill(Path(rect), with: .color(options.foregroundColor))
                        }
                    }
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

/// A convenience view that encodes a string and renders the resulting Aztec symbol.
@available(iOS 15.0, macOS 12.0, tvOS 15.0, watchOS 8.0, visionOS 1.0, *)
public struct AztecCodeView: View {
    private let content: AztecCodeContent
    private let options: AztecSymbolRenderOptions
    private let encodingOptions: AztecEncoder.Options

    private enum AztecCodeContent {
        case string(String)
        case bytes([UInt8])
        case data(Data)
    }

    /// Creates an Aztec code view from a string.
    ///
    /// - Parameters:
    ///   - string: The string to encode.
    ///   - encodingOptions: Options for the Aztec encoder.
    ///   - renderOptions: Options for rendering the symbol.
    public init(
        _ string: String,
        encodingOptions: AztecEncoder.Options = AztecEncoder.Options(),
        renderOptions: AztecSymbolRenderOptions = AztecSymbolRenderOptions()
    ) {
        self.content = .string(string)
        self.encodingOptions = encodingOptions
        self.options = renderOptions
    }

    /// Creates an Aztec code view from bytes.
    ///
    /// - Parameters:
    ///   - bytes: The bytes to encode.
    ///   - encodingOptions: Options for the Aztec encoder.
    ///   - renderOptions: Options for rendering the symbol.
    public init(
        bytes: [UInt8],
        encodingOptions: AztecEncoder.Options = AztecEncoder.Options(),
        renderOptions: AztecSymbolRenderOptions = AztecSymbolRenderOptions()
    ) {
        self.content = .bytes(bytes)
        self.encodingOptions = encodingOptions
        self.options = renderOptions
    }

    /// Creates an Aztec code view from Data.
    ///
    /// - Parameters:
    ///   - data: The data to encode.
    ///   - encodingOptions: Options for the Aztec encoder.
    ///   - renderOptions: Options for rendering the symbol.
    public init(
        data: Data,
        encodingOptions: AztecEncoder.Options = AztecEncoder.Options(),
        renderOptions: AztecSymbolRenderOptions = AztecSymbolRenderOptions()
    ) {
        self.content = .data(data)
        self.encodingOptions = encodingOptions
        self.options = renderOptions
    }

    public var body: some View {
        if let symbol = encodedSymbol {
            AztecSymbolView(symbol: symbol, options: options)
        } else {
            // Fallback for encoding failures - show placeholder
            Rectangle()
                .fill(options.backgroundColor)
                .aspectRatio(1, contentMode: .fit)
                .overlay {
                    Text("Encoding Error")
                        .foregroundStyle(options.foregroundColor)
                        .font(.caption)
                }
        }
    }

    private var encodedSymbol: AztecSymbol? {
        do {
            switch content {
            case .string(let string):
                return try AztecEncoder.encode(string, options: encodingOptions)
            case .bytes(let bytes):
                return try AztecEncoder.encode(bytes, options: encodingOptions)
            case .data(let data):
                return try AztecEncoder.encode(data, options: encodingOptions)
            }
        } catch {
            return nil
        }
    }
}

// MARK: - Preview Support

#if DEBUG
@available(iOS 15.0, macOS 12.0, tvOS 15.0, watchOS 8.0, visionOS 1.0, *)
struct AztecSymbolView_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 20) {
            if let symbol = try? AztecEncoder.encode("Hello, World!") {
                AztecSymbolView(symbol: symbol)
                    .frame(width: 200, height: 200)
            }

            AztecCodeView("12345")
                .frame(width: 150, height: 150)

            AztecCodeView(
                "Custom Colors",
                renderOptions: AztecSymbolRenderOptions(
                    foregroundColor: .blue,
                    backgroundColor: .yellow,
                    quietZoneModules: 2
                )
            )
            .frame(width: 180, height: 180)
        }
        .padding()
    }
}
#endif

#endif // canImport(SwiftUI)
