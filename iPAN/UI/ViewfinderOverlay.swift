import SwiftUI

/// 65:24 取景窗口：窗口外压暗，窗口四角是胶片取景器式的角标，窗口内左上角显示画幅信息。
struct PanoramaMask: View {
    /// 窗口占取景器的比例
    let window: CGSize
    let caption: String
    let iconRotation: Angle
    var mainCoverage: CGFloat? = nil

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let rect = CGRect(x: (size.width - size.width * window.width) / 2,
                              y: (size.height - size.height * window.height) / 2,
                              width: size.width * window.width,
                              height: size.height * window.height)
            ZStack {
                // 窗口外的遮罩（even-odd 填充挖洞）
                Path { p in
                    p.addRect(CGRect(origin: .zero, size: size))
                    p.addRect(rect)
                }
                .fill(Color.black.opacity(0.72), style: FillStyle(eoFill: true))

                CornerMarks(rect: rect)
                    .stroke(Color.white.opacity(0.9), style: StrokeStyle(lineWidth: 2, lineCap: .round))

                if let mainCoverage {
                    let w = size.width * mainCoverage, h = size.height * mainCoverage
                    RoundedRectangle(cornerRadius: 3)
                        .stroke(OPPOStyle.accent.opacity(0.85), style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
                        .frame(width: w, height: h)
                        .position(x: size.width / 2, y: size.height / 2)
                    Text("主摄")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(OPPOStyle.accent)
                        .rotationEffect(iconRotation)
                        .position(x: size.width / 2, y: (size.height - h) / 2 + 12)
                }

                Text(caption)
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.9))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Color.black.opacity(0.35)))
                    .fixedSize()
                    .rotationEffect(iconRotation)
                    .position(captionPosition(in: rect))
            }
            .animation(.spring(response: 0.45, dampingFraction: 0.85), value: window)
        }
        .allowsHitTesting(false)
    }

    /// 标签放在窗口「视觉上的左上角」（随手机方向变化）
    private func captionPosition(in rect: CGRect) -> CGPoint {
        let degrees = Int(iconRotation.degrees.rounded()) % 360
        let normalized = (degrees + 360) % 360
        switch normalized {
        case 90: return CGPoint(x: rect.maxX - 14, y: rect.minY + 52) // 右转横持：窗口右上
        case 270: return CGPoint(x: rect.minX + 14, y: rect.maxY - 52)
        default: return CGPoint(x: rect.minX + 58, y: rect.minY + 14)
        }
    }
}

private struct CornerMarks: Shape {
    var rect: CGRect

    var animatableData: AnimatablePair<AnimatablePair<CGFloat, CGFloat>, AnimatablePair<CGFloat, CGFloat>> {
        get { AnimatablePair(AnimatablePair(rect.origin.x, rect.origin.y), AnimatablePair(rect.size.width, rect.size.height)) }
        set { rect = CGRect(x: newValue.first.first, y: newValue.first.second, width: newValue.second.first, height: newValue.second.second) }
    }

    func path(in _: CGRect) -> Path {
        let l = min(18, min(rect.width, rect.height) / 4)
        var p = Path()
        let corners: [(CGPoint, CGFloat, CGFloat)] = [
            (CGPoint(x: rect.minX, y: rect.minY), 1, 1),
            (CGPoint(x: rect.maxX, y: rect.minY), -1, 1),
            (CGPoint(x: rect.minX, y: rect.maxY), 1, -1),
            (CGPoint(x: rect.maxX, y: rect.maxY), -1, -1),
        ]
        for (c, dx, dy) in corners {
            p.move(to: CGPoint(x: c.x + dx * l, y: c.y))
            p.addLine(to: c)
            p.addLine(to: CGPoint(x: c.x, y: c.y + dy * l))
        }
        return p
    }
}

/// 快门后的显影层：快门帘（黑）→ 负片 → 显影成正片（Metal 着色器）
struct DevelopOverlay: View {
    let phase: CameraModel.DevelopPhase
    let image: UIImage?
    let progress: Double
    let window: CGSize
    let namespace: Namespace.ID

    var body: some View {
        GeometryReader { proxy in
            let w = proxy.size.width * window.width, h = proxy.size.height * window.height
            ZStack {
                if phase == .curtain {
                    Rectangle().fill(Color.black)
                        .frame(width: w, height: h)
                        .transition(.opacity)
                }
                if phase == .developing, let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: w, height: h)
                        .modifier(FilmDevelopEffect(progress: progress))
                        .clipShape(Rectangle())
                        .matchedGeometryEffect(id: "shot", in: namespace)
                        .transition(.identity)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .allowsHitTesting(false)
    }
}

/// 把 progress 做成可动画参数，驱动 filmDevelop 着色器
struct FilmDevelopEffect: ViewModifier, Animatable {
    var progress: Double
    var seed: Float = Float.random(in: 0...100)

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    func body(content: Content) -> some View {
        let p = Float(progress)
        let s = seed
        return content.visualEffect { view, proxy in
            view.colorEffect(ShaderLibrary.filmDevelop(.float2(proxy.size), .float(p), .float(s)))
        }
    }
}

/// 拼接模式竖持时的提示
struct RotateHint: View {
    @State private var rotate = false

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "iphone")
                .font(.system(size: 44, weight: .light))
                .rotationEffect(.degrees(rotate ? -90 : 0))
                .animation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true), value: rotate)
            Text("请横置手机使用双镜头拼接")
                .font(.system(size: 14, weight: .semibold))
        }
        .foregroundStyle(.white)
        .padding(22)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 22))
        .onAppear { rotate = true }
    }
}
