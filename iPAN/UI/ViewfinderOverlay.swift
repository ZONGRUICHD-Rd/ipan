import SwiftUI

/// 65:24 取景窗口：窗口外压暗（仿 OPPO XPAN），窗口四角是胶片取景器式的角标，窗口上方显示画幅信息。
struct PanoramaMask: View {
    /// 取景窗口（全屏归一化坐标，原点左上）
    let band: CGRect
    let caption: String
    /// 拼接模式：主摄覆盖范围（相对取景窗口）
    var mainCoverage: CGSize? = nil

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let rect = CGRect(x: band.minX * size.width, y: band.minY * size.height,
                              width: band.width * size.width, height: band.height * size.height)
            ZStack(alignment: .topLeading) {
                Path { p in
                    p.addRect(CGRect(origin: .zero, size: size))
                    p.addRect(rect)
                }
                .fill(Color.black.opacity(0.78), style: FillStyle(eoFill: true))

                CornerMarks(rect: rect)
                    .stroke(Color.white.opacity(0.9), style: StrokeStyle(lineWidth: 2, lineCap: .round))

                if let mainCoverage {
                    let w = rect.width * mainCoverage.width, h = rect.height * mainCoverage.height
                    RoundedRectangle(cornerRadius: 3)
                        .stroke(OPPOStyle.accent.opacity(0.85), style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
                        .frame(width: w, height: h)
                        .position(x: rect.midX, y: rect.midY)
                    Text("主摄")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(OPPOStyle.accent)
                        .position(x: rect.midX, y: rect.midY - h / 2 + 10)
                }

                // 窗口上方：左边是拍摄信息，右边是品牌标
                HStack(alignment: .firstTextBaseline) {
                    Text(caption)
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .kerning(0.4)
                        .foregroundStyle(.white.opacity(0.85))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Spacer(minLength: 8)
                    Text("iPAN")
                        .font(.system(size: 12, weight: .heavy, design: .rounded))
                        .kerning(1.2)
                        .foregroundStyle(OPPOStyle.accent)
                }
                .frame(width: max(0, rect.width - 4))
                .offset(x: rect.minX + 2, y: max(0, rect.minY - 20))
            }
            .animation(.spring(response: 0.45, dampingFraction: 0.85), value: band)
        }
        .allowsHitTesting(false)
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
    let band: CGRect
    let namespace: Namespace.ID

    var body: some View {
        GeometryReader { proxy in
            let w = proxy.size.width * band.width, h = proxy.size.height * band.height
            let center = CGPoint(x: proxy.size.width * band.midX, y: proxy.size.height * band.midY)
            ZStack {
                if phase == .curtain {
                    Rectangle().fill(Color.black)
                        .frame(width: w, height: h)
                        .position(center)
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
                        .position(center)
                        .transition(.identity)
                }
            }
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
