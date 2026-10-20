import AVFoundation
import SwiftUI

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
                    Picker("竖屏窗口时输出", selection: $settings.portraitOutput) {
                        ForEach(PortraitOutput.allCases) { Text($0.title).tag($0) }
                    }
                    Toggle("快门负片显影动画", isOn: $settings.developAnimation)
                    Toggle("同时保存 48MP 原图", isOn: $settings.saveOriginal)
                } header: {
                    Text("拍摄")
                } footer: {
                    Text("默认横屏，以最高分辨率（48MP）拍摄，裁切后按实际像素输出 HEIC，不做插值放大。横屏时 65:24 沿传感器长边裁切，像素最多。")
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
                    Text("水印（semi-utils）")
                } footer: {
                    Text("模板、Logo 与字体来自 ZONGRUICHD-Rd/semi-utils-ios-support，渲染逻辑为其 Python 处理管道的 Swift 移植。")
                }

                Section("焦段与输出分辨率") {
                    ForEach(FocalLength.all) { focal in
                        let plan = lineup.plan(for: focal)
                        HStack {
                            Text("\(focal.millimeters)mm").monospacedDigit()
                            Spacer()
                            Text(plan.lens == .main ? "主摄" : "长焦")
                                .foregroundStyle(.secondary)
                            Text(resolution(for: plan))
                                .font(.system(.footnote, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Section("关于调色盘") {
                    Text("iOS 的「摄影风格」调色盘（色调 / 色彩 / 调色板）目前没有提供给第三方 App 的读取或设置接口，AVFoundation 里也没有对应的拍摄参数。iPAN 内置了一套交互一致的调色盘，用 Core Image 实时渲染，预览与成片一致。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
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
