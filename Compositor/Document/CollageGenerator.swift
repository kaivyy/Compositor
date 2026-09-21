import Foundation
import CoreGraphics
import AppKit

public enum CollagePreset: String, CaseIterable, Identifiable, Sendable {
    case grid2x2 = "2 × 2 Grid"
    case grid3x3 = "3 × 3 Grid"
    case customGrid = "Custom Grid"
    case heroLeft = "Hero Left (1 + 2)"
    case heroTop = "Hero Top (1 + 2)"
    case threeColumns = "3 Columns Equal"
    case threeRows = "3 Rows Equal"

    public var id: String { rawValue }
}

nonisolated public struct CollageOptions: Sendable, Equatable {
    public var preset: CollagePreset
    public var rows: Int
    public var columns: Int
    public var spacing: CGFloat
    public var margin: CGFloat
    public var groupPerCell: Bool
    public var frameNamePrefix: String

    public init(
        preset: CollagePreset = .grid2x2,
        rows: Int = 2,
        columns: Int = 2,
        spacing: CGFloat = 10,
        margin: CGFloat = 10,
        groupPerCell: Bool = true,
        frameNamePrefix: String = "Frame"
    ) {
        self.preset = preset
        self.rows = max(1, rows)
        self.columns = max(1, columns)
        self.spacing = max(0, spacing)
        self.margin = max(0, margin)
        self.groupPerCell = groupPerCell
        self.frameNamePrefix = frameNamePrefix
    }
}

nonisolated public struct CollageCellGeometry: Sendable, Equatable {
    public let index: Int
    public let rect: CGRect
    public let name: String

    public init(index: Int, rect: CGRect, name: String) {
        self.index = index
        self.rect = rect
        self.name = name
    }
}

nonisolated public enum CollageGenerator {
    /// Computes deterministic rectangle geometry for each frame in the collage.
    public static func computeCells(for canvasSize: CGSize, options: CollageOptions) -> [CollageCellGeometry] {
        let width = canvasSize.width
        let height = canvasSize.height
        guard width > 0, height > 0 else { return [] }

        let spacing = max(0, options.spacing)
        let margin = max(0, options.margin)
        let availW = max(1, width - 2 * margin)
        let availH = max(1, height - 2 * margin)

        switch options.preset {
        case .grid2x2:
            return computeUniformGrid(canvasSize: canvasSize, rows: 2, columns: 2, spacing: spacing, margin: margin, prefix: options.frameNamePrefix)

        case .grid3x3:
            return computeUniformGrid(canvasSize: canvasSize, rows: 3, columns: 3, spacing: spacing, margin: margin, prefix: options.frameNamePrefix)

        case .customGrid:
            return computeUniformGrid(canvasSize: canvasSize, rows: max(1, options.rows), columns: max(1, options.columns), spacing: spacing, margin: margin, prefix: options.frameNamePrefix)

        case .threeColumns:
            return computeUniformGrid(canvasSize: canvasSize, rows: 1, columns: 3, spacing: spacing, margin: margin, prefix: options.frameNamePrefix)

        case .threeRows:
            return computeUniformGrid(canvasSize: canvasSize, rows: 3, columns: 1, spacing: spacing, margin: margin, prefix: options.frameNamePrefix)

        case .heroLeft:
            let colW = max(1, (availW - spacing) / 2)
            let rowH = max(1, (availH - spacing) / 2)

            let x0 = round(margin)
            let xMid = round(margin + colW)
            let xRightStart = round(xMid + spacing)
            let xRightEnd = round(width - margin)
            let y0 = round(margin)
            let yMid = round(margin + rowH)
            let yBottomStart = round(yMid + spacing)
            let yBottomEnd = round(height - margin)

            let heroRect = CGRect(x: x0, y: y0, width: max(1, xMid - x0), height: max(1, yBottomEnd - y0))
            let topCell = CGRect(x: xRightStart, y: y0, width: max(1, xRightEnd - xRightStart), height: max(1, yMid - y0))
            let bottomCell = CGRect(x: xRightStart, y: yBottomStart, width: max(1, xRightEnd - xRightStart), height: max(1, yBottomEnd - yBottomStart))

            return [
                CollageCellGeometry(index: 1, rect: heroRect, name: "\(options.frameNamePrefix) 1 (Hero)"),
                CollageCellGeometry(index: 2, rect: topCell, name: "\(options.frameNamePrefix) 2"),
                CollageCellGeometry(index: 3, rect: bottomCell, name: "\(options.frameNamePrefix) 3")
            ]

        case .heroTop:
            let colW = max(1, (availW - spacing) / 2)
            let rowH = max(1, (availH - spacing) / 2)

            let x0 = round(margin)
            let xMid = round(margin + colW)
            let xRightStart = round(xMid + spacing)
            let xRightEnd = round(width - margin)
            let y0 = round(margin)
            let yMid = round(margin + rowH)
            let yBottomStart = round(yMid + spacing)
            let yBottomEnd = round(height - margin)

            let heroRect = CGRect(x: x0, y: y0, width: max(1, xRightEnd - x0), height: max(1, yMid - y0))
            let leftCell = CGRect(x: x0, y: yBottomStart, width: max(1, xMid - x0), height: max(1, yBottomEnd - yBottomStart))
            let rightCell = CGRect(x: xRightStart, y: yBottomStart, width: max(1, xRightEnd - xRightStart), height: max(1, yBottomEnd - yBottomStart))

            return [
                CollageCellGeometry(index: 1, rect: heroRect, name: "\(options.frameNamePrefix) 1 (Hero)"),
                CollageCellGeometry(index: 2, rect: leftCell, name: "\(options.frameNamePrefix) 2"),
                CollageCellGeometry(index: 3, rect: rightCell, name: "\(options.frameNamePrefix) 3")
            ]
        }
    }

    private static func computeUniformGrid(
        canvasSize: CGSize,
        rows: Int,
        columns: Int,
        spacing: CGFloat,
        margin: CGFloat,
        prefix: String
    ) -> [CollageCellGeometry] {
        let width = canvasSize.width
        let height = canvasSize.height
        let totalSpacingX = spacing * CGFloat(columns - 1)
        let totalSpacingY = spacing * CGFloat(rows - 1)
        let availW = max(1, width - 2 * margin - totalSpacingX)
        let availH = max(1, height - 2 * margin - totalSpacingY)
        let cellW = availW / CGFloat(columns)
        let cellH = availH / CGFloat(rows)

        var cells: [CollageCellGeometry] = []
        var index = 1
        for r in 0..<rows {
            let y0 = round(margin + CGFloat(r) * (cellH + spacing))
            let y1 = (r == rows - 1) ? round(height - margin) : round(margin + CGFloat(r) * (cellH + spacing) + cellH)
            let h = max(1, y1 - y0)

            for c in 0..<columns {
                let x0 = round(margin + CGFloat(c) * (cellW + spacing))
                let x1 = (c == columns - 1) ? round(width - margin) : round(margin + CGFloat(c) * (cellW + spacing) + cellW)
                let w = max(1, x1 - x0)

                let rect = CGRect(x: x0, y: y0, width: w, height: h)
                cells.append(CollageCellGeometry(index: index, rect: rect, name: "\(prefix) \(index)"))
                index += 1
            }
        }
        return cells
    }

    /// Generates a standard frame placeholder image with neutral fill and subtle inner border.
    static func makeFramePlaceholder(
        width: Int,
        height: Int,
        name: String,
        fillColor: (r: UInt8, g: UInt8, b: UInt8) = (244, 246, 249),
        borderColor: (r: UInt8, g: UInt8, b: UInt8) = (205, 210, 220)
    ) -> ImportedImage? {
        let w = max(1, width)
        let h = max(1, height)
        let total = w * h * 4
        var pixels = [UInt8](repeating: 0, count: total)

        for y in 0..<h {
            for x in 0..<w {
                let off = (y * w + x) * 4
                let isBorder = (x == 0 || x == w - 1 || y == 0 || y == h - 1)
                if isBorder {
                    pixels[off + 0] = borderColor.r
                    pixels[off + 1] = borderColor.g
                    pixels[off + 2] = borderColor.b
                    pixels[off + 3] = 255
                } else {
                    pixels[off + 0] = fillColor.r
                    pixels[off + 1] = fillColor.g
                    pixels[off + 2] = fillColor.b
                    pixels[off + 3] = 255
                }
            }
        }

        let data = Data(pixels)
        guard let provider = CGDataProvider(data: data as CFData),
              let cgImage = CGImage(
                width: w,
                height: h,
                bitsPerComponent: 8,
                bitsPerPixel: 32,
                bytesPerRow: w * 4,
                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue),
                provider: provider,
                decode: nil,
                shouldInterpolate: true,
                intent: .defaultIntent
              ) else { return nil }

        let thumbnail = (try? PixelInvert.thumbnail(of: cgImage)) ?? cgImage
        return ImportedImage(image: cgImage, thumbnail: thumbnail, name: name)
    }

    /// Generates the layer tree containing the root collage group and standard image frames.
    static func generateLayers(
        for canvasSize: CGSize,
        options: CollageOptions = CollageOptions()
    ) -> [ImageLayer] {
        let cells = computeCells(for: canvasSize, options: options)
        guard !cells.isEmpty else { return [] }

        var collageGroup = ImageLayer(name: "Collage (\(options.preset.rawValue))", blankSize: canvasSize)
        collageGroup.isGroup = true
        let rootID = collageGroup.id

        var result: [ImageLayer] = [collageGroup]

        for cell in cells {
            let w = max(1, Int(cell.rect.width.rounded()))
            let h = max(1, Int(cell.rect.height.rounded()))
            let frameAsset = makeFramePlaceholder(width: w, height: h, name: cell.name)

            if options.groupPerCell {
                var cellGroup = ImageLayer(name: cell.name, blankSize: canvasSize)
                cellGroup.isGroup = true
                cellGroup.parentID = rootID
                let cellGroupID = cellGroup.id
                result.append(cellGroup)

                var frameLayer: ImageLayer
                if let frameAsset {
                    frameLayer = ImageLayer(asset: frameAsset, origin: cell.rect.origin)
                } else {
                    frameLayer = ImageLayer(name: "\(cell.name) Frame", blankSize: cell.rect.size)
                    frameLayer.transform = LayerTransform(origin: cell.rect.origin, size: cell.rect.size)
                }
                frameLayer.name = "\(cell.name) Frame"
                frameLayer.parentID = cellGroupID
                result.append(frameLayer)
            } else {
                var frameLayer: ImageLayer
                if let frameAsset {
                    frameLayer = ImageLayer(asset: frameAsset, origin: cell.rect.origin)
                } else {
                    frameLayer = ImageLayer(name: cell.name, blankSize: cell.rect.size)
                    frameLayer.transform = LayerTransform(origin: cell.rect.origin, size: cell.rect.size)
                }
                frameLayer.name = cell.name
                frameLayer.parentID = rootID
                result.append(frameLayer)
            }
        }

        return result
    }
}

@MainActor
extension EditorSession {
    @discardableResult
    func addCollage(options: CollageOptions = CollageOptions()) -> UUID? {
        guard canEditLayers, let document else { return nil }
        let canvasSize = CGSize(width: document.width, height: document.height)
        let newLayers = CollageGenerator.generateLayers(for: canvasSize, options: options)
        guard !newLayers.isEmpty else { return nil }

        beginEdit("Add Collage Layout")
        defer { endEdit() }

        self.document?.layers.append(contentsOf: newLayers)
        if let root = newLayers.first {
            activeLayerID = root.id
            return root.id
        }
        return nil
    }
}
