import AppKit
import CoreImage

nonisolated enum FilterLayerKind: String, Codable, CaseIterable, Sendable {
    case gaussianBlur = "Gaussian Blur"
    case motionBlur = "Motion Blur"
    case addNoise = "Add Noise"
    case lensCorrection = "Lens Correction"
    case curves = "Curves"
    case exposure = "Exposure"
    case gradientMap = "Gradient Map"
    case grain = "Grain"
    case blackWhite = "Black & White"
    case colorBalance = "Color Balance"
    case invert = "Invert"

    var symbol: String {
        switch self {
        case .gaussianBlur: return "drop.fill"
        case .motionBlur: return "wind"
        case .addNoise: return "circle.dotted"
        case .lensCorrection: return "camera.metering.matrix"
        case .curves: return "point.topleft.down.to.point.bottomright.curvepath"
        case .exposure: return "plusminus.circle"
        case .gradientMap: return "paintpalette"
        case .grain: return "circle.grid.3x3"
        case .blackWhite: return "circle.filled.pattern.diagonalline.rectangle"
        case .colorBalance: return "scale.3d"
        case .invert: return "circle.righthalf.filled"
        }
    }

    var isEditable: Bool { self != .invert }

    var filterKind: FilterKind? {
        switch self {
        case .gaussianBlur: return .gaussianBlur
        case .motionBlur: return .motionBlur
        case .addNoise: return .addNoise
        case .lensCorrection: return .lensCorrection
        case .curves: return .curves
        case .exposure: return .exposure
        case .gradientMap: return .gradientMap
        case .grain: return .grain
        case .blackWhite: return .blackWhite
        case .colorBalance: return .colorBalance
        case .invert: return nil
        }
    }
}

nonisolated struct LayerFilterSettings: Codable, Equatable, Sendable {
    var radius: Double = 10
    var angle: Double = 0
    var distance: Double = 10
    var amount: Double = 10
    var gaussian: Bool = false
    var monochromatic: Bool = false
    var distortion: Double = 0
    var seed: UInt32 = 0

    var curves: CurvesSettings = CurvesSettings()
    var exposure: ExposureSettings = ExposureSettings()
    var gradientMap: GradientMapSettings = GradientMapSettings()
    var grain: GrainSettings = GrainSettings()
    var blackWhite: BlackWhiteSettings = BlackWhiteSettings()
    var colorBalance: ColorBalanceSettings = ColorBalanceSettings()

    init() {}

    init(from s: FilterSettings, seed: UInt32 = 0) {
        self.radius = s.radius
        self.angle = s.angle
        self.distance = s.distance
        self.amount = s.amount
        self.gaussian = s.gaussian
        self.monochromatic = s.monochromatic
        self.distortion = s.distortion
        self.seed = seed
        self.curves = s.curves
        self.exposure = s.exposure
        self.gradientMap = s.gradientMap
        self.grain = s.grain
        self.blackWhite = s.blackWhite
        self.colorBalance = s.colorBalance
    }

    func toFilterSettings() -> FilterSettings {
        var s = FilterSettings()
        s.radius = radius
        s.angle = angle
        s.distance = distance
        s.amount = amount
        s.gaussian = gaussian
        s.monochromatic = monochromatic
        s.distortion = distortion
        s.curves = curves
        s.exposure = exposure
        s.gradientMap = gradientMap
        s.grain = grain
        s.blackWhite = blackWhite
        s.colorBalance = colorBalance
        return s
    }
}

nonisolated struct LayerFilter: Codable, Equatable, Sendable {
    var kind: FilterLayerKind
    var settings: LayerFilterSettings

    init(kind: FilterLayerKind, settings: LayerFilterSettings = LayerFilterSettings()) {
        self.kind = kind
        self.settings = settings
    }

    var isValid: Bool {
        settings.radius.isFinite && (0.1...250).contains(settings.radius)
            && settings.angle.isFinite && (-90...90).contains(settings.angle)
            && settings.distance.isFinite && (1...2000).contains(settings.distance)
            && settings.amount.isFinite && (0.1...400).contains(settings.amount)
            && settings.distortion.isFinite && (-100...100).contains(settings.distortion)
            && settings.curves.isValid && settings.exposure.isValid && settings.gradientMap.isValid
            && settings.grain.isValid && settings.blackWhite.isValid && settings.colorBalance.isValid
    }

    func apply(_ image: CGImage, region: CGRect? = nil) throws -> CGImage {
        if kind == .invert {
            return try PixelInvert.run(PixelInvert.Job(image: image, isMask: false, pixelToDocument: .identity, selection: nil))
        }
        if kind == .grain {
            let r = region ?? CGRect(x: 0, y: 0, width: image.width, height: image.height)
            return try settings.grain.apply(image, origin: r.origin, unitsPerPixel: r.width / CGFloat(max(1, image.width)), seed: settings.seed)
        }
        guard let fKind = kind.filterKind else { throw ProjectError.invalid }
        let job = FilterJob(kind: fKind, image: image, settings: settings.toFilterSettings(), scale: 1, selection: nil, mapping: .identity, seed: settings.seed)
        return try PixelFilter.run(job)
    }
}

extension EditorSession {
    func addFilterLayer(_ kind: FilterLayerKind) {
        guard canEditLayers, let document, document.layers.count < 10_000 else { return }
        var layer = ImageLayer(name: kind.rawValue, blankSize: document.size)
        var filter = LayerFilter(kind: kind)
        if kind == .gradientMap {
            filter.settings.gradientMap = GradientMapSettings(shadows: AdjustmentColor(foregroundColor), highlights: AdjustmentColor(backgroundColor))
        }
        if kind == .grain { filter.settings.grain.seed = .random(in: .min ... .max) }
        if kind == .addNoise { filter.settings.seed = .random(in: .min ... .max) }
        layer.filter = filter
        layer.parentID = activeLayer?.isGroup == true ? activeLayerID : activeLayer?.parentID
        let index = document.layers.firstIndex { $0.id == activeLayerID }.map { $0 + 1 } ?? document.layers.count
        beginEdit("New \(kind.rawValue) Filter")
        self.document?.layers.insert(layer, at: index)
        if let parent = layer.parentID { collapsedGroupIDs.remove(parent) }
        activeLayerID = layer.id
        endEdit()
        if kind.isEditable { filterEditingID = layer.id }
    }

    func updateFilterLayer(_ id: UUID, value: LayerFilter) {
        guard let index = document?.layers.firstIndex(where: { $0.id == id }), value.isValid else { return }
        document?.layers[index].filter = value
        brushRevision += 1
    }
}
