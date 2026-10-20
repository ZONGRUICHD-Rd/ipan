import SwiftUI

/// 光圈面板（液态玻璃）：自动 + 推荐档位。光圈优先，快门与 ISO 自动。
struct AperturePanel: View {
    let support: VariableAperture.Support
    let locked: Float?
    let live: Float
    var onSelect: (Float?) -> Void
    var onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("光圈")
                    .font(.system(size: 15, weight: .semibold))
                Text("当前 ƒ\(VariableAperture.label(live))")
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark").font(.system(size: 13, weight: .bold))
                }
                .buttonStyle(.glass)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    chip("自动", selected: locked == nil) { onSelect(nil) }
                    ForEach(support.stops, id: \.self) { stop in
                        chip("ƒ\(VariableAperture.label(stop))", selected: locked.map { abs($0 - stop) < 0.05 } ?? false) {
                            onSelect(stop)
                        }
                    }
                }
            }

            Text("光圈优先：锁定光圈后快门与 ISO 仍自动调整。光圈越小（f 值越大）景深越深、画面越锐利，进光越少。")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 26))
        .foregroundStyle(.white)
    }

    private func chip(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 14, weight: selected ? .bold : .medium, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(selected ? Color.black : Color.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Capsule().fill(selected ? OPPOStyle.accent : Color.white.opacity(0.1)))
        }
        .buttonStyle(.plain)
    }
}
