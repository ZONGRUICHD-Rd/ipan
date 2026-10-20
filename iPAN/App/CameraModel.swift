import AVFoundation
import SwiftUI

/// 界面状态 + 拍摄流程编排
@MainActor
final class CameraModel: ObservableObject {
    enum DevelopPhase: Equatable {
        case idle
        /// 快门帘：取景窗口短暂黑屏
        case curtain
        /// 负片显影中
        case developing
    }

    struct LastShot {
        let preview: UIImage
        let pixelSize: CGSize
        let focal: Int
        let note: String?
    }

    let settings: AppSettings
    let camera = CameraController()
    let renderer = PreviewRenderer()
    let previewState = PreviewState()

    @Published var mode: CaptureMode = .ipan
    @Published var developPhase: DevelopPhase = .idle
    @Published var developProgress: Double = 0
    @Published var developImage: UIImage?
    @Published var thumbnail: UIImage?
    @Published var lastShot: LastShot?
    @Published var processingCount = 0
    @Published var toast: String?
    @Published var focusPoint: CGPoint?

    private var toastTask: Task<Void, Never>?

    init(settings: AppSettings) {
        self.settings = settings
    }

    var plan: FocalPlan { camera.lineup.plan(for: settings.focal) }

    // MARK: 取景窗口

    /// 取景窗口在 3:4 取景器中所占比例（宽, 高）
    func window(isLandscape: Bool) -> CGSize {
        let longOnScreen = (PanoramaFormat.short / PanoramaFormat.long) * (4.0 / 3.0) // 竖向窄条的宽度占比
        switch mode {
        case .stitch:
            return CGSize(width: longOnScreen * 0.98, height: 0.98)
        case .ipan:
            if isLandscape || settings.portraitOutput == .portraitBand {
                return CGSize(width: longOnScreen, height: 1)
            }
            return CGSize(width: 1, height: (PanoramaFormat.short / PanoramaFormat.long) * (3.0 / 4.0))
        }
    }

    /// 拼接模式下主摄在超广角预览中的覆盖范围
    var mainCoverage: CGFloat { 1 / camera.dualWideFocalRatio() }

    // MARK: 生命周期

    func start() {
        camera.start(with: currentConfiguration)
        syncPreview()
    }

    var currentConfiguration: CameraConfiguration {
        mode == .stitch ? .dualWide : .lens(plan.lens)
    }

    func syncPreview() {
        var v = previewState.values
        v.cropScale = mode == .stitch ? 1 : plan.cropScale
        v.film = settings.filmMode
        v.palette = settings.palette
        v.vignette = settings.vignette
        v.window = window(isLandscape: camera.isLandscape)
        previewState.values = v
    }

    func select(focal: FocalLength) {
        guard focal != settings.focal || mode != .ipan else { return }
        settings.focal = focal
        if mode != .ipan { mode = .ipan }
        camera.configure(currentConfiguration)
        syncPreview()
        UISelectionFeedbackGenerator().selectionChanged()
    }

    func select(mode newMode: CaptureMode) {
        guard newMode != mode else { return }
        if newMode == .stitch && !camera.dualWideAvailable {
            showToast("这台设备没有超广角镜头")
            return
        }
        mode = newMode
        camera.configure(currentConfiguration)
        syncPreview()
        UISelectionFeedbackGenerator().selectionChanged()
    }

    func toggleFilm() {
        settings.filmMode = settings.filmMode == .color ? .mono : .color
        syncPreview()
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    // MARK: 对焦

    /// - Parameter normalized: 取景器内的点击位置（0…1）
    func focus(atNormalized normalized: CGPoint) {
        let cs = previewState.values.cropScale
        let u = 0.5 + (normalized.x - 0.5) * cs
        let v = 0.5 + (normalized.y - 0.5) * cs
        // 竖屏预览 → 传感器坐标（横向，原点左上）
        camera.focus(at: CGPoint(x: v, y: 1 - u))
        focusPoint = normalized
        Task {
            try? await Task.sleep(for: .seconds(1.2))
            if focusPoint == normalized { focusPoint = nil }
        }
    }

    // MARK: 拍摄

    var canShoot: Bool {
        camera.authorization == .authorized && processingCount < 2 && !(mode == .stitch && !camera.isLandscape)
    }

    func shutter() {
        guard canShoot else {
            if mode == .stitch && !camera.isLandscape { showToast("双摄拼接需要横置手机") }
            return
        }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        let window = window(isLandscape: camera.isLandscape)
        let snapshot = renderer.snapshot(window: window)
        let options = ProcessingOptions(
            plan: plan,
            film: settings.filmMode,
            palette: settings.palette,
            vignette: settings.vignette,
            portraitOutput: settings.portraitOutput,
            watermarkTemplate: settings.watermarkEnabled ? settings.watermarkTemplate : nil,
            saveOriginal: settings.saveOriginal
        )
        let captureMode = mode
        let focalRatio = camera.dualWideFocalRatio()
        processingCount += 1

        camera.capture(willCapture: { [weak self] in
            self?.runDevelopAnimation(snapshot)
        }, completion: { [weak self] result in
            guard let self else { return }
            switch result {
            case .failure(let error):
                self.processingCount -= 1
                self.showToast("拍摄失败：\(error.localizedDescription)")
            case .success(let photos):
                Task { await self.process(photos, mode: captureMode, options: options, focalRatio: focalRatio) }
            }
        })
    }

    private func process(_ photos: [AVCapturePhoto], mode: CaptureMode, options: ProcessingOptions, focalRatio: CGFloat) async {
        defer { processingCount -= 1 }
        do {
            let output = try await Task.detached(priority: .userInitiated) { () -> (ProcessedPhoto, Int, String?, Data?) in
                switch mode {
                case .ipan:
                    guard let photo = photos.first else { throw ProcessingError.decode }
                    let processed = try PhotoProcessor.process(photo: photo, options: options)
                    return (processed, options.plan.focal.millimeters, nil, options.saveOriginal ? photo.fileDataRepresentation() : nil)
                case .stitch:
                    let wide = photos.first { $0.sourceDeviceType == .builtInWideAngleCamera }
                    let uw = photos.first { $0.sourceDeviceType == .builtInUltraWideCamera }
                    guard let wide, let uw,
                          let wideImage = PhotoProcessor.orientedImage(from: wide),
                          let uwImage = PhotoProcessor.orientedImage(from: uw) else { throw ProcessingError.decode }
                    let stitched = try DualLensStitcher.stitch(wide: wideImage, ultraWide: uwImage, focalRatio: focalRatio,
                                                               context: PhotoProcessor.context)
                    let equivalent = Int((24 / (focalRatio * 0.98)).rounded())
                    var opts = options
                    opts.plan = FocalPlan(focal: FocalLength(millimeters: equivalent), lens: .main, nativeFocal: 24)
                    let info = CaptureInfo(metadata: wide.metadata, focal35mm: equivalent)
                    let processed = try PhotoProcessor.finish(stitched.image, metadata: wide.metadata, info: info, options: opts)
                    return (processed, equivalent, stitched.registration, nil)
                }
            }.value
            try await PhotoProcessor.saveToLibrary(output.0.heic, original: output.3)
            lastShot = LastShot(preview: output.0.preview, pixelSize: output.0.pixelSize, focal: output.1, note: output.2)
            if developPhase == .idle { thumbnail = output.0.preview }
            let px = output.0.pixelSize
            showToast("已保存 HEIC · \(Int(px.width))×\(Int(px.height))" + (output.2.map { " · \($0)" } ?? ""))
        } catch {
            showToast("处理失败：\(error.localizedDescription)")
        }
    }

    // MARK: 显影动画（仿 OPPO XPAN：快门帘 → 负片 → 显影成正片 → 飞入缩略图）

    private func runDevelopAnimation(_ snapshot: UIImage?) {
        guard settings.developAnimation, let snapshot else {
            if let snapshot { thumbnail = snapshot }
            return
        }
        developImage = snapshot
        developProgress = 0
        withAnimation(.easeIn(duration: 0.06)) { developPhase = .curtain }
        Task {
            try? await Task.sleep(for: .milliseconds(110))
            withAnimation(.easeOut(duration: 0.12)) { developPhase = .developing }
            withAnimation(.timingCurve(0.45, 0.05, 0.25, 1, duration: 1.35)) { developProgress = 1 }
            try? await Task.sleep(for: .milliseconds(1500))
            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
            withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) {
                developPhase = .idle
                thumbnail = lastShot?.preview ?? snapshot
            }
        }
    }

    // MARK: 提示

    func showToast(_ text: String) {
        toastTask?.cancel()
        withAnimation(.snappy) { toast = text }
        toastTask = Task {
            try? await Task.sleep(for: .seconds(2.2))
            guard !Task.isCancelled else { return }
            withAnimation(.snappy) { toast = nil }
        }
    }
}
