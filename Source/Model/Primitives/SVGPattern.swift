import SwiftUI

enum SVGPatternUnits: String {
    case userSpaceOnUse
    case objectBoundingBox
}

public class SVGPattern: SVGPaint {

    private let element: XMLElement
    private weak var index: SVGIndex?

    private let x: CGFloat
    private let y: CGFloat
    private let width: CGFloat
    private let height: CGFloat
    private let patternUnits: SVGPatternUnits
    private let contentUnits: SVGPatternUnits
    fileprivate let viewBox: CGRect?
    private let patternTransform: CGAffineTransform

    private var cachedNodes: [SVGNode]?

    init(element: XMLElement, index: SVGIndex) {
        self.element = element
        self.index = index
        self.patternUnits = SVGPatternUnits(rawValue: element.attributes["patternUnits"] ?? "") ?? .objectBoundingBox
        self.contentUnits = SVGPatternUnits(rawValue: element.attributes["patternContentUnits"] ?? "") ?? .userSpaceOnUse
        self.x = SVGHelper.parseCGFloat(element.attributes, "x")
        self.y = SVGHelper.parseCGFloat(element.attributes, "y")
        self.width = max(0, SVGHelper.parseCGFloat(element.attributes, "width"))
        self.height = max(0, SVGHelper.parseCGFloat(element.attributes, "height"))
        self.viewBox = SVGPattern.parseViewBox(element.attributes["viewBox"])
        self.patternTransform = SVGHelper.parseTransform(element.attributes["patternTransform"] ?? "")
    }

    func apply<S: View>(view: S, model: SVGShape?) -> some View {
        guard let model = model else {
            return AnyView(view.foregroundColor(.clear))
        }
        return AnyView(
            view
                .foregroundColor(.clear)
                .overlay(
                    SVGPatternFillView(pattern: self, model: model)
                        .mask(view)
                )
        )
    }

    fileprivate func tileSize(for bounds: CGRect) -> CGSize {
        switch patternUnits {
        case .userSpaceOnUse:
            return CGSize(width: width, height: height)
        case .objectBoundingBox:
            return CGSize(width: width * bounds.width, height: height * bounds.height)
        }
    }

    fileprivate func relativeOrigin(for bounds: CGRect) -> CGPoint {
        switch patternUnits {
        case .userSpaceOnUse:
            // For userSpaceOnUse, x/y are absolute coordinates
            // We need to find the first tile that covers the bounds
            let firstTileX = floor((bounds.minX - x) / width) * width + x
            let firstTileY = floor((bounds.minY - y) / height) * height + y
            return CGPoint(x: firstTileX - bounds.minX, y: firstTileY - bounds.minY)
        case .objectBoundingBox:
            return CGPoint(x: x * bounds.width, y: y * bounds.height)
        }
    }

    fileprivate func contentTransform(bounds: CGRect, tileSize: CGSize) -> CGAffineTransform {
        var transform = CGAffineTransform.identity
        
        // First, apply viewBox transformation if present
        if let viewBox = viewBox, viewBox.width != 0, viewBox.height != 0, tileSize.width != 0, tileSize.height != 0 {
            let scaleX = tileSize.width / viewBox.width
            let scaleY = tileSize.height / viewBox.height
            // Translate viewBox to origin (0,0), then scale to tileSize
            // This maps viewBox coordinates to tile coordinates
            transform = CGAffineTransform(translationX: -viewBox.minX, y: -viewBox.minY)
                .concatenating(CGAffineTransform(scaleX: scaleX, y: scaleY))
        }
        
        // Then apply contentUnits scaling if needed
        if contentUnits == .objectBoundingBox {
            transform = transform.scaledBy(x: bounds.width, y: bounds.height)
        }

        // Finally apply patternTransform
        return transform.concatenating(patternTransform)
    }
    
    fileprivate func nodes() -> [SVGNode] {
        if let cached = cachedNodes {
            return cached
        }
        guard let index = index,
              let rootContext = index.makeRootContext(),
              let patternContext = rootContext.create(for: element) else {
            return []
        }
        let result = element.contents
            .compactMap { $0 as? XMLElement }
            .compactMap { SVGParser.parse(element: $0, in: patternContext) }
        cachedNodes = result
        return result
    }

    private static func parseViewBox(_ attribute: String?) -> CGRect? {
        guard let attribute = attribute else { return nil }
        let components = attribute
            .replacingOccurrences(of: ",", with: " ")
            .split(whereSeparator: { $0.isWhitespace })
        guard components.count == 4,
              let x = Double(components[0]),
              let y = Double(components[1]),
              let width = Double(components[2]),
              let height = Double(components[3]) else {
            return nil
        }
        return CGRect(x: x, y: y, width: width, height: height)
    }
}

private struct SVGPatternFillView: View {

    let pattern: SVGPattern
    let model: SVGShape

    var body: some View {
        let frame = model.frame()
        let bounds = model.bounds()
        SVGPatternTiledView(pattern: pattern, frame: frame, bounds: bounds)
            .frame(width: bounds.width, height: bounds.height, alignment: .topLeading)
            .offset(x: bounds.minX, y: bounds.minY)
    }
}

private struct SVGPatternTiledView: View {

    let pattern: SVGPattern
    let frame: CGRect
    let bounds: CGRect

    var body: some View {
        let nodes = pattern.nodes()
        let tileSize = pattern.tileSize(for: bounds)
        guard !nodes.isEmpty,
              tileSize.width > 0,
              tileSize.height > 0 else {
            return AnyView(Color.clear)
        }

        let start = pattern.startOffset(for: frame, bounds: bounds, tileSize: tileSize)
        let columns = pattern.tileCount(length: bounds.width - start.x, tile: tileSize.width)
        let rows = pattern.tileCount(length: bounds.height - start.y, tile: tileSize.height)
        let contentTransform = pattern.contentTransform(bounds: bounds, tileSize: tileSize)

        return AnyView(
            ZStack(alignment: .topLeading) {
                ForEach(0..<rows, id: \.self) { row in
                    ForEach(0..<columns, id: \.self) { column in
                        SVGPatternTileContentView(
                            nodes: nodes,
                            transform: contentTransform,
                            tileSize: tileSize,
                            viewBox: pattern.viewBox
                        )
                        .frame(width: tileSize.width, height: tileSize.height, alignment: .topLeading)
                        .offset(
                            x: start.x + CGFloat(column) * tileSize.width,
                            y: start.y + CGFloat(row) * tileSize.height
                        )
                    }
                }
            }
        )
    }
}

private struct SVGPatternTileContentView: View {

    let nodes: [SVGNode]
    let transform: CGAffineTransform
    let tileSize: CGSize
    let viewBox: CGRect?

    var body: some View {
        // The transform maps viewBox coordinates to tile coordinates
        // Content should fill the entire tile after transformation
        GeometryReader { geometry in
            SVGPatternNodeStack(nodes: nodes)
                .transformEffect(transform)
                // Position content to fill the tile
                .frame(
                    width: max(geometry.size.width, tileSize.width),
                    height: max(geometry.size.height, tileSize.height),
                    alignment: .topLeading
                )
        }
        .frame(width: tileSize.width, height: tileSize.height)
        .clipped() // Clip to tile bounds
    }
}

private struct SVGPatternNodeStack: View {

    let nodes: [SVGNode]

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(Array(nodes.enumerated()), id: \.offset) { item in
                item.element.toSwiftUI()
            }
        }
    }
}

private extension SVGPattern {

    func startOffset(for frame: CGRect, bounds: CGRect, tileSize: CGSize) -> CGPoint {
        switch patternUnits {
        case .userSpaceOnUse:
            // For userSpaceOnUse, calculate the first tile that covers the frame
            let firstTileX = floor((frame.minX - x) / width) * width + x
            let firstTileY = floor((frame.minY - y) / height) * height + y
            // Convert to relative coordinates within bounds
            return CGPoint(x: firstTileX - frame.minX, y: firstTileY - frame.minY)
        case .objectBoundingBox:
            var origin = relativeOrigin(for: bounds)
            origin.x = normalizedStart(value: origin.x, tile: tileSize.width)
            origin.y = normalizedStart(value: origin.y, tile: tileSize.height)
            return origin
        }
    }

    func tileCount(length: CGFloat, tile: CGFloat) -> Int {
        guard tile > 0 else { return 0 }
        return max(1, Int(ceil(length / tile)))
    }

    func normalizedStart(value: CGFloat, tile: CGFloat) -> CGFloat {
        guard tile > 0 else { return 0 }
        var start = value.truncatingRemainder(dividingBy: tile)
        if start > 0 {
            start -= tile
        }
        return start
    }
}

