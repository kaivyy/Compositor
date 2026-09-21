import Testing
import CoreGraphics
import AppKit
@testable import Compositor

@MainActor
struct CollageGridTests {
    @Test func deterministicGrid2x2Geometry() {
        let canvas = CGSize(width: 400, height: 300)
        let options = CollageOptions(
            preset: .grid2x2,
            spacing: 10,
            margin: 10,
            groupPerCell: true,
            frameNamePrefix: "Frame"
        )
        let cells = CollageGenerator.computeCells(for: canvas, options: options)
        #expect(cells.count == 4)

        // Cell 1: top-left
        #expect(cells[0].rect == CGRect(x: 10, y: 10, width: 185, height: 135))
        #expect(cells[0].name == "Frame 1")

        // Cell 2: top-right
        #expect(cells[1].rect == CGRect(x: 205, y: 10, width: 185, height: 135))
        #expect(cells[1].name == "Frame 2")

        // Cell 3: bottom-left
        #expect(cells[2].rect == CGRect(x: 10, y: 155, width: 185, height: 135))
        #expect(cells[2].name == "Frame 3")

        // Cell 4: bottom-right
        #expect(cells[3].rect == CGRect(x: 205, y: 155, width: 185, height: 135))
        #expect(cells[3].name == "Frame 4")
    }

    @Test func heroLeftPresetGeometry() {
        let canvas = CGSize(width: 600, height: 400)
        let options = CollageOptions(
            preset: .heroLeft,
            spacing: 20,
            margin: 20
        )
        let cells = CollageGenerator.computeCells(for: canvas, options: options)
        #expect(cells.count == 3)

        // Hero on left: x: 20..<290 (w=270), y: 20..<380 (h=360)
        let hero = cells[0]
        #expect(hero.rect.minX == 20)
        #expect(hero.rect.minY == 20)
        #expect(hero.rect.maxY == 380)

        // Stacked on right: x: 310..<580 (w=270)
        let top = cells[1]
        let bottom = cells[2]
        #expect(top.rect.minX == 310)
        #expect(top.rect.minY == 20)
        #expect(bottom.rect.minX == 310)
        #expect(bottom.rect.maxY == 380)
        #expect(top.rect.maxY + 20 == bottom.rect.minY)
    }

    @Test func heroTopPresetGeometry() {
        let canvas = CGSize(width: 600, height: 400)
        let options = CollageOptions(
            preset: .heroTop,
            spacing: 20,
            margin: 20
        )
        let cells = CollageGenerator.computeCells(for: canvas, options: options)
        #expect(cells.count == 3)

        // Hero on top: full width x: 20..<580 (w=560), y: 20..<190 (h=170)
        let hero = cells[0]
        #expect(hero.rect.minX == 20)
        #expect(hero.rect.maxX == 580)
        #expect(hero.rect.minY == 20)

        // Split below: y: 210..<380 (h=170)
        let left = cells[1]
        let right = cells[2]
        #expect(left.rect.minY == 210)
        #expect(right.rect.minY == 210)
        #expect(left.rect.minX == 20)
        #expect(right.rect.maxX == 580)
        #expect(left.rect.maxX + 20 == right.rect.minX)
    }

    @Test func columnAndRowPresets() {
        let canvas = CGSize(width: 300, height: 300)

        let colCells = CollageGenerator.computeCells(for: canvas, options: CollageOptions(preset: .threeColumns, spacing: 0, margin: 0))
        #expect(colCells.count == 3)
        #expect(colCells[0].rect == CGRect(x: 0, y: 0, width: 100, height: 300))
        #expect(colCells[1].rect == CGRect(x: 100, y: 0, width: 100, height: 300))
        #expect(colCells[2].rect == CGRect(x: 200, y: 0, width: 100, height: 300))

        let rowCells = CollageGenerator.computeCells(for: canvas, options: CollageOptions(preset: .threeRows, spacing: 0, margin: 0))
        #expect(rowCells.count == 3)
        #expect(rowCells[0].rect == CGRect(x: 0, y: 0, width: 300, height: 100))
        #expect(rowCells[1].rect == CGRect(x: 0, y: 100, width: 300, height: 100))
        #expect(rowCells[2].rect == CGRect(x: 0, y: 200, width: 300, height: 100))
    }

    @Test func placeholderFrameImageGeneration() throws {
        let placeholder = try #require(CollageGenerator.makeFramePlaceholder(width: 80, height: 60, name: "SampleFrame"))
        #expect(placeholder.name == "SampleFrame")
        #expect(placeholder.image.width == 80)
        #expect(placeholder.image.height == 60)

        let rep = try #require(NSBitmapImageRep(cgImage: placeholder.image))
        // Border pixel at (0, 0)
        let borderCol = try #require(rep.colorAt(x: 0, y: 0))
        #expect(abs(borderCol.alphaComponent - 1.0) < 0.01)

        // Interior pixel at (40, 30)
        let interiorCol = try #require(rep.colorAt(x: 40, y: 30))
        #expect(abs(interiorCol.alphaComponent - 1.0) < 0.01)
    }

    @Test func layerTreeHierarchyWithGroupsAndFrames() throws {
        let canvas = CGSize(width: 500, height: 500)
        let layers = CollageGenerator.generateLayers(for: canvas, options: CollageOptions(preset: .grid2x2, groupPerCell: true))
        // 1 root group + 4 cell groups + 4 frame layers = 9 layers
        #expect(layers.count == 9)

        let root = layers[0]
        #expect(root.isGroup)
        #expect(root.parentID == nil)
        #expect(root.asset == nil)

        // All children validate properly under LayerHierarchy
        let records = layers.map(\.hierarchyRecord)
        #expect(throws: Never.self) {
            try LayerHierarchy.validate(records)
        }

        // Test non-grouped version
        let flatLayers = CollageGenerator.generateLayers(for: canvas, options: CollageOptions(preset: .grid2x2, groupPerCell: false))
        // 1 root group + 4 frame layers = 5 layers
        #expect(flatLayers.count == 5)
        #expect(throws: Never.self) {
            try LayerHierarchy.validate(flatLayers.map(\.hierarchyRecord))
        }
    }

    @Test func editorSessionAddCollageAndUndo() throws {
        let session = EditorSession()
        session.createDocument(width: 600, height: 400)
        #expect(session.document?.layers.isEmpty == true)

        let collageID = try #require(session.addCollage(options: CollageOptions(preset: .grid2x2, groupPerCell: true)))
        #expect(session.document?.layers.count == 9)
        #expect(session.activeLayerID == collageID)

        // Undo removes collage cleanly
        session.undo()
        #expect(session.document?.layers.isEmpty == true)

        // Redo restores collage
        session.redo()
        #expect(session.document?.layers.count == 9)
    }
}
