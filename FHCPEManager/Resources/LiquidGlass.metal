#include <metal_stdlib>
#include <SwiftUI/SwiftUI_Metal.h>
using namespace metal;

// MARK: - 液态玻璃折射
//
// 原理：
// 1. 取圆角矩形边缘的法线（往内指）
// 2. 边缘附近按法线方向偏移采样位置 → 产生"背景被弯折"的折射
// 3. 叠加高光、色散（RGB 分离）与内阴影，模拟玻璃厚度

static float roundedBoxSDF(float2 p, float2 halfSize, float r) {
    float2 q = abs(p) - halfSize + r;
    return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
}

[[ stitchable ]] half4 liquidGlassRefraction(
    float2 position,
    SwiftUI::Layer layer,
    float2 size,
    float cornerRadius,
    float edgeWidth,
    float refractionStrength,
    float3 tintColor,
    float tintOpacity,
    float lightAngle
) {
    float2 center = size * 0.5;
    float2 p = position - center;
    float2 halfSize = center;

    // 圆角矩形 SDF（内部为负）
    float d = roundedBoxSDF(p, halfSize, cornerRadius);

    // 到边缘的归一化距离（0 = 边缘，1 = edgeWidth 以外）
    float edgeT = clamp(-d / max(edgeWidth, 0.001), 0.0, 1.0);

    // 边缘法线：SDF 梯度，往内指
    float2 eps = float2(0.75, 0.0);
    float dx = roundedBoxSDF(p + eps.xy, halfSize, cornerRadius)
             - roundedBoxSDF(p - eps.xy, halfSize, cornerRadius);
    float dy = roundedBoxSDF(p + eps.yx, halfSize, cornerRadius)
             - roundedBoxSDF(p - eps.yx, halfSize, cornerRadius);
    float2 n = normalize(float2(dx, dy) + float2(1e-5, 1e-5));

    // 折射：越靠近边缘偏移越大，做了 pow 曲线让过渡更自然
    float bend = pow(1.0 - edgeT, 2.6);
    float2 offset = -n * bend * refractionStrength;

    // 色散：R/G/B 采样位置略有差异，模拟真实玻璃
    float ca = bend * refractionStrength * 0.16;
    half3 col;
    col.r = layer.sample(position + offset + n * ca).r;
    col.g = layer.sample(position + offset).g;
    col.b = layer.sample(position + offset - n * ca).b;

    // 高光：光源方向与法线的夹角
    float2 lightDir = normalize(float2(cos(lightAngle), sin(lightAngle)));
    float spec = pow(max(dot(-n, lightDir), 0.0), 3.0);
    float rim  = smoothstep(0.0, 0.35, 1.0 - edgeT);   // 边缘一圈

    // 内阴影：底部略暗，模拟厚度
    float bottomShade = smoothstep(0.0, 1.0, (p.y + halfSize.y) / (halfSize.y * 2.0));
    col *= mix(1.0, 0.94, bottomShade * 0.5);

    // 边缘高光带
    col += half3(1.0, 1.0, 1.0) * half(spec * 0.55 + rim * 0.06);

    // 浸染色
    col = mix(col, half3(tintColor), half(tintOpacity * (0.35 + 0.65 * rim)));

    return col;
}

// MARK: - 玻璃边缘描边（单独一层，方便控制亮度）

[[ stitchable ]] half4 liquidGlassRim(
    float2 position,
    float2 size,
    float cornerRadius,
    float lineWidth,
    float intensity
) {
    float2 center = size * 0.5;
    float2 p = position - center;
    float2 halfSize = center;

    float d = roundedBoxSDF(p, halfSize, cornerRadius);
    float inside = abs(d);

    // 只画线宽内的像素
    float a = smoothstep(lineWidth, lineWidth * 0.35, inside);

    // 顶部更亮，底部更暗
    float v = clamp((p.y + halfSize.y) / (halfSize.y * 2.0), 0.0, 1.0);
    float lum = mix(1.0, 0.25, v);

    return half4(half3(1.0), half(a * intensity * lum));
}
