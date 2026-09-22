import AppKit
import Testing
@testable import Compositor

@MainActor
struct RGBAChannelTests {
    @Test func straightRGBAPreservesColorsInZeroAlphaPixels() throws {
        // Create an un-premultiplied straight RGBA buffer where Alpha = 0, but RGB has distinct data (packed texture)
        var buffer = RGBAChannelBuffer(width: 2, height: 2)
        // Pixel 0: Red=250, Green=120, Blue=40, Alpha=0
        buffer.pixels[0] = 250
        buffer.pixels[1] = 120
        buffer.pixels[2] = 40
        buffer.pixels[3] = 0

        // Pixel 1: Red=10, Green=200, Blue=80, Alpha=255
        buffer.pixels[4] = 10
        buffer.pixels[5] = 200
        buffer.pixels[6] = 80
        buffer.pixels[7] = 255

        let straightImage = try #require(buffer.makeStraightCGImage())
        let recovered = RGBAChannelBuffer(image: straightImage)

        // Verify RGB values in Pixel 0 (Alpha=0) were NOT wiped to 0
        #expect(recovered.pixels[0] == 250)
        #expect(recovered.pixels[1] == 120)
        #expect(recovered.pixels[2] == 40)
        #expect(recovered.pixels[3] == 0)

        // Verify Pixel 1
        #expect(recovered.pixels[4] == 10)
        #expect(recovered.pixels[5] == 200)
        #expect(recovered.pixels[6] == 80)
        #expect(recovered.pixels[7] == 255)
    }

    @Test func editingSingleChannelDoesNotAffectOtherChannels() {
        var buffer = RGBAChannelBuffer(width: 2, height: 2)
        // Fill all pixels with initial values
        for i in 0..<4 {
            let off = i * 4
            buffer.pixels[off + 0] = 50  // Red
            buffer.pixels[off + 1] = 100 // Green
            buffer.pixels[off + 2] = 150 // Blue
            buffer.pixels[off + 3] = 200 // Alpha
        }

        // Edit ONLY Red channel
        buffer.setChannel(.red, values: [220, 225, 230, 235])

        for i in 0..<4 {
            let off = i * 4
            #expect(buffer.pixels[off + 0] >= 220) // Red changed
            #expect(buffer.pixels[off + 1] == 100) // Green unchanged!
            #expect(buffer.pixels[off + 2] == 150) // Blue unchanged!
            #expect(buffer.pixels[off + 3] == 200) // Alpha unchanged!
        }

        // Invert ONLY Green channel
        buffer.invertChannel(.green)
        for i in 0..<4 {
            let off = i * 4
            #expect(buffer.pixels[off + 0] >= 220) // Red unchanged
            #expect(buffer.pixels[off + 1] == 155) // Green inverted (255 - 100 = 155)
            #expect(buffer.pixels[off + 2] == 150) // Blue unchanged
            #expect(buffer.pixels[off + 3] == 200) // Alpha unchanged
        }

        // Fill ONLY Blue channel with 0
        buffer.fillChannel(.blue, value: 0)
        for i in 0..<4 {
            let off = i * 4
            #expect(buffer.pixels[off + 0] >= 220) // Red unchanged
            #expect(buffer.pixels[off + 1] == 155) // Green unchanged
            #expect(buffer.pixels[off + 2] == 0)   // Blue filled with 0
            #expect(buffer.pixels[off + 3] == 200) // Alpha unchanged
        }
    }

    @Test func channelViewingGeneratesAccurateGrayscale() throws {
        var buffer = RGBAChannelBuffer(width: 1, height: 1)
        buffer.pixels[0] = 45  // Red
        buffer.pixels[1] = 90  // Green
        buffer.pixels[2] = 180 // Blue
        buffer.pixels[3] = 220 // Alpha

        let redGray = try #require(buffer.makeGrayscaleImage(for: .red))
        #expect(redGray.width == 1 && redGray.height == 1)

        let redIsolation = try #require(buffer.channelIsolationImage(for: .red))
        let redBuffer = RGBAChannelBuffer(image: redIsolation)
        #expect(redBuffer.pixels[0] == 45)
        #expect(redBuffer.pixels[1] == 45)
        #expect(redBuffer.pixels[2] == 45)
        #expect(redBuffer.pixels[3] == 255)

        let alphaIsolation = try #require(buffer.channelIsolationImage(for: .alpha))
        let alphaBuffer = RGBAChannelBuffer(image: alphaIsolation)
        #expect(alphaBuffer.pixels[0] == 220)
        #expect(alphaBuffer.pixels[1] == 220)
        #expect(alphaBuffer.pixels[2] == 220)
    }

    @Test func channelCopyAndPasteInSession() throws {
        let session = EditorSession()
        session.createDocument(width: 4, height: 4)

        var buffer = RGBAChannelBuffer(width: 4, height: 4)
        for i in 0..<16 {
            let off = i * 4
            buffer.pixels[off + 0] = 240 // Red
            buffer.pixels[off + 1] = 60  // Green
            buffer.pixels[off + 2] = 120 // Blue
            buffer.pixels[off + 3] = 255 // Alpha
        }
        let image = try #require(buffer.makeStraightCGImage())
        session.insert(ImportedImage(image: image, thumbnail: image, name: "Test"))
        let layerID = try #require(session.activeLayerID)

        // Select Red channel and copy
        session.selectChannel(.red)
        let copied = session.copyChannel()
        #expect(copied)

        // Paste Red channel into Green channel
        let pasted = session.pasteChannel(into: .green)
        #expect(pasted)

        let modifiedLayer = try #require(session.document?.layers.first(where: { $0.id == layerID }))
        let modifiedImage = try #require(modifiedLayer.asset?.image)
        let modifiedBuffer = RGBAChannelBuffer(image: modifiedImage)

        // Green channel should now have the high values copied from Red
        let greenVal = modifiedBuffer.pixels[1]
        #expect(greenVal >= 230) // Close to 240
    }

    @Test func channelLoadAsSelection() throws {
        let session = EditorSession()
        session.createDocument(width: 8, height: 8)

        var buffer = RGBAChannelBuffer(width: 8, height: 8)
        // Center 4x4 white in alpha channel, outer black
        for y in 0..<8 {
            for x in 0..<8 {
                let off = (y * 8 + x) * 4
                buffer.pixels[off + 0] = 255
                buffer.pixels[off + 1] = 255
                buffer.pixels[off + 2] = 255
                let inCenter = (x >= 2 && x < 6 && y >= 2 && y < 6)
                buffer.pixels[off + 3] = inCenter ? 255 : 0
            }
        }
        let image = try #require(buffer.makeStraightCGImage())
        session.insert(ImportedImage(image: image, thumbnail: image, name: "Masked"))

        #expect(session.document?.selection == nil)

        let loaded = session.loadChannelAsSelection(.alpha)
        #expect(loaded)
        #expect(session.document?.selection != nil)
        #expect(session.document?.selection?.isEmpty == false)
    }

    @Test func straightPNGExportPreservesUnpremultipliedColors() async throws {
        var buffer = RGBAChannelBuffer(width: 4, height: 4)
        // Texture packing: roughness in Red, metallic in Green, AO in Blue, Opacity in Alpha
        for i in 0..<16 {
            let off = i * 4
            buffer.pixels[off + 0] = 180 // Roughness
            buffer.pixels[off + 1] = 90  // Metallic
            buffer.pixels[off + 2] = 45  // AO
            buffer.pixels[off + 3] = (i % 2 == 0) ? 255 : 0 // Half pixels transparent
        }

        let pngData = try await ImageExporter.shared.straightPNGData(for: buffer)
        #expect(!pngData.isEmpty)

        // Decode exported PNG
        let source = try #require(CGImageSourceCreateWithData(pngData as CFData, nil))
        let decoded = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        let decodedBuffer = RGBAChannelBuffer(image: decoded)

        // In transparent pixels (Alpha = 0), Roughness (180), Metallic (90), AO (45) are intact!
        for i in stride(from: 1, to: 16, by: 2) {
            let off = i * 4
            #expect(decodedBuffer.pixels[off + 3] == 0)   // Alpha is 0
            #expect(decodedBuffer.pixels[off + 0] == 180) // Red intact
            #expect(decodedBuffer.pixels[off + 1] == 90)  // Green intact
            #expect(decodedBuffer.pixels[off + 2] == 45)  // Blue intact
        }
    }
}
