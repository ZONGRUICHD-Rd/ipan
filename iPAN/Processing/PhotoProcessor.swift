import AVFoundation
import CoreImage
import ImageIO
import Photos
import UIKit
import UniformTypeIdentifiers

/// 一次拍摄时的参数快照（拍摄后在后台处理，不受界面后续改动影响）
struct ProcessingOptions {
    var plan: FocalPlan
    var film: FilmMode
    var palette: PaletteSettings
    var vignette: Bool
    var portraitOutput: PortraitOutput
    var watermarkTemplate: String?
    var watermarkLogo: Bool = false
    var saveOriginal: Bool
}

struct ProcessedPhoto {
    let heic: Data
    let preview: UIImage
    let pixelSize: CGSize
}

enum ProcessingError: LocalizedError {
    case decode, render, encode, notLandscape

    var errorDescription: String? {
        switch self {
        case .decode: return "无法解码照片"
        case .render: return "渲染失败"
        case .encode: return "HEIC 编码失败"
        case .notLandscape: return "拼接模式需要横持手机"
        }
    }
}

enum PhotoProcessor {
    static let context = CIContext(options: [
        .workingColorSpace: CGColorSpace(name: CGColorSpace.extendedLinearDisplayP3) as Any,
        .cacheIntermediates: false,
    ])
    static let outputColorSpace = CGColorSpace(name: CGColorSpace.displayP3)!

    /// 已摆正（按 EXIF 方向）的 CIImage
    static func orientedImage(from photo: AVCapturePhoto) -> CIImage? {
        if let data = photo.fileDataRepresentation(),
           let image = CIImage(data: data, options: [.applyOrientationProperty: true]) {
            return image
        }
        if let buffer = photo.pixelBuffer {
            let orientation = (photo.metadata[kCGImagePropertyOrientation as String] as? NSNumber)?.int32Value ?? 1
            return CIImage(cvPixelBuffer: buffer).oriented(forExifOrientation: orientation)
        }
        return nil
    }

    /// 65:24 的裁切框（像素坐标，CI 坐标系）。横持时用传感器长边；竖持按设置输出横幅或竖幅。
    static func panoramaRect(in extent: CGRect, cropScale: CGFloat, portraitOutput: PortraitOutput) -> CGRect {
        let w = extent.width, h = extent.height
        var size: CGSize
        if w >= h {
            let long = w * cropScale
            size = CGSize(width: long, height: long / PanoramaFormat.ratio)
        } else if portraitOutput == .landscapeBand {
            let long = w * cropScale
            size = CGSize(width: long, height: long / PanoramaFormat.ratio)
        } else {
            let long = h * cropScale
            size = CGSize(width: long / PanoramaFormat.ratio, height: long)
        }
        // 偶数像素，避免编码器边缘填充
        size.width = (size.width / 2).rounded(.down) * 2
        size.height = (size.height / 2).rounded(.down) * 2
        return CGRect(x: (extent.midX - size.width / 2).rounded(), y: (extent.midY - size.height / 2).rounded(),
                      width: size.width, height: size.height)
    }

    /// 普通 iPAN：单颗镜头全像素画面 → 65:24 裁切 → 胶片/调色盘 → 水印 → HEIC
    static func process(photo: AVCapturePhoto, options: ProcessingOptions) throws -> ProcessedPhoto {
        guard let oriented = orientedImage(from: photo) else { throw ProcessingError.decode }
        let image = oriented.transformed(by: CGAffineTransform(translationX: -oriented.extent.minX, y: -oriented.extent.minY))
        let rect = panoramaRect(in: image.extent, cropScale: options.plan.cropScale, portraitOutput: options.portraitOutput)
        let cropped = image.cropped(to: rect).transformed(by: CGAffineTransform(translationX: -rect.minX, y: -rect.minY))
        let info = CaptureInfo(metadata: photo.metadata, focal35mm: options.plan.focal.millimeters)
        return try finish(cropped, metadata: photo.metadata, info: info, options: options)
    }

    static func finish(_ image: CIImage, metadata: [String: Any], info: CaptureInfo, options: ProcessingOptions) throws -> ProcessedPhoto {
        let looked = FilmLook.apply(image, film: options.film, palette: options.palette, vignette: options.vignette)
        guard var cg = context.createCGImage(looked, from: image.extent, format: .RGBA8, colorSpace: outputColorSpace) else {
            throw ProcessingError.render
        }
        if let template = options.watermarkTemplate {
            do {
                cg = try WatermarkService.apply(template: template, to: cg, info: info, showLogo: options.watermarkLogo)
            } catch {
                print("[iPAN] 水印失败: \(error)")
            }
        }
        let heic = try encodeHEIC(cg, metadata: metadata, focal35mm: options.plan.focal.millimeters)
        let preview = UIImage(cgImage: downscale(cg, maxSide: 1600) ?? cg)
        return ProcessedPhoto(heic: heic, preview: preview, pixelSize: CGSize(width: cg.width, height: cg.height))
    }

    /// 苹果原生 HEIC，保留原始 EXIF，并更新尺寸 / 方向 / 等效焦距
    static func encodeHEIC(_ image: CGImage, metadata: [String: Any], focal35mm: Int, quality: Double = 0.92) throws -> Data {
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(data, UTType.heic.identifier as CFString, 1, nil) else {
            throw ProcessingError.encode
        }
        var props = metadata
        props[kCGImagePropertyOrientation as String] = 1
        props[kCGImagePropertyPixelWidth as String] = image.width
        props[kCGImagePropertyPixelHeight as String] = image.height
        var exif = props[kCGImagePropertyExifDictionary as String] as? [String: Any] ?? [:]
        exif[kCGImagePropertyExifPixelXDimension as String] = image.width
        exif[kCGImagePropertyExifPixelYDimension as String] = image.height
        exif[kCGImagePropertyExifFocalLenIn35mmFilm as String] = focal35mm
        props[kCGImagePropertyExifDictionary as String] = exif
        var tiff = props[kCGImagePropertyTIFFDictionary as String] as? [String: Any] ?? [:]
        tiff[kCGImagePropertyTIFFOrientation as String] = 1
        tiff[kCGImagePropertyTIFFSoftware as String] = "iPAN"
        props[kCGImagePropertyTIFFDictionary as String] = tiff
        props[kCGImageDestinationLossyCompressionQuality as String] = quality
        CGImageDestinationAddImage(dest, image, props as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { throw ProcessingError.encode }
        return data as Data
    }

    static func downscale(_ image: CGImage, maxSide: CGFloat) -> CGImage? {
        let scale = min(1, maxSide / CGFloat(max(image.width, image.height)))
        guard scale < 1 else { return image }
        let ci = CIImage(cgImage: image).transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        return context.createCGImage(ci, from: ci.extent.integral, format: .RGBA8, colorSpace: outputColorSpace)
    }

    static func saveToLibrary(_ data: Data, original: Data? = nil) async throws {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else {
            throw NSError(domain: "iPAN", code: 1, userInfo: [NSLocalizedDescriptionKey: "没有相册写入权限"])
        }
        try await PHPhotoLibrary.shared().performChanges {
            PHAssetCreationRequest.forAsset().addResource(with: .photo, data: data, options: nil)
            if let original {
                PHAssetCreationRequest.forAsset().addResource(with: .photo, data: original, options: nil)
            }
        }
    }
}
