import AVFoundation
import CoreImage
import SwiftUI
import UIKit

/// 预览帧缓存：视频线程写入，Metal 渲染线程读取
final class FrameStore {
    private let lock = NSLock()
    private var image: CIImage?
    private(set) var generation = 0

    var latest: CIImage? {
        lock.lock(); defer { lock.unlock() }
        return image
    }

    func update(_ newImage: CIImage) {
        lock.lock()
        image = newImage
        generation &+= 1
        lock.unlock()
    }
}

/// 会话配置：普通 iPAN 用单颗物理镜头；拼接测试用「双广角」虚拟设备（主摄 + 超广角同步曝光）
enum CameraConfiguration: Equatable {
    case lens(PhysicalLens)
    case dualWide
}

final class CameraController: NSObject, ObservableObject {
    enum Authorization { case unknown, authorized, denied }

    @Published private(set) var authorization: Authorization = .unknown
    @Published private(set) var configuration: CameraConfiguration?
    @Published private(set) var isSwitching = false
    /// 界面方向。预览与成片都以界面方向为准，保证取景窗口里看到的就是输出的画面。
    @Published private(set) var interfaceOrientation: UIInterfaceOrientation = .landscapeRight
    var isLandscape: Bool { interfaceOrientation.isLandscape }
    @Published private(set) var photoDimensions: CMVideoDimensions?
    @Published private(set) var dualWideAvailable = false
    @Published private(set) var lastError: String?
    /// Camera Control 的控件是否全屏展开（展开时界面收起）
    @Published private(set) var controlsFullscreen = false

    let session = AVCaptureSession()
    let frames = FrameStore()
    let lineup = LensLineup.discover()

    private let sessionQueue = DispatchQueue(label: "ipan.session")
    private let videoQueue = DispatchQueue(label: "ipan.video", qos: .userInteractive)
    private let photoOutput = AVCapturePhotoOutput()
    private let videoOutput = AVCaptureVideoDataOutput()
    private var input: AVCaptureDeviceInput?
    /// 只在 sessionQueue 上读写
    private var rotationAngle: CGFloat = 0
    private var inFlight: [Int64: PhotoCaptureDelegate] = [:]
    // Camera Control 控件（只在 sessionQueue 上访问）
    private var focalPicker: AVCaptureIndexPicker?
    private var lookPicker: AVCaptureIndexPicker?
    private var exposureSlider: AVCaptureSystemExposureBiasSlider?

    var currentDevice: AVCaptureDevice? { input?.device }

    override init() {
        super.init()
        dualWideAvailable = AVCaptureDevice.default(.builtInDualWideCamera, for: .video, position: .back) != nil
    }

    // MARK: 权限 & 启动

    func start(with configuration: CameraConfiguration) {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            authorization = .authorized
            configure(configuration)
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async {
                    self.authorization = granted ? .authorized : .denied
                    if granted { self.configure(configuration) }
                }
            }
        default:
            authorization = .denied
        }
    }

    func stop() {
        sessionQueue.async {
            if self.session.isRunning { self.session.stopRunning() }
        }
    }

    func resume() {
        sessionQueue.async {
            if !self.session.isRunning && self.input != nil { self.session.startRunning() }
        }
    }

    // MARK: 配置

    func configure(_ configuration: CameraConfiguration) {
        guard authorization == .authorized else { return }
        if configuration == self.configuration && session.isRunning { return }
        isSwitching = true
        sessionQueue.async {
            let result = self.applyConfiguration(configuration)
            if !self.session.isRunning { self.session.startRunning() }
            DispatchQueue.main.async {
                self.configuration = configuration
                self.photoDimensions = self.photoOutput.maxPhotoDimensions
                self.lastError = result
                // 留一点时间给新镜头出第一帧，配合界面的模糊过渡
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) { self.isSwitching = false }
            }
        }
    }

    /// 返回错误描述（nil 表示成功）。在 sessionQueue 上调用。
    private func applyConfiguration(_ configuration: CameraConfiguration) -> String? {
        let device: AVCaptureDevice?
        switch configuration {
        case .lens(let lens):
            device = AVCaptureDevice.default(lens.deviceType, for: .video, position: .back)
                ?? AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
        case .dualWide:
            device = AVCaptureDevice.default(.builtInDualWideCamera, for: .video, position: .back)
        }
        guard let device else { return "找不到可用的摄像头" }

        session.beginConfiguration()
        defer { session.commitConfiguration() }

        if let input { session.removeInput(input) }
        input = nil
        session.sessionPreset = .photo

        do {
            let newInput = try AVCaptureDeviceInput(device: device)
            guard session.canAddInput(newInput) else { return "无法添加摄像头输入" }
            session.addInput(newInput)
            input = newInput
        } catch {
            return error.localizedDescription
        }

        if !session.outputs.contains(photoOutput), session.canAddOutput(photoOutput) {
            session.addOutput(photoOutput)
        }
        if !session.outputs.contains(videoOutput), session.canAddOutput(videoOutput) {
            videoOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
            videoOutput.alwaysDiscardsLateVideoFrames = true
            videoOutput.setSampleBufferDelegate(self, queue: videoQueue)
            session.addOutput(videoOutput)
        }

        let isDual = configuration == .dualWide
        if photoOutput.isVirtualDeviceConstituentPhotoDeliverySupported {
            photoOutput.isVirtualDeviceConstituentPhotoDeliveryEnabled = isDual
        }

        // 48MP：选一个支持最大照片尺寸的 4:3 格式
        selectBestPhotoFormat(for: device, preferMaxResolution: !isDual)
        let dims = device.activeFormat.supportedMaxPhotoDimensions
        if isDual {
            // 双摄同步出图时用 12MP 档（成片按主摄像素密度拼接，最终约 20MP）
            let target = dims.min { abs(Int($0.width) - 4032) < abs(Int($1.width) - 4032) }
            if let target { photoOutput.maxPhotoDimensions = target }
        } else if let largest = dims.max(by: { Int($0.width) * Int($0.height) < Int($1.width) * Int($1.height) }) {
            photoOutput.maxPhotoDimensions = largest
        }
        photoOutput.maxPhotoQualityPrioritization = .quality

        if let connection = videoOutput.connection(with: .video) {
            if connection.isVideoRotationAngleSupported(rotationAngle) { connection.videoRotationAngle = rotationAngle }
            if connection.isVideoMirroringSupported { connection.isVideoMirrored = false }
        }

        installControls(for: device)

        do {
            try device.lockForConfiguration()
            if device.isFocusModeSupported(.continuousAutoFocus) { device.focusMode = .continuousAutoFocus }
            if device.isExposureModeSupported(.continuousAutoExposure) { device.exposureMode = .continuousAutoExposure }
            if isDual { device.videoZoomFactor = 1 } // 双广角虚拟设备 1x = 超广角视野
            device.unlockForConfiguration()
        } catch {}
        return nil
    }

    private func selectBestPhotoFormat(for device: AVCaptureDevice, preferMaxResolution: Bool) {
        func area(_ d: CMVideoDimensions) -> Int { Int(d.width) * Int(d.height) }
        let currentMax = device.activeFormat.supportedMaxPhotoDimensions.map(area).max() ?? 0
        guard preferMaxResolution, currentMax < 40_000_000 else { return }
        let candidates = device.formats.filter { format in
            let d = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
            let ratio = Double(d.width) / Double(max(1, d.height))
            return abs(ratio - 4.0 / 3.0) < 0.02 && format.videoSupportedFrameRateRanges.contains { $0.maxFrameRate >= 29 }
        }
        let best = candidates.max { a, b in
            let pa = a.supportedMaxPhotoDimensions.map(area).max() ?? 0
            let pb = b.supportedMaxPhotoDimensions.map(area).max() ?? 0
            if pa != pb { return pa < pb }
            // 同样的照片尺寸下，取预览分辨率更接近 1920 宽的格式，省电
            let wa = abs(Int(CMVideoFormatDescriptionGetDimensions(a.formatDescription).width) - 1920)
            let wb = abs(Int(CMVideoFormatDescriptionGetDimensions(b.formatDescription).width) - 1920)
            return wa > wb
        }
        guard let best, (best.supportedMaxPhotoDimensions.map(area).max() ?? 0) > currentMax else { return }
        do {
            try device.lockForConfiguration()
            device.activeFormat = best
            device.unlockForConfiguration()
        } catch {}
    }

    // MARK: Camera Control

    /// 创建 Camera Control 的控件：焦段、曝光补偿（系统滑块）、色彩。选择结果在主线程回调。
    func setupCameraControls(focalTitles: [String], focalIndex: Int, lookTitles: [String], lookIndex: Int,
                             onFocal: @escaping (Int) -> Void, onLook: @escaping (Int) -> Void) {
        sessionQueue.async {
            guard self.session.supportsControls else { return }
            let focal = AVCaptureIndexPicker("焦段", symbolName: "camera.aperture", localizedIndexTitles: focalTitles)
            focal.selectedIndex = focalIndex
            focal.setActionQueue(.main) { onFocal($0) }
            let look = AVCaptureIndexPicker("色彩", symbolName: "camera.filters", localizedIndexTitles: lookTitles)
            look.selectedIndex = lookIndex
            look.setActionQueue(.main) { onLook($0) }
            self.focalPicker = focal
            self.lookPicker = look
            // 系统只有在设置了 controls delegate 后才会展示控件
            self.session.setControlsDelegate(self, queue: .main)
            self.session.beginConfiguration()
            self.installControls(for: self.currentDevice)
            self.session.commitConfiguration()
        }
    }

    /// 在 sessionQueue、begin/commitConfiguration 之间调用。
    /// 曝光滑块绑定具体镜头，换镜头时只替换它；两个选择器保持不动，避免正在操作的控件被移除。
    private func installControls(for device: AVCaptureDevice?) {
        guard session.supportsControls, let focalPicker, let lookPicker else { return }
        if let old = exposureSlider, session.controls.contains(where: { $0 === old }) {
            session.removeControl(old)
        }
        exposureSlider = nil
        for picker in [focalPicker, lookPicker] where !session.controls.contains(where: { $0 === picker }) {
            if session.canAddControl(picker) { session.addControl(picker) }
        }
        if let device {
            let slider = AVCaptureSystemExposureBiasSlider(device: device)
            if session.canAddControl(slider) {
                session.addControl(slider)
                exposureSlider = slider
            }
        }
    }

    /// 界面上改动后同步 Camera Control 的选中项
    func syncControls(focalIndex: Int?, lookIndex: Int?) {
        sessionQueue.async {
            if let focalIndex, let picker = self.focalPicker, picker.selectedIndex != focalIndex {
                picker.selectedIndex = focalIndex
            }
            if let lookIndex, let picker = self.lookPicker, picker.selectedIndex != lookIndex {
                picker.selectedIndex = lookIndex
            }
        }
    }

    // MARK: 方向

    /// 后置摄像头的视频旋转角：传感器原生方向等于界面 landscapeRight（0°）
    static func rotationAngle(for orientation: UIInterfaceOrientation) -> CGFloat {
        switch orientation {
        case .landscapeLeft: return 180
        case .portrait: return 90
        case .portraitUpsideDown: return 270
        default: return 0
        }
    }

    func updateInterfaceOrientation(_ orientation: UIInterfaceOrientation) {
        guard orientation != .unknown, orientation != interfaceOrientation else { return }
        interfaceOrientation = orientation
        let angle = CameraController.rotationAngle(for: orientation)
        sessionQueue.async {
            self.rotationAngle = angle
            if let connection = self.videoOutput.connection(with: .video), connection.isVideoRotationAngleSupported(angle) {
                connection.videoRotationAngle = angle
            }
        }
    }

    // MARK: 对焦

    func focus(at devicePoint: CGPoint) {
        sessionQueue.async {
            guard let device = self.currentDevice, (try? device.lockForConfiguration()) != nil else { return }
            if device.isFocusPointOfInterestSupported {
                device.focusPointOfInterest = devicePoint
                if device.isFocusModeSupported(.autoFocus) { device.focusMode = .autoFocus }
            }
            if device.isExposurePointOfInterestSupported {
                device.exposurePointOfInterest = devicePoint
                if device.isExposureModeSupported(.autoExpose) { device.exposureMode = .autoExpose }
            }
            device.isSubjectAreaChangeMonitoringEnabled = true
            device.unlockForConfiguration()
        }
    }

    // MARK: 拍摄

    /// - Parameters:
    ///   - willCapture: 快门真正开始曝光时（主线程）
    ///   - completion: 拿到全部照片（拼接模式下两张）后回调（主线程）
    func capture(willCapture: @escaping () -> Void, completion: @escaping (Result<[AVCapturePhoto], Error>) -> Void) {
        sessionQueue.async {
            let angle = self.rotationAngle
            guard self.input != nil else {
                DispatchQueue.main.async { completion(.failure(ProcessingError.decode)) }
                return
            }
            let settings: AVCapturePhotoSettings
            if self.photoOutput.availablePhotoCodecTypes.contains(.hevc) {
                settings = AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.hevc])
            } else {
                settings = AVCapturePhotoSettings()
            }
            settings.maxPhotoDimensions = self.photoOutput.maxPhotoDimensions
            settings.photoQualityPrioritization = .quality
            if self.configuration == .dualWide || self.photoOutput.isVirtualDeviceConstituentPhotoDeliveryEnabled,
               let device = self.currentDevice, device.isVirtualDevice {
                settings.virtualDeviceConstituentPhotoDeliveryEnabledDevices = device.constituentDevices
            }
            if let connection = self.photoOutput.connection(with: .video), connection.isVideoRotationAngleSupported(angle) {
                connection.videoRotationAngle = angle
            }
            let id = settings.uniqueID
            let delegate = PhotoCaptureDelegate(willCapture: willCapture) { [weak self] result in
                self?.sessionQueue.async { self?.inFlight[id] = nil }
                DispatchQueue.main.async { completion(result) }
            }
            self.inFlight[id] = delegate
            self.photoOutput.capturePhoto(with: settings, delegate: delegate)
        }
    }

    /// 双摄拼接时用到的焦距比（超广角 → 主摄）
    func dualWideFocalRatio() -> CGFloat {
        guard let device = currentDevice, device.isVirtualDevice else { return 24.0 / 13.0 }
        let constituents = device.constituentDevices
        guard let wide = constituents.first(where: { $0.deviceType == .builtInWideAngleCamera }),
              let uw = constituents.first(where: { $0.deviceType == .builtInUltraWideCamera }) else { return 24.0 / 13.0 }
        let tw = tan(Double(wide.activeFormat.videoFieldOfView) * .pi / 360)
        let tu = tan(Double(uw.activeFormat.videoFieldOfView) * .pi / 360)
        guard tw > 0 else { return 24.0 / 13.0 }
        return CGFloat(tu / tw)
    }
}

extension CameraController: AVCaptureSessionControlsDelegate {
    func sessionControlsDidBecomeActive(_ session: AVCaptureSession) {}

    func sessionControlsWillEnterFullscreenAppearance(_ session: AVCaptureSession) {
        controlsFullscreen = true
    }

    func sessionControlsWillExitFullscreenAppearance(_ session: AVCaptureSession) {
        controlsFullscreen = false
    }

    func sessionControlsDidBecomeInactive(_ session: AVCaptureSession) {
        controlsFullscreen = false
    }
}

extension CameraController: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        frames.update(CIImage(cvPixelBuffer: buffer))
    }
}

private final class PhotoCaptureDelegate: NSObject, AVCapturePhotoCaptureDelegate {
    private let willCapture: () -> Void
    private let completion: (Result<[AVCapturePhoto], Error>) -> Void
    private var photos: [AVCapturePhoto] = []
    private var error: Error?

    init(willCapture: @escaping () -> Void, completion: @escaping (Result<[AVCapturePhoto], Error>) -> Void) {
        self.willCapture = willCapture
        self.completion = completion
    }

    func photoOutput(_ output: AVCapturePhotoOutput, willCapturePhotoFor resolvedSettings: AVCaptureResolvedPhotoSettings) {
        DispatchQueue.main.async(execute: willCapture)
    }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        if let error { self.error = error } else { photos.append(photo) }
    }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishCaptureFor resolvedSettings: AVCaptureResolvedPhotoSettings, error: Error?) {
        if let error = error ?? self.error, photos.isEmpty {
            completion(.failure(error))
        } else {
            completion(.success(photos))
        }
    }
}
