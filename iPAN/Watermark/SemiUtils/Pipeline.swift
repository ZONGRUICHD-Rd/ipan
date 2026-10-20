import CoreGraphics
import Foundation

/// 处理管道的运行环境：资源目录、输入图片、EXIF。
final class SUEnvironment {
    static let inputPath = "__IPAN_INPUT__"

    let configDir: URL
    let input: CGImage
    let exif: [String: String]
    private var imageCache: [String: CGImage] = [:]

    var fontsDir: URL { configDir.appendingPathComponent("fonts") }
    var logosDir: URL { configDir.appendingPathComponent("logos") }
    var templatesDir: URL { configDir.appendingPathComponent("templates") }

    init(configDir: URL, input: CGImage, exif: [String: String]) {
        self.configDir = configDir
        self.input = input
        self.exif = exif
    }

    func loadImage(_ path: String) throws -> CGImage {
        if path == SUEnvironment.inputPath { return input }
        if let cached = imageCache[path] { return cached }
        let resolved: String
        if path.hasPrefix("/") {
            resolved = path
        } else {
            // 模板里的相对路径相对于 semi-utils 项目根目录（config 的上一级）
            let base = configDir.deletingLastPathComponent()
            resolved = base.appendingPathComponent(path.hasPrefix("./") ? String(path.dropFirst(2)) : path).path
        }
        guard let image = Raster.load(path: resolved) else {
            throw SUError("无法读取图片: \(path)")
        }
        imageCache[path] = image
        return image
    }
}

struct SUError: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}

/// processor.core.PipelineContext
final class SUContext {
    var config: [String: Any]
    let env: SUEnvironment

    init(_ config: [String: Any], env: SUEnvironment) {
        self.config = config
        self.env = env
    }

    func has(_ key: String) -> Bool { config[key] != nil }

    /// 与 Python 版一致：值为 None 时返回默认值
    func get(_ key: String) -> Any? {
        guard let v = config[key], !(v is NSNull) else { return nil }
        return v
    }

    func string(_ key: String) -> String? {
        guard let v = get(key) else { return nil }
        if let s = v as? String { return s }
        if let n = v as? NSNumber { return n.stringValue }
        return "\(v)"
    }

    func double(_ key: String) -> Double? {
        guard let v = get(key) else { return nil }
        if let n = v as? NSNumber { return n.doubleValue }
        if let s = v as? String { return Double(s.trimmingCharacters(in: .whitespaces)) }
        return nil
    }

    func int(_ key: String, _ fallback: Int = 0) -> Int {
        guard let d = double(key) else { return fallback }
        return Int(d)
    }

    func bool(_ key: String, _ fallback: Bool) -> Bool {
        guard let v = get(key) else { return fallback }
        if let b = v as? Bool { return b }
        if let n = v as? NSNumber { return n.boolValue }
        if let s = v as? String { return !s.isEmpty && s.lowercased() != "false" && s != "0" }
        return fallback
    }

    func color(_ key: String, _ fallback: RGBA) -> RGBA {
        RGBA.parse(get(key)) ?? fallback
    }

    /// json.loads(ctx.get(key, default))
    func json(_ key: String) -> Any? {
        guard let v = get(key) else { return nil }
        if let s = v as? String, let data = s.data(using: .utf8) {
            return try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        }
        return v
    }

    func dict(_ key: String) -> [String: Any]? { get(key) as? [String: Any] }

    // MARK: buffer

    private var bufferLoaded: Bool {
        get { (config["buffer_loaded"] as? Bool) ?? false }
        set { config["buffer_loaded"] = newValue }
    }

    var buffer: [CGImage] {
        get {
            if !bufferLoaded, let paths = get("buffer_path") as? [String], !paths.isEmpty {
                let images = paths.compactMap { try? env.loadImage($0) }
                config["buffer"] = images
                bufferLoaded = true
            }
            return (config["buffer"] as? [CGImage]) ?? []
        }
        set { config["buffer"] = newValue }
    }

    func setInitialBuffer(_ images: [CGImage]) {
        config["buffer"] = images
        bufferLoaded = true
    }
}

protocol SUProcessor {
    var name: String { get }
    var category: String { get }
    func process(_ ctx: SUContext) throws
}

enum SUPipeline {
    static let registry: [String: () -> SUProcessor] = {
        let all: [() -> SUProcessor] = [
            { BlurFilter() }, { ResizeFilter() }, { TrimFilter() }, { MarginFilter() }, { MarginWithRatioFilter() },
            { WatermarkFilter() }, { WatermarkWithTimestampFilter() }, { RoundedCornerFilter() }, { ShadowFilter() },
            { CropFilter() }, { SolidColorGenerator() }, { GradientColorGenerator() }, { RichTextGenerator() },
            { MultiRichTextGenerator() }, { ImageLoader() }, { AlignmentMerger() }, { ConcatMerger() },
        ]
        var map: [String: () -> SUProcessor] = [:]
        for make in all { map[make().name] = make }
        return map
    }()

    /// processor.core.start_process
    @discardableResult
    static func run(_ data: [[String: Any]], env: SUEnvironment, inputPath: String? = nil, initialBuffer: [CGImage]? = nil) throws -> CGImage? {
        guard !data.isEmpty else { return initialBuffer?.first }
        let nodes = data.map { SUContext($0, env: env) }
        if let initialBuffer {
            nodes[0].setInitialBuffer(initialBuffer)
        } else if let inputPath {
            nodes[0].config["buffer_path"] = [inputPath]
        }
        if inputPath != nil {
            for node in nodes where node.config["exif"] == nil { node.config["exif"] = env.exif }
        }

        var output = nodes[0].buffer
        var allBuffer: [[CGImage]] = [output]
        var lastMergerIndex = -1

        for (idx, node) in nodes.enumerated() {
            guard let name = node.string("processor_name"), let make = registry[name] else {
                throw SUError("Processor '\(node.string("processor_name") ?? "nil")' not found")
            }
            let processor = make()
            if node.has("select") {
                let indexes = (node.json("select") as? [Any])?.compactMap { ($0 as? NSNumber)?.intValue } ?? []
                node.buffer = indexes.flatMap { allBuffer.indices.contains($0) ? allBuffer[$0] : [] }
            } else if processor.category != "merger" {
                node.buffer = output
            } else {
                let toMerge = allBuffer[(lastMergerIndex + 1)...min(idx, allBuffer.count - 1)]
                node.buffer = toMerge.flatMap { $0 }
                lastMergerIndex = idx
            }
            try processor.process(node)
            output = node.buffer
            allBuffer.append(output)
        }
        return nodes.last?.buffer.first
    }
}
