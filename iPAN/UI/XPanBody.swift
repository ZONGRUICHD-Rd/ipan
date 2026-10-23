import SwiftUI

/// 横屏「相机机身」界面，复刻 OPPO Find X9 Ultra 的哈苏 XPAN 模式：
/// 深灰机身、上下两道带梯形缺口的接缝、顶部 HASSELBLAD 铭牌、带边框的取景窗（就是 65:24 画幅本身），
/// 右侧竖排 XPAN 标识、色彩风格卡片、金属快门和缩略图，左侧上下两个圆钮。
///
/// 位置按截图比例换算（基准为 874×402pt 的横屏 iPhone），在其他尺寸上等比缩放。
struct XPanBodyLayout {
    let size: CGSize

    private var sx: CGFloat { size.width / 874 }
    private var sy: CGFloat { size.height / 402 }

    /// 取景窗可用区域（画幅在里面按 65:24 居中放置）
    var windowRegion: CGRect { CGRect(x: 56 * sx, y: 91 * sy, width: 577 * sx, height: 215 * sy) }

    /// 上下接缝线的高度
    var topSeamY: CGFloat { 33 * sy }
    var bottomSeamY: CGFloat { 368 * sy }
    /// 中间梯形缺口：顶边宽度、底边宽度、深度
    var notchCenterX: CGFloat { windowRegion.midX }
    var notchOuterWidth: CGFloat { 250 * sx }
    var notchInnerWidth: CGFloat { 190 * sx }
    var notchDepth: CGFloat { 22 * sy }

    var plate: CGRect {
        CGRect(x: notchCenterX - 87 * sx, y: 23 * sy, width: 174 * sx, height: 22 * sy)
    }

    var leftColumnX: CGFloat { 69 * sx }
    var settingsCenter: CGPoint { CGPoint(x: leftColumnX, y: 34 * sy) }
    var toolsCenter: CGPoint { CGPoint(x: leftColumnX, y: 366 * sy) }
    var buttonDiameter: CGFloat { 44 * min(sx, sy) }

    var badge: CGRect { CGRect(x: 656 * sx, y: 146 * sy, width: 35 * sx, height: 106 * sy) }

    var rightColumnX: CGFloat { 760 * sx }
    var tileSize: CGFloat { 52 * min(sx, sy) }
    var styleTileCenter: CGPoint { CGPoint(x: rightColumnX, y: 85 * sy) }
    var shutterCenter: CGPoint { CGPoint(x: rightColumnX, y: 199 * sy) }
    var shutterDiameter: CGFloat { 72 * min(sx, sy) }
    var thumbnailCenter: CGPoint { CGPoint(x: rightColumnX, y: 320 * sy) }
}

// MARK: - 机身

private enum BodyPalette {
    static let fill = Color(red: 0.106, green: 0.110, blue: 0.122)
    static let fillLight = Color(red: 0.135, green: 0.139, blue: 0.152)
    static let seamDark = Color.black.opacity(0.55)
    static let seamLight = Color.white.opacity(0.07)
    static let bezel = Color(red: 0.07, green: 0.072, blue: 0.08)
    static let orange = Color(red: 0.93, green: 0.52, blue: 0.20)
}

/// 机身背景：整块深灰（取景窗处挖空露出预览）+ 接缝 + 铭牌 + 取景窗边框
struct XPanBodyBackground: View {
    let layout: XPanBodyLayout
    /// 取景窗（= 65:24 画幅）在全屏中的位置
    let window: CGRect

    var body: some View {
        let size = layout.size
        let hole = window
        let bezel = hole.insetBy(dx: -9, dy: -9)
        ZStack(alignment: .topLeading) {
            // 机身（挖空取景窗）
            Path { p in
                p.addRect(CGRect(origin: .zero, size: size))
                p.addRoundedRect(in: hole, cornerSize: CGSize(width: 12, height: 12), style: .continuous)
            }
            .fill(LinearGradient(colors: [BodyPalette.fillLight, BodyPalette.fill, BodyPalette.fillLight.opacity(0.9)],
                                 startPoint: .top, endPoint: .bottom),
                  style: FillStyle(eoFill: true))

            // 上下接缝（暗线 + 下方一条高光，做出压纹的感觉）
            Seam(layout: layout, y: layout.topSeamY, notchDown: true)
                .stroke(BodyPalette.seamDark, lineWidth: 1.5)
            Seam(layout: layout, y: layout.topSeamY + 1.5, notchDown: true)
                .stroke(BodyPalette.seamLight, lineWidth: 1)
            Seam(layout: layout, y: layout.bottomSeamY, notchDown: false)
                .stroke(BodyPalette.seamDark, lineWidth: 1.5)
            Seam(layout: layout, y: layout.bottomSeamY + 1.5, notchDown: false)
                .stroke(BodyPalette.seamLight, lineWidth: 1)

            // 取景窗边框
            Path { p in
                p.addRoundedRect(in: bezel, cornerSize: CGSize(width: 20, height: 20), style: .continuous)
                p.addRoundedRect(in: hole, cornerSize: CGSize(width: 12, height: 12), style: .continuous)
            }
            .fill(BodyPalette.bezel, style: FillStyle(eoFill: true))
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
                .frame(width: bezel.width, height: bezel.height)
                .offset(x: bezel.minX, y: bezel.minY)
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.black.opacity(0.8), lineWidth: 1.5)
                .frame(width: hole.width, height: hole.height)
                .offset(x: hole.minX, y: hole.minY)

            // 铭牌
            NamePlate()
                .frame(width: layout.plate.width, height: layout.plate.height)
                .offset(x: layout.plate.minX, y: layout.plate.minY)
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .allowsHitTesting(false)
    }
}

/// 一道横贯机身的接缝，中间有梯形缺口（顶部向下凹，底部向上凸）
private struct Seam: Shape {
    let layout: XPanBodyLayout
    let y: CGFloat
    let notchDown: Bool

    func path(in rect: CGRect) -> Path {
        let cx = layout.notchCenterX
        let outer = layout.notchOuterWidth / 2, inner = layout.notchInnerWidth / 2
        let depth = notchDown ? layout.notchDepth : -layout.notchDepth
        var p = Path()
        p.move(to: CGPoint(x: 0, y: y))
        p.addLine(to: CGPoint(x: cx - outer, y: y))
        p.addLine(to: CGPoint(x: cx - inner, y: y + depth))
        p.addLine(to: CGPoint(x: cx + inner, y: y + depth))
        p.addLine(to: CGPoint(x: cx + outer, y: y))
        p.addLine(to: CGPoint(x: layout.size.width, y: y))
        return p
    }
}

private struct NamePlate: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 4, style: .continuous)
            .fill(LinearGradient(colors: [Color.black.opacity(0.85), Color(white: 0.09)], startPoint: .top, endPoint: .bottom))
            .overlay(RoundedRectangle(cornerRadius: 4, style: .continuous).stroke(Color.white.opacity(0.12), lineWidth: 0.8))
            .overlay(
                Text("HASSELBLAD")
                    .font(.system(size: 15, weight: .heavy, design: .serif))
                    .italic()
                    .kerning(4.5)
                    .foregroundStyle(LinearGradient(colors: [Color(white: 0.86), Color(white: 0.62)], startPoint: .top, endPoint: .bottom))
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .padding(.horizontal, 8)
            )
    }
}

// MARK: - 取景窗内

/// 旁轴取景器式的亮框线：四角折角 + 上下左右的短亮线
struct RangefinderFrameLines: View {
    let window: CGRect

    var body: some View {
        let w = window.width, h = window.height
        let inset: CGFloat = 10
        Path { p in
            let r = window.insetBy(dx: inset, dy: inset)
            let l = min(22, r.height / 6)
            // 四角
            for (c, dx, dy) in [(CGPoint(x: r.minX, y: r.minY), 1.0, 1.0), (CGPoint(x: r.maxX, y: r.minY), -1.0, 1.0),
                                (CGPoint(x: r.minX, y: r.maxY), 1.0, -1.0), (CGPoint(x: r.maxX, y: r.maxY), -1.0, -1.0)] {
                p.move(to: CGPoint(x: c.x + dx * l, y: c.y))
                p.addLine(to: c)
                p.addLine(to: CGPoint(x: c.x, y: c.y + dy * l))
            }
            // 上边 / 下边的亮线段
            for (a, b) in [(0.17, 0.27), (0.44, 0.64)] {
                p.move(to: CGPoint(x: window.minX + w * a, y: r.minY))
                p.addLine(to: CGPoint(x: window.minX + w * b, y: r.minY))
            }
            for (a, b) in [(0.07, 0.11), (0.28, 0.39), (0.69, 0.77)] {
                p.move(to: CGPoint(x: window.minX + w * a, y: r.maxY))
                p.addLine(to: CGPoint(x: window.minX + w * b, y: r.maxY))
            }
            // 左右两侧的竖线段
            for x in [r.minX, r.maxX] {
                for (a, b) in [(0.10, 0.20), (0.40, 0.62), (0.80, 0.90)] {
                    p.move(to: CGPoint(x: x, y: window.minY + h * a))
                    p.addLine(to: CGPoint(x: x, y: window.minY + h * b))
                }
            }
        }
        .stroke(Color.white.opacity(0.82), style: StrokeStyle(lineWidth: 2, lineCap: .round))
        .allowsHitTesting(false)
    }
}

/// 取景窗左侧的曝光补偿刻度尺：上下拖动调节，双击归零
struct EVRuler: View {
    let value: Float
    let range: ClosedRange<Float>
    var onChange: (Float) -> Void

    @State private var dragStart: Float?
    @State private var lastTick: Int = 0

    private let step: Float = 0.1

    var body: some View {
        GeometryReader { proxy in
            let h = proxy.size.height
            let span = range.upperBound - range.lowerBound
            // 正值在上
            let y = CGFloat((range.upperBound - value) / max(0.01, span)) * h
            ZStack(alignment: .topLeading) {
                Canvas { ctx, size in
                    let count = Int((span / 0.2).rounded())
                    for i in 0...count {
                        let ev = range.upperBound - Float(i) * 0.2
                        let ty = CGFloat(i) / CGFloat(max(1, count)) * size.height
                        let major = abs(ev.rounded() - ev) < 0.01
                        let len: CGFloat = major ? 16 : 8
                        let rect = CGRect(x: size.width - len - 2, y: ty - 0.75, width: len, height: 1.5)
                        ctx.fill(Path(rect), with: .color(.white.opacity(major ? 0.85 : 0.5)))
                    }
                }
                .frame(width: 26)

                HStack(spacing: 4) {
                    Rectangle().fill(Color.white).frame(width: 14, height: 2)
                    Image(systemName: "arrowtriangle.left.fill")
                        .font(.system(size: 11))
                    Text(abs(value) < 0.05 ? "0.0" : String(format: "%+.1f", value))
                        .font(.system(size: 15, weight: .regular, design: .rounded))
                        .monospacedDigit()
                }
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.5), radius: 3)
                .fixedSize()
                .offset(x: 14, y: y - 10)
            }
            .frame(width: proxy.size.width, height: h, alignment: .topLeading)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 2)
                    .onChanged { g in
                        let start = dragStart ?? value
                        if dragStart == nil { dragStart = start }
                        let delta = Float(-g.translation.height / h) * span
                        var v = start + delta
                        v = (v / step).rounded() * step
                        v = min(range.upperBound, max(range.lowerBound, v))
                        let tick = Int((v / step).rounded())
                        if tick != lastTick {
                            lastTick = tick
                            UISelectionFeedbackGenerator().selectionChanged()
                        }
                        onChange(v)
                    }
                    .onEnded { _ in dragStart = nil }
            )
            .onTapGesture(count: 2) {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                onChange(0)
            }
        }
        .accessibilityLabel("曝光补偿")
        .accessibilityValue(String(format: "%.1f", value))
    }
}

/// 取景窗右侧的变焦圆钮（OPPO 显示倍率：1× = 24mm）
struct XPanZoomChips: View {
    let focals: [FocalLength]
    let selected: FocalLength
    let onSelect: (FocalLength) -> Void

    static func label(_ focal: FocalLength) -> String {
        let x = Double(focal.millimeters) / 24
        let text = x == x.rounded() ? String(Int(x)) : String(format: "%.1f", x)
        return text
    }

    var body: some View {
        VStack(spacing: 2) {
            // 长焦在上，和 OPPO 一致
            ForEach(Array(focals.reversed())) { focal in
                let isSelected = focal == selected
                Button {
                    onSelect(focal)
                } label: {
                    Text(isSelected ? Self.label(focal) + "×" : Self.label(focal))
                        .font(.system(size: isSelected ? 13 : 12, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                        .frame(width: 31, height: 31)
                        .background(Circle().fill(Color.black.opacity(isSelected ? 0.6 : 0.16)))
                        .shadow(color: .black.opacity(isSelected ? 0 : 0.6), radius: 2)
                }
                .buttonStyle(.plain)
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.75), value: selected)
    }
}

// MARK: - 机身按键

/// 机身上的圆形按键（设置、工具）
struct BodyRoundButton: View {
    let systemName: String
    let diameter: CGFloat
    var active = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: diameter * 0.42, weight: .regular))
                .foregroundStyle(active ? BodyPalette.orange : .white)
                .frame(width: diameter, height: diameter)
                .background(
                    Circle()
                        .fill(LinearGradient(colors: [Color(white: 0.17), Color(white: 0.10)], startPoint: .top, endPoint: .bottom))
                        .shadow(color: .black.opacity(0.6), radius: 3, y: 2)
                )
                .overlay(Circle().stroke(Color.white.opacity(0.08), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

/// 竖排的 XPAN 标识面板。点按切换拍摄模式（iPAN ⇄ 双摄拼接）
struct XPanBadge: View {
    let mode: CaptureMode
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .bold))
                    .opacity(mode == .stitch ? 1 : 0.9)
                Text(mode == .ipan ? "iPAN" : "WIDE")
                    .font(.system(size: 21, weight: .light))
                    .kerning(2)
                    .fixedSize()
                    .rotationEffect(.degrees(-90))
                    .frame(maxHeight: .infinity)
            }
            .foregroundStyle(BodyPalette.orange)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(LinearGradient(colors: [Color(white: 0.15), Color(white: 0.10)], startPoint: .leading, endPoint: .trailing))
            )
            .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).stroke(Color.white.opacity(0.08), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(mode == .ipan ? "iPAN 模式，点按切换到双摄拼接" : "双摄拼接模式，点按切换到 iPAN")
    }
}

/// 金属质感的快门
struct MetalShutterButton: View {
    let diameter: CGFloat
    var isBusy: Bool
    var isEnabled: Bool
    let action: () -> Void

    @State private var pressed = false
    @State private var spin = false

    var body: some View {
        ZStack {
            // 外圈
            Circle()
                .fill(LinearGradient(colors: [Color(white: 0.55), Color(white: 0.22)], startPoint: .top, endPoint: .bottom))
            Circle()
                .fill(Color(white: 0.12))
                .padding(diameter * 0.045)
            // 金属按钮
            Circle()
                .fill(LinearGradient(colors: [Color(white: 0.98), Color(white: 0.80), Color(white: 0.70)],
                                     startPoint: .top, endPoint: .bottom))
                .overlay(
                    Circle()
                        .fill(RadialGradient(colors: [Color.white.opacity(0.7), .clear], center: .init(x: 0.4, y: 0.25),
                                             startRadius: 0, endRadius: diameter * 0.35))
                )
                .overlay(Circle().stroke(Color.white.opacity(0.6), lineWidth: 0.8))
                .padding(diameter * 0.11)
                .scaleEffect(pressed ? 0.93 : 1)
                .brightness(pressed ? -0.08 : 0)
            if isBusy {
                Circle()
                    .trim(from: 0, to: 0.22)
                    .stroke(BodyPalette.orange, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    .padding(diameter * 0.02)
                    .rotationEffect(.degrees(spin ? 360 : 0))
                    .onAppear { withAnimation(.linear(duration: 0.9).repeatForever(autoreverses: false)) { spin = true } }
                    .onDisappear { spin = false }
            }
        }
        .frame(width: diameter, height: diameter)
        .shadow(color: .black.opacity(0.6), radius: 6, y: 3)
        .opacity(isEnabled ? 1 : 0.5)
        .contentShape(Circle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    if !pressed { withAnimation(.easeOut(duration: 0.08)) { pressed = true } }
                }
                .onEnded { _ in
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.6)) { pressed = false }
                    action()
                }
        )
        .accessibilityLabel("快门")
        .accessibilityAddTraits(.isButton)
    }
}

/// 色彩风格卡片（对应 OPPO 的「Original」滤镜卡）
struct StyleTile: View {
    let film: FilmMode
    let size: CGFloat
    var selected = false

    static func label(_ film: FilmMode) -> String {
        switch film {
        case .hncs: return "HNCS"
        case .color: return "XPan"
        case .natural: return "Original"
        case .mono: return "Mono"
        }
    }

    static func swatch(_ film: FilmMode) -> [Color] {
        switch film {
        case .hncs: return [Color(red: 0.95, green: 0.62, blue: 0.30), Color(red: 0.55, green: 0.32, blue: 0.22), Color(red: 0.20, green: 0.33, blue: 0.48)]
        case .color: return [Color(red: 0.98, green: 0.70, blue: 0.35), Color(red: 0.70, green: 0.35, blue: 0.20), Color(red: 0.25, green: 0.18, blue: 0.15)]
        case .natural: return [Color(red: 0.95, green: 0.55, blue: 0.20), Color(red: 0.10, green: 0.10, blue: 0.12), Color(red: 0.15, green: 0.45, blue: 0.85)]
        case .mono: return [Color(white: 0.92), Color(white: 0.35), Color(white: 0.08)]
        }
    }

    var body: some View {
        ZStack {
            LinearGradient(colors: Self.swatch(film), startPoint: .top, endPoint: .bottom)
            Text(Self.label(film))
                .font(.system(size: size * 0.22, weight: .bold))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.7), radius: 2)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .padding(.horizontal, 4)
        }
        // 和 OPPO 的滤镜卡一样是横向的小卡片
        .frame(width: size - 8, height: size * 0.72 - 8)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .padding(4)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color(white: 0.06)))
        .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous)
            .stroke(selected ? BodyPalette.orange : Color.white.opacity(0.15), lineWidth: selected ? 1.5 : 1))
        .shadow(color: .black.opacity(0.5), radius: 3, y: 2)
    }
}

/// 色彩风格选择条（从风格卡片向左展开）
struct StylePickerStrip: View {
    let selected: FilmMode
    let tileSize: CGFloat
    let onSelect: (FilmMode) -> Void

    var body: some View {
        HStack(spacing: 10) {
            ForEach(FilmMode.allCases) { film in
                Button { onSelect(film) } label: {
                    StyleTile(film: film, size: tileSize, selected: film == selected)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(10)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 18))
    }
}

/// 缩略图卡片
struct ThumbnailTile: View {
    let image: UIImage?
    let size: CGFloat

    var body: some View {
        ZStack {
            Color(white: 0.12)
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            }
        }
        .frame(width: size - 8, height: size - 8)
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        .padding(4)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color(white: 0.06)))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Color.white.opacity(0.15), lineWidth: 1))
        .shadow(color: .black.opacity(0.5), radius: 3, y: 2)
    }
}
