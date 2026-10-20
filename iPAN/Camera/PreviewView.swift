import CoreImage
import MetalKit
import SwiftUI

/// 预览渲染参数（SwiftUI 写入，渲染线程读取）
final class PreviewState {
    struct Values {
        var cropScale: CGFloat = 1
        var film: FilmMode = .color
        var palette = PaletteSettings()
        var vignette = true
        /// 取景窗口在视图中的尺寸（0…1 的比例），用于让暗角以取景窗口为中心
        var window = CGSize(width: 1, height: 1)
    }

    private let lock = NSLock()
    private var _values = Values()

    var values: Values {
        get { lock.lock(); defer { lock.unlock() }; return _values }
        set { lock.lock(); _values = newValue; lock.unlock() }
    }
}

/// 用 Core Image + Metal 渲染相机帧：数码裁切出 28/35/48/200mm 视角，并实时套用胶片模式和调色盘，所见即所得。
struct CameraPreview: UIViewRepresentable {
    let frames: FrameStore
    let state: PreviewState
    let renderer: PreviewRenderer

    func makeUIView(context: Context) -> MTKView {
        let view = MTKView(frame: .zero, device: renderer.device)
        view.framebufferOnly = false
        view.colorPixelFormat = .bgra8Unorm
        view.preferredFramesPerSecond = 60
        view.isOpaque = true
        view.backgroundColor = .black
        view.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        view.delegate = renderer
        renderer.attach(frames: frames, state: state)
        return view
    }

    func updateUIView(_ uiView: MTKView, context: Context) {}
}

final class PreviewRenderer: NSObject, MTKViewDelegate {
    let device: MTLDevice?
    private let queue: MTLCommandQueue?
    private let context: CIContext
    private weak var frames: FrameStore?
    private var state: PreviewState?
    private let lock = NSLock()
    private var lastRendered: CIImage?
    private var lastDrawableSize: CGSize = .zero

    override init() {
        device = MTLCreateSystemDefaultDevice()
        queue = device?.makeCommandQueue()
        if let device {
            context = CIContext(mtlDevice: device, options: [.cacheIntermediates: false, .name: "ipan.preview"])
        } else {
            context = CIContext()
        }
        super.init()
    }

    func attach(frames: FrameStore, state: PreviewState) {
        self.frames = frames
        self.state = state
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        guard let frame = frames?.latest, let drawable = view.currentDrawable,
              let buffer = queue?.makeCommandBuffer() else { return }
        let values = state?.values ?? PreviewState.Values()
        let size = view.drawableSize
        let image = compose(frame, values: values, drawableSize: size)

        let destination = CIRenderDestination(width: Int(size.width), height: Int(size.height),
                                              pixelFormat: view.colorPixelFormat, commandBuffer: buffer,
                                              mtlTextureProvider: { drawable.texture })
        _ = try? context.startTask(toRender: image, to: destination)
        buffer.present(drawable)
        buffer.commit()

        lock.lock()
        lastRendered = image
        lastDrawableSize = size
        lock.unlock()
    }

    /// 帧（竖屏方向）→ 中心裁切（焦段）→ 缩放到画面 → 风格 → 暗角
    private func compose(_ frame: CIImage, values: PreviewState.Values, drawableSize: CGSize) -> CIImage {
        let e = frame.extent
        let cs = max(0.05, min(1, values.cropScale))
        let crop = CGRect(x: e.midX - e.width * cs / 2, y: e.midY - e.height * cs / 2, width: e.width * cs, height: e.height * cs)
        let scale = max(drawableSize.width / crop.width, drawableSize.height / crop.height)
        let tx = (drawableSize.width - crop.width * scale) / 2
        let ty = (drawableSize.height - crop.height * scale) / 2
        var image = frame.cropped(to: crop)
            .transformed(by: CGAffineTransform(translationX: -crop.minX, y: -crop.minY))
            .transformed(by: CGAffineTransform(scaleX: scale, y: scale))
            .transformed(by: CGAffineTransform(translationX: tx, y: ty))
            .cropped(to: CGRect(origin: .zero, size: drawableSize))
        image = FilmLook.applyPalette(image, values.palette)
        image = FilmLook.applyFilm(image, values.film)
        if values.vignette {
            let window = CGSize(width: drawableSize.width * values.window.width, height: drawableSize.height * values.window.height)
            let v = CIFilter(name: "CIVignetteEffect", parameters: [
                kCIInputImageKey: image,
                kCIInputCenterKey: CIVector(x: drawableSize.width / 2, y: drawableSize.height / 2),
                kCIInputRadiusKey: hypot(window.width, window.height) * 0.42,
                kCIInputIntensityKey: 0.45,
                "inputFalloff": 0.6,
            ])
            image = v?.outputImage?.cropped(to: CGRect(origin: .zero, size: drawableSize)) ?? image
        }
        return image
    }

    /// 截取当前取景窗口内的画面，用于快门后的负片显影动画
    func snapshot(window: CGSize, maxSide: CGFloat = 1200) -> UIImage? {
        lock.lock()
        let image = lastRendered
        let size = lastDrawableSize
        lock.unlock()
        guard let image, size.width > 0 else { return nil }
        let w = size.width * window.width, h = size.height * window.height
        let rect = CGRect(x: (size.width - w) / 2, y: (size.height - h) / 2, width: w, height: h).integral
        let s = min(1, maxSide / max(rect.width, rect.height))
        let out = image.cropped(to: rect)
            .transformed(by: CGAffineTransform(translationX: -rect.minX, y: -rect.minY))
            .transformed(by: CGAffineTransform(scaleX: s, y: s))
        guard let cg = context.createCGImage(out, from: out.extent.integral) else { return nil }
        return UIImage(cgImage: cg)
    }
}
