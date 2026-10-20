import SwiftUI

/// XPan 原版提供两种胶片：彩色与黑白。
enum FilmMode: String, CaseIterable, Identifiable {
    case color
    case mono

    var id: String { rawValue }
    var title: String { self == .color ? "彩色" : "黑白" }
    var badge: String { self == .color ? "C" : "BW" }
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
    @AppStorage("filmMode") var filmMode: FilmMode = .color
    @AppStorage("focal") var focalMillimeters: Int = FocalLength.default.millimeters
    @AppStorage("vignette") var vignette: Bool = true
    @AppStorage("portraitOutput") var portraitOutput: PortraitOutput = .landscapeBand
    @AppStorage("watermarkEnabled") var watermarkEnabled: Bool = false
    @AppStorage("watermarkTemplate") var watermarkTemplate: String = "标准水印"
    @AppStorage("saveOriginal") var saveOriginal: Bool = false
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
