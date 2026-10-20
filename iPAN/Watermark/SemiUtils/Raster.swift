import CoreGraphics
import CoreImage
import CoreText
import Foundation
import ImageIO

/// semi-utils 里 PIL 操作的 CoreGraphics 对应实现。坐标一律按 PIL 习惯：原点在左上角。
enum Raster {
    static let colorSpace = CGColorSpace(name: CGColorSpace.displayP3) ?? CGColorSpaceCreateDeviceRGB()
    static let ciContext = CIContext(options: [.workingColorSpace: CGColorSpace(name: CGColorSpace.extendedLinearDisplayP3) as Any])

    /// RGBA（预乘）画布
    static func context(width: Int, height: Int, fill: RGBA? = nil) -> CGContext? {
        guard width > 0, height > 0,
              let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        ctx.interpolationQuality = .high
        if let fill {
            ctx.setFillColor(fill.cgColor)
            ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }
        return ctx
    }

    static func image(width: Int, height: Int, fill: RGBA, draw: ((CGContext) -> Void)? = nil) -> CGImage? {
        guard let ctx = context(width: max(1, width), height: max(1, height), fill: fill) else { return nil }
        draw?(ctx)
        return ctx.makeImage()
    }

    static func resize(_ image: CGImage, width: Int, height: Int) -> CGImage? {
        Raster.image(width: width, height: height, fill: .clear) { ctx in
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
    }

    /// PIL Image.crop(left, top, right, bottom)，越界部分透明
    static func crop(_ image: CGImage, left: Int, top: Int, right: Int, bottom: Int) -> CGImage? {
        let w = right - left, h = bottom - top
        return Raster.image(width: w, height: h, fill: .clear) { ctx in
            ctx.paste(image, x: -left, y: -top, canvasHeight: h)
        }
    }

    static func gaussianBlur(_ image: CGImage, sigma: Double) -> CGImage? {
        let input = CIImage(cgImage: image)
        let output = input.clampedToExtent().applyingGaussianBlur(sigma: sigma).cropped(to: input.extent)
        return ciContext.createCGImage(output, from: input.extent, format: .RGBA8, colorSpace: colorSpace)
    }

    static func load(path: String) -> CGImage? {
        let url = URL(fileURLWithPath: path)
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [kCGImageSourceShouldCacheImmediately: true]
        // 按 EXIF 方向摆正（对应 ImageOps.exif_transpose）
        let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any]
        let orientation = (props?[kCGImagePropertyOrientation] as? UInt32) ?? 1
        guard let cg = CGImageSourceCreateImageAtIndex(src, 0, options as CFDictionary) else { return nil }
        guard orientation != 1 else { return cg }
        let ci = CIImage(cgImage: cg).oriented(forExifOrientation: Int32(orientation))
        return ciContext.createCGImage(ci, from: ci.extent, format: .RGBA8, colorSpace: colorSpace)
    }

    /// 读出 RGBA8 预乘像素
    static func pixels(of image: CGImage) -> (data: [UInt8], width: Int, height: Int)? {
        let w = image.width, h = image.height
        var data = [UInt8](repeating: 0, count: w * h * 4)
        let ok: Bool = data.withUnsafeMutableBytes { buf in
            guard let ctx = CGContext(data: buf.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                      space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return false }
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        return ok ? (data, w, h) : nil
    }

    static func image(fromPixels data: [UInt8], width: Int, height: Int) -> CGImage? {
        // 由 CGContext 自己持有像素内存，避免 makeImage 引用已释放的缓冲区
        guard let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                  space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let dst = ctx.data, ctx.bytesPerRow == width * 4
        else { return nil }
        data.withUnsafeBytes { src in
            dst.copyMemory(from: src.baseAddress!, byteCount: min(src.count, width * height * 4))
        }
        return ctx.makeImage()
    }

    /// 铺到不透明背景上（对应最终保存前的 convert("RGB")）
    static func flatten(_ image: CGImage, background: RGBA = .white) -> CGImage? {
        guard let ctx = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: colorSpace, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
        else { return nil }
        ctx.setFillColor(background.cgColor)
        ctx.fill(CGRect(x: 0, y: 0, width: image.width, height: image.height))
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return ctx.makeImage()
    }
}

extension CGContext {
    /// PIL paste：以左上角为原点的坐标贴图（带 alpha 混合）
    func paste(_ image: CGImage, x: Int, y: Int, canvasHeight: Int) {
        draw(image, in: CGRect(x: x, y: canvasHeight - y - image.height, width: image.width, height: image.height))
    }
}

// MARK: - 颜色

struct RGBA: Equatable {
    var r: Double, g: Double, b: Double, a: Double // 0...255

    static let clear = RGBA(r: 0, g: 0, b: 0, a: 0)
    static let white = RGBA(r: 255, g: 255, b: 255, a: 255)
    static let black = RGBA(r: 0, g: 0, b: 0, a: 255)

    var cgColor: CGColor {
        CGColor(srgbRed: r / 255, green: g / 255, blue: b / 255, alpha: a / 255)
    }

    private static let named: [String: (Double, Double, Double)] = [
        "white": (255, 255, 255), "black": (0, 0, 0), "red": (255, 0, 0), "green": (0, 128, 0),
        "lime": (0, 255, 0), "blue": (0, 0, 255), "yellow": (255, 255, 0), "orange": (255, 165, 0),
        "gray": (128, 128, 128), "grey": (128, 128, 128), "silver": (192, 192, 192), "darkgray": (169, 169, 169),
        "lightgray": (211, 211, 211), "purple": (128, 0, 128), "pink": (255, 192, 203), "brown": (165, 42, 42),
        "cyan": (0, 255, 255), "magenta": (255, 0, 255), "navy": (0, 0, 128), "gold": (255, 215, 0),
        "transparent": (0, 0, 0),
    ]

    /// 对应 semi-utils 的 _parse_color：元组、'(r,g,b[,a])'、#RGB/#RRGGBB/#RRGGBBAA、颜色名
    static func parse(_ any: Any?) -> RGBA? {
        if let list = any as? [Any] {
            let v = list.compactMap { ($0 as? NSNumber)?.doubleValue }
            if v.count == 3 { return RGBA(r: v[0], g: v[1], b: v[2], a: 255) }
            if v.count == 4 { return RGBA(r: v[0], g: v[1], b: v[2], a: v[3]) }
            return nil
        }
        guard var s = (any as? String)?.trimmingCharacters(in: .whitespaces), !s.isEmpty else { return nil }
        let stripped = s.trimmingCharacters(in: CharacterSet(charactersIn: "()"))
        if stripped.contains(",") {
            let parts = stripped.split(separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
            if parts.count == 3 { return RGBA(r: parts[0], g: parts[1], b: parts[2], a: 255) }
            if parts.count == 4 { return RGBA(r: parts[0], g: parts[1], b: parts[2], a: parts[3]) }
        }
        s = s.lowercased()
        if s.hasPrefix("#") {
            let hex = String(s.dropFirst())
            func byte(_ str: Substring) -> Double { Double(Int(str, radix: 16) ?? 0) }
            switch hex.count {
            case 3, 4:
                let c = hex.map { Double(Int(String($0), radix: 16) ?? 0) * 17 }
                return RGBA(r: c[0], g: c[1], b: c[2], a: c.count == 4 ? c[3] : 255)
            case 6, 8:
                let chars = Array(hex)
                func at(_ i: Int) -> Double { byte(Substring(String(chars[i...i + 1]))) }
                return RGBA(r: at(0), g: at(2), b: at(4), a: hex.count == 8 ? at(6) : 255)
            default:
                return nil
            }
        }
        if let n = named[s] {
            return RGBA(r: n.0, g: n.1, b: n.2, a: s == "transparent" ? 0 : 255)
        }
        return nil
    }
}

// MARK: - 文字

enum TextRaster {
    /// semi-utils 的 BASE_FONT_SIZE
    static let baseFontSize: CGFloat = 512
    private static var fontCache: [String: CTFont] = [:]
    private static let lock = NSLock()

    static func font(path: String?, fontsDir: URL) -> CTFont {
        lock.lock(); defer { lock.unlock() }
        let candidates: [URL] = {
            if let path, !path.isEmpty {
                let url = path.hasPrefix("/") ? URL(fileURLWithPath: path) : fontsDir.appendingPathComponent(path)
                return [url]
            }
            return [fontsDir.appendingPathComponent("AlibabaPuHuiTi-2-45-Light.otf")]
        }()
        for url in candidates {
            if let cached = fontCache[url.path] { return cached }
            if let descriptors = CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [CTFontDescriptor],
               let first = descriptors.first {
                let font = CTFontCreateWithFontDescriptor(first, baseFontSize, nil)
                fontCache[url.path] = font
                return font
            }
        }
        // 模板引用了仓库里没有的字体（例如 SpecialAlphabets P04）时退回默认字体
        let fallback = fontsDir.appendingPathComponent("AlibabaPuHuiTi-2-45-Light.otf")
        if let cached = fontCache[fallback.path] { return cached }
        if let descriptors = CTFontManagerCreateFontDescriptorsFromURL(fallback as CFURL) as? [CTFontDescriptor],
           let first = descriptors.first {
            let font = CTFontCreateWithFontDescriptor(first, baseFontSize, nil)
            fontCache[fallback.path] = font
            return font
        }
        return CTFontCreateUIFontForLanguage(.system, baseFontSize, nil) ?? CTFontCreateWithName("Helvetica" as CFString, baseFontSize, nil)
    }

    /// 对应 RichTextGenerator 里的 draw.text：画布宽 = 文字宽，高 = ascent + descent
    static func render(_ text: String, font: CTFont, color: RGBA) -> CGImage? {
        let attributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): color.cgColor,
        ]
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attributes))
        let glyphBounds = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)
        let typographic = CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
        let ascent = CTFontGetAscent(font), descent = CTFontGetDescent(font)
        let width = Int(ceil(max(typographic, glyphBounds.maxX))) + 2
        let height = Int(ceil(ascent + descent))
        return Raster.image(width: max(1, width), height: max(1, height), fill: .clear) { ctx in
            ctx.textPosition = CGPoint(x: 0, y: descent)
            CTLineDraw(line, ctx)
        }
    }
}
