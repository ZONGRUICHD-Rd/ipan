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
- 横持时 65:24 沿传感器长边裁切（像素最多）；竖持默认仍输出横幅 65:24（与 OPPO 一致），可在设置里改为竖幅 24:65。
- 焦段到镜头的映射按机型实际镜头自动推算（长焦等效焦距由视场角算出），老机型也能用。
- 默认输出苹果原生 **HEIC**（保留原始 EXIF，更新尺寸、方向与等效焦距）。

## 功能

- **负片显影动效**（仿 OPPO XPAN）：按下快门 → 取景窗口快门帘黑屏 → 画面以 C-41 彩色负片（反相 + 橙色片基 + 颗粒）出现 → 由中心向外显影成正片 → 飞入左下角缩略图。着色器见 `iPAN/UI/Shaders/FilmDevelop.metal`。
- **胶片模式**：XPan 彩色 / 黑白，以及可选的广角边缘失光（暗角）。预览用 Core Image + Metal 实时渲染，所见即所得。
- **调色盘**：底色风格 + 色调/色彩二维盘 + 调色板强度，交互仿 iOS「摄影风格」（原因见下文）。
- **水印**：使用 [semi-utils-ios-support](https://github.com/ZONGRUICHD-Rd/semi-utils-ios-support)（以 git submodule 放在 `Vendor/semi-utils`）。它的模板、Logo、字体原样打包进 App，Python 处理管道（Jinja2 模板 + filters/generators/mergers）移植到了 Swift（`iPAN/Watermark/SemiUtils`）。全部 7 个模板的渲染结果已和真实 Jinja2 逐项比对一致。
- **双摄拼接（测试）**：必须横持。用「双广角」虚拟设备让主摄和超广角同步曝光；超广角按焦距比放大作底，主摄经 Vision 单应性配准后贴在中间，羽化接缝 + 色彩匹配，输出约 13mm 视角的 65:24。配准失败时退回平移配准或居中对齐，成片预览里会显示用了哪种方式。
- **UI**：顶栏、调色盘面板、设置与提示使用 iOS 26 液态玻璃（`glassEffect`）；快门、焦段圆钮、模式轮播、缩略图、对焦框仿 OPPO ColorOS 相机。界面锁定竖屏，横持时图标跟随旋转。

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
