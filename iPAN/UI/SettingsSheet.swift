import AVFoundation
import SwiftUI

enum AppInfo {
    static var versionText: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = info?["CFBundleVersion"] as? String ?? "1"
        return "\(version)（\(build)）"
    }

    static let repositoryURL = URL(string: "https://github.com/ZONGRUICHD-Rd/ipan")!
}

struct SettingsSheet: View {
    @ObservedObject var settings: AppSettings
    let lineup: LensLineup
    let mainPhotoSize: CMVideoDimensions?
    var onChange: () -> Void
    @Environment(\.dismiss) private var dismiss

    private let templates = WatermarkService.availableTemplates()

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("色彩", selection: $settings.filmMode) {
                        ForEach(FilmMode.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    Toggle("XPan 暗角", isOn: $settings.vignette)
                    Toggle("快门负片显影动画", isOn: $settings.developAnimation)
                    Toggle("同时保存 48MP 原图", isOn: $settings.saveOriginal)
                    if UIDevice.current.userInterfaceIdiom == .pad {
                        Picker("竖向窗口输出", selection: $settings.portraitOutput) {
                            ForEach(PortraitOutput.allCases) { Text($0.title).tag($0) }
                        }
                    }
                } header: {
                    Text("拍摄")
                } footer: {
                    Text("HNCS 为默认色彩；XPan 胶片带抬起的黑位与暖调；原色不做任何调色。")
                }

                Section {
                    Toggle("添加水印", isOn: $settings.watermarkEnabled)
                    if settings.watermarkEnabled {
                        Picker("模板", selection: $settings.watermarkTemplate) {
                            ForEach(templates, id: \.self) { Text($0).tag($0) }
                        }
                        Toggle("显示品牌 Logo", isOn: $settings.watermarkLogo)
                    }
                } header: {
                    Text("水印")
                }

                Section {
                    ForEach(FocalLength.all) { focal in
                        let plan = lineup.plan(for: focal)
                        HStack {
                            Text("\(focal.millimeters)mm").monospacedDigit()
                            Text(plan.lens == .main ? "主摄" : "长焦")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(resolution(for: plan))
                                .font(.system(.footnote, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Text("输出规格")
                } footer: {
                    Text("以传感器最高分辨率（48MP）拍摄，裁成 65:24 后按实际像素输出苹果原生 HEIC，不做插值放大。")
                }

                Section {
                    LabeledContent("版本", value: AppInfo.versionText)
                    DisclosureGroup("色彩与调色盘") {
                        Text("HNCS 是按哈苏公开描述（自然肤色、细腻影调过渡、胶片曲线、克制的饱和度）做的风格复刻，并非哈苏官方算法。iOS 的「摄影风格」调色盘没有开放给第三方 App，iPAN 内置了交互一致的调色盘，预览与成片一致。")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    DisclosureGroup("致谢") {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("水印：semi-utils（Apache License 2.0），模板、Logo 与字体来自 ZONGRUICHD-Rd/semi-utils-ios-support")
                            Text("字体：阿里巴巴普惠体、Roboto")
                            Text("画幅致敬：Hasselblad XPan")
                        }
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    }
                    Link(destination: AppInfo.repositoryURL) {
                        Label("项目主页", systemImage: "arrow.up.right.square")
                    }
                } header: {
                    Text("关于")
                }
            }
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") {
                        onChange()
                        dismiss()
                    }
                }
            }
        }
        .onChange(of: settings.vignette) { onChange() }
        .onChange(of: settings.filmMode) { onChange() }
        .onChange(of: settings.portraitOutput) { onChange() }
    }

    /// 横持时的输出分辨率（按 48MP 4:3 传感器估算）
    private func resolution(for plan: FocalPlan) -> String {
        let width = CGFloat(mainPhotoSize.map { max($0.width, $0.height) } ?? 8064)
        let long = (width * plan.cropScale / 2).rounded(.down) * 2
        let short = (long / PanoramaFormat.ratio / 2).rounded(.down) * 2
        let mp = long * short / 1_000_000
        return String(format: "%.0f×%.0f · %.1fMP", long, short, mp)
    }
}

/// 上一张成片预览
struct ShotReview: View {
    let shot: CameraModel.LastShot
    @Environment(\.dismiss) private var dismiss
    @State private var zoom: CGFloat = 1

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            Image(uiImage: shot.preview)
                .resizable()
                .scaledToFit()
                .scaleEffect(zoom)
                .gesture(MagnifyGesture().onChanged { zoom = max(1, $0.magnification) }.onEnded { _ in
                    withAnimation(.spring) { zoom = 1 }
                })
                .padding(.horizontal, 8)
        }
        .overlay(alignment: .top) {
            HStack {
                Text("\(shot.focal)mm · \(Int(shot.pixelSize.width))×\(Int(shot.pixelSize.height)) · HEIC")
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .glassEffect(.regular, in: Capsule())
                Spacer()
                if let url = shot.fileURL {
                    ShareLink(item: url) {
                        Image(systemName: "square.and.arrow.up").font(.system(size: 15, weight: .bold)).padding(10)
                    }
                    .buttonStyle(.glass)
                }
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark").font(.system(size: 15, weight: .bold)).padding(10)
                }
                .buttonStyle(.glass)
            }
            .padding()
        }
        .overlay(alignment: .bottom) {
            if let note = shot.note {
                Text("拼接：\(note)")
                    .font(.footnote)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .glassEffect(.regular, in: Capsule())
                    .padding(.bottom, 30)
            }
        }
        .foregroundStyle(.white)
    }
}
