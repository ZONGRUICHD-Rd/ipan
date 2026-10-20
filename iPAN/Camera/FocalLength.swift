import AVFoundation
import CoreGraphics

/// 物理镜头。iPAN 的每个焦段都由其中一颗镜头的全像素（48MP）画面裁切得到。
enum PhysicalLens: String, CaseIterable {
    case main
    case telephoto

    var deviceType: AVCaptureDevice.DeviceType {
        switch self {
        case .main: return .builtInWideAngleCamera
        case .telephoto: return .builtInTelephotoCamera
        }
    }
}

/// iPAN 焦段（35mm 等效，按 4:3 全幅计算，与系统相机的标注一致）。
struct FocalLength: Hashable, Identifiable {
    let millimeters: Int
    var id: Int { millimeters }

    static let all: [FocalLength] = [24, 28, 35, 48, 100, 200].map(FocalLength.init(millimeters:))
    static let `default` = FocalLength(millimeters: 35)

    var label: String { "\(millimeters)" }
}

/// 65:24 —— 哈苏 XPan 的 24×65mm 画幅。
enum PanoramaFormat {
    static let long: CGFloat = 65
    static let short: CGFloat = 24
    static var ratio: CGFloat { long / short }
}

/// 某个焦段在当前机型上的实现方式：用哪颗镜头、在它的画面上裁多少。
struct FocalPlan: Equatable {
    let focal: FocalLength
    let lens: PhysicalLens
    /// 镜头原生等效焦距
    let nativeFocal: CGFloat
    /// 裁切比例（0, 1]：保留传感器边长的比例，1 表示整幅宽度。
    var cropScale: CGFloat { min(1, nativeFocal / CGFloat(focal.millimeters)) }
}

/// 根据机型实际可用的镜头，把 24/28/35/48/100/200 映射到镜头 + 裁切比例。
struct LensLineup {
    /// 每颗可用镜头的原生等效焦距
    let natives: [PhysicalLens: CGFloat]

    static func discover() -> LensLineup {
        var natives: [PhysicalLens: CGFloat] = [:]
        let main = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
        if main != nil { natives[.main] = 24 }
        if let tele = AVCaptureDevice.default(.builtInTelephotoCamera, for: .video, position: .back) {
            if let main {
                // 用视场角之比推算长焦的等效焦距（iPhone 18 Pro 约 100mm，老机型可能是 77/120mm）
                let mainHalf = tan(Double(main.activeFormat.videoFieldOfView) * .pi / 360)
                let teleHalf = tan(Double(tele.activeFormat.videoFieldOfView) * .pi / 360)
                let eq = teleHalf > 0 ? 24 * mainHalf / teleHalf : 100
                natives[.telephoto] = CGFloat((eq / 5).rounded() * 5)
            } else {
                natives[.telephoto] = 100
            }
        }
        if natives.isEmpty { natives[.main] = 24 } // 模拟器 / 无相机时的兜底
        return LensLineup(natives: natives)
    }

    /// 选原生焦距不超过目标焦段的最长镜头，这样裁切损失最小。
    func plan(for focal: FocalLength) -> FocalPlan {
        let target = CGFloat(focal.millimeters)
        let candidates = natives.filter { $0.value <= target + 0.5 }
        if let best = candidates.max(by: { $0.value < $1.value }) {
            return FocalPlan(focal: focal, lens: best.key, nativeFocal: best.value)
        }
        let widest = natives.min(by: { $0.value < $1.value })!
        return FocalPlan(focal: focal, lens: widest.key, nativeFocal: widest.value)
    }
}
