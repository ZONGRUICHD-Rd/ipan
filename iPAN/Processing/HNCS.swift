import CoreImage
import Foundation

/// 仿哈苏 HNCS（Hasselblad Natural Colour Solution）的色彩科学。
///
/// HNCS 的公开描述是：不按题材套不同的色彩配置，而是用同一套映射追求自然的颜色；
/// 重点是肤色的准确、细腻的影调过渡，以及配合 Hasselblad Film Curve 的影调曲线，
/// 不靠粗暴拉高饱和度和对比度。这里按这些特征做一张 3D LUT（在感知均匀的 OKLab / OKLCh 空间里调整）：
///
/// - 影调：柔和的 S 曲线 + 轻微抬起的趾部 + 高光柔和滚降（胶片曲线）
/// - 整体饱和度略低于手机默认，高饱和区做软压缩，保证渐变平滑不断层
/// - 肤色：色相向健康的橙黄收拢，略微提亮
/// - 红色稍浓；绿色压低饱和并偏向橄榄；天空蓝稍向青偏、略压暗；品紫收敛
/// - 高光和暗部逐渐去饱和，白平衡略暖
///
/// 这是根据公开描述做的风格复刻，不是哈苏的官方算法。
enum HNCS {
    static let cubeSize = 33

    /// 33³ RGBA Float32，Display P3（Gamma 编码）空间
    static let cubeData: Data = {
        let n = cubeSize
        var values = [Float](repeating: 0, count: n * n * n * 4)
        var i = 0
        for b in 0..<n {
            for g in 0..<n {
                for r in 0..<n {
                    let rgb = map(SIMD3(Double(r), Double(g), Double(b)) / Double(n - 1))
                    values[i] = Float(rgb.x)
                    values[i + 1] = Float(rgb.y)
                    values[i + 2] = Float(rgb.z)
                    values[i + 3] = 1
                    i += 4
                }
            }
        }
        return values.withUnsafeBufferPointer { Data(buffer: $0) }
    }()

    static let colorSpace = CGColorSpace(name: CGColorSpace.displayP3)!

    static func apply(_ input: CIImage) -> CIImage {
        input.applyingFilter("CIColorCubeWithColorSpace", parameters: [
            "inputCubeDimension": cubeSize,
            "inputCubeData": cubeData,
            "inputColorSpace": colorSpace,
        ])
    }

    // MARK: - 映射

    /// Display P3（Gamma）→ Display P3（Gamma）
    static func map(_ encoded: SIMD3<Double>) -> SIMD3<Double> {
        let linear = SIMD3(decode(encoded.x), decode(encoded.y), decode(encoded.z))
        var lab = oklab(fromLinearP3: linear)

        // 1. 影调（只动亮度，色相不变）
        let L0 = lab.x
        let L1 = filmCurve(L0)
        var C = (lab.y * lab.y + lab.z * lab.z).squareRoot()
        var h = atan2(lab.z, lab.y) * 180 / .pi
        if h < 0 { h += 360 }
        // 提亮的地方保留一点饱和度，压暗的地方相应收一点，避免发灰或发脏
        if L0 > 1e-4 { C *= min(1.15, max(0.85, pow(L1 / L0, 0.35))) }

        // 2. 分色相调整（高斯权重，色相环上平滑过渡）
        var chromaGain = 0.95
        var hueShift = 0.0
        var lightShift = 0.0

        let skin = weight(h, center: 58, width: 16)
        hueShift += skin * (58 - h) * 0.3
        chromaGain *= 1 + 0.05 * skin
        lightShift += 0.010 * skin

        let red = weight(h, center: 27, width: 14)
        chromaGain *= 1 + 0.05 * red

        let yellow = weight(h, center: 105, width: 18)
        chromaGain *= 1 - 0.04 * yellow

        let green = weight(h, center: 142, width: 32)
        chromaGain *= 1 - 0.12 * green
        hueShift -= 5 * green            // 向黄绿（橄榄）偏
        lightShift -= 0.010 * green

        let cyan = weight(h, center: 195, width: 20)
        chromaGain *= 1 - 0.08 * cyan

        let sky = weight(h, center: 248, width: 26)
        hueShift -= 4 * sky              // 天空蓝略偏青，不发紫
        lightShift -= 0.015 * sky

        let magenta = weight(h, center: 328, width: 30)
        chromaGain *= 1 - 0.12 * magenta

        C *= chromaGain
        h += hueShift
        var L = L1 + lightShift * min(1, C / 0.05)

        // 3. 高饱和软压缩（只压拐点以上）：渐变平滑，不断层
        let knee = 0.17, cMax = 0.34
        if C > knee { C = knee + (cMax - knee) * tanh((C - knee) / (cMax - knee)) }

        // 4. 高光、暗部逐渐去饱和
        C *= 1 - 0.6 * smoothstep(0.86, 1.0, L)
        C *= 0.85 + 0.15 * smoothstep(0.03, 0.15, L)

        L = min(1, max(0, L))
        let rad = h * .pi / 180
        // 5. 白平衡略暖（纯白保持纯白）
        let warm = 1 - smoothstep(0.9, 1.0, L)
        lab = SIMD3(L, C * cos(rad) + 0.0010 * warm, C * sin(rad) + 0.0040 * warm)

        // 6. 回到 P3，超出色域时收饱和度
        var out = linearP3(fromOklab: lab)
        var tries = 0
        while (out.min() < -0.0005 || out.max() > 1.0005) && tries < 8 {
            lab.y *= 0.88
            lab.z *= 0.88
            out = linearP3(fromOklab: lab)
            tries += 1
        }
        out = SIMD3(min(1, max(0, out.x)), min(1, max(0, out.y)), min(1, max(0, out.z)))
        return SIMD3(encode(out.x), encode(out.y), encode(out.z))
    }

    /// 中灰（18% 反射率）在 OKLab 中的亮度，S 曲线以它为支点，中间调亮度不变
    private static let midGrayL = 0.5656
    private static let pivotGamma = log(0.5) / log(midGrayL)

    /// Hasselblad Film Curve 风格：以中灰为支点的柔和 S 形 + 趾部轻微抬起 + 高光柔和滚降（白点不变）
    static func filmCurve(_ x: Double) -> Double {
        let u = pow(max(0, x), pivotGamma)
        let su = u - 0.16 * sin(2 * .pi * u) / (2 * .pi)
        let s = pow(max(0, su), 1 / pivotGamma)
        let toe = 0.012 * pow(1 - x, 4)
        let shoulder = x > 0.80 ? -0.012 * sin(.pi * (x - 0.80) / 0.20) : 0
        return min(1, max(0, s + toe + shoulder))
    }

    private static func weight(_ h: Double, center: Double, width: Double) -> Double {
        var d = abs(h - center).truncatingRemainder(dividingBy: 360)
        if d > 180 { d = 360 - d }
        return exp(-(d * d) / (2 * width * width))
    }

    private static func smoothstep(_ a: Double, _ b: Double, _ x: Double) -> Double {
        let t = min(1, max(0, (x - a) / (b - a)))
        return t * t * (3 - 2 * t)
    }

    // MARK: - 色彩空间

    static func decode(_ v: Double) -> Double {
        v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
    }

    static func encode(_ v: Double) -> Double {
        v <= 0.0031308 ? v * 12.92 : 1.055 * pow(v, 1 / 2.4) - 0.055
    }

    /// 线性 Display P3 → OKLab（经 XYZ D65）
    static func oklab(fromLinearP3 p: SIMD3<Double>) -> SIMD3<Double> {
        let x = 0.4865709 * p.x + 0.2656677 * p.y + 0.1982173 * p.z
        let y = 0.2289746 * p.x + 0.6917385 * p.y + 0.0792869 * p.z
        let z = 0.0000000 * p.x + 0.0451134 * p.y + 1.0439444 * p.z
        let l = cbrt(0.8189330101 * x + 0.3618667424 * y - 0.1288597137 * z)
        let m = cbrt(0.0329845436 * x + 0.9293118715 * y + 0.0361456387 * z)
        let s = cbrt(0.0482003018 * x + 0.2643662691 * y + 0.6338517070 * z)
        return SIMD3(0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s,
                     1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s,
                     0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s)
    }

    static func linearP3(fromOklab lab: SIMD3<Double>) -> SIMD3<Double> {
        let l_ = lab.x + 0.3963377774 * lab.y + 0.2158037573 * lab.z
        let m_ = lab.x - 0.1055613458 * lab.y - 0.0638541728 * lab.z
        let s_ = lab.x - 0.0894841775 * lab.y - 1.2914855480 * lab.z
        let l = l_ * l_ * l_, m = m_ * m_ * m_, s = s_ * s_ * s_
        let x = 1.2270138511 * l - 0.5577999807 * m + 0.2812561490 * s
        let y = -0.0405801784 * l + 1.1122568696 * m - 0.0716766787 * s
        let z = -0.0763812845 * l - 0.4214819784 * m + 1.5861632204 * s
        return SIMD3(2.4934969 * x - 0.9313836 * y - 0.4027108 * z,
                     -0.8294890 * x + 1.7626641 * y + 0.0236247 * z,
                     0.0358458 * x - 0.0761724 * y + 0.9568845 * z)
    }
}
