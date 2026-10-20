# iPAN

为 iPhone 18 Pro 做的「XPan 类似物」：仿哈苏 XPan / OPPO XPAN 模式，拍摄 65:24 宽幅照片。

## 实现思路

OPPO / 一加的 XPan 模式并不拼接画面，而是**从单颗镜头的全像素画面里裁出 65:24**（一加 9 Pro：30mm 来自超广角，45mm 来自主摄）。iPAN 用同样的方法覆盖 iPhone 18 Pro 的全部焦段：

| 焦段 | 镜头 | 裁切 | 横持输出（48MP 传感器） |
|---|---|---|---|
| 24mm | 主摄 48MP | 整幅宽度 | 8064×2976 · 24MP |
| 28mm | 主摄 48MP | 0.857 | 6912×2552 · 17.6MP |
| 35mm | 主摄 48MP | 0.686 | 5528×2040 · 11.3MP |
| 48mm | 主摄 48MP | 0.5 | 4032×1488 · 6.0MP |
| 100mm | 长焦 48MP | 整幅宽度 | 8064×2976 · 24MP |
| 200mm | 长焦 48MP | 0.5 | 4032×1488 · 6.0MP |

- 默认以最高分辨率（48MP）拍摄，裁切后**按实际像素输出，不插值放大**。
- 默认横屏，65:24 沿传感器长边裁切（像素最多）。预览与成片都以界面方向为准，取景窗口里看到的就是输出的画面。竖向窗口（iPad）默认输出横幅 65:24，可在设置里改为竖幅 24:65。
- 焦段到镜头的映射按机型实际镜头自动推算（长焦等效焦距由视场角算出），老机型也能用。
- 默认输出苹果原生 **HEIC**（保留原始 EXIF，更新尺寸、方向与等效焦距）。

## 功能

- **负片显影动效**（仿 OPPO XPAN）：按下快门 → 取景窗口快门帘黑屏 → 画面以 C-41 彩色负片（反相 + 橙色片基 + 颗粒）出现 → 由中心向外显影成正片 → 飞入左下角缩略图。着色器见 `iPAN/UI/Shaders/FilmDevelop.metal`。
- **色彩**：HNCS（默认，仿哈苏自然色彩，见下文）/ XPan 胶片 / 原色 / 黑白，以及可选的广角边缘失光（暗角）。预览用 Core Image + Metal 实时渲染，所见即所得。
- **可变光圈**（iPhone 18 Pro 主摄 f/1.48–f/4.0，需要 iOS 27）：左侧工具栏的 ƒ 按钮打开光圈面板，可选自动或系统推荐的档位；采用光圈优先，快门与 ISO 仍自动调整。Camera Control 里也有「光圈」选择器。切到长焦或双摄拼接时隐藏（这些镜头是固定光圈）。iOS 27 才有光圈 API，而工程按要求用 Xcode 26（iOS 26 SDK）构建，所以通过 Objective-C 运行时调用（`iPAN/Camera/VariableAperture.swift`），在不支持的系统上自动隐藏。
- **Camera Control 按键**（iPhone 16 及以后）：完全按下拍照（音量键同样可以）；轻按弹出控件，轻点两下切换：焦段（24–200mm）、曝光补偿（系统滑块）、色彩、光圈（支持的机型）。控件全屏展开时界面会自动收起。
- **调色盘**：底色风格 + 色调/色彩二维盘 + 调色板强度，交互仿 iOS「摄影风格」（原因见下文）。
- **水印**：使用 [semi-utils-ios-support](https://github.com/ZONGRUICHD-Rd/semi-utils-ios-support)（以 git submodule 放在 `Vendor/semi-utils`）。它的模板、Logo、字体原样打包进 App，Python 处理管道（Jinja2 模板 + filters/generators/mergers）移植到了 Swift（`iPAN/Watermark/SemiUtils`）。全部 7 个模板的渲染结果已和真实 Jinja2 逐项比对一致。
- **双摄拼接（测试）**：必须横持。用「双广角」虚拟设备让主摄和超广角同步曝光；超广角按焦距比放大作底，主摄经 Vision 单应性配准后贴在中间，羽化接缝 + 色彩匹配，输出约 13mm 视角的 65:24。配准失败时退回平移配准或居中对齐，成片预览里会显示用了哪种方式。
- **UI**：默认横屏，布局参照 OPPO 相机横持时的样子：取景画面铺满全屏，65:24 窗口尽量大、窗口外压暗；左侧是竖排的工具栏（设置、水印、暗角、调色盘，iOS 26 液态玻璃）；右侧从内到外是竖排焦段圆钮、竖排模式栏、快门列（上为胶片切换，中为快门，下为缩略图）。快门、焦段圆钮、模式栏、缩略图、对焦框仿 OPPO ColorOS 相机；调色盘面板、设置与提示使用液态玻璃。iPad 或竖向窗口会自动切换成上中下布局。

## HNCS 色彩科学复刻

哈苏对 HNCS（Hasselblad Natural Colour Solution）的公开描述是：不按题材套不同的色彩配置，用同一套映射追求自然的颜色；重点是肤色准确、细腻的影调过渡，配合 Hasselblad Film Curve 的影调曲线，不靠粗暴拉高饱和度和对比度。iPAN 按这些特征生成一张 33³ 的 3D LUT（`iPAN/Processing/HNCS.swift`，在感知均匀的 OKLab / OKLCh 空间计算）：

- 影调：以中灰为支点的柔和 S 曲线，趾部轻微抬起，高光柔和滚降，白点不变
- 整体饱和度略低于手机默认；只对拐点以上的高饱和做软压缩，渐变平滑不断层
- 肤色：色相向健康的橙黄收拢，略微提亮
- 红色稍浓；绿色压低饱和并偏向橄榄；天空蓝略偏青、略压暗；品紫收敛
- 高光与暗部逐渐去饱和，白平衡略暖（纯白保持纯白）

这是根据公开描述做的风格复刻，不是哈苏的官方算法。

## 关于苹果「调色盘」的外部接口

调研结论：**没有**。

- iOS 的「摄影风格」（色调、色彩、调色板三参数加底色）只在系统相机和照片 App 里提供。AVFoundation 的 `AVCapturePhotoOutput`、`AVCapturePhotoSettings`、`AVCaptureDevice` 里都没有读取或设置风格的 API（已对照 Apple 开发者文档的符号列表核实）。
- 风格的可编辑性依赖系统相机写入 HEIC 的私有数据，第三方 App 无法生成可在照片 App 里继续调整风格的照片。
- 开发者论坛有人反馈 iOS 27 beta 中第三方 App 拍的照片也被套上了系统风格，但那是系统行为，不是可控制的接口。

所以 iPAN 在 App 内用 Core Image 实现了一套交互一致的调色盘，参数直接作用于预览和成片。

## 构建

GitHub Actions（`.github/workflows/build-ipa.yml`）在 `macos-26` runner 上用 Xcode 26 构建**未签名** IPA：

1. 带 submodule checkout
2. `xcodegen generate` 生成工程（`project.yml`）
3. `xcodebuild ... CODE_SIGNING_ALLOWED=NO`
4. 打包 `Payload/iPAN.app` 为 `iPAN-unsigned.ipa` 并作为 artifact 上传
5. 每次推送都会发布一个 GitHub Release（tag `v0.1.<构建序号>`），附带 `iPAN-0.1.<构建序号>-unsigned.ipa`，说明里是本次提交的更改；App 的版本号与构建号同步

本地构建：

```sh
git submodule update --init
brew install xcodegen
xcodegen generate
open iPAN.xcodeproj
```

未签名 IPA 需要自行签名（例如 AltStore、SideStore、TrollStore 或自己的开发者证书）后安装。

## 目录

```
iPAN/
  App/          入口、设置、拍摄流程编排
  Camera/       AVFoundation 会话、焦段映射、Metal 预览
  Processing/   65:24 裁切、胶片/调色盘、HEIC 编码、双摄拼接
  Watermark/    semi-utils 处理管道的 Swift 移植
  UI/           OPPO 风格控件、液态玻璃面板、显影着色器
Vendor/semi-utils  水印项目（submodule）
```
