import CoreImage
import CoreImage.CIFilterBuiltins

/// 底色风格。苹果「摄影风格」的调色盘没有对第三方开放的接口（见 README），
/// 这里在 App 内用 Core Image 复刻同样的交互：底色 + 色调/色彩二维盘 + 调色板强度。
enum PaletteStyle: String, CaseIterable, Identifiable {
    case standard, amber, gold, roseGold, neutral, coolRose
    case vibrant, natural, luminous, dramatic, quiet, cozy, ethereal

    var id: String { rawValue }

    var title: String {
        switch self {
        case .standard: return "标准"
        case .amber: return "琥珀色"
        case .gold: return "金色"
        case .roseGold: return "玫瑰金"
        case .neutral: return "中性"
        case .coolRose: return "冷玫瑰"
        case .vibrant: return "鲜明"
        case .natural: return "自然"
        case .luminous: return "明亮"
        case .dramatic: return "戏剧"
        case .quiet: return "静谧"
        case .cozy: return "温馨"
        case .ethereal: return "空灵"
        }
    }

    /// 底色参数：暖色(-1 冷…+1 暖)、品红(-1 绿…+1 品红)、饱和度倍数、对比度倍数、曝光(EV)
    var params: (warmth: Double, tint: Double, saturation: Double, contrast: Double, exposure: Double) {
        switch self {
        case .standard: return (0, 0, 1, 1, 0)
        case .amber: return (0.9, 0.1, 1.02, 1, 0)
        case .gold: return (0.7, -0.15, 1.06, 1.02, 0.02)
        case .roseGold: return (0.4, 0.6, 1.0, 1, 0.02)
        case .neutral: return (-0.3, 0, 0.92, 0.98, 0)
        case .coolRose: return (-0.6, 0.5, 0.98, 1, 0)
        case .vibrant: return (0, 0, 1.25, 1.06, 0)
        case .natural: return (0.15, 0, 0.94, 0.97, 0)
        case .luminous: return (-0.1, 0.1, 1.05, 0.94, 0.12)
        case .dramatic: return (-0.2, 0, 0.9, 1.2, -0.08)
        case .quiet: return (0.1, 0, 0.72, 0.9, 0.04)
        case .cozy: return (0.8, 0.1, 0.98, 1.04, -0.02)
        case .ethereal: return (-0.35, 0.3, 0.8, 0.88, 0.1)
        }
    }
}

struct PaletteSettings: Equatable {
    var style: PaletteStyle = .standard
    /// 色调：-1 加深阴影/提高反差 … +1 提亮阴影/压低反差
    var tone: Double = 0
    /// 色彩：-1 低饱和 … +1 高饱和
    var color: Double = 0
    /// 调色板：底色风格的强度 0…1
    var amount: Double = 1

    var isIdentity: Bool { style == .standard && abs(tone) < 0.01 && abs(color) < 0.01 }
}

/// 把胶片模式、调色盘和暗角串成一条 Core Image 滤镜链。预览和成片共用，保证所见即所得。
enum FilmLook {
    static func apply(_ input: CIImage, film: FilmMode, palette: PaletteSettings, vignette: Bool) -> CIImage {
        var image = applyPalette(input, palette)
        image = applyFilm(image, film)
        if vignette { image = applyVignette(image) }
        return image
    }

    static func applyPalette(_ input: CIImage, _ palette: PaletteSettings) -> CIImage {
        guard !palette.isIdentity else { return input }
        var styled = input
        let p = palette.style.params
        if p.warmth != 0 || p.tint != 0 {
            styled = channelGain(styled, warmth: p.warmth * 0.08, tint: p.tint * 0.05)
        }
        if p.exposure != 0 {
            let f = CIFilter.exposureAdjust()
            f.inputImage = styled
            f.ev = Float(p.exposure)
            styled = f.outputImage ?? styled
        }
        if p.saturation != 1 || p.contrast != 1 {
            let f = CIFilter.colorControls()
            f.inputImage = styled
            f.saturation = Float(p.saturation)
            f.contrast = Float(p.contrast)
            f.brightness = 0
            styled = f.outputImage ?? styled
        }
        // 调色板：在原图和底色风格之间混合
        if palette.style != .standard && palette.amount < 0.999 {
            let f = CIFilter.dissolveTransition()
            f.inputImage = input
            f.targetImage = styled
            f.time = Float(palette.amount)
            styled = f.outputImage?.cropped(to: input.extent) ?? styled
        }
        // 色调（纵轴）
        if abs(palette.tone) > 0.01 {
            let t = Float(palette.tone)
            let hs = CIFilter.highlightShadowAdjust()
            hs.inputImage = styled
            hs.shadowAmount = max(0, t) * 0.6
            hs.highlightAmount = 1 - max(0, t) * 0.15
            styled = hs.outputImage ?? styled
            let cc = CIFilter.colorControls()
            cc.inputImage = styled
            cc.saturation = 1
            cc.contrast = 1 - t * 0.12
            cc.brightness = t * 0.02
            styled = cc.outputImage ?? styled
        }
        // 色彩（横轴）
        if abs(palette.color) > 0.01 {
            let c = Float(palette.color)
            let v = CIFilter.vibrance()
            v.inputImage = styled
            v.amount = c * 0.7
            styled = v.outputImage ?? styled
            let cc = CIFilter.colorControls()
            cc.inputImage = styled
            cc.saturation = 1 + c * 0.25
            cc.contrast = 1
            cc.brightness = 0
            styled = cc.outputImage ?? styled
        }
        return styled
    }

    static func applyFilm(_ input: CIImage, _ film: FilmMode) -> CIImage {
        switch film {
        case .hncs:
            return HNCS.apply(input)
        case .natural:
            return input
        case .color:
            // 轻微暖调 + 抬黑位的胶片曲线
            let curve = CIFilter.toneCurve()
            curve.inputImage = input
            curve.point0 = CGPoint(x: 0, y: 0.03)
            curve.point1 = CGPoint(x: 0.25, y: 0.23)
            curve.point2 = CGPoint(x: 0.5, y: 0.51)
            curve.point3 = CGPoint(x: 0.75, y: 0.78)
            curve.point4 = CGPoint(x: 1, y: 0.97)
            let warm = channelGain(curve.outputImage ?? input, warmth: 0.025, tint: 0.01)
            let sat = CIFilter.colorControls()
            sat.inputImage = warm
            sat.saturation = 0.92
            sat.contrast = 1.02
            sat.brightness = 0
            return sat.outputImage ?? input
        case .mono:
            let mono = CIFilter.colorControls()
            mono.inputImage = input
            mono.saturation = 0
            mono.contrast = 1.12
            mono.brightness = 0
            let curve = CIFilter.toneCurve()
            curve.inputImage = mono.outputImage
            curve.point0 = CGPoint(x: 0, y: 0.02)
            curve.point1 = CGPoint(x: 0.25, y: 0.2)
            curve.point2 = CGPoint(x: 0.5, y: 0.5)
            curve.point3 = CGPoint(x: 0.75, y: 0.8)
            curve.point4 = CGPoint(x: 1, y: 0.98)
            return curve.outputImage ?? input
        }
    }

    /// 用通道增益做色温/色调偏移：warmth>0 加红减蓝，tint>0 减绿（偏品红）
    static func channelGain(_ input: CIImage, warmth: Double, tint: Double) -> CIImage {
        let f = CIFilter.colorMatrix()
        f.inputImage = input
        f.rVector = CIVector(x: CGFloat(1 + warmth), y: 0, z: 0, w: 0)
        f.gVector = CIVector(x: 0, y: CGFloat(1 - tint), z: 0, w: 0)
        f.bVector = CIVector(x: 0, y: 0, z: CGFloat(1 - warmth), w: 0)
        f.aVector = CIVector(x: 0, y: 0, z: 0, w: 1)
        f.biasVector = CIVector(x: 0, y: 0, z: 0, w: 0)
        return f.outputImage ?? input
    }

    /// 模拟 XPan 广角镜头的边缘失光
    static func applyVignette(_ input: CIImage) -> CIImage {
        let extent = input.extent
        let f = CIFilter.vignetteEffect()
        f.inputImage = input
        f.center = CGPoint(x: extent.midX, y: extent.midY)
        f.radius = Float(hypot(extent.width, extent.height) * 0.42)
        f.intensity = 0.45
        f.falloff = 0.6
        return f.outputImage?.cropped(to: extent) ?? input
    }
}
