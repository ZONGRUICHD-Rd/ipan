import CoreGraphics
import Foundation
import ImageIO

/// 拍摄参数，用来生成 semi-utils 模板需要的 exiftool 风格 EXIF 字典。
struct CaptureInfo {
    var make = "Apple"
    var model = "iPhone"
    var lensModel = ""
    var focal35mm: Int = 0
    var fNumber: Double = 0
    var exposureDuration: Double = 0
    var iso: Int = 0
    var date = Date()

    init() {}

    /// 从 AVCapturePhoto.metadata（ImageIO 属性字典）读取
    init(metadata: [String: Any], focal35mm: Int) {
        let tiff = metadata[kCGImagePropertyTIFFDictionary as String] as? [String: Any] ?? [:]
        let exif = metadata[kCGImagePropertyExifDictionary as String] as? [String: Any] ?? [:]
        make = tiff[kCGImagePropertyTIFFMake as String] as? String ?? "Apple"
        model = tiff[kCGImagePropertyTIFFModel as String] as? String ?? "iPhone"
        lensModel = exif[kCGImagePropertyExifLensModel as String] as? String ?? ""
        self.focal35mm = focal35mm
        fNumber = (exif[kCGImagePropertyExifFNumber as String] as? NSNumber)?.doubleValue ?? 0
        exposureDuration = (exif[kCGImagePropertyExifExposureTime as String] as? NSNumber)?.doubleValue ?? 0
        iso = ((exif[kCGImagePropertyExifISOSpeedRatings as String] as? [NSNumber])?.first)?.intValue ?? 0
        if let s = exif[kCGImagePropertyExifDateTimeOriginal as String] as? String {
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_US_POSIX")
            f.dateFormat = "yyyy:MM:dd HH:mm:ss"
            date = f.date(from: s) ?? Date()
        }
    }

    var shutterText: String {
        guard exposureDuration > 0 else { return "-" }
        if exposureDuration >= 1 { return String(format: "%g", (exposureDuration * 10).rounded() / 10) }
        return "1/\(Int((1 / exposureDuration).rounded()))"
    }

    /// 与 semi-utils 的 get_exif（exiftool 输出去空格作 key）同名的字段
    func exifDictionary(width: Int, height: Int) -> [String: String] {
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.dateFormat = "yyyy-MM-dd HH:mm:ss.SSSZ"
        let dateText = df.string(from: date)
        var d: [String: String] = [
            "Make": make,
            "CameraModelName": model,
            "Model": model,
            "LensModel": lensModel,
            "LensMake": make,
            "FocalLengthIn35mmFormat": focal35mm > 0 ? "\(focal35mm) mm" : "",
            "FNumber": fNumber > 0 ? String(format: "%.1f", fNumber) : "",
            "ApertureValue": fNumber > 0 ? String(format: "%.1f", fNumber) : "",
            "ExposureTime": shutterText,
            "ShutterSpeed": shutterText,
            "ShutterSpeedValue": shutterText,
            "ISO": iso > 0 ? "\(iso)" : "",
            "DateTimeOriginal": dateText,
            "CreateDate": dateText,
            "ImageWidth": "\(width)",
            "ImageHeight": "\(height)",
            "FileName": "iPAN.heic",
        ]
        // exiftool 输出里非 ASCII 会被过滤掉
        for (k, v) in d { d[k] = String(v.unicodeScalars.filter { $0.isASCII }.map { Character($0) }) }
        return d.filter { !$0.value.isEmpty }
    }
}

/// 使用 semi-utils（ZONGRUICHD-Rd/semi-utils-ios-support）的模板、Logo 与字体给照片加水印。
enum WatermarkService {
    static var configDir: URL? {
        Bundle.main.url(forResource: "config", withExtension: nil)
    }

    static func availableTemplates() -> [String] {
        guard let dir = configDir?.appendingPathComponent("templates"),
              let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
        else { return [] }
        return files.filter { $0.pathExtension == "json" }
            .map { $0.deletingPathExtension().lastPathComponent }
            .sorted()
    }

    /// - Parameter showLogo: false 时模板里的 auto_logo() 返回空，不画品牌 Logo（连同旁边的分隔线）
    static func apply(template: String, to image: CGImage, info: CaptureInfo, showLogo: Bool = false) throws -> CGImage {
        guard let configDir else { throw SUError("App 内缺少 semi-utils 的 config 资源") }
        var url = configDir.appendingPathComponent("templates").appendingPathComponent(template + ".json")
        if !FileManager.default.fileExists(atPath: url.path), let fallback = availableTemplates().first {
            // 保存的模板名找不到（例如上游改名）时退回第一个可用模板
            url = configDir.appendingPathComponent("templates").appendingPathComponent(fallback + ".json")
        }
        let source = try String(contentsOf: url, encoding: .utf8)
        let exif = info.exifDictionary(width: image.width, height: image.height)
        let env = SUEnvironment(configDir: configDir, input: image, exif: exif)

        var exifValue: [String: JValue] = [:]
        for (k, v) in exif { exifValue[k] = .string(v) }
        let variables: [String: JValue] = [
            "exif": .dict(exifValue),
            "file_path": .string(SUEnvironment.inputPath),
            "file_dir": .string("/iPAN"),
        ]
        let rendered = try TemplateEngine.render(source, variables: variables, functions: SUFunctions(env: env, showLogo: showLogo))
        guard let data = rendered.data(using: .utf8),
              let nodes = try JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        else { throw SUError("模板 \(template) 渲染后不是合法的 JSON 数组") }

        guard let output = try SUPipeline.run(nodes, env: env, inputPath: SUEnvironment.inputPath) else {
            throw SUError("模板 \(template) 没有输出图片")
        }
        return Raster.flatten(output) ?? output
    }
}

/// core/jinja2renders.py 中注册到模板的 vh / vw / auto_logo
struct SUFunctions: TemplateFunctions {
    let env: SUEnvironment
    var showLogo = true

    func call(_ name: String, _ args: [JValue], _ kwargs: [String: JValue]) throws -> JValue {
        switch name {
        case "vw", "vh":
            let percent = args.first?.number ?? 0
            let base = Double(env.exif[name == "vw" ? "ImageWidth" : "ImageHeight"] ?? "0") ?? 0
            return .int(Int(base * percent / 100))
        case "auto_logo":
            guard showLogo else { return .none }
            var brand = (args.first ?? kwargs["brand"])?.str ?? ""
            if brand.isEmpty || brand == "None" { brand = env.exif["Make"] ?? "default" }
            brand = brand.lowercased()
            let files = (try? FileManager.default.contentsOfDirectory(at: env.logosDir, includingPropertiesForKeys: nil)) ?? []
            for f in files.sorted(by: { $0.lastPathComponent < $1.lastPathComponent })
            where ["png", "jpg", "jpeg"].contains(f.pathExtension.lowercased()) {
                if brand.contains(f.deletingPathExtension().lastPathComponent.lowercased()) { return .string(f.path) }
            }
            return .none
        default:
            throw TemplateError(description: "未知函数 \(name)")
        }
    }
}
