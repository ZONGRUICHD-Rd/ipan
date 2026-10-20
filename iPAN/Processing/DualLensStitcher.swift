import CoreImage
import CoreImage.CIFilterBuiltins
import Vision

/// 测试功能：主摄 + 超广角同时曝光，拼成一张比主摄更宽的 65:24。
///
/// 思路：以主摄的像素密度为准建立画布，把超广角按焦距比放大铺满画布作为底图，
/// 主摄画面经过视觉配准（Vision 单应性配准）后贴到中间，羽化边缘 + 色彩匹配，
/// 最后按超广角能覆盖的宽度裁出 65:24。只能横持使用（输出的长边沿传感器长边、两颗镜头水平排列）。
enum DualLensStitcher {
    struct Result {
        let image: CIImage
        /// 主摄在成片中的四边形（调试用）
        let mainQuad: [CGPoint]
        let registration: String
    }

    static func stitch(wide: CIImage, ultraWide: CIImage, focalRatio: CGFloat, context: CIContext) throws -> Result {
        let wide = normalized(wide)
        let uw = normalized(ultraWide)
        guard wide.extent.width >= wide.extent.height else { throw ProcessingError.notLandscape }

        // 1. 超广角放大到主摄像素密度
        let k = focalRatio * wide.extent.width / uw.extent.width
        let canvas = uw.transformed(by: CGAffineTransform(scaleX: k, y: k))
        let canvasRect = canvas.extent
        let W = wide.extent.width, H = wide.extent.height
        let expected = CGRect(x: (canvasRect.width - W) / 2, y: (canvasRect.height - H) / 2, width: W, height: H)

        // 2. 配准：超广角对应区域 vs 主摄，在缩小图上做
        let (corners, method) = register(wide: wide, reference: canvas.cropped(to: expected), expected: expected, context: context)

        // 3. 主摄透视变换到画布
        let warp = CIFilter.perspectiveTransform()
        warp.inputImage = wide
        warp.bottomLeft = corners[0]
        warp.bottomRight = corners[1]
        warp.topRight = corners[2]
        warp.topLeft = corners[3]
        guard let warpedWide = warp.outputImage else { throw ProcessingError.render }

        // 4. 色彩匹配：用重叠区平均色给超广角做通道增益
        let probe = expected.insetBy(dx: W * 0.15, dy: H * 0.15)
        let gains = channelGains(from: canvas, to: warpedWide, in: probe, context: context)
        let matched = canvas.applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": CIVector(x: gains.r, y: 0, z: 0, w: 0),
            "inputGVector": CIVector(x: 0, y: gains.g, z: 0, w: 0),
            "inputBVector": CIVector(x: 0, y: 0, z: gains.b, w: 0),
            "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1),
        ])

        // 5. 羽化蒙版（同样做透视变换）
        let feather = W * 0.04
        let maskBase = CIImage(color: .white).cropped(to: wide.extent.insetBy(dx: feather, dy: feather))
            .composited(over: CIImage(color: .black).cropped(to: wide.extent))
            .applyingGaussianBlur(sigma: feather / 2.5)
            .cropped(to: wide.extent)
        let maskWarp = CIFilter.perspectiveTransform()
        maskWarp.inputImage = maskBase
        maskWarp.bottomLeft = corners[0]
        maskWarp.bottomRight = corners[1]
        maskWarp.topRight = corners[2]
        maskWarp.topLeft = corners[3]
        guard let mask = maskWarp.outputImage else { throw ProcessingError.render }

        let blend = CIFilter.blendWithMask()
        blend.inputImage = warpedWide
        blend.backgroundImage = matched
        blend.maskImage = mask
        guard let composed = blend.outputImage?.cropped(to: canvasRect) else { throw ProcessingError.render }

        // 6. 裁 65:24：宽度取超广角能覆盖的 98%
        var outW = (canvasRect.width * 0.98)
        var outH = outW / PanoramaFormat.ratio
        if outH > canvasRect.height * 0.98 {
            outH = canvasRect.height * 0.98
            outW = outH * PanoramaFormat.ratio
        }
        outW = (outW / 2).rounded(.down) * 2
        outH = (outH / 2).rounded(.down) * 2
        let out = CGRect(x: (canvasRect.midX - outW / 2).rounded(), y: (canvasRect.midY - outH / 2).rounded(), width: outW, height: outH)
        let final = composed.cropped(to: out).transformed(by: CGAffineTransform(translationX: -out.minX, y: -out.minY))
        let quad = corners.map { CGPoint(x: $0.x - out.minX, y: $0.y - out.minY) }
        return Result(image: final, mainQuad: quad, registration: method)
    }

    private static func normalized(_ image: CIImage) -> CIImage {
        image.transformed(by: CGAffineTransform(translationX: -image.extent.minX, y: -image.extent.minY))
    }

    /// 返回主摄四角在画布上的位置（左下、右下、右上、左上）
    private static func register(wide: CIImage, reference: CIImage, expected: CGRect, context: CIContext) -> ([CGPoint], String) {
        let W = wide.extent.width, H = wide.extent.height
        let identity = [CGPoint(x: expected.minX, y: expected.minY), CGPoint(x: expected.maxX, y: expected.minY),
                        CGPoint(x: expected.maxX, y: expected.maxY), CGPoint(x: expected.minX, y: expected.maxY)]

        let d = min(1, 1024 / W)
        let small = CGAffineTransform(scaleX: d, y: d)
        let floating = wide.transformed(by: small)
        let ref = reference.transformed(by: CGAffineTransform(translationX: -expected.minX, y: -expected.minY)).transformed(by: small)
        guard let floatingCG = context.createCGImage(floating, from: floating.extent.integral),
              let refCG = context.createCGImage(ref, from: ref.extent.integral) else { return (identity, "居中对齐") }

        let maxShift = W * 0.06
        func plausible(_ pts: [CGPoint]) -> Bool {
            zip(pts, identity).allSatisfy { hypot($0.x - $1.x, $0.y - $1.y) < maxShift }
        }

        // 单应性配准
        let homography = VNHomographicImageRegistrationRequest(targetedCGImage: floatingCG, options: [:])
        let handler = VNImageRequestHandler(cgImage: refCG, options: [:])
        if (try? handler.perform([homography])) != nil,
           let obs = homography.results?.first as? VNImageHomographicAlignmentObservation {
            let m = obs.warpTransform
            let local = [CGPoint(x: 0, y: 0), CGPoint(x: W, y: 0), CGPoint(x: W, y: H), CGPoint(x: 0, y: H)]
            let pts = local.map { p -> CGPoint in
                let v = m * SIMD3<Float>(Float(p.x * d), Float(p.y * d), 1)
                guard abs(v.z) > 1e-6 else { return .zero }
                return CGPoint(x: CGFloat(v.x / v.z) / d + expected.minX, y: CGFloat(v.y / v.z) / d + expected.minY)
            }
            if plausible(pts) { return (pts, "单应性配准") }
        }

        // 退回平移配准
        let translational = VNTranslationalImageRegistrationRequest(targetedCGImage: floatingCG, options: [:])
        if (try? handler.perform([translational])) != nil,
           let obs = translational.results?.first as? VNImageTranslationAlignmentObservation {
            let t = obs.alignmentTransform
            let dx = t.tx / d, dy = t.ty / d
            let pts = identity.map { CGPoint(x: $0.x + dx, y: $0.y + dy) }
            if plausible(pts) { return (pts, "平移配准") }
        }
        return (identity, "居中对齐")
    }

    private static func channelGains(from source: CIImage, to target: CIImage, in rect: CGRect, context: CIContext) -> (r: CGFloat, g: CGFloat, b: CGFloat) {
        func average(_ image: CIImage) -> [Float]? {
            let f = CIFilter.areaAverage()
            f.inputImage = image
            f.extent = rect
            guard let out = f.outputImage else { return nil }
            var px = [Float](repeating: 0, count: 4)
            context.render(out, toBitmap: &px, rowBytes: 16, bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
                           format: .RGBAf, colorSpace: nil)
            return px
        }
        guard let s = average(source), let t = average(target) else { return (1, 1, 1) }
        func gain(_ i: Int) -> CGFloat {
            guard s[i] > 0.001 else { return 1 }
            return CGFloat(min(1.25, max(0.8, t[i] / s[i])))
        }
        return (gain(0), gain(1), gain(2))
    }
}
