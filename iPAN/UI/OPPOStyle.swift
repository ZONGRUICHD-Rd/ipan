import SwiftUI

/// 仿 OPPO ColorOS 相机的视觉规范（快门、焦段圆钮、模式轮播等）
enum OPPOStyle {
    /// ColorOS 相机选中态的暖黄色
    static let accent = Color(red: 1.0, green: 0.80, blue: 0.24)
    static let chipFill = Color.black.opacity(0.42)
    static let secondaryText = Color.white.opacity(0.62)
    static let font = Font.system(size: 13, weight: .semibold, design: .rounded)
}

// MARK: - 快门（白色外环 + 实心内圆，按下内圆收缩）

struct OPPOShutterButton: View {
    var isBusy: Bool
    var isEnabled: Bool
    var action: () -> Void

    @State private var pressed = false
    @State private var spin = false

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(isEnabled ? 1 : 0.4), lineWidth: 4)
                .frame(width: 78, height: 78)
            if isBusy {
                Circle()
                    .trim(from: 0, to: 0.22)
                    .stroke(OPPOStyle.accent, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .frame(width: 78, height: 78)
                    .rotationEffect(.degrees(spin ? 360 : 0))
                    .onAppear {
                        withAnimation(.linear(duration: 0.9).repeatForever(autoreverses: false)) { spin = true }
                    }
                    .onDisappear { spin = false }
            }
            Circle()
                .fill(Color.white.opacity(isEnabled ? 1 : 0.4))
                .frame(width: 64, height: 64)
                .scaleEffect(pressed ? 0.86 : 1)
        }
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

// MARK: - 焦段选择（OPPO 的半透明小圆钮，选中项放大并显示单位；横屏时竖排在快门一侧）

struct OPPOFocalSelector: View {
    let focals: [FocalLength]
    let selected: FocalLength?
    var axis: Axis = .horizontal
    let onSelect: (FocalLength) -> Void

    var body: some View {
        let layout = axis == .horizontal ? AnyLayout(HStackLayout(spacing: 10)) : AnyLayout(VStackLayout(spacing: 8))
        layout {
            ForEach(focals) { focal in
                let isSelected = focal == selected
                Button {
                    onSelect(focal)
                } label: {
                    Text(isSelected ? "\(focal.millimeters)mm" : focal.label)
                        .font(.system(size: isSelected ? 12 : 11, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(isSelected ? OPPOStyle.accent : .white.opacity(0.9))
                        .minimumScaleFactor(0.6)
                        .lineLimit(1)
                        .frame(width: isSelected ? 46 : 34, height: isSelected ? 46 : 34)
                        .background(Circle().fill(OPPOStyle.chipFill))
                        .overlay(Circle().stroke(Color.white.opacity(isSelected ? 0.0 : 0.08), lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, axis == .horizontal ? 10 : 5)
        .padding(.vertical, axis == .horizontal ? 6 : 10)
        .background(Capsule().fill(Color.black.opacity(0.18)))
        .animation(.spring(response: 0.3, dampingFraction: 0.75), value: selected)
    }
}

// MARK: - 模式轮播（ColorOS：选中项居中变白加粗并带小圆点；横屏时竖排滚动）

struct OPPOModeCarousel: View {
    let modes: [CaptureMode]
    let selected: CaptureMode
    var axis: Axis = .horizontal
    let onSelect: (CaptureMode) -> Void

    @GestureState private var drag: CGFloat = 0

    private var itemLength: CGFloat { axis == .horizontal ? 112 : 46 }

    var body: some View {
        let index = CGFloat(modes.firstIndex(of: selected) ?? 0)
        let base = (CGFloat(modes.count - 1) / 2 - index) * itemLength
        let layout = axis == .horizontal ? AnyLayout(HStackLayout(spacing: 0)) : AnyLayout(VStackLayout(spacing: 0))
        layout {
            ForEach(modes) { mode in
                item(mode, isSelected: mode == selected)
                    .frame(width: axis == .horizontal ? itemLength : nil, height: axis == .vertical ? itemLength : nil)
                    .contentShape(Rectangle())
                    .onTapGesture { onSelect(mode) }
            }
        }
        .offset(x: axis == .horizontal ? base + drag : 0, y: axis == .vertical ? base + drag : 0)
        .frame(maxWidth: axis == .horizontal ? .infinity : nil, maxHeight: axis == .vertical ? .infinity : nil)
        .clipped()
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 12)
                .updating($drag) { value, state, _ in
                    state = (axis == .horizontal ? value.translation.width : value.translation.height) * 0.6
                }
                .onEnded { value in
                    let t = axis == .horizontal ? value.translation.width : value.translation.height
                    let current = modes.firstIndex(of: selected) ?? 0
                    if t < -30, current + 1 < modes.count { onSelect(modes[current + 1]) }
                    if t > 30, current > 0 { onSelect(modes[current - 1]) }
                }
        )
        .animation(.spring(response: 0.35, dampingFraction: 0.82), value: selected)
        .animation(.interactiveSpring, value: drag)
    }

    @ViewBuilder
    private func item(_ mode: CaptureMode, isSelected: Bool) -> some View {
        let label = Text(axis == .vertical ? mode.shortTitle : mode.title)
            .font(.system(size: 14, weight: isSelected ? .bold : .medium))
            .foregroundStyle(isSelected ? .white : OPPOStyle.secondaryText)
            .lineLimit(1)
            .fixedSize()
        let dot = Circle().fill(isSelected ? OPPOStyle.accent : .clear).frame(width: 4, height: 4)
        if axis == .horizontal {
            VStack(spacing: 5) { label; dot }
        } else {
            HStack(spacing: 5) { dot; label }
        }
    }
}

// MARK: - 圆形功能钮（缩略图旁的胶片切换等）

struct OPPOCircleButton<Label: View>: View {
    var size: CGFloat = 48
    var action: () -> Void
    @ViewBuilder var label: () -> Label

    var body: some View {
        Button(action: action) {
            label()
                .frame(width: size, height: size)
                .background(Circle().fill(Color.white.opacity(0.12)))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 对焦框

struct OPPOFocusIndicator: View {
    @State private var appear = false

    var body: some View {
        RoundedRectangle(cornerRadius: 4)
            .stroke(OPPOStyle.accent, lineWidth: 1.5)
            .frame(width: 64, height: 64)
            .overlay(
                Circle().fill(OPPOStyle.accent).frame(width: 4, height: 4)
            )
            .scaleEffect(appear ? 1 : 1.35)
            .opacity(appear ? 1 : 0)
            .onAppear { withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { appear = true } }
    }
}
