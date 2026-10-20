import AVKit
import SwiftUI
import UIKit

struct CameraScreen: View {
    @StateObject private var model: CameraModel

    init(settings: AppSettings) {
        _model = StateObject(wrappedValue: CameraModel(settings: settings))
    }

    var body: some View {
        CameraScreenContent(model: model, camera: model.camera, settings: model.settings)
    }
}

/// 界面布局。默认横屏，按 OPPO 相机横持时的布局：
/// 左侧是原顶栏（竖排，液态玻璃）；中间是全屏取景、65:24 窗口尽量大；
/// 右侧从内到外依次是焦段圆钮（竖排）、模式栏（竖排）、快门列（上：胶片切换，中：快门，下：缩略图）。
/// 竖屏窗口（iPad、分屏等）退回上中下布局。
struct CameraLayout {
    let size: CGSize
    let safe: EdgeInsets
    let orientation: UIInterfaceOrientation
    /// 屏幕尺寸（随界面方向）。App 跑在 LiveContainer 等容器的小窗里时，窗口比屏幕小。
    var screenSize: CGSize = .zero
    var isPhone: Bool = true

    var isLandscape: Bool { size.width > size.height }

    // 横屏各列宽度
    static let leftRail: CGFloat = 56
    static let focalRail: CGFloat = 56
    static let modeRail: CGFloat = 64
    static let controlRail: CGFloat = 96
    // 竖屏上下区域高度
    static let topBar: CGFloat = 60
    static let bottomControls: CGFloat = 220

    /// 灵动岛在哪一侧：界面 landscapeRight 时机身顶部（灵动岛）在左，landscapeLeft 时在右；未知时返回 nil
    var islandOnLeading: Bool? {
        switch orientation {
        case .landscapeRight: return true
        case .landscapeLeft: return false
        default: return nil
        }
    }

    /// 横屏时灵动岛伸进屏幕约 61pt。容器小窗里系统报告的安全区可能是 0，所以 iPhone 上自己保证这段距离。
    static let islandClearance: CGFloat = 64
    /// 容器小窗顶部的标题栏（App 名 + 最小化/关闭按钮）
    static let windowChromeHeight: CGFloat = 52

    /// 不是全屏，而是跑在别的 App 的小窗里
    var isWindowed: Bool {
        screenSize.width > 0 && (abs(size.width - screenSize.width) > 2 || abs(size.height - screenSize.height) > 2)
    }

    private var islandInset: CGFloat { isPhone ? Self.islandClearance : 0 }

    /// 灵动岛那一侧保留足够距离；另一侧没有遮挡，只留一点边距，把空间让给取景窗口。方向未知时两侧都避开。
    var leading: CGFloat {
        islandOnLeading == false ? max(min(safe.leading, 14), 10) : max(safe.leading, islandInset, 10)
    }
    var trailing: CGFloat {
        islandOnLeading == true ? max(min(safe.trailing, 14), 8) : max(safe.trailing, islandInset, 8)
    }
    var top: CGFloat {
        if isWindowed { return max(safe.top, Self.windowChromeHeight) }
        // 竖屏时灵动岛在顶部
        return isLandscape ? max(safe.top, 10) : max(safe.top, isPhone ? 59 : 10)
    }
    var bottom: CGFloat { max(safe.bottom, 10) }

    var rightRailsWidth: CGFloat { Self.focalRail + Self.modeRail + Self.controlRail }
    var rightRailsMinX: CGFloat { size.width - trailing - rightRailsWidth }

    /// 取景窗口可用的区域（点）
    var bandRegion: CGRect {
        if isLandscape {
            let minX = leading + Self.leftRail + 8
            let maxX = rightRailsMinX - 6
            return CGRect(x: minX, y: top + 22, width: max(0, maxX - minX), height: max(0, size.height - top - bottom - 30))
        }
        let minY = top + Self.topBar + 22
        let maxY = size.height - bottom - Self.bottomControls
        return CGRect(x: 12, y: minY, width: size.width - 24, height: max(0, maxY - minY))
    }

    /// 灵动岛位置。只有全屏运行的 iPhone、并且安全区显示出灵动岛（横屏两侧 ≥ 55pt / 竖屏顶部 ≥ 51pt）时才认为有；
    /// 否则在取景区上方用一个浮动的黑色胶囊代替。
    var island: IslandGeometry {
        let hasIsland = isPhone && !isWindowed &&
            (isLandscape ? max(safe.leading, safe.trailing) >= 55 : safe.top >= 51)
        let L = IslandGeometry.length, T = IslandGeometry.thickness, g = IslandGeometry.gap
        if hasIsland, isLandscape, let onLeading = islandOnLeading {
            let x = onLeading ? g : size.width - g - T
            return IslandGeometry(anchor: CGRect(x: x, y: size.height / 2 - L / 2, width: T, height: L),
                                  edge: onLeading ? .leading : .trailing, isHardware: true, screen: size)
        }
        if hasIsland, !isLandscape {
            return IslandGeometry(anchor: CGRect(x: size.width / 2 - L / 2, y: g, width: L, height: T),
                                  edge: .top, isHardware: true, screen: size)
        }
        let region = bandRegion
        return IslandGeometry(anchor: CGRect(x: region.midX - 50, y: top + 2, width: 100, height: 30),
                              edge: .top, isHardware: false, screen: size)
    }

    /// 把指定宽高比的窗口放进可用区域并居中，返回全屏归一化坐标
    func band(ratio: CGFloat) -> CGRect {
        let region = bandRegion
        guard region.width > 0, region.height > 0, size.width > 0, size.height > 0 else {
            return CGRect(x: 0.1, y: 0.3, width: 0.8, height: 0.3)
        }
        var w = region.width
        var h = w / ratio
        if h > region.height {
            h = region.height
            w = h * ratio
        }
        let rect = CGRect(x: region.midX - w / 2, y: region.midY - h / 2, width: w, height: h)
        return CGRect(x: rect.minX / size.width, y: rect.minY / size.height,
                      width: rect.width / size.width, height: rect.height / size.height)
    }
}

private struct CameraScreenContent: View {
    /// 当前屏幕尺寸（随界面方向），用来判断是否跑在容器小窗里
    static var screenSize: CGSize {
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        return scene?.screen.bounds.size ?? .zero
    }

    @ObservedObject var model: CameraModel
    @ObservedObject var camera: CameraController
    @ObservedObject var settings: AppSettings

    @Environment(\.scenePhase) private var scenePhase
    @Namespace private var shotNamespace
    @State private var showPalette = false
    @State private var showAperture = false
    @State private var showSettings = false
    @State private var showReview = false

    var body: some View {
        GeometryReader { proxy in
            let layout = CameraLayout(size: proxy.size, safe: proxy.safeAreaInsets, orientation: camera.interfaceOrientation,
                                      screenSize: Self.screenSize, isPhone: UIDevice.current.userInterfaceIdiom == .phone)
            let band = layout.band(ratio: model.bandRatio(isLandscapeUI: layout.isLandscape))
            ZStack(alignment: .topLeading) {
                Color.black

                viewfinder(screen: proxy.size)

                Group {
                    if layout.isLandscape {
                        landscapeControls(layout)
                    } else {
                        portraitControls(layout)
                    }
                }
                // Camera Control 的控件全屏展开时收起界面，让取景更干净（系统建议的做法）
                .opacity(camera.controlsFullscreen ? 0 : 1)
                .animation(.easeInOut(duration: 0.2), value: camera.controlsFullscreen)

                if showPalette {
                    paletteOverlay(layout)
                        .transition(.move(edge: layout.isLandscape ? .trailing : .bottom).combined(with: .opacity))
                }

                if showAperture, let support = camera.apertureSupport {
                    apertureOverlay(layout, support: support)
                        .transition(.move(edge: layout.isLandscape ? .trailing : .bottom).combined(with: .opacity))
                }

                // 灵动岛：快门动效、冲洗进度、保存完成（点按查看）、各种提示
                DynamicIslandOverlay(geometry: layout.island, message: model.island, pulse: model.islandPulse) {
                    model.dismissIsland()
                    if model.lastShot != nil { showReview = true }
                }
            }
            .onAppear {
                model.refreshInterfaceOrientation(fallbackSize: proxy.size)
                model.updateBand(band)
            }
            .onChange(of: band) { _, newBand in model.updateBand(newBand) }
            .onChange(of: proxy.size) { _, newSize in model.refreshInterfaceOrientation(fallbackSize: newSize) }
        }
        .ignoresSafeArea()
        .onAppear { model.start() }
        // Camera Control 完全按下（以及音量键）拍照
        .onCameraCaptureEvent(isEnabled: camera.authorization == .authorized) { event in
            if event.phase == .ended { model.shutter() }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { camera.resume() } else if phase == .background { camera.stop() }
        }
        .sheet(isPresented: $showSettings) {
            SettingsSheet(settings: settings, lineup: camera.lineup, mainPhotoSize: camera.photoDimensions, onChange: { model.syncPreview() })
                .presentationDetents([.large])
        }
        .fullScreenCover(isPresented: $showReview) {
            if let shot = model.lastShot { ShotReview(shot: shot) }
        }
    }

    // MARK: 取景

    private var caption: String {
        switch model.mode {
        case .ipan:
            var parts = ["\(model.plan.focal.millimeters)mm", "65:24", settings.filmMode.caption]
            if camera.apertureSupport != nil && camera.liveAperture > 0 {
                parts.append("ƒ" + VariableAperture.label(camera.liveAperture))
            }
            return parts.joined(separator: "  ·  ")
        case .stitch:
            return ["WIDE β", "双摄拼接", "65:24"].joined(separator: "  ·  ")
        }
    }

    private func viewfinder(screen: CGSize) -> some View {
        ZStack(alignment: .topLeading) {
            CameraPreview(frames: camera.frames, state: model.previewState, renderer: model.renderer)
                .blur(radius: camera.isSwitching ? 22 : 0)
                .animation(.easeInOut(duration: 0.22), value: camera.isSwitching)
                .allowsHitTesting(false)

            PanoramaMask(band: model.band, caption: caption,
                         mainCoverage: model.mode == .stitch ? model.mainCoverage : nil)

            DevelopOverlay(phase: model.developPhase, image: model.developImage, progress: model.developProgress,
                           band: model.band, namespace: shotNamespace)

            // 只在 65:24 窗口内点击对焦：按钮都在窗口外，不会再和对焦冲突
            let bandFrame = CGRect(x: model.band.minX * screen.width, y: model.band.minY * screen.height,
                                   width: model.band.width * screen.width, height: model.band.height * screen.height)
            Color.clear
                .contentShape(Rectangle())
                .frame(width: bandFrame.width, height: bandFrame.height)
                .onTapGesture { location in
                    let x = (bandFrame.minX + location.x) / max(1, screen.width)
                    let y = (bandFrame.minY + location.y) / max(1, screen.height)
                    model.focus(at: CGPoint(x: x, y: y), screen: screen)
                }
                .offset(x: bandFrame.minX, y: bandFrame.minY)

            if let point = model.focusPoint {
                OPPOFocusIndicator()
                    .position(x: point.x * screen.width, y: point.y * screen.height)
                    .id(point.x + point.y)
            }

            if model.mode == .stitch && !camera.isLandscape {
                RotateHint()
                    .position(x: screen.width / 2, y: screen.height / 2)
                    .transition(.opacity)
            }

            if camera.authorization == .denied {
                VStack(spacing: 14) {
                    Image(systemName: "camera.aperture")
                        .font(.system(size: 40, weight: .light))
                        .foregroundStyle(OPPOStyle.accent)
                    Text("需要相机权限")
                        .font(.system(size: 18, weight: .semibold))
                    Text("iPAN 用相机拍摄 65:24 宽幅照片，照片只会保存到你的相册。")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    Button("前往设置") {
                        if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                    }
                    .buttonStyle(.glassProminent)
                    .tint(OPPOStyle.accent)
                }
                .foregroundStyle(.white)
                .padding(28)
                .frame(maxWidth: 360)
                .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 30))
                .position(x: screen.width / 2, y: screen.height / 2)
            }
        }
        .frame(width: screen.width, height: screen.height)
    }

    // MARK: 横屏控件

    private func landscapeControls(_ layout: CameraLayout) -> some View {
        let railHeight = layout.size.height - layout.top - layout.bottom
        return ZStack(alignment: .topLeading) {
            // 左：工具栏（液态玻璃，竖排）
            toolRail(axis: .vertical)
                .frame(width: CameraLayout.leftRail, height: railHeight)
                .position(x: layout.leading + CameraLayout.leftRail / 2, y: layout.top + railHeight / 2)

            // 右：焦段 · 模式 · 快门列（OPPO）
            HStack(spacing: 0) {
                Group {
                    if model.mode == .ipan {
                        OPPOFocalSelector(focals: FocalLength.all, selected: settings.focal, axis: .vertical) { model.select(focal: $0) }
                            .transition(.opacity)
                    } else {
                        Color.clear
                    }
                }
                .frame(width: CameraLayout.focalRail)

                OPPOModeCarousel(modes: CaptureMode.allCases, selected: model.mode, axis: .vertical) { model.select(mode: $0) }
                    .frame(width: CameraLayout.modeRail, height: min(railHeight, 220))

                VStack {
                    filmButton
                    Spacer()
                    shutter
                    Spacer()
                    thumbnailButton
                }
                .padding(.vertical, 8)
                .frame(width: CameraLayout.controlRail, height: railHeight)
            }
            .frame(width: layout.rightRailsWidth, height: railHeight)
            .position(x: layout.rightRailsMinX + layout.rightRailsWidth / 2, y: layout.top + railHeight / 2)
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: model.mode)
    }

    // MARK: 竖屏控件（iPad / 竖向窗口）

    private func portraitControls(_ layout: CameraLayout) -> some View {
        ZStack(alignment: .topLeading) {
            toolRail(axis: .horizontal)
                .frame(width: layout.size.width - 32, height: CameraLayout.topBar)
                .position(x: layout.size.width / 2, y: layout.top + CameraLayout.topBar / 2)

            VStack(spacing: 16) {
                if model.mode == .ipan {
                    OPPOFocalSelector(focals: FocalLength.all, selected: settings.focal) { model.select(focal: $0) }
                } else {
                    Text("超广角 + 主摄同步曝光，横持拍摄")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(OPPOStyle.secondaryText)
                        .frame(height: 46)
                }
                OPPOModeCarousel(modes: CaptureMode.allCases, selected: model.mode) { model.select(mode: $0) }
                    .frame(height: 30)
                HStack {
                    thumbnailButton
                    Spacer()
                    shutter
                    Spacer()
                    filmButton
                }
                .padding(.horizontal, 36)
            }
            .frame(width: layout.size.width, height: CameraLayout.bottomControls)
            .position(x: layout.size.width / 2, y: layout.size.height - layout.bottom - CameraLayout.bottomControls / 2)
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: model.mode)
    }

    // MARK: 组件

    /// 原 OPPO 顶栏：设置 / 水印 / 暗角 / 调色盘（液态玻璃）
    private func toolRail(axis: Axis) -> some View {
        let outer = axis == .vertical ? AnyLayout(VStackLayout(spacing: 12)) : AnyLayout(HStackLayout(spacing: 12))
        let inner = axis == .vertical ? AnyLayout(VStackLayout(spacing: 18)) : AnyLayout(HStackLayout(spacing: 18))
        return GlassEffectContainer(spacing: 12) {
            outer {
                Button { showSettings = true } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: 17, weight: .medium))
                        .frame(width: 42, height: 42)
                }
                .buttonStyle(.plain)
                .glassEffect(.regular.interactive(), in: Circle())

                Spacer(minLength: 0)

                inner {
                    Button {
                        settings.watermarkEnabled.toggle()
                        model.showToast(settings.watermarkEnabled ? "水印：\(settings.watermarkTemplate)" : "水印已关闭")
                    } label: {
                        Image(systemName: settings.watermarkEnabled ? "signature" : "text.badge.xmark")
                            .foregroundStyle(settings.watermarkEnabled ? OPPOStyle.accent : .white)
                    }
                    Button {
                        settings.vignette.toggle()
                        model.syncPreview()
                    } label: {
                        Image(systemName: settings.vignette ? "circle.dashed.inset.filled" : "circle.dashed")
                    }
                    Button {
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                            showPalette.toggle()
                            if showPalette { showAperture = false }
                        }
                    } label: {
                        Image(systemName: "paintpalette")
                            .foregroundStyle(settings.palette.isIdentity && !showPalette ? .white : OPPOStyle.accent)
                    }
                    // 可变光圈（iOS 27 + 支持的镜头才显示）
                    if camera.apertureSupport != nil {
                        Button {
                            withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                                showAperture.toggle()
                                if showAperture { showPalette = false }
                            }
                        } label: {
                            Text(camera.lockedAperture.map { "ƒ" + VariableAperture.label($0) } ?? "ƒA")
                                .font(.system(size: 13, weight: .heavy, design: .rounded))
                                .monospacedDigit()
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                                .frame(width: 32)
                                .foregroundStyle(camera.lockedAperture != nil || showAperture ? OPPOStyle.accent : .white)
                        }
                    }
                }
                .font(.system(size: 17, weight: .medium))
                .buttonStyle(.plain)
                .padding(axis == .vertical ? .vertical : .horizontal, 16)
                .padding(axis == .vertical ? .horizontal : .vertical, 11)
                .glassEffect(.regular.interactive(), in: Capsule())

                Spacer(minLength: 0)

                Color.clear.frame(width: 42, height: 42)
            }
        }
        .foregroundStyle(.white)
    }

    private var shutter: some View {
        OPPOShutterButton(isBusy: model.processingCount > 0, isEnabled: model.canShoot) {
            model.shutter()
        }
    }

    private var filmButton: some View {
        OPPOCircleButton {
            model.toggleFilm()
        } label: {
            VStack(spacing: 0) {
                Text(settings.filmMode.badge)
                    .font(.system(size: 15, weight: .heavy, design: .rounded))
                Text(settings.filmMode.title)
                    .font(.system(size: 7, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .opacity(0.75)
            }
            .foregroundStyle(settings.filmMode == .hncs ? OPPOStyle.accent : .white)
            .frame(width: 44)
        }
    }

    private var thumbnailButton: some View {
        Button {
            if model.lastShot != nil { showReview = true }
        } label: {
            ZStack {
                Circle().fill(Color.white.opacity(0.12))
                if model.developPhase == .idle, let thumb = model.thumbnail {
                    Image(uiImage: thumb)
                        .resizable()
                        .scaledToFill()
                        .matchedGeometryEffect(id: "shot", in: shotNamespace)
                }
            }
            .frame(width: 48, height: 48)
            .clipShape(Circle())
            .overlay(Circle().stroke(Color.white.opacity(0.9), lineWidth: 1.5))
        }
        .buttonStyle(.plain)
    }

    private func apertureOverlay(_ layout: CameraLayout, support: VariableAperture.Support) -> some View {
        let region = layout.bandRegion
        let width = layout.isLandscape ? min(440, region.width) : layout.size.width - 24
        return AperturePanel(support: support, locked: camera.lockedAperture, live: camera.liveAperture,
                             onSelect: { model.setAperture($0) }) {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { showAperture = false }
        }
        .frame(width: max(280, width))
        .position(x: layout.isLandscape ? region.midX : layout.size.width / 2,
                  y: layout.isLandscape ? layout.size.height / 2 : layout.size.height - layout.bottom - CameraLayout.bottomControls - 90)
    }

    private func paletteOverlay(_ layout: CameraLayout) -> some View {
        let region = layout.bandRegion
        let width = layout.isLandscape ? min(520, region.width) : layout.size.width - 24
        return PalettePanel(settings: settings, compact: layout.isLandscape, onChange: { model.syncPreview() }) {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { showPalette = false }
        }
        .frame(width: max(300, width))
        .position(x: layout.isLandscape ? region.midX : layout.size.width / 2,
                  y: layout.isLandscape ? layout.size.height / 2 : layout.size.height - layout.bottom - CameraLayout.bottomControls - 150)
    }
}
