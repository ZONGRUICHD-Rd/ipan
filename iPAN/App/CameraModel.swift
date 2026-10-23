import AVFoundation
import UIKit
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
        /// 成片 HEIC 的临时文件，用于分享
        let fileURL: URL?
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
    /// 从灵动岛弹出的消息
    @Published var island: IslandMessage?
    /// 每次按快门 +1，驱动灵动岛的「快门」动效
    @Published var islandPulse = 0
    @Published var focusPoint: CGPoint?

    private var islandTask: Task<Void, Never>?

    init(settings: AppSettings) {
        self.settings = settings
        // 旧版本默认是「XPan 胶片」，升级后默认改为 HNCS（只迁移一次，之后尊重用户选择）
        let key = "migratedToHNCS"
        if !UserDefaults.standard.bool(forKey: key) {
            if settings.filmMode == .color { settings.filmMode = .hncs }
            UserDefaults.standard.set(true, forKey: key)
        }
    }

    var plan: FocalPlan { camera.lineup.plan(for: settings.focal) }

    // MARK: 取景窗口

    /// 65:24 取景窗口在全屏中的位置（0…1，原点左上），由界面布局计算后写入
    @Published private(set) var band = CGRect(x: 0.1, y: 0.3, width: 0.8, height: 0.3)

    /// 取景窗口宽高比。竖屏界面且设置为竖幅时是 24:65，其余都是 65:24。
    func bandRatio(isLandscapeUI: Bool) -> CGFloat {
        if mode == .ipan && !isLandscapeUI && settings.portraitOutput == .portraitBand {
            return PanoramaFormat.short / PanoramaFormat.long
        }
        return PanoramaFormat.ratio
    }

    /// 取景窗口覆盖的画面比例：拼接模式只用超广角宽度的 98%
    var bandSpan: CGFloat { mode == .stitch ? 0.98 : 1 }

    func updateBand(_ newBand: CGRect) {
        guard newBand != band else { return }
        band = newBand
        syncPreview()
    }

    /// 拼接模式下主摄在超广角预览中的覆盖范围（相对取景窗口的宽高比例）
    var mainCoverage: CGSize {
        let r = camera.dualWideFocalRatio()
        // 取景窗口宽度 = 超广角画面宽度 × 0.98；画面为 4:3
        let frameWidthInBands = 1 / bandSpan
        return CGSize(width: frameWidthInBands / r, height: frameWidthInBands * 0.75 * PanoramaFormat.ratio / r)
    }

    // MARK: 界面方向

    private var sceneObservation: NSKeyValueObservation?

    func observeInterfaceOrientation() {
        guard sceneObservation == nil,
              let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first
        else { return }
        sceneObservation = scene.observe(\.effectiveGeometry, options: [.initial, .new]) { [weak self] scene, _ in
            let orientation = scene.effectiveGeometry.interfaceOrientation
            DispatchQueue.main.async { self?.applyInterfaceOrientation(orientation) }
        }
    }

    /// LiveContainer 等容器里取不到方向时，用窗口宽高兜底
    func refreshInterfaceOrientation(fallbackSize size: CGSize) {
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        var orientation = scene?.effectiveGeometry.interfaceOrientation ?? .unknown
        if orientation == .unknown || orientation.isLandscape != (size.width > size.height) {
            orientation = size.width > size.height ? .landscapeRight : .portrait
        }
        applyInterfaceOrientation(orientation)
    }

    private func applyInterfaceOrientation(_ orientation: UIInterfaceOrientation) {
        camera.updateInterfaceOrientation(orientation)
        syncPreview()
    }

    // MARK: 生命周期

    /// 连续两次启动后没能稳定运行（多半是闪退）时，进入安全模式：跳过 Camera Control 与可变光圈这类依赖新系统接口的功能
    private static let unstableLaunchKey = "unstableLaunchCount"
    private(set) var safeMode = false

    func start() {
        let defaults = UserDefaults.standard
        let unstable = defaults.integer(forKey: Self.unstableLaunchKey)
        safeMode = unstable >= 2
        defaults.set(unstable + 1, forKey: Self.unstableLaunchKey)
        Task {
            // 稳定运行 8 秒视为启动成功
            try? await Task.sleep(for: .seconds(8))
            UserDefaults.standard.set(0, forKey: Self.unstableLaunchKey)
        }

        observeInterfaceOrientation()
        if SimulatorDemo.isActive {
            camera.frames.update(SimulatorDemo.frame())
            thumbnail = SimulatorDemo.thumbnail()
        }
        if safeMode {
            showToast("上次启动异常，已暂时关闭 Camera Control 与光圈", warning: true)
        } else {
            setupCameraControls()
            camera.setAperture(settings.aperture > 0 ? Float(settings.aperture) : nil)
        }
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
        v.band = band
        v.span = bandSpan
        previewState.values = v
    }

    func select(focal: FocalLength) {
        guard focal != settings.focal || mode != .ipan else { return }
        settings.focal = focal
        if mode != .ipan { mode = .ipan }
        camera.configure(currentConfiguration)
        syncPreview()
        syncCameraControls()
        UISelectionFeedbackGenerator().selectionChanged()
    }

    func select(mode newMode: CaptureMode) {
        guard newMode != mode else { return }
        if newMode == .stitch && !camera.dualWideAvailable {
            showToast("这台设备没有超广角镜头", warning: true)
            return
        }
        mode = newMode
        camera.configure(currentConfiguration)
        syncPreview()
        UISelectionFeedbackGenerator().selectionChanged()
    }

    func toggleFilm() {
        setFilm(settings.filmMode.next)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    func setFilm(_ film: FilmMode) {
        settings.filmMode = film
        syncPreview()
        syncCameraControls()
    }

    // MARK: 可变光圈

    /// nil = 自动。光圈优先：锁定光圈，快门与 ISO 自动。
    func setAperture(_ value: Float?, fromControl: Bool = false) {
        guard !safeMode else { return }
        settings.aperture = Double(value ?? 0)
        camera.setAperture(value)
        if !fromControl { UISelectionFeedbackGenerator().selectionChanged() }
    }

    // MARK: 相机控制（Camera Control 按键）

    /// 轻按 Camera Control 弹出的控件：焦段、曝光补偿（系统）、色彩。完全按下由界面的 onCameraCaptureEvent 触发快门。
    private func setupCameraControls() {
        let focals = FocalLength.all
        let films = FilmMode.allCases
        camera.setupCameraControls(
            focalTitles: focals.map { "\($0.millimeters)mm" },
            focalIndex: focals.firstIndex(of: settings.focal) ?? 0,
            lookTitles: films.map(\.title),
            lookIndex: films.firstIndex(of: settings.filmMode) ?? 0,
            onFocal: { [weak self] index in
                guard let self, focals.indices.contains(index) else { return }
                self.select(focal: focals[index])
                let lens = self.plan.lens == .main ? "主摄" : "长焦"
                self.announce(IslandMessage(kind: .info, title: "\(focals[index].millimeters)mm",
                                            detail: "\(lens) · 65:24", symbol: "camera.aperture"))
            },
            onLook: { [weak self] index in
                guard let self, films.indices.contains(index) else { return }
                self.setFilm(films[index])
                self.announce(IslandMessage(kind: .info, title: films[index].title, symbol: "camera.filters"))
            },
            onAperture: { [weak self] value in
                guard let self else { return }
                self.setAperture(value, fromControl: true)
                self.announce(IslandMessage(kind: .info, title: value.map { "ƒ" + VariableAperture.label($0) } ?? "光圈自动",
                                            detail: "光圈优先 · 快门与 ISO 自动", symbol: "camera.aperture"))
            }
        )
    }

    /// 界面上改了焦段 / 色彩后，同步到 Camera Control 的选中项
    func syncCameraControls() {
        camera.syncControls(focalIndex: FocalLength.all.firstIndex(of: settings.focal),
                            lookIndex: FilmMode.allCases.firstIndex(of: settings.filmMode))
    }

    // MARK: 对焦

    /// - Parameters:
    ///   - point: 点击位置（全屏归一化坐标，原点左上）
    ///   - screen: 全屏尺寸（点）
    func focus(at point: CGPoint, screen: CGSize) {
        guard band.width > 0, band.height > 0 else { return }
        // 取景窗口对应画面的长边（横窗口对应宽度），由此换算出点击点在整幅画面中的位置
        let bandPx = CGSize(width: band.width * screen.width, height: band.height * screen.height)
        let frameAspect: CGFloat = camera.isLandscape ? 3.0 / 4.0 : 4.0 / 3.0 // 高 / 宽
        let frameW = (bandPx.width >= bandPx.height ? bandPx.width : bandPx.height / frameAspect) / bandSpan
        let frameH = frameW * frameAspect
        let dx = (point.x - band.midX) * screen.width / frameW
        let dy = (point.y - band.midY) * screen.height / frameH
        let cs = previewState.values.cropScale
        let u = min(1, max(0, 0.5 + dx * cs)), v = min(1, max(0, 0.5 + dy * cs))
        // 界面坐标 → 传感器坐标（landscapeRight 方向，原点左上）
        let device: CGPoint
        switch camera.interfaceOrientation {
        case .landscapeLeft: device = CGPoint(x: 1 - u, y: 1 - v)
        case .portrait: device = CGPoint(x: v, y: 1 - u)
        case .portraitUpsideDown: device = CGPoint(x: 1 - v, y: u)
        default: device = CGPoint(x: u, y: v)
        }
        camera.focus(at: device)
        focusPoint = point
        Task {
            try? await Task.sleep(for: .seconds(1.2))
            if focusPoint == point { focusPoint = nil }
        }
    }

    // MARK: 拍摄

    var canShoot: Bool {
        camera.authorization == .authorized && processingCount < 2 && !(mode == .stitch && !camera.isLandscape)
    }

    func shutter() {
        guard canShoot else {
            if mode == .stitch && !camera.isLandscape { showToast("双摄拼接需要横置手机", warning: true) }
            return
        }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        let snapshot = renderer.snapshot(band: band)
        let options = ProcessingOptions(
            plan: plan,
            film: settings.filmMode,
            palette: settings.palette,
            vignette: settings.vignette,
            portraitOutput: settings.portraitOutput,
            watermarkTemplate: settings.watermarkEnabled ? settings.watermarkTemplate : nil,
            watermarkLogo: settings.watermarkLogo,
            saveOriginal: settings.saveOriginal
        )
        let captureMode = mode
        let focalRatio = camera.dualWideFocalRatio()
        processingCount += 1
        let detail = "\(captureMode == .stitch ? "WIDE" : "\(plan.focal.millimeters)mm") · \(settings.filmMode.caption)"

        camera.capture(willCapture: { [weak self] in
            guard let self else { return }
            self.islandPulse &+= 1
            self.runDevelopAnimation(snapshot)
            // 显影动画结束后还没冲洗完，就在灵动岛里显示进度
            Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(1700))
                guard let self, self.processingCount > 0, self.island == nil || self.island?.kind == .info else { return }
                self.announce(IslandMessage(kind: .processing, title: "冲洗中", detail: detail, image: snapshot))
            }
        }, completion: { [weak self] result in
            guard let self else { return }
            switch result {
            case .failure(let error):
                self.processingCount -= 1
                self.showToast("拍摄失败：\(error.localizedDescription)", warning: true)
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
            let fileURL = Self.writeShareFile(output.0.heic)
            lastShot = LastShot(preview: output.0.preview, pixelSize: output.0.pixelSize, focal: output.1, note: output.2, fileURL: fileURL)
            if developPhase == .idle { thumbnail = output.0.preview }
            let px = output.0.pixelSize
            let megapixels = px.width * px.height / 1_000_000
            announce(IslandMessage(kind: .saved, title: "已存入相册",
                                   detail: String(format: "HEIC · %ld×%ld · %.1fMP", Int(px.width), Int(px.height), megapixels)
                                       + (output.2.map { "\n拼接：\($0)" } ?? ""),
                                   image: output.0.preview))
        } catch {
            showToast("处理失败：\(error.localizedDescription)", warning: true)
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

    // MARK: 灵动岛消息

    /// 显示一条从灵动岛弹出的消息；有时长的消息到时自动收回
    func announce(_ message: IslandMessage) {
        islandTask?.cancel()
        island = message
        guard let duration = message.duration else { return }
        let id = message.id
        islandTask = Task {
            try? await Task.sleep(for: .seconds(duration))
            guard !Task.isCancelled, self.island?.id == id else { return }
            self.island = nil
        }
    }

    func dismissIsland() {
        islandTask?.cancel()
        island = nil
    }

    func showToast(_ text: String, warning: Bool = false) {
        announce(IslandMessage(kind: warning ? .warning : .info, title: text))
    }

    /// 把成片写到临时目录，供分享使用（只保留最近一张）
    private static func writeShareFile(_ data: Data) -> URL? {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("share", isDirectory: true)
        try? FileManager.default.removeItem(at: dir)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        let url = dir.appendingPathComponent("iPAN_\(formatter.string(from: Date())).heic")
        do {
            try data.write(to: url)
            return url
        } catch {
            return nil
        }
    }
}
