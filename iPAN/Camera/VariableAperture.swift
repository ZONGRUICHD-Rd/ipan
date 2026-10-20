import AVFoundation
import Darwin

/// 可变光圈（iPhone 18 Pro 主摄 f/1.48–f/4.0）。
///
/// 相关 API 是 iOS 27 才加入 AVFoundation 的（`setExposureModeCustom(lensAperture:duration:iso:)`、
/// `Format.minLensAperture / maxLensAperture / recommendedLensApertureStops` 等）。工程按要求用 Xcode 26（iOS 26 SDK）构建，
/// SDK 里还没有这些符号，所以这里通过 Objective-C 运行时调用；系统或镜头不支持时一律返回 nil / false，界面隐藏光圈控件。
///
/// 采用「光圈优先」：锁定光圈，快门和 ISO 仍由自动曝光调整，画面亮度保持正常。
enum VariableAperture {
    struct Support: Equatable {
        let min: Float
        let max: Float
        /// 推荐档位（系统提供；没有时用常见档位）
        let stops: [Float]
    }

    // MARK: 运行时符号

    private static let rtldDefault = UnsafeMutableRawPointer(bitPattern: -2)

    private static func constant<T>(_ name: String, _: T.Type) -> T? {
        guard let pointer = dlsym(rtldDefault, name) else { return nil }
        return pointer.assumingMemoryBound(to: T.self).pointee
    }

    /// AVCaptureExposureDurationAuto / AVCaptureISOAuto：交给自动曝光管理
    private static let durationAuto: CMTime? = constant("AVCaptureExposureDurationAuto", CMTime.self)
    private static let isoAuto: Float? = constant("AVCaptureISOAuto", Float.self)

    private static let setSelector = NSSelectorFromString("setExposureModeCustomWithLensAperture:duration:ISO:completionHandler:")
    private static let supportsSelector = NSSelectorFromString("supportsExposureModeCustomWithLensAperture:duration:ISO:")

    private typealias SetFunction = @convention(c) (AnyObject, Selector, Float, CMTime, Float, AnyObject?) -> Void
    private typealias SupportsFunction = @convention(c) (AnyObject, Selector, Float, CMTime, Float) -> Bool

    // MARK: 查询

    static func support(for device: AVCaptureDevice) -> Support? {
        let format = device.activeFormat
        guard durationAuto != nil, isoAuto != nil,
              device.responds(to: setSelector),
              format.responds(to: NSSelectorFromString("minLensAperture")),
              format.responds(to: NSSelectorFromString("maxLensAperture")),
              let minValue = (format.value(forKey: "minLensAperture") as? NSNumber)?.floatValue,
              let maxValue = (format.value(forKey: "maxLensAperture") as? NSNumber)?.floatValue,
              maxValue - minValue > 0.05
        else { return nil }

        var stops: [Float] = []
        if format.responds(to: NSSelectorFromString("recommendedLensApertureStops")),
           let values = format.value(forKey: "recommendedLensApertureStops") as? [NSNumber] {
            stops = values.map(\.floatValue)
        }
        if stops.isEmpty { stops = [minValue, 2, 2.8, maxValue] }
        stops = stops.filter { $0 >= minValue - 0.01 && $0 <= maxValue + 0.01 }
        stops = Array(Set(stops.map { ($0 * 100).rounded() / 100 })).sorted()
        return Support(min: minValue, max: maxValue, stops: stops)
    }

    // MARK: 设置

    /// 光圈优先：锁定光圈，快门和 ISO 自动。需要先 lockForConfiguration。返回是否成功。
    @discardableResult
    static func lock(_ device: AVCaptureDevice, aperture: Float, support: Support) -> Bool {
        guard let durationAuto, let isoAuto, device.responds(to: setSelector) else { return false }
        let value = min(support.max, max(support.min, aperture))
        let format = device.activeFormat
        // 不支持的组合会抛 Objective-C 异常（Swift 里无法捕获），所以先校验
        if format.responds(to: supportsSelector) {
            let supports = unsafeBitCast(format.method(for: supportsSelector), to: SupportsFunction.self)
            guard supports(format, supportsSelector, value, durationAuto, isoAuto) else { return false }
        }
        let set = unsafeBitCast(device.method(for: setSelector), to: SetFunction.self)
        set(device, setSelector, value, durationAuto, isoAuto, nil)
        return true
    }

    /// 回到全自动曝光（光圈也交还给系统）。需要先 lockForConfiguration。
    static func unlock(_ device: AVCaptureDevice) {
        if device.isExposureModeSupported(.continuousAutoExposure) {
            device.exposureMode = .continuousAutoExposure
        }
    }

    static func label(_ value: Float) -> String {
        let text = String(format: "%.1f", value)
        return text.hasSuffix(".0") ? String(text.dropLast(2)) : text
    }
}
