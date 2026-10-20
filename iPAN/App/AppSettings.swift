import SwiftUI

/// 色彩：HNCS（仿哈苏自然色彩，默认）、XPan 胶片、苹果原色、黑白。
/// rawValue 沿用旧版本的 "color" / "mono"，升级后设置不丢。
enum FilmMode: String, CaseIterable, Identifiable {
    case hncs
    case color
    case natural
    case mono

    var id: String { rawValue }

    var title: String {
        switch self {
        case .hncs: return "HNCS"
        case .color: return "XPan 胶片"
        case .natural: return "原色"
        case .mono: return "黑白"
        }
    }

    /// 快门旁圆钮上的短标
    var badge: String {
        switch self {
        case .hncs: return "H"
        case .color: return "X"
        case .natural: return "N"
        case .mono: return "BW"
        }
    }

    /// 取景窗口上方的信息
    var caption: String {
        switch self {
        case .hncs: return "HNCS"
        case .color: return "XPAN FILM"
        case .natural: return "NATURAL"
        case .mono: return "B&W"
        }
    }

    var next: FilmMode {
        let all = FilmMode.allCases
        return all[(all.firstIndex(of: self)! + 1) % all.count]
    }
}

/// 拍摄模式（底部 OPPO 风格的模式轮播）
enum CaptureMode: String, CaseIterable, Identifiable {
    case ipan
    case stitch

    var id: String { rawValue }
    var title: String { self == .ipan ? "iPAN" : "双摄拼接 β" }
    /// 横屏竖排模式栏用的短名
    var shortTitle: String { self == .ipan ? "iPAN" : "拼接β" }
}

/// 竖握手机时的输出方向
enum PortraitOutput: String, CaseIterable, Identifiable {
    /// 仍然输出横向 65:24（与 OPPO / 一加的 XPan 一致，用传感器短边，像素更少）
    case landscapeBand
    /// 输出竖向 24:65（用传感器长边，像素最多）
    case portraitBand

    var id: String { rawValue }
    var title: String { self == .landscapeBand ? "横幅 65:24" : "竖幅 24:65" }
}

final class AppSettings: ObservableObject {
    @AppStorage("filmMode") var filmMode: FilmMode = .hncs
    @AppStorage("focal") var focalMillimeters: Int = FocalLength.default.millimeters
    @AppStorage("vignette") var vignette: Bool = true
    @AppStorage("portraitOutput") var portraitOutput: PortraitOutput = .landscapeBand
    @AppStorage("watermarkEnabled") var watermarkEnabled: Bool = false
    @AppStorage("watermarkTemplate") var watermarkTemplate: String = "标准水印"
    /// 水印里的品牌 Logo（semi-utils 的 auto_logo，iPhone 上是苹果 Logo），默认不加
    @AppStorage("watermarkLogo") var watermarkLogo: Bool = false
    @AppStorage("saveOriginal") var saveOriginal: Bool = false
    /// 锁定的光圈 f 值，0 表示自动
    @AppStorage("aperture") var aperture: Double = 0
    @AppStorage("developAnimation") var developAnimation: Bool = true

    // 调色盘（仿 iOS 摄影风格的色调 / 色彩 / 调色板三参数 + 底色风格）
    @AppStorage("palette.style") var paletteStyle: PaletteStyle = .standard
    @AppStorage("palette.tone") var paletteTone: Double = 0
    @AppStorage("palette.color") var paletteColor: Double = 0
    @AppStorage("palette.amount") var paletteAmount: Double = 1

    var focal: FocalLength {
        get { FocalLength(millimeters: focalMillimeters) }
        set { focalMillimeters = newValue.millimeters }
    }

    var palette: PaletteSettings {
        PaletteSettings(style: paletteStyle, tone: paletteTone, color: paletteColor, amount: paletteAmount)
    }

    func resetPalette() {
        paletteStyle = .standard
        paletteTone = 0
        paletteColor = 0
        paletteAmount = 1
    }
}
