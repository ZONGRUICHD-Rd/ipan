#include <metal_stdlib>
#include <SwiftUI/SwiftUI_Metal.h>
using namespace metal;

static float ipanHash(float2 p) {
    p = fract(p * float2(123.34, 456.21));
    p += dot(p, p + 45.32);
    return fract(p.x * p.y);
}

/// 快门后的「负片显影」：画面先以 C-41 彩色负片的样子出现（反相 + 橙色片基 + 颗粒），
/// 再由中心向四周显影成正片。progress: 0 = 负片，1 = 正片。
[[ stitchable ]] half4 filmDevelop(float2 position, half4 color, float2 size, float progress, float seed) {
    float2 uv = position / max(size, float2(1.0));
    float aspect = size.x / max(size.y, 1.0);
    float2 centered = (uv - 0.5) * float2(aspect, 1.0);
    float maxDistance = length(float2(aspect, 1.0) * 0.5);
    float d = length(centered) / maxDistance;

    // 显影前沿：中心先显，边缘后显，带一条柔和的过渡带
    float t = smoothstep(0.0, 1.0, clamp(progress * 1.55 - d * 0.55, 0.0, 1.0));

    half3 positive = color.rgb;
    half3 filmBase = half3(1.0h, 0.60h, 0.36h);
    half3 negative = (1.0h - positive) * filmBase;

    // 显影中段略微过曝，模拟显影液里逐渐浮现的影像
    half3 developed = mix(negative, positive, half(t));
    float glow = sin(t * 3.14159) * 0.12;
    developed += half3(glow);

    float grain = (ipanHash(position + seed) - 0.5) * 0.10 * (1.0 - t * 0.85);
    developed += half3(grain);

    return half4(clamp(developed, 0.0h, 1.0h) * color.a, color.a);
}
