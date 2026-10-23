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
    var bottomSeamY: CGFloat { 363 * sy }
    /// 中间梯形缺口：中心、外沿宽度、内沿宽度、深度（量自截图）
    var notchCenterX: CGFloat { 335 * sx }
    var notchOuterWidth: CGFloat { 236 * sx }
    var notchInnerWidth: CGFloat { 156 * sx }
    var notchDepth: CGFloat { 23 * sy }

    var plate: CGRect {
        CGRect(x: notchCenterX - 86 * sx, y: 23 * sy, width: 173 * sx, height: 21 * sy)
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

/// 颜色取自参考截图的像素
private enum BodyPalette {
    /// 机身上半部 #222126 → 下半部 #18171B
    static let top = Color(red: 0.133, green: 0.129, blue: 0.149)
    static let bottom = Color(red: 0.094, green: 0.090, blue: 0.106)
    /// 两侧握把区域
    static let grip = Color(red: 0.118, green: 0.114, blue: 0.133)
    static let seamDark = Color(red: 0.07, green: 0.067, blue: 0.086)
    static let seamLight = Color(red: 0.216, green: 0.212, blue: 0.231)
    /// 取景窗边框环 #1F1E23
    static let ring = Color(red: 0.122, green: 0.118, blue: 0.137)
    static let orange = Color(red: 0.863, green: 0.604, blue: 0.365)
    static let buttonFill = Color(red: 0.145, green: 0.141, blue: 0.161)
    static let buttonRim = Color(red: 0.075, green: 0.071, blue: 0.090)
}

/// 机身背景：整块深灰（取景窗处挖空露出预览）+ 两侧握把 + 接缝 + 铭牌 + 取景窗边框
struct XPanBodyBackground: View {
    let layout: XPanBodyLayout
    /// 取景窗（= 65:24 画幅）在全屏中的位置
    let window: CGRect

    var body: some View {
        let size = layout.size
        let hole = window
        let ring: CGFloat = 5.5
        let bezel = hole.insetBy(dx: -ring, dy: -ring)
        let holeRadius: CGFloat = 11
        let bezelRadius = holeRadius + ring
        ZStack(alignment: .topLeading) {
            // 机身（挖空取景窗）：上亮下暗
            Path { p in
                p.addRect(CGRect(origin: .zero, size: size))
                p.addRoundedRect(in: hole, cornerSize: CGSize(width: holeRadius, height: holeRadius), style: .continuous)
            }
            .fill(LinearGradient(colors: [BodyPalette.top, BodyPalette.top, BodyPalette.bottom],
                                 startPoint: .top, endPoint: .bottom),
                  style: FillStyle(eoFill: true))

            // 两侧握把：略亮的竖条，内侧边缘柔和过渡
            HStack(spacing: 0) {
                LinearGradient(colors: [BodyPalette.grip.opacity(0.9), BodyPalette.top.opacity(0.95), BodyPalette.top.opacity(0)],
                               startPoint: .leading, endPoint: .trailing)
                    .frame(width: 46)
                Spacer(minLength: 0)
                LinearGradient(colors: [BodyPalette.top.opacity(0), BodyPalette.top.opacity(0.95), BodyPalette.grip.opacity(0.9)],
                               startPoint: .leading, endPoint: .trailing)
                    .frame(width: 46)
            }
            .frame(width: size.width, height: size.height)
            .mask(
                Path { p in
                    p.addRect(CGRect(origin: .zero, size: size))
                    p.addRoundedRect(in: bezel, cornerSize: CGSize(width: bezelRadius, height: bezelRadius), style: .continuous)
                }
                .fill(style: FillStyle(eoFill: true))
            )

            // 上下接缝：一条暗线 + 紧贴下方的一条亮线，梯形转角是圆滑的
            ForEach([(layout.topSeamY, true), (layout.bottomSeamY, false)], id: \.0) { seam in
                Seam(layout: layout, y: seam.0, notchDown: seam.1)
                    .stroke(BodyPalette.seamDark, style: StrokeStyle(lineWidth: 1.4, lineJoin: .round))
                Seam(layout: layout, y: seam.0 + 1.3, notchDown: seam.1)
                    .stroke(BodyPalette.seamLight, style: StrokeStyle(lineWidth: 0.9, lineJoin: .round))
            }

            // 取景窗边框：外沿一圈细高光 + 暗线，中间与机身同色的环，内沿黑边
            Path { p in
                p.addRoundedRect(in: bezel, cornerSize: CGSize(width: bezelRadius, height: bezelRadius), style: .continuous)
                p.addRoundedRect(in: hole, cornerSize: CGSize(width: holeRadius, height: holeRadius), style: .continuous)
            }
            .fill(BodyPalette.ring, style: FillStyle(eoFill: true))
            RoundedRectangle(cornerRadius: bezelRadius + 1, style: .continuous)
                .stroke(Color.white.opacity(0.16), lineWidth: 0.8)
                .frame(width: bezel.width + 2, height: bezel.height + 2)
                .offset(x: bezel.minX - 1, y: bezel.minY - 1)
            RoundedRectangle(cornerRadius: bezelRadius, style: .continuous)
                .stroke(Color.black.opacity(0.7), lineWidth: 1)
                .frame(width: bezel.width, height: bezel.height)
                .offset(x: bezel.minX, y: bezel.minY)
            // 内沿黑边 + 向画面里渐隐的内阴影
            RoundedRectangle(cornerRadius: holeRadius, style: .continuous)
                .stroke(Color.black, lineWidth: 2.5)
                .frame(width: hole.width, height: hole.height)
                .offset(x: hole.minX, y: hole.minY)
            RoundedRectangle(cornerRadius: holeRadius, style: .continuous)
                .stroke(Color.black.opacity(0.75), lineWidth: 10)
                .blur(radius: 6)
                .frame(width: hole.width, height: hole.height)
                .clipShape(RoundedRectangle(cornerRadius: holeRadius, style: .continuous))
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

/// 一道横贯机身的接缝，中间有梯形缺口（顶部向下凹，底部向上凸），转角用二次曲线做圆滑
private struct Seam: Shape {
    let layout: XPanBodyLayout
    let y: CGFloat
    let notchDown: Bool

    func path(in rect: CGRect) -> Path {
        let cx = layout.notchCenterX
        let outer = layout.notchOuterWidth / 2, inner = layout.notchInnerWidth / 2
        let depth = notchDown ? layout.notchDepth : -layout.notchDepth
        let r: CGFloat = 9
        // 斜边方向
        let dx = outer - inner, len = (dx * dx + depth * depth).squareRoot()
        let ux = dx / len, uy = depth / len
        var p = Path()
        p.move(to: CGPoint(x: 0, y: y))
        // 左上转角
        p.addLine(to: CGPoint(x: cx - outer - r, y: y))
        p.addQuadCurve(to: CGPoint(x: cx - outer + ux * r, y: y + uy * r), control: CGPoint(x: cx - outer, y: y))
        // 左下转角
        p.addLine(to: CGPoint(x: cx - inner - ux * r, y: y + depth - uy * r))
        p.addQuadCurve(to: CGPoint(x: cx - inner + r, y: y + depth), control: CGPoint(x: cx - inner, y: y + depth))
        // 右下转角
        p.addLine(to: CGPoint(x: cx + inner - r, y: y + depth))
        p.addQuadCurve(to: CGPoint(x: cx + inner + ux * r, y: y + depth - uy * r), control: CGPoint(x: cx + inner, y: y + depth))
        // 右上转角
        p.addLine(to: CGPoint(x: cx + outer - ux * r, y: y + uy * r))
        p.addQuadCurve(to: CGPoint(x: cx + outer + r, y: y), control: CGPoint(x: cx + outer, y: y))
        p.addLine(to: CGPoint(x: layout.size.width, y: y))
        return p
    }
}

/// 铭牌：比机身略深的凹槽，宽体斜体字标
private struct NamePlate: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 3, style: .continuous)
            .fill(LinearGradient(colors: [Color(white: 0.055), Color(white: 0.085)], startPoint: .top, endPoint: .bottom))
            .overlay(RoundedRectangle(cornerRadius: 3, style: .continuous).stroke(Color.black.opacity(0.8), lineWidth: 1))
            .overlay(RoundedRectangle(cornerRadius: 3, style: .continuous).stroke(Color.white.opacity(0.07), lineWidth: 0.6).padding(-1))
            .overlay(
                Text("HASSELBLAD")
                    // 斜体要放在 Font 上：宽体 + 斜体 + 粗
                    .font(.system(size: 14, weight: .bold).width(.expanded).italic())
                    .kerning(2.8)
                    .foregroundStyle(LinearGradient(colors: [Color(white: 0.78), Color(white: 0.58)], startPoint: .top, endPoint: .bottom))
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .padding(.horizontal, 6)
            )
    }
}

// MARK: - 取景窗内

/// 旁轴取景器式的亮框线（位置量自截图）：左边只有竖线段，右边上下是折角、中间一段竖线，上下边是长短不一的横线段
struct RangefinderFrameLines: View {
    let window: CGRect

    var body: some View {
        let w = window.width, h = window.height
        let ix: CGFloat = 7.5, iy: CGFloat = 6.5
        let left = window.minX + ix, right = window.maxX - ix
        let top = window.minY + iy, bottom = window.maxY - iy
        Path { p in
            func hLine(_ a: CGFloat, _ b: CGFloat, _ y: CGFloat) {
                p.move(to: CGPoint(x: window.minX + w * a, y: y))
                p.addLine(to: CGPoint(x: window.minX + w * b, y: y))
            }
            func vLine(_ x: CGFloat, _ a: CGFloat, _ b: CGFloat) {
                p.move(to: CGPoint(x: x, y: window.minY + h * a))
                p.addLine(to: CGPoint(x: x, y: window.minY + h * b))
            }
            hLine(0.162, 0.267, top)
            hLine(0.431, 0.632, top)
            hLine(0.073, 0.114, bottom)
            hLine(0.280, 0.388, bottom)
            hLine(0.679, 0.756, bottom)
            vLine(left, 0.067, 0.173)
            vLine(left, 0.381, 0.639)
            vLine(left, 0.798, 0.946)
            vLine(right, 0.375, 0.630)
            // 右上 / 右下折角
            p.move(to: CGPoint(x: window.minX + w * 0.957, y: top))
            p.addLine(to: CGPoint(x: right, y: top))
            p.addLine(to: CGPoint(x: right, y: window.minY + h * 0.24))
            p.move(to: CGPoint(x: right, y: window.minY + h * 0.75))
            p.addLine(to: CGPoint(x: right, y: bottom))
            p.addLine(to: CGPoint(x: window.minX + w * 0.948, y: bottom))
        }
        .stroke(Color(white: 0.84), style: StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round))
        .shadow(color: .black.opacity(0.35), radius: 1)
        .allowsHitTesting(false)
    }
}

/// 取景窗左侧的曝光补偿刻度尺：指示器固定在中间，刻度随数值上下移动；
/// 长刻度为整档，中间两个小点为 1/3 档。上下拖动调节，双击归零。
struct EVRuler: View {
    let value: Float
    let range: ClosedRange<Float>
    var onChange: (Float) -> Void

    @State private var dragStart: Float?
    @State private var lastTick: Int = 0

    private let step: Float = 0.1
    /// 每 1EV 的间距（pt）
    private let spacing: CGFloat = 26

    var body: some View {
        GeometryReader { proxy in
            let h = proxy.size.height
            let tickX: CGFloat = 28
            ZStack(alignment: .topLeading) {
                Canvas { ctx, size in
                    let mid = size.height / 2
                    // 正值在上：数值为 v 时，刻度 e 位于 mid - (e - v) * spacing
                    var e = (range.lowerBound * 3).rounded(.down) / 3
                    while e <= range.upperBound + 0.001 {
                        let y = mid - CGFloat(e - value) * spacing
                        if y > -2 && y < size.height + 2 {
                            let major = abs(e - e.rounded()) < 0.01
                            // 越靠近边缘越淡
                            let fade = max(0, 1 - abs(y - mid) / (size.height / 2)) * 0.6 + 0.4
                            let rect = major
                                ? CGRect(x: tickX - 4, y: y - 0.85, width: 8, height: 1.7)
                                : CGRect(x: tickX - 1, y: y - 1, width: 2, height: 2)
                            ctx.fill(Path(rect), with: .color(.white.opacity(0.85 * fade)))
                        }
                        e += 1.0 / 3
                    }
                }
                .frame(width: proxy.size.width, height: h)

                HStack(spacing: 0) {
                    Rectangle().fill(Color.white).frame(width: 16, height: 2)
                    Image(systemName: "arrowtriangle.left.fill")
                        .font(.system(size: 12))
                        .padding(.leading, 9)
                    Text(abs(value) < 0.05 ? "0.0" : String(format: "%+.1f", value))
                        .font(.system(size: 17, weight: .light))
                        .monospacedDigit()
                        .padding(.leading, 9)
                }
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.5), radius: 3)
                .fixedSize()
                .offset(x: tickX - 10, y: h / 2 - 10)
            }
            .frame(width: proxy.size.width, height: h, alignment: .topLeading)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 2)
                    .onChanged { g in
                        let start = dragStart ?? value
                        if dragStart == nil { dragStart = start }
                        // 向上拖 = 增加曝光
                        var v = start + Float(-g.translation.height / spacing)
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

/// 取景窗右侧的变焦圆钮（OPPO 显示倍率：1× = 24mm）。选中项深色底 + 橙色字
struct XPanZoomChips: View {
    let focals: [FocalLength]
    let selected: FocalLength
    let onSelect: (FocalLength) -> Void

    static func label(_ focal: FocalLength) -> String {
        let x = Double(focal.millimeters) / 24
        if x >= 3 { return String(Int(x.rounded(.down))) }   // 100mm = 4×、200mm = 8×
        let rounded = (x * 10).rounded() / 10
        return rounded == rounded.rounded() ? String(Int(rounded)) : String(format: "%.1f", rounded)
    }

    var body: some View {
        VStack(spacing: 3) {
            // 长焦在上，和 OPPO 一致
            ForEach(Array(focals.reversed())) { focal in
                let isSelected = focal == selected
                Button {
                    onSelect(focal)
                } label: {
                    Text(isSelected ? Self.label(focal) + "×" : Self.label(focal))
                        .font(.system(size: 12.5, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(isSelected ? BodyPalette.orange : .white)
                        .frame(width: 30, height: 30)
                        .background(Circle().fill(Color.black.opacity(isSelected ? 0.85 : 0.42)))
                }
                .buttonStyle(.plain)
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.75), value: selected)
    }
}

// MARK: - 机身按键

/// 机身上的圆形按键（设置、工具）：深色圆盘 + 暗色外圈
struct BodyRoundButton: View {
    let systemName: String
    let diameter: CGFloat
    var active = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: diameter * 0.45, weight: .light))
                .foregroundStyle(active ? BodyPalette.orange : .white)
                .frame(width: diameter, height: diameter)
                .background(
                    Circle()
                        .fill(BodyPalette.buttonFill)
                        .overlay(Circle().stroke(BodyPalette.buttonRim, lineWidth: 2))
                        .overlay(Circle().stroke(Color.white.opacity(0.06), lineWidth: 0.8).padding(-1.5))
                )
        }
        .buttonStyle(.plain)
    }
}

/// 竖排的标识面板（参考里是 XPAN 字标）。点按切换拍摄模式（iPAN ⇄ 双摄拼接）
struct XPanBadge: View {
    let mode: CaptureMode
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .bold))
                    .padding(.top, 12)
                logo
                    .fixedSize()
                    .rotationEffect(.degrees(-90))
                    .frame(maxHeight: .infinity)
            }
            .foregroundStyle(BodyPalette.orange)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(Color(red: 0.075, green: 0.071, blue: 0.086)))
            .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous).stroke(Color.white.opacity(0.1), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(mode == .ipan ? "iPAN 模式，点按切换到双摄拼接" : "双摄拼接模式，点按切换到 iPAN")
    }

    /// 仿 XPAN 字标：细长字体，后几个字母下方带一道下划线
    private var logo: some View {
        let first = mode == .ipan ? "i" : "W"
        let rest = mode == .ipan ? "PAN" : "IDE"
        let font = Font.system(size: 27, weight: .light).width(.condensed)
        return HStack(alignment: .lastTextBaseline, spacing: 1) {
            Text(first).font(font)
            VStack(spacing: 2) {
                Text(rest)
                    .font(font)
                    .kerning(1.2)
                Rectangle().frame(height: 1.4)
            }
        }
    }
}

/// 金属快门：浅色金属外环 + 细暗缝 + 内凹的浅灰按钮（上暗下亮）
struct MetalShutterButton: View {
    let diameter: CGFloat
    var isBusy: Bool
    var isEnabled: Bool
    let action: () -> Void

    @State private var pressed = false
    @State private var spin = false

    var body: some View {
        ZStack {
            // 外环
            Circle()
                .fill(LinearGradient(colors: [Color(white: 0.80), Color(white: 0.56), Color(white: 0.72)],
                                     startPoint: .top, endPoint: .bottom))
                .overlay(Circle().stroke(Color.black.opacity(0.6), lineWidth: 1))
            // 暗缝
            Circle()
                .fill(Color(white: 0.30))
                .padding(diameter * 0.075)
            // 按钮（内凹：上暗下亮）
            Circle()
                .fill(LinearGradient(colors: [Color(white: 0.69), Color(white: 0.79), Color(white: 0.88)],
                                     startPoint: .top, endPoint: .bottom))
                .overlay(Circle().stroke(Color.white.opacity(0.75), lineWidth: 1).padding(0.5))
                .padding(diameter * 0.09)
                .scaleEffect(pressed ? 0.94 : 1)
                .brightness(pressed ? -0.08 : 0)
            if isBusy {
                Circle()
                    .trim(from: 0, to: 0.22)
                    .stroke(BodyPalette.orange, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    .padding(diameter * 0.035)
                    .rotationEffect(.degrees(spin ? 360 : 0))
                    .onAppear { withAnimation(.linear(duration: 0.9).repeatForever(autoreverses: false)) { spin = true } }
                    .onDisappear { spin = false }
            }
        }
        .frame(width: diameter, height: diameter)
        .shadow(color: .black.opacity(0.55), radius: 5, y: 2)
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

/// 色彩风格卡片（参考里的「Original」卡）：黑底，上下两道彩色胶片条纹，中间是名称
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

    static func subtitle(_ film: FilmMode) -> String {
        switch film {
        case .hncs: return "Hasselblad Natural"
        case .color: return "Film Curve"
        case .natural: return "Natural tone"
        case .mono: return "Black & White"
        }
    }

    static func stripes(_ film: FilmMode) -> [Color] {
        switch film {
        case .hncs: return [Color(red: 0.95, green: 0.62, blue: 0.30), Color(red: 0.86, green: 0.78, blue: 0.62), Color(red: 0.36, green: 0.52, blue: 0.70)]
        case .color: return [Color(red: 0.98, green: 0.66, blue: 0.30), Color(red: 0.86, green: 0.40, blue: 0.22), Color(red: 0.55, green: 0.30, blue: 0.20)]
        case .natural: return [Color(red: 0.95, green: 0.55, blue: 0.20), Color(red: 0.90, green: 0.80, blue: 0.60), Color(red: 0.25, green: 0.50, blue: 0.85)]
        case .mono: return [Color(white: 0.9), Color(white: 0.55), Color(white: 0.25)]
        }
    }

    var body: some View {
        let stripe = LinearGradient(colors: Self.stripes(film), startPoint: .leading, endPoint: .trailing)
        VStack(spacing: 0) {
            stripe.frame(height: 3).opacity(0.95)
            Spacer(minLength: 0)
            VStack(spacing: 0) {
                Text(Self.label(film))
                    .font(.system(size: size * 0.21, weight: .heavy))
                    .foregroundStyle(.white)
                Text(Self.subtitle(film))
                    .font(.system(size: size * 0.07, weight: .medium))
                    .foregroundStyle(.white.opacity(0.6))
            }
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .padding(.horizontal, 3)
            Spacer(minLength: 0)
            stripe.frame(height: 3).opacity(0.95)
        }
        .frame(width: size - 10, height: size * 0.72 - 10)
        .background(
            RadialGradient(colors: [Color(white: 0.16), Color.black], center: .center, startRadius: 0, endRadius: size * 0.4)
        )
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .padding(5)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color(white: 0.06)))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
            .stroke(selected ? BodyPalette.orange : Color(white: 0.22), lineWidth: selected ? 1.5 : 1))
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

/// 缩略图卡片：厚的深色边框
struct ThumbnailTile: View {
    let image: UIImage?
    let size: CGFloat

    var body: some View {
        ZStack {
            Color(white: 0.1)
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            }
        }
        .frame(width: size - 8, height: size - 8)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .padding(4)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color(white: 0.09)))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Color(white: 0.22), lineWidth: 1))
    }
}
