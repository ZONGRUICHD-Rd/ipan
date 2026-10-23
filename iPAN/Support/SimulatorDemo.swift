import CoreImage
import CoreImage.CIFilterBuiltins
import UIKit

/// 只在模拟器里用：模拟器没有相机，用一张程序生成的演示画面代替取景，方便在 CI 里截图检查界面。
enum SimulatorDemo {
    static var isActive: Bool {
        #if targetEnvironment(simulator)
        return true
        #else
        return false
        #endif
    }

    /// 截图时要展开的面板：通过启动参数 `-iPANUIState tools|styles|palette` 传入
    static var uiState: String? { UserDefaults.standard.string(forKey: "iPANUIState") }

    /// 4:3 横向的演示画面：黄昏天空、楼群剪影、地面
    static func frame() -> CIImage {
        let size = CGSize(width: 1920, height: 1440)
        let full = CGRect(origin: .zero, size: size)
        let horizon = size.height * 0.42

        let sky = CIFilter.linearGradient()
        sky.point0 = CGPoint(x: 0, y: size.height)
        sky.point1 = CGPoint(x: 0, y: horizon)
        sky.color0 = CIColor(red: 0.18, green: 0.26, blue: 0.45)
        sky.color1 = CIColor(red: 0.98, green: 0.62, blue: 0.32)
        var image = sky.outputImage!.cropped(to: full)

        let ground = CIFilter.linearGradient()
        ground.point0 = CGPoint(x: 0, y: horizon)
        ground.point1 = CGPoint(x: 0, y: 0)
        ground.color0 = CIColor(red: 0.20, green: 0.17, blue: 0.15)
        ground.color1 = CIColor(red: 0.07, green: 0.07, blue: 0.08)
        image = ground.outputImage!.cropped(to: CGRect(x: 0, y: 0, width: size.width, height: horizon)).composited(over: image)

        // 楼群剪影
        var x: CGFloat = 0
        var seed: CGFloat = 0.37
        while x < size.width {
            seed = (seed * 9301 + 0.49297).truncatingRemainder(dividingBy: 1)
            let w = 90 + seed * 160
            let h = 160 + seed * 520
            let tone = 0.05 + seed * 0.06
            let building = CIImage(color: CIColor(red: tone, green: tone, blue: tone + 0.02))
                .cropped(to: CGRect(x: x, y: horizon, width: w, height: h))
            image = building.composited(over: image)
            // 亮着的窗户
            var wy = horizon + 30
            while wy < horizon + h - 40 {
                if (Int(wy) / 37 + Int(x)) % 3 == 0 {
                    let light = CIImage(color: CIColor(red: 1, green: 0.78, blue: 0.45))
                        .cropped(to: CGRect(x: x + w * 0.3, y: wy, width: w * 0.18, height: 14))
                    image = light.composited(over: image)
                }
                wy += 46
            }
            x += w + 14 + seed * 40
        }
        return image
    }

    static func thumbnail() -> UIImage? {
        let image = frame()
        let crop = CGRect(x: 0, y: 380, width: 1920, height: 1920 * 24 / 65)
        let context = CIContext()
        guard let cg = context.createCGImage(image.cropped(to: crop), from: crop) else { return nil }
        return UIImage(cgImage: cg)
    }
}
