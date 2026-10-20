import CoreGraphics
import CoreImage
import Foundation

// semi-utils processor/filters.py、generators.py、mergers.py 的 Swift 移植。
// 逻辑（参数名、默认值、布局计算）与 Python 版逐行对应，方便跟随上游模板更新。

enum SUAlignment {
    case start, center, end

    static func parse(_ value: String?, default fallback: SUAlignment) -> SUAlignment {
        switch value?.lowercased() {
        case "start", "top", "left": return .start
        case "center", "middle": return .center
        case "end", "bottom", "right": return .end
        default: return fallback
        }
    }

    func offset(size: Int, max: Int) -> Int {
        switch self {
        case .start: return 0
        case .center: return (max - size) / 2
        case .end: return max - size
        }
    }
}

enum SUDirection: String {
    case horizontal, vertical, diagonal, radial

    static func parse(_ value: String?, default fallback: SUDirection) -> SUDirection {
        guard let value else { return fallback }
        return SUDirection(rawValue: value.lowercased()) ?? fallback
    }
}

// MARK: - Filters

struct BlurFilter: SUProcessor {
    let name = "blur"
    let category = "filter"

    func process(_ ctx: SUContext) throws {
        let radius = ctx.int("blur_radius", 5)
        ctx.buffer = ctx.buffer.compactMap { Raster.gaussianBlur($0, sigma: Double(radius)) }
    }
}

struct ResizeFilter: SUProcessor {
    let name = "resize"
    let category = "filter"

    func process(_ ctx: SUContext) throws {
        let width = ctx.double("width"), height = ctx.double("height"), scale = ctx.double("scale")
        var out: [CGImage] = []
        for img in ctx.buffer {
            let target: (Int, Int)
            if let width, let height, width > 0, height > 0 {
                target = (Int(width), Int(height))
            } else {
                let f: Double
                if let width, width > 0 { f = width / Double(img.width) }
                else if let height, height > 0 { f = height / Double(img.height) }
                else if let scale { f = scale }
                else { return }
                target = (Int(Double(img.width) * f), Int(Double(img.height) * f))
            }
            if let r = Raster.resize(img, width: max(1, target.0), height: max(1, target.1)) { out.append(r) }
        }
        ctx.buffer = out
    }
}

struct TrimFilter: SUProcessor {
    let name = "trim"
    let category = "filter"

    func process(_ ctx: SUContext) throws {
        var out: [CGImage] = []
        for img in ctx.buffer where img.width * img.height > 0 {
            let box = TrimFilter.foregroundBox(img,
                                               trimLeft: ctx.bool("trim_left", true), trimRight: ctx.bool("trim_right", true),
                                               trimTop: ctx.bool("trim_top", true), trimBottom: ctx.bool("trim_bottom", true))
            if let c = Raster.crop(img, left: box.left, top: box.top, right: box.right, bottom: box.bottom) { out.append(c) }
        }
        ctx.buffer = out
    }

    /// 取四角均值作为背景色，从四个方向收缩到与背景差异 > threshold 的像素
    static func foregroundBox(_ image: CGImage, threshold: Double = 10, trimLeft: Bool, trimRight: Bool, trimTop: Bool, trimBottom: Bool)
        -> (left: Int, top: Int, right: Int, bottom: Int) {
        guard let px = Raster.pixels(of: image) else { return (0, 0, image.width, image.height) }
        let w = px.width, h = px.height
        let d = px.data
        func pixel(_ x: Int, _ y: Int) -> (Double, Double, Double, Double) {
            let i = (y * w + x) * 4
            return (Double(d[i]), Double(d[i + 1]), Double(d[i + 2]), Double(d[i + 3]))
        }
        let corners = [pixel(0, 0), pixel(w - 1, 0), pixel(0, h - 1), pixel(w - 1, h - 1)]
        let bg = (corners.map(\.0).reduce(0, +) / 4, corners.map(\.1).reduce(0, +) / 4,
                  corners.map(\.2).reduce(0, +) / 4, corners.map(\.3).reduce(0, +) / 4)
        let t2 = threshold * threshold
        var colHit = [Bool](repeating: false, count: w)
        var rowHit = [Bool](repeating: false, count: h)
        d.withUnsafeBufferPointer { buf in
            for y in 0..<h {
                var rowAny = false
                let rowBase = y * w * 4
                for x in 0..<w {
                    let i = rowBase + x * 4
                    let dr = Double(buf[i]) - bg.0, dg = Double(buf[i + 1]) - bg.1
                    let db = Double(buf[i + 2]) - bg.2, da = Double(buf[i + 3]) - bg.3
                    if dr * dr + dg * dg + db * db + da * da > t2 {
                        colHit[x] = true
                        rowAny = true
                    }
                }
                rowHit[y] = rowAny
            }
        }
        guard let firstCol = colHit.firstIndex(of: true) else { return (0, 0, w, h) }
        var left = firstCol
        var right = (colHit.lastIndex(of: true) ?? (w - 1)) + 1
        var top = rowHit.firstIndex(of: true) ?? 0
        var bottom = (rowHit.lastIndex(of: true) ?? (h - 1)) + 1
        if !trimLeft { left = 0 }
        if !trimRight { right = w }
        if !trimTop { top = 0 }
        if !trimBottom { bottom = h }
        return (max(0, left), max(0, top), min(w, right), min(h, bottom))
    }
}

struct MarginFilter: SUProcessor {
    let name = "margin"
    let category = "filter"

    func process(_ ctx: SUContext) throws {
        let l = ctx.int("left_margin"), r = ctx.int("right_margin")
        let t = ctx.int("top_margin"), b = ctx.int("bottom_margin")
        let color = ctx.color("margin_color", .white)
        ctx.buffer = ctx.buffer.compactMap { img in
            let w = img.width + l + r, h = img.height + t + b
            return Raster.image(width: w, height: h, fill: color) { c in
                c.paste(img, x: l, y: t, canvasHeight: h)
            }
        }
    }
}

struct MarginWithRatioFilter: SUProcessor {
    let name = "margin_with_ratio"
    let category = "filter"

    func process(_ ctx: SUContext) throws {
        guard let img = ctx.buffer.first else { return }
        let exif = (ctx.get("exif") as? [String: String]) ?? ctx.env.exif
        var realRatio = (Double(exif["ImageWidth"] ?? "") ?? Double(img.width)) / (Double(exif["ImageHeight"] ?? "") ?? Double(img.height))
        if let ratio = ctx.string("ratio"), ratio.range(of: #"^[0-9.]+:[0-9.]+"#, options: .regularExpression) != nil {
            let parts = ratio.split(separator: ":").compactMap { Double($0) }
            if parts.count == 2, parts[1] != 0 { realRatio = parts[0] / parts[1] }
        }
        let cur = Double(img.width) / Double(img.height)
        if cur - realRatio > 0.01 {
            let pad = Int(Double(img.width) / realRatio) - img.height
            ctx.config["top_margin"] = Double(pad) / 2
            ctx.config["bottom_margin"] = Double(pad) - Double(pad) / 2
        } else if cur - realRatio < 0.01 {
            let pad = Int(Double(img.height) * realRatio) - img.width
            ctx.config["left_margin"] = Double(pad) / 2
            ctx.config["right_margin"] = Double(pad) - Double(pad) / 2
        } else {
            return
        }
        try MarginFilter().process(ctx)
    }
}

struct WatermarkFilter: SUProcessor {
    let name = "watermark"
    let category = "filter"

    func process(_ ctx: SUContext) throws {
        guard let img = ctx.buffer.first else { return }
        let color = ctx.color("color", .white)
        let delimiterColor = ctx.color("delimiter_color", .black)
        let delimiterWidth = ctx.int("delimiter_width", Int(Double(img.width) * 0.003))
        let leftMargin = ctx.int("left_margin", 0)
        let rightMargin = ctx.int("right_margin", 0)
        let topMargin = ctx.int("top_margin", 0)
        let bottomMargin = ctx.int("bottom_margin", Int(Double(img.height) * 0.12))
        let middleSpacing = ctx.int("middle_spacing", Int(Double(bottomMargin) * 0.05))
        let rightAlignment = SUAlignment.parse(ctx.string("right_alignment"), default: .end)

        func element(_ key: String) throws -> CGImage {
            var spec = ctx.dict(key) ?? ["processor_name": "rich_text"]
            if spec["height"] == nil { spec["height"] = Int(Double(bottomMargin) * 0.3) }
            ctx.config[key] = spec
            return try SUPipeline.run([spec], env: ctx.env)
                ?? Raster.image(width: 1, height: 1, fill: .clear)!
        }
        let leftTop = try element("left_top")
        let leftBottom = try element("left_bottom")
        let rightTop = try element("right_top")
        let rightBottom = try element("right_bottom")

        func logo(_ key: String) -> CGImage? {
            guard let path = ctx.string(key), !path.isEmpty, path != "None" else { return nil }
            return try? ctx.env.loadImage(path)
        }
        let leftLogo = logo("left_logo")
        let rightLogo = logo("right_logo")
        var centerLogo = logo("center_logo")
        let centerLogoHeight = ctx.int("center_logo_height", 0)

        let canvasWidth = img.width + leftMargin + rightMargin
        let canvasHeight = img.height + topMargin + bottomMargin
        let commonSpacing = Int(0.02 * Double(canvasWidth))

        guard let canvas = Raster.context(width: canvasWidth, height: canvasHeight, fill: color) else { return }
        canvas.paste(img, x: leftMargin, y: topMargin, canvasHeight: canvasHeight)
        let footerStartY = topMargin + img.height

        var leftLogoWidth = 0
        if let leftLogo {
            let size = canvasHeight - footerStartY
            if let resized = Raster.resize(leftLogo, width: size, height: size) {
                canvas.paste(resized, x: leftMargin, y: footerStartY, canvasHeight: canvasHeight)
            }
            leftLogoWidth = size
        }

        if let logo = centerLogo {
            let logoHeight = centerLogoHeight > 0 ? centerLogoHeight : canvasHeight - footerStartY
            let w = Int(Double(logo.width) * Double(logoHeight) / Double(logo.height))
            centerLogo = Raster.resize(logo, width: max(1, w), height: max(1, logoHeight))
            if let centerLogo {
                let x = (canvasWidth - centerLogo.width) / 2
                let y = footerStartY + ((canvasHeight - footerStartY) - centerLogo.height) / 2
                canvas.paste(centerLogo, x: x, y: y, canvasHeight: canvasHeight)
            }
        }

        let elemHeight = max(leftTop.height + leftBottom.height, rightTop.height + rightBottom.height) + middleSpacing
        let elemMargin = Int(Double(bottomMargin - elemHeight) / 2)
        let lx = leftMargin + leftLogoWidth + commonSpacing
        let rightContentEndX = canvasWidth - rightMargin

        let ltY = canvasHeight - (elemMargin + leftBottom.height + middleSpacing + leftTop.height)
        let lbY = canvasHeight - (elemMargin + leftBottom.height)
        let rtY = (ltY + leftTop.height) - rightTop.height
        var rtX = rightContentEndX - rightTop.width - commonSpacing
        let rbY = (lbY + leftBottom.height) - rightBottom.height
        var rbX = rightContentEndX - rightBottom.width - commonSpacing
        if rightAlignment == .start {
            rtX = min(rtX, rbX)
            rbX = rtX
        }

        canvas.paste(leftTop, x: lx, y: ltY, canvasHeight: canvasHeight)
        canvas.paste(leftBottom, x: lx, y: lbY, canvasHeight: canvasHeight)
        canvas.paste(rightTop, x: rtX, y: rtY, canvasHeight: canvasHeight)
        canvas.paste(rightBottom, x: rbX, y: rbY, canvasHeight: canvasHeight)

        if let rightLogo {
            let logoSize = elemHeight
            let delimiterHeight = Int(Double(logoSize) * 1.1)
            let delimiterX = canvasWidth - rightMargin - max(rightTop.width, rightBottom.width) - 2 * commonSpacing - delimiterWidth
            let delimiterY = Int(Double(footerStartY + elemMargin) - Double(logoSize) * 0.05)
            canvas.setFillColor(delimiterColor.cgColor)
            canvas.fill(CGRect(x: delimiterX, y: canvasHeight - delimiterY - delimiterHeight, width: delimiterWidth, height: delimiterHeight))
            if let resized = Raster.resize(rightLogo, width: max(1, logoSize), height: max(1, logoSize)) {
                let x = delimiterX - commonSpacing - logoSize
                canvas.paste(resized, x: x, y: footerStartY + elemMargin, canvasHeight: canvasHeight)
            }
        }

        if let result = canvas.makeImage() { ctx.buffer = [result] }
    }
}

struct WatermarkWithTimestampFilter: SUProcessor {
    let name = "watermark_with_timestamp"
    let category = "filter"

    func process(_ ctx: SUContext) throws {
        guard let img = ctx.buffer.first else { return }
        if ctx.get("height") == nil { ctx.config["height"] = Int(Double(img.height) * 0.02) }
        try MultiRichTextGenerator().process(ctx)
        guard let text = ctx.buffer.first else { return }
        let x = Int(Double(img.width) * 0.93) - text.width
        let y = Int(Double(img.height) * 0.95)
        let result = Raster.image(width: img.width, height: img.height, fill: .clear) { c in
            c.paste(img, x: 0, y: 0, canvasHeight: img.height)
            c.paste(text, x: x, y: y, canvasHeight: img.height)
        }
        if let result { ctx.buffer = [result] }
    }
}

struct RoundedCornerFilter: SUProcessor {
    let name = "rounded_corner"
    let category = "filter"

    func process(_ ctx: SUContext) throws {
        let radius = CGFloat(ctx.int("border_radius", 10))
        ctx.buffer = ctx.buffer.compactMap { img in
            Raster.image(width: img.width, height: img.height, fill: .clear) { c in
                let rect = CGRect(x: 0, y: 0, width: img.width, height: img.height)
                let r = min(radius, min(rect.width, rect.height) / 2)
                c.addPath(CGPath(roundedRect: rect, cornerWidth: r, cornerHeight: r, transform: nil))
                c.clip()
                c.draw(img, in: rect)
            }
        }
    }
}

struct ShadowFilter: SUProcessor {
    let name = "shadow"
    let category = "filter"

    func process(_ ctx: SUContext) throws {
        let shadowColor = ctx.color("shadow_color", RGBA(r: 0, g: 0, b: 0, a: 180))
        let radius = ctx.int("shadow_radius", 30)
        let falloff = 1.5
        ctx.buffer = ctx.buffer.compactMap { img in
            guard radius > 0 else { return img }
            let padding = radius * 2
            let fw = img.width + padding * 2, fh = img.height + padding * 2
            // 1. 剪影：用原图 alpha 作为蒙版填充阴影色
            guard let silhouette = Raster.image(width: fw, height: fh, fill: .clear, draw: { c in
                let rect = CGRect(x: padding, y: padding, width: img.width, height: img.height)
                c.draw(img, in: rect)
                c.setBlendMode(.sourceIn)
                c.setFillColor(shadowColor.cgColor)
                c.fill(rect)
            }),
                // 2. 高斯模糊
                let blurred = Raster.gaussianBlur(silhouette, sigma: Double(radius)),
                // 3. alpha 幂函数衰减，消除边缘残留
                var px = Raster.pixels(of: blurred)
            else { return img }
            var lut = [UInt8](repeating: 0, count: 256)
            for a in 0..<256 {
                let v = pow(Double(a) / 255, falloff)
                lut[a] = v < 0.01 ? 0 : UInt8(min(255, (v * 255).rounded(.down)))
            }
            px.data.withUnsafeMutableBufferPointer { buf in
                var i = 0
                while i < buf.count {
                    let a = Int(buf[i + 3])
                    if a > 0 {
                        let na = Int(lut[a])
                        buf[i] = UInt8(Int(buf[i]) * na / a)
                        buf[i + 1] = UInt8(Int(buf[i + 1]) * na / a)
                        buf[i + 2] = UInt8(Int(buf[i + 2]) * na / a)
                        buf[i + 3] = UInt8(na)
                    }
                    i += 4
                }
            }
            guard let shadow = Raster.image(fromPixels: px.data, width: px.width, height: px.height) else { return img }
            // 4. 合成原图
            return Raster.image(width: fw, height: fh, fill: .clear) { c in
                c.draw(shadow, in: CGRect(x: 0, y: 0, width: fw, height: fh))
                c.paste(img, x: padding, y: padding, canvasHeight: fh)
            }
        }
    }
}

struct CropFilter: SUProcessor {
    let name = "crop"
    let category = "filter"

    func process(_ ctx: SUContext) throws {
        var width = ctx.int("width", 0)
        var height = ctx.int("height", 0)
        let offset = ((ctx.json("offset") as? [Any]) ?? []).compactMap { ($0 as? NSNumber)?.intValue }
        ctx.buffer = ctx.buffer.compactMap { img in
            if width <= 0 { width = img.width }
            if height <= 0 { height = img.height }
            var left = (img.width - width) / 2 + (offset.count > 0 ? offset[0] : 0)
            var top = (img.height - height) / 2 + (offset.count > 1 ? offset[1] : 0)
            left = max(0, min(left, img.width - width))
            top = max(0, min(top, img.height - height))
            return Raster.crop(img, left: left, top: top, right: left + width, bottom: top + height)
        }
    }
}

// MARK: - Generators

struct SolidColorGenerator: SUProcessor {
    let name = "solid_color"
    let category = "generator"

    func process(_ ctx: SUContext) throws {
        let w = ctx.int("width"), h = ctx.int("height")
        if let img = Raster.image(width: w, height: h, fill: ctx.color("color", .white)) { ctx.buffer = [img] }
    }
}

struct GradientColorGenerator: SUProcessor {
    let name = "gradient_color"
    let category = "generator"

    func process(_ ctx: SUContext) throws {
        let w = max(1, ctx.int("width")), h = max(1, ctx.int("height"))
        let start = ctx.color("start_color", .black), end = ctx.color("end_color", .white)
        let direction = SUDirection.parse(ctx.string("direction"), default: .horizontal)
        let method = ctx.string("interpolate_method")?.lowercased() ?? "linear"
        func ease(_ t: Double) -> Double {
            switch method {
            case "ease_in": return t * t
            case "ease_out": return 1 - (1 - t) * (1 - t)
            case "ease_in_out": return t < 0.5 ? 2 * t * t : 1 - pow(-2 * t + 2, 2) / 2
            default: return t
            }
        }
        // 用 32 个色标近似缓动曲线
        let steps = 32
        var colors: [CGColor] = []
        var locations: [CGFloat] = []
        for i in 0...steps {
            let t = Double(i) / Double(steps)
            let e = ease(t)
            let c = RGBA(r: start.r + (end.r - start.r) * e, g: start.g + (end.g - start.g) * e,
                         b: start.b + (end.b - start.b) * e, a: start.a + (end.a - start.a) * e)
            colors.append(c.cgColor)
            locations.append(CGFloat(t))
        }
        guard let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: colors as CFArray, locations: locations) else { return }
        let img = Raster.image(width: w, height: h, fill: .clear) { c in
            // CG 原点在左下角；PIL 的 y 向下，所以起点取顶部
            switch direction {
            case .horizontal:
                c.drawLinearGradient(gradient, start: CGPoint(x: 0, y: 0), end: CGPoint(x: w, y: 0), options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
            case .vertical:
                c.drawLinearGradient(gradient, start: CGPoint(x: 0, y: h), end: CGPoint(x: 0, y: 0), options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
            case .diagonal:
                let d = CGFloat(w + h) / 2
                c.drawLinearGradient(gradient, start: CGPoint(x: 0, y: h), end: CGPoint(x: d, y: CGFloat(h) - d), options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
            case .radial:
                let center = CGPoint(x: CGFloat(w) / 2, y: CGFloat(h) / 2)
                c.drawRadialGradient(gradient, startCenter: center, startRadius: 0, endCenter: center,
                                     endRadius: hypot(center.x, center.y), options: [.drawsAfterEndLocation])
            }
        }
        if let img { ctx.buffer = [img] }
    }
}

struct TextSegment {
    var text: String?
    var fontPath: String?
    var height: Int = 100
    var isBold = false
    var color: String = "black"
    var trim = false

    init(_ d: [String: Any]) {
        text = d["text"] as? String ?? (d["text"] as? NSNumber)?.stringValue
        fontPath = d["font_path"] as? String
        if let h = d["height"] as? NSNumber { height = h.intValue }
        else if let h = d["height"] as? String, let v = Double(h) { height = Int(v) }
        color = (d["color"] as? String) ?? "black"
        isBold = (d["is_bold"] as? Bool) ?? false
        trim = (d["trim"] as? Bool) ?? false
    }
}

struct RichTextGenerator: SUProcessor {
    let name = "rich_text"
    let category = "generator"

    static func generate(_ segment: TextSegment, env: SUEnvironment) throws -> CGImage? {
        let font = TextRaster.font(path: segment.fontPath, fontsDir: env.fontsDir)
        let text = (segment.text ?? "").isEmpty ? " " : segment.text!
        guard let image = TextRaster.render(text, font: font, color: RGBA.parse(segment.color) ?? .black) else { return nil }
        let pipeline: [[String: Any]] = [
            ["processor_name": "trim", "trim_top": segment.trim, "trim_bottom": segment.trim],
            ["processor_name": "resize", "height": segment.isBold ? Double(segment.height) * 1.13 : Double(segment.height)],
        ]
        return try SUPipeline.run(pipeline, env: env, initialBuffer: [image])
    }

    func process(_ ctx: SUContext) throws {
        if let img = try RichTextGenerator.generate(TextSegment(ctx.config), env: ctx.env) { ctx.buffer = [img] }
    }
}

struct MultiRichTextGenerator: SUProcessor {
    let name = "multi_rich_text"
    let category = "generator"

    func process(_ ctx: SUContext) throws {
        let segments = ((ctx.get("text_segments") as? [[String: Any]]) ?? []).map(TextSegment.init)
        let height = ctx.double("height").map { Int($0) } ?? 100
        var images: [CGImage] = []
        for var segment in segments {
            segment.height = height
            if let img = try RichTextGenerator.generate(segment, env: ctx.env) { images.append(img) }
        }
        guard !images.isEmpty else { return }
        var concat: [String: Any] = ["processor_name": "concat", "spacing": ctx.int("text_spacing", 0)]
        if let alignment = ctx.string("text_alignment") { concat["alignment"] = alignment }
        if let result = try SUPipeline.run([concat], env: ctx.env, initialBuffer: images) { ctx.buffer = [result] }
    }
}

struct ImageLoader: SUProcessor {
    let name = "image"
    let category = "generator"

    func process(_ ctx: SUContext) throws {
        if let path = ctx.get("path") as? String {
            ctx.buffer = [try ctx.env.loadImage(path)]
        } else if let paths = ctx.get("path") as? [String] {
            ctx.buffer = try paths.map { try ctx.env.loadImage($0) }
        }
    }
}

// MARK: - Mergers

struct AlignmentMerger: SUProcessor {
    let name = "alignment"
    let category = "merger"

    func process(_ ctx: SUContext) throws {
        var buffer = ctx.buffer
        guard !buffer.isEmpty else { return }
        let horizontal = SUAlignment.parse(ctx.string("horizontal_alignment"), default: .center)
        let vertical = SUAlignment.parse(ctx.string("vertical_alignment"), default: .center)
        let background = ctx.color("background", RGBA(r: 255, g: 255, b: 255, a: 0))
        let offsets: [[Int]] = ((ctx.json("offsets") as? [Any]) ?? []).map { item in
            ((item as? [Any]) ?? []).compactMap { ($0 as? NSNumber)?.intValue }
        }
        var weights = ((ctx.json("weights") as? [Any]) ?? []).compactMap { ($0 as? NSNumber)?.doubleValue }

        let maxW = buffer.map(\.width).max()!, maxH = buffer.map(\.height).max()!
        if !weights.isEmpty {
            weights += [Double](repeating: 0, count: max(0, buffer.count - weights.count))
            // Python sorted() 是稳定排序
            buffer = zip(weights, buffer).enumerated()
                .sorted { a, b in a.element.0 == b.element.0 ? a.offset < b.offset : a.element.0 < b.element.0 }
                .map { $0.element.1 }
        }
        let img = Raster.image(width: maxW, height: maxH, fill: background) { c in
            for (i, item) in buffer.enumerated() {
                let off = i < offsets.count && offsets[i].count >= 2 ? offsets[i] : [0, 0]
                let x = horizontal.offset(size: item.width, max: maxW) - off[0]
                let y = vertical.offset(size: item.height, max: maxH) - off[1]
                c.paste(item, x: x, y: y, canvasHeight: maxH)
            }
        }
        if let img { ctx.buffer = [img] }
    }
}

struct ConcatMerger: SUProcessor {
    let name = "concat"
    let category = "merger"

    func process(_ ctx: SUContext) throws {
        let images = ctx.buffer
        guard !images.isEmpty else { return }
        let alignment = SUAlignment.parse(ctx.string("alignment"), default: .end)
        let direction = SUDirection.parse(ctx.string("direction"), default: .horizontal)
        let spacing = ctx.int("spacing", 10)
        let background = ctx.color("background", RGBA(r: 255, g: 255, b: 255, a: 0))

        let horizontal = direction == .horizontal
        let width = horizontal ? images.map(\.width).reduce(0, +) + spacing * (images.count - 1) : images.map(\.width).max()!
        let height = horizontal ? images.map(\.height).max()! : images.map(\.height).reduce(0, +) + spacing * (images.count - 1)
        let img = Raster.image(width: width, height: height, fill: background) { c in
            var pos = 0
            for item in images {
                if horizontal {
                    c.paste(item, x: pos, y: alignment.offset(size: item.height, max: height), canvasHeight: height)
                    pos += item.width + spacing
                } else {
                    c.paste(item, x: alignment.offset(size: item.width, max: width), y: pos, canvasHeight: height)
                    pos += item.height + spacing
                }
            }
        }
        if let img { ctx.buffer = [img] }
    }
}
