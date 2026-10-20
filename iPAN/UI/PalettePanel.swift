import SwiftUI

/// 调色盘（液态玻璃面板）：底色风格 + 色调/色彩二维盘 + 调色板强度，交互仿 iOS「摄影风格」。
struct PalettePanel: View {
    @ObservedObject var settings: AppSettings
    /// 横屏时高度有限，缩小二维盘并省略说明文字
    var compact: Bool = false
    var onChange: () -> Void
    var onClose: () -> Void

    var body: some View {
        VStack(spacing: compact ? 10 : 14) {
            HStack {
                Text("调色盘")
                    .font(.system(size: 15, weight: .semibold))
                Spacer()
                Button("重置") {
                    settings.resetPalette()
                    onChange()
                }
                .font(.system(size: 13, weight: .medium))
                .buttonStyle(.glass)
                Button {
                    onClose()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .bold))
                }
                .buttonStyle(.glass)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(PaletteStyle.allCases) { style in
                        let selected = settings.paletteStyle == style
                        Button {
                            settings.paletteStyle = style
                            onChange()
                            UISelectionFeedbackGenerator().selectionChanged()
                        } label: {
                            Text(style.title)
                                .font(.system(size: 13, weight: selected ? .semibold : .regular))
                                .foregroundStyle(selected ? Color.black : Color.white)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 7)
                                .background(Capsule().fill(selected ? Color.white : Color.white.opacity(0.08)))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            HStack(alignment: .center, spacing: 18) {
                TonePad(tone: $settings.paletteTone, color: $settings.paletteColor, style: settings.paletteStyle, onChange: onChange)
                    .frame(width: compact ? 136 : 168, height: compact ? 136 : 168)
                VStack(alignment: .leading, spacing: 10) {
                    valueRow("色调", settings.paletteTone)
                    valueRow("色彩", settings.paletteColor)
                    Divider().overlay(Color.white.opacity(0.2))
                    Text("调色板")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                    Slider(value: $settings.paletteAmount, in: 0...1) { _ in onChange() }
                        .tint(.white)
                        .disabled(settings.paletteStyle == .standard)
                        .onChange(of: settings.paletteAmount) { onChange() }
                    if !compact {
                        Text("苹果没有开放系统摄影风格的接口，这里是 iPAN 内置的同款调色盘，预览与成片一致。")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .padding(16)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 28))
        .foregroundStyle(.white)
    }

    private func valueRow(_ title: String, _ value: Double) -> some View {
        HStack {
            Text(title).font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
            Spacer()
            Text(String(format: "%+.0f", value * 100))
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .monospacedDigit()
        }
    }
}

/// 二维盘：横轴色彩，纵轴色调。点阵按当前位置着色，拖动圆点调整。
struct TonePad: View {
    @Binding var tone: Double
    @Binding var color: Double
    let style: PaletteStyle
    var onChange: () -> Void

    private let steps = 9

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            ZStack {
                RoundedRectangle(cornerRadius: 18)
                    .fill(Color.black.opacity(0.25))
                Canvas { ctx, canvasSize in
                    for ix in 0..<steps {
                        for iy in 0..<steps {
                            let x = (CGFloat(ix) + 0.5) / CGFloat(steps) * canvasSize.width
                            let y = (CGFloat(iy) + 0.5) / CGFloat(steps) * canvasSize.height
                            let sat = Double(ix) / Double(steps - 1)
                            let bri = 1 - Double(iy) / Double(steps - 1)
                            let hue = style.dotHue
                            let rect = CGRect(x: x - 2.5, y: y - 2.5, width: 5, height: 5)
                            ctx.fill(Path(ellipseIn: rect),
                                     with: .color(Color(hue: hue, saturation: 0.15 + sat * 0.75, brightness: 0.35 + bri * 0.6)))
                        }
                    }
                }
                .padding(8)
                Path { p in
                    p.move(to: CGPoint(x: size.width / 2, y: 10))
                    p.addLine(to: CGPoint(x: size.width / 2, y: size.height - 10))
                    p.move(to: CGPoint(x: 10, y: size.height / 2))
                    p.addLine(to: CGPoint(x: size.width - 10, y: size.height / 2))
                }
                .stroke(Color.white.opacity(0.12), lineWidth: 1)

                Circle()
                    .fill(Color.white)
                    .frame(width: 22, height: 22)
                    .shadow(color: .black.opacity(0.4), radius: 4)
                    .position(x: (color + 1) / 2 * size.width, y: (1 - (tone + 1) / 2) * size.height)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        color = clamp(Double(value.location.x / size.width) * 2 - 1)
                        tone = clamp(1 - Double(value.location.y / size.height) * 2)
                        onChange()
                    }
            )
            .onTapGesture(count: 2) {
                color = 0
                tone = 0
                onChange()
            }
        }
        .overlay(alignment: .top) {
            Text("色调").font(.system(size: 9, weight: .medium)).foregroundStyle(.secondary).offset(y: -14)
        }
        .overlay(alignment: .trailing) {
            Text("色彩").font(.system(size: 9, weight: .medium)).foregroundStyle(.secondary).offset(x: 24)
        }
    }

    private func clamp(_ v: Double) -> Double { min(1, max(-1, v)) }
}

private extension PaletteStyle {
    var dotHue: Double {
        let w = params.warmth, t = params.tint
        if abs(w) < 0.05 && abs(t) < 0.05 { return 0.08 }
        if w > 0 { return t > 0.3 ? 0.97 : 0.09 }
        return t > 0.2 ? 0.9 : 0.58
    }
}
