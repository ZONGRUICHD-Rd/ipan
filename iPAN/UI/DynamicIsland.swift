import SwiftUI

/// 从灵动岛里「长」出来的消息（应用内实现：在灵动岛的位置画一个纯黑胶囊，与真实灵动岛融为一体后展开）。
struct IslandMessage: Equatable, Identifiable {
    enum Kind: Equatable {
        /// 普通提示（焦段、色彩、光圈切换等）
        case info
        /// 冲洗中（拍摄后处理时间较长时）
        case processing
        /// 已保存，可点按查看
        case saved
        /// 出错 / 需要注意
        case warning
    }

    let id = UUID()
    var kind: Kind
    var title: String
    var detail: String?
    var symbol: String?
    var image: UIImage?

    static func == (lhs: IslandMessage, rhs: IslandMessage) -> Bool { lhs.id == rhs.id }

    var duration: Double? {
        switch kind {
        case .info: return 1.6
        case .saved: return 2.8
        case .warning: return 3.2
        case .processing: return nil
        }
    }
}

/// 灵动岛的位置。系统不提供灵动岛的坐标，这里按 iPhone 14 Pro 以来的尺寸估算（126×37pt，距屏幕边缘 11pt）。
struct IslandGeometry: Equatable {
    enum Edge { case leading, trailing, top }

    /// 灵动岛（或没有灵动岛时的替代锚点）在全屏坐标里的位置
    var anchor: CGRect
    var edge: Edge
    /// 设备真的有灵动岛（全屏运行时才判断得出）
    var isHardware: Bool
    var screen: CGSize

    static let length: CGFloat = 126
    static let thickness: CGFloat = 37
    static let gap: CGFloat = 11

    /// 展开后的卡片
    var expandedRect: CGRect {
        switch edge {
        case .leading:
            let size = CGSize(width: min(340, screen.width * 0.5), height: 132)
            return CGRect(x: anchor.minX, y: anchor.midY - size.height / 2, width: size.width, height: size.height)
        case .trailing:
            let size = CGSize(width: min(340, screen.width * 0.5), height: 132)
            return CGRect(x: anchor.maxX - size.width, y: anchor.midY - size.height / 2, width: size.width, height: size.height)
        case .top:
            let size = CGSize(width: min(370, screen.width - 24), height: isHardware ? 108 : 72)
            return CGRect(x: anchor.midX - size.width / 2, y: anchor.minY, width: size.width, height: size.height)
        }
    }

    /// 内容需要避开真实灵动岛（摄像头开孔），按所在边留出空间
    var contentInsets: EdgeInsets {
        let hole = isHardware ? Self.thickness + 12 : 14
        switch edge {
        case .leading: return EdgeInsets(top: 14, leading: hole + 4, bottom: 14, trailing: 18)
        case .trailing: return EdgeInsets(top: 14, leading: 18, bottom: 14, trailing: hole + 4)
        case .top: return EdgeInsets(top: isHardware ? hole : 12, leading: 20, bottom: 12, trailing: 20)
        }
    }

    var expandedRadius: CGFloat { edge == .top && !isHardware ? 36 : 40 }
}

/// 灵动岛互动：
/// - 按快门时灵动岛像快门一样「收缩—回弹」一下
/// - 冲洗较久时展开显示负片缩略图与进度
/// - 保存完成后展开显示成片缩略图、分辨率，点按打开预览
/// - 焦段 / 色彩 / 光圈切换（尤其是用 Camera Control 时）和各种提示都从灵动岛弹出
struct DynamicIslandOverlay: View {
    let geometry: IslandGeometry
    let message: IslandMessage?
    let pulse: Int
    var onTap: () -> Void

    @State private var pulsing = false

    var body: some View {
        let expanded = message != nil
        let rect = currentRect(expanded: expanded)
        let radius = expanded ? geometry.expandedRadius : min(rect.width, rect.height) / 2
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(Color.black)
                .shadow(color: .black.opacity(expanded ? 0.45 : 0), radius: 18, y: 6)
                .frame(width: rect.width, height: rect.height)
                .offset(x: rect.minX, y: rect.minY)
                // 收起时完全隐藏：系统不给灵动岛坐标，估算的位置和真实灵动岛可能差几个点，不画就不会露馅
                .opacity(expanded || pulsing ? 1 : 0)

            if let message {
                content(message)
                    .padding(geometry.contentInsets)
                    .frame(width: rect.width, height: rect.height, alignment: .leading)
                    .offset(x: rect.minX, y: rect.minY)
                    .transition(.asymmetric(insertion: .opacity.animation(.easeOut(duration: 0.2).delay(0.14)),
                                            removal: .opacity.animation(.easeIn(duration: 0.1))))
                    .id(message.id)
            }
        }
        .frame(width: geometry.screen.width, height: geometry.screen.height, alignment: .topLeading)
        .contentShape(Path(roundedRect: rect, cornerRadius: radius))
        .allowsHitTesting(expanded)
        .onTapGesture { if message?.kind == .saved { onTap() } }
        .animation(.spring(response: 0.46, dampingFraction: 0.78), value: message?.id)
        .animation(.spring(response: 0.46, dampingFraction: 0.78), value: geometry)
        .onChange(of: pulse) {
            withAnimation(.spring(response: 0.16, dampingFraction: 0.6)) { pulsing = true }
            Task {
                try? await Task.sleep(for: .milliseconds(220))
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { pulsing = false }
            }
        }
    }

    private func currentRect(expanded: Bool) -> CGRect {
        if expanded { return geometry.expandedRect }
        if pulsing {
            // 快门：沿长边伸长、短边略收，像快门帘闪了一下
            switch geometry.edge {
            case .leading, .trailing: return geometry.anchor.insetBy(dx: 2, dy: -10)
            case .top: return geometry.anchor.insetBy(dx: -10, dy: 2)
            }
        }
        return geometry.anchor
    }

    @ViewBuilder
    private func content(_ message: IslandMessage) -> some View {
        HStack(spacing: 12) {
            if let image = message.image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 112, height: 112 * 24 / 65)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .modifier(FilmDevelopEffect(progress: message.kind == .processing ? 0 : 1))
                    .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).stroke(Color.white.opacity(0.15), lineWidth: 0.5))
            }
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    icon(message)
                    Text(message.title)
                        .font(.system(size: 15, weight: .semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                if let detail = message.detail {
                    Text(detail)
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.6))
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)
                }
            }
            Spacer(minLength: 0)
            if message.kind == .saved {
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white.opacity(0.4))
            }
        }
        .foregroundStyle(.white)
    }

    @ViewBuilder
    private func icon(_ message: IslandMessage) -> some View {
        switch message.kind {
        case .processing:
            ProgressView().controlSize(.mini).tint(OPPOStyle.accent)
        case .saved:
            Image(systemName: message.symbol ?? "checkmark.circle.fill").foregroundStyle(OPPOStyle.accent)
        case .warning:
            Image(systemName: message.symbol ?? "exclamationmark.triangle.fill").foregroundStyle(.yellow)
        case .info:
            if let symbol = message.symbol {
                Image(systemName: symbol).foregroundStyle(OPPOStyle.accent)
            }
        }
    }
}
