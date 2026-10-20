import SwiftUI

struct CameraScreen: View {
    @StateObject private var model: CameraModel

    init(settings: AppSettings) {
        _model = StateObject(wrappedValue: CameraModel(settings: settings))
    }

    var body: some View {
        CameraScreenContent(model: model, camera: model.camera, settings: model.settings)
    }
}

private struct CameraScreenContent: View {
    @ObservedObject var model: CameraModel
    @ObservedObject var camera: CameraController
    @ObservedObject var settings: AppSettings

    @Environment(\.scenePhase) private var scenePhase
    @Namespace private var shotNamespace
    @State private var showPalette = false
    @State private var showSettings = false
    @State private var showReview = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 0) {
                topBar
                    .padding(.horizontal, 16)
                    .padding(.top, 6)
                    .padding(.bottom, 10)
                viewfinder
                Spacer(minLength: 8)
                controls
            }

            if showPalette {
                VStack {
                    Spacer()
                    PalettePanel(settings: settings, onChange: { model.syncPreview() }) {
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { showPalette = false }
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 24)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            if let toast = model.toast {
                VStack {
                    Text(toast)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 9)
                        .glassEffect(.regular, in: Capsule())
                        .rotationEffect(camera.iconRotation)
                        .padding(.top, 70)
                    Spacer()
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
                .allowsHitTesting(false)
            }
        }
        .onAppear { model.start() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { camera.resume() } else if phase == .background { camera.stop() }
        }
        .onChange(of: camera.isLandscape) { model.syncPreview() }
        .sheet(isPresented: $showSettings) {
            SettingsSheet(settings: settings, lineup: camera.lineup, mainPhotoSize: camera.photoDimensions, onChange: { model.syncPreview() })
                .presentationDetents([.medium, .large])
        }
        .fullScreenCover(isPresented: $showReview) {
            if let shot = model.lastShot { ShotReview(shot: shot) }
        }
    }

    // MARK: 顶栏（液态玻璃）

    private var topBar: some View {
        GlassEffectContainer(spacing: 12) {
            HStack(spacing: 12) {
                glassIcon(systemName: "gearshape") { showSettings = true }
                Spacer()
                HStack(spacing: 14) {
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
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { showPalette.toggle() }
                    } label: {
                        Image(systemName: "paintpalette")
                            .foregroundStyle(settings.palette.isIdentity ? .white : OPPOStyle.accent)
                    }
                }
                .font(.system(size: 17, weight: .medium))
                .rotationEffect(camera.iconRotation)
                .buttonStyle(.plain)
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .glassEffect(.regular.interactive(), in: Capsule())
                Spacer()
                Text(settings.filmMode == .color ? "C" : "BW")
                    .font(.system(size: 13, weight: .heavy, design: .rounded))
                    .frame(width: 40, height: 40)
                    .rotationEffect(camera.iconRotation)
                    .glassEffect(.regular.interactive(), in: Circle())
                    .onTapGesture { model.toggleFilm() }
            }
        }
        .animation(.spring(response: 0.45, dampingFraction: 0.8), value: camera.iconRotation)
    }

    private func glassIcon(systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(.white)
                .frame(width: 40, height: 40)
                .rotationEffect(camera.iconRotation)
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: Circle())
    }

    // MARK: 取景器

    private var window: CGSize { model.window(isLandscape: camera.isLandscape) }

    private var caption: String {
        switch model.mode {
        case .ipan:
            let plan = model.plan
            return "iPAN \(plan.focal.millimeters)mm · 65:24 · \(settings.filmMode == .color ? "C" : "BW")"
        case .stitch:
            return "iPAN WIDE β · 双摄拼接"
        }
    }

    private var viewfinder: some View {
        GeometryReader { proxy in
            ZStack {
                CameraPreview(frames: camera.frames, state: model.previewState, renderer: model.renderer)
                    .blur(radius: camera.isSwitching ? 22 : 0)
                    .scaleEffect(camera.isSwitching ? 1.04 : 1)
                    .animation(.easeInOut(duration: 0.22), value: camera.isSwitching)

                PanoramaMask(window: window, caption: caption, iconRotation: camera.iconRotation,
                             mainCoverage: model.mode == .stitch ? model.mainCoverage : nil)

                DevelopOverlay(phase: model.developPhase, image: model.developImage, progress: model.developProgress,
                               window: window, namespace: shotNamespace)

                if let point = model.focusPoint {
                    OPPOFocusIndicator()
                        .position(x: point.x * proxy.size.width, y: point.y * proxy.size.height)
                        .id(point.x + point.y)
                }

                if model.mode == .stitch && !camera.isLandscape {
                    RotateHint().transition(.opacity)
                }

                if camera.authorization == .denied {
                    VStack(spacing: 10) {
                        Image(systemName: "camera.fill").font(.largeTitle)
                        Text("请在「设置」中允许 iPAN 使用相机")
                    }
                    .foregroundStyle(.white)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { location in
                model.focus(atNormalized: CGPoint(x: location.x / proxy.size.width, y: location.y / proxy.size.height))
            }
        }
        .aspectRatio(3.0 / 4.0, contentMode: .fit)
        .clipped()
        .animation(.easeInOut(duration: 0.25), value: camera.isLandscape)
    }

    // MARK: 底部控制区（OPPO 风格）

    private var controls: some View {
        VStack(spacing: 18) {
            if model.mode == .ipan {
                OPPOFocalSelector(focals: FocalLength.all, selected: settings.focal, iconRotation: camera.iconRotation) { focal in
                    model.select(focal: focal)
                }
                .transition(.opacity)
            } else {
                Text("超广角 + 主摄同步曝光，横持拍摄")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(OPPOStyle.secondaryText)
                    .frame(height: 46)
            }

            OPPOModeCarousel(modes: CaptureMode.allCases, selected: model.mode) { mode in
                model.select(mode: mode)
            }
            .frame(height: 30)

            HStack {
                thumbnailButton
                Spacer()
                OPPOShutterButton(isBusy: model.processingCount > 0, isEnabled: model.canShoot) {
                    model.shutter()
                }
                Spacer()
                OPPOCircleButton {
                    model.toggleFilm()
                } label: {
                    Image(systemName: settings.filmMode == .color ? "film" : "film.fill")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(.white)
                        .rotationEffect(camera.iconRotation)
                }
            }
            .padding(.horizontal, 36)
            .padding(.bottom, 18)
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: model.mode)
        .animation(.spring(response: 0.45, dampingFraction: 0.8), value: camera.iconRotation)
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
            .rotationEffect(camera.iconRotation)
        }
        .buttonStyle(.plain)
    }
}
