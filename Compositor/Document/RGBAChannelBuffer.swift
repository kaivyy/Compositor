import AppKit
import CoreGraphics

/// Channels available for isolated viewing and editing.
public enum EditChannel: String, CaseIterable, Codable, Sendable, Identifiable {
    case rgb = "RGB"
    case red = "Red"
    case green = "Green"
    case blue = "Blue"
    case alpha = "Alpha"

    public var id: String { rawValue }

    public var channelIndex: Int? {
        switch self {
        case .rgb: return nil
        case .red: return 0
        case .green: return 1
        case .blue: return 2
        case .alpha: return 3
        }
    }
}

/// Un-premultiplied straight RGBA pixel buffer providing lossless channel storage and editing.
/// Keeps RGB data fully preserved even when alpha is 0 (essential for packed textures and games).
nonisolated public struct RGBAChannelBuffer: @unchecked Sendable {
    public let width: Int
    public let height: Int
    public var pixels: [UInt8] // [R, G, B, A, R, G, B, A, ...]

    public init(width: Int, height: Int, pixels: [UInt8]? = nil) {
        self.width = max(1, width)
        self.height = max(1, height)
        let total = self.width * self.height * 4
        if let pixels, pixels.count == total {
            self.pixels = pixels
        } else {
            self.pixels = [UInt8](repeating: 0, count: total)
        }
    }

    /// Creates an RGBAChannelBuffer from any CGImage, recovering un-premultiplied straight values.
    public nonisolated init(image: CGImage) {
        let w = image.width
        let h = image.height
        self.width = w
        self.height = h
        let total = w * h * 4

        // If the CGImage is already 32-bit straight RGBA (alphaInfo .last), read bytes directly if available
        let alphaInfo = image.alphaInfo
        let isStraight = (alphaInfo == .last || alphaInfo == .noneSkipLast)
        if isStraight, let data = image.dataProvider?.data, let bytes = CFDataGetBytePtr(data) {
            let count = CFDataGetLength(data)
            if count >= total {
                self.pixels = Array(UnsafeBufferPointer(start: bytes, count: total))
                return
            }
        }

        // Draw into a temporary premultiplied context and un-premultiply to recover straight RGB
        guard let context = CGContext(
            data: nil,
            width: w,
            height: h,
            bitsPerComponent: 8,
            bytesPerRow: w * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        ) else {
            self.pixels = [UInt8](repeating: 0, count: total)
            return
        }
        context.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        guard let data = context.data else {
            self.pixels = [UInt8](repeating: 0, count: total)
            return
        }

        let raw = data.assumingMemoryBound(to: UInt8.self)
        var buffer = [UInt8](repeating: 0, count: total)
        let pixelCount = w * h
        for i in 0..<pixelCount {
            let offset = i * 4
            let r_pm = Int(raw[offset + 0])
            let g_pm = Int(raw[offset + 1])
            let b_pm = Int(raw[offset + 2])
            let a = raw[offset + 3]

            if a == 0 {
                // In zero alpha, if source was premultiplied, R/G/B become 0
                buffer[offset + 0] = 0
                buffer[offset + 1] = 0
                buffer[offset + 2] = 0
                buffer[offset + 3] = 0
            } else if a == 255 {
                buffer[offset + 0] = UInt8(r_pm)
                buffer[offset + 1] = UInt8(g_pm)
                buffer[offset + 2] = UInt8(b_pm)
                buffer[offset + 3] = 255
            } else {
                let alphaVal = Int(a)
                buffer[offset + 0] = UInt8(min(255, (r_pm * 255 + alphaVal / 2) / alphaVal))
                buffer[offset + 1] = UInt8(min(255, (g_pm * 255 + alphaVal / 2) / alphaVal))
                buffer[offset + 2] = UInt8(min(255, (b_pm * 255 + alphaVal / 2) / alphaVal))
                buffer[offset + 3] = a
            }
        }
        self.pixels = buffer
    }

    /// Creates a straight RGBA CGImage where transparent pixels preserve un-premultiplied RGB.
    public func makeStraightCGImage() -> CGImage? {
        let data = Data(pixels)
        guard let provider = CGDataProvider(data: data as CFData) else { return nil }
        return CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: width * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue | CGBitmapInfo.byteOrder32Big.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: true,
            intent: .defaultIntent
        )
    }

    /// Creates a premultiplied RGBA CGImage for CoreGraphics canvas compositing.
    public func makePremultipliedCGImage() -> CGImage? {
        var pm = [UInt8](repeating: 0, count: pixels.count)
        let pixelCount = width * height
        for i in 0..<pixelCount {
            let offset = i * 4
            let a = Int(pixels[offset + 3])
            pm[offset + 0] = UInt8((Int(pixels[offset + 0]) * a + 127) / 255)
            pm[offset + 1] = UInt8((Int(pixels[offset + 1]) * a + 127) / 255)
            pm[offset + 2] = UInt8((Int(pixels[offset + 2]) * a + 127) / 255)
            pm[offset + 3] = UInt8(a)
        }
        let data = Data(pm)
        guard let provider = CGDataProvider(data: data as CFData) else { return nil }
        return CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: width * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: true,
            intent: .defaultIntent
        )
    }

    /// Extracts an 8-bit grayscale image representing the isolated values of a single channel.
    public func makeGrayscaleImage(for channel: EditChannel) -> CGImage? {
        guard let idx = channel.channelIndex else {
            return makeStraightCGImage()
        }
        let pixelCount = width * height
        var gray = [UInt8](repeating: 0, count: pixelCount)
        for i in 0..<pixelCount {
            gray[i] = pixels[i * 4 + idx]
        }
        let data = Data(gray)
        guard let provider = CGDataProvider(data: data as CFData) else { return nil }
        return CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 8,
            bytesPerRow: width,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: true,
            intent: .defaultIntent
        )
    }

    /// Creates an RGBA display image rendering the selected channel as grayscale (white = 255, black = 0) with full opacity.
    public func channelIsolationImage(for channel: EditChannel) -> CGImage? {
        guard let idx = channel.channelIndex else {
            return makeStraightCGImage()
        }
        let pixelCount = width * height
        var display = [UInt8](repeating: 255, count: pixelCount * 4)
        for i in 0..<pixelCount {
            let val = pixels[i * 4 + idx]
            let off = i * 4
            display[off + 0] = val
            display[off + 1] = val
            display[off + 2] = val
            display[off + 3] = 255
        }
        let data = Data(display)
        guard let provider = CGDataProvider(data: data as CFData) else { return nil }
        return CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: width * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: true,
            intent: .defaultIntent
        )
    }

    /// Reads all bytes for a specific channel.
    public func getChannel(_ channel: EditChannel) -> [UInt8]? {
        guard let idx = channel.channelIndex else { return nil }
        let pixelCount = width * height
        var result = [UInt8](repeating: 0, count: pixelCount)
        for i in 0..<pixelCount {
            result[i] = pixels[i * 4 + idx]
        }
        return result
    }

    /// Replaces the values of a single channel without modifying any other channels.
    public mutating func setChannel(_ channel: EditChannel, values: [UInt8]) {
        guard let idx = channel.channelIndex else { return }
        let pixelCount = width * height
        let count = min(pixelCount, values.count)
        for i in 0..<count {
            pixels[i * 4 + idx] = values[i]
        }
    }

    /// Replaces the values of a single channel from a grayscale image.
    public mutating func setChannel(_ channel: EditChannel, from image: CGImage) {
        guard let idx = channel.channelIndex else { return }
        guard let grayContext = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else { return }
        grayContext.interpolationQuality = .high
        grayContext.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let data = grayContext.data else { return }
        let raw = data.assumingMemoryBound(to: UInt8.self)
        let pixelCount = width * height
        for i in 0..<pixelCount {
            pixels[i * 4 + idx] = raw[i]
        }
    }

    /// Inverts only the selected channel (255 - value).
    public mutating func invertChannel(_ channel: EditChannel) {
        guard let idx = channel.channelIndex else { return }
        let pixelCount = width * height
        for i in 0..<pixelCount {
            pixels[i * 4 + idx] = 255 - pixels[i * 4 + idx]
        }
    }

    /// Fills only the selected channel with a uniform value.
    public mutating func fillChannel(_ channel: EditChannel, value: UInt8) {
        guard let idx = channel.channelIndex else { return }
        let pixelCount = width * height
        for i in 0..<pixelCount {
            pixels[i * 4 + idx] = value
        }
    }
}

extension EditorSession {
    func selectChannel(_ channel: EditChannel) {
        guard activeChannel != channel else { return }
        activeChannel = channel
    }

    @discardableResult
    func copyChannel(_ channel: EditChannel? = nil) -> Bool {
        let target = channel ?? activeChannel
        guard let layer = activeLayer, let image = layer.asset?.image else { return false }
        let buffer = RGBAChannelBuffer(image: image)
        guard let gray = buffer.makeGrayscaleImage(for: target) else { return false }
        let bitmap = NSBitmapImageRep(cgImage: gray)
        guard let pngData = bitmap.representation(using: .png, properties: [:]) else { return false }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setData(pngData, forType: .png)
        return true
    }

    @discardableResult
    func pasteChannel(into channel: EditChannel? = nil) -> Bool {
        let target = channel ?? activeChannel
        guard target != .rgb, canEditLayers, let layer = activeLayer, let asset = layer.asset else { return false }
        let pasteboard = NSPasteboard.general
        guard let pngData = pasteboard.data(forType: .png) ?? pasteboard.data(forType: .tiff),
              let source = CGImageSourceCreateWithData(pngData as CFData, nil),
              let pastedImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return false }
        var buffer = RGBAChannelBuffer(image: asset.image)
        buffer.setChannel(target, from: pastedImage)
        guard let newImage = buffer.makeStraightCGImage(),
              let thumbnail = try? PixelInvert.thumbnail(of: newImage) else { return false }
        beginEdit("Paste " + target.rawValue + " Channel")
        if let index = document?.layers.firstIndex(where: { $0.id == layer.id }) {
            document?.layers[index].asset = ImportedImage(image: newImage, thumbnail: thumbnail, name: asset.name)
        }
        endEdit()
        return true
    }

    @discardableResult
    func loadChannelAsSelection(_ channel: EditChannel? = nil) -> Bool {
        let target = channel ?? activeChannel
        guard canEditSelection, let layer = activeLayer, let image = layer.asset?.image else { return false }
        let buffer = RGBAChannelBuffer(image: image)
        guard let gray = buffer.makeGrayscaleImage(for: target),
              let localPath = MaskTracing.whitePixels(in: gray) else {
            document?.selection = nil
            return false
        }
        var toDocument = BrushRaster.pixelToDocument(layer.transform, width: image.width, height: image.height)
        guard let outline = localPath.copy(using: &toDocument) else { return false }
        applySelection(outline, mode: .replace, name: "Load " + target.rawValue + " Channel Selection")
        return true
    }

    func fillChannel(_ channel: EditChannel? = nil, value: UInt8, on layerID: UUID? = nil) {
        let target = channel ?? activeChannel
        guard target != .rgb, canEditLayers else { return }
        let id = layerID ?? activeLayerID
        guard let id, let index = document?.layers.firstIndex(where: { $0.id == id }),
              let layer = document?.layers[index], let asset = layer.asset else { return }
        var buffer = RGBAChannelBuffer(image: asset.image)
        buffer.fillChannel(target, value: value)
        guard let newImage = buffer.makeStraightCGImage(),
              let thumbnail = try? PixelInvert.thumbnail(of: newImage) else { return }
        beginEdit("Fill " + target.rawValue + " Channel")
        document?.layers[index].asset = ImportedImage(image: newImage, thumbnail: thumbnail, name: asset.name)
        endEdit()
    }

    func invertChannel(_ channel: EditChannel? = nil, on layerID: UUID? = nil) {
        let target = channel ?? activeChannel
        guard target != .rgb, canEditLayers else { return }
        let id = layerID ?? activeLayerID
        guard let id, let index = document?.layers.firstIndex(where: { $0.id == id }),
              let layer = document?.layers[index], let asset = layer.asset else { return }
        var buffer = RGBAChannelBuffer(image: asset.image)
        buffer.invertChannel(target)
        guard let newImage = buffer.makeStraightCGImage(),
              let thumbnail = try? PixelInvert.thumbnail(of: newImage) else { return }
        beginEdit("Invert " + target.rawValue + " Channel")
        document?.layers[index].asset = ImportedImage(image: newImage, thumbnail: thumbnail, name: asset.name)
        endEdit()
    }
}
