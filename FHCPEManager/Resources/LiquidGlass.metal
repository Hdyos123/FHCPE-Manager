#include <metal_stdlib>
#include <SwiftUI/SwiftUI_Metal.h>
using namespace metal;

// MARK: - 液态玻璃折射
//
// 原理：
// 1. 取圆角矩形边缘的法线（往内指）
// 2. 边缘附近按法线方向偏移采样位置 → 产生"背景被弯折"的折射
// 3. 叠加高光、色散（RGB 分离）与内阴影，模拟玻璃厚度
//
// 注意：layer.sample() 越界会返回未定义值（表现为白色斜纹块），
// 所有采样坐标必须 clamp 到 [0, size] 范围内。

static float roundedBoxSDF(float2 p, float2 halfSize, float r) {
    float2 q = abs(p) - halfSize + r;
    return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
}

/// 安全的采样坐标：clamp 到图层范围内（留 0.5px 余量）
static float2 safeCoord(float2 p, float2 size) {
    return clamp(p, float2(0.5, 0.5), size - float2(0.5, 0.5));
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
    float2 grad = float2(dx, dy);
    float glen = length(grad);
    // 梯度为 0 时给一个默认方向，避免 normalize(0) 产生 NaN
    float2 n = glen > 1e-4 ? grad / glen : float2(0.0, -1.0);

    // 折射：越靠近边缘偏移越大
    float bend = pow(1.0 - edgeT, 2.6);
    float2 offset = -n * bend * refractionStrength;

    // 色散
    float ca = bend * refractionStrength * 0.16;

    // 关键：所有采样坐标 clamp 到图层内
    float2 base = position + offset;
    half3 col;
    col.r = layer.sample(safeCoord(base + n * ca, size)).r;
    col.g = layer.sample(safeCoord(base, size)).g;
    col.b = layer.sample(safeCoord(base - n * ca, size)).b;

    // 高光
    float2 lightDir = normalize(float2(cos(lightAngle), sin(lightAngle)));
    float spec = pow(max(dot(-n, lightDir), 0.0), 3.0);
    float rim  = smoothstep(0.0, 0.35, 1.0 - edgeT);

    // 内阴影
    float bottomShade = smoothstep(0.0, 1.0, (p.y + halfSize.y) / max(halfSize.y * 2.0, 1.0));
    col *= mix(1.0, 0.94, bottomShade * 0.5);

    // 边缘高光带
    col += half3(1.0, 1.0, 1.0) * half(spec * 0.55 + rim * 0.06);

    // 浸染色
    col = mix(col, half3(tintColor), half(tintOpacity * (0.35 + 0.65 * rim)));

    // 保持原图 alpha
    half a = layer.sample(safeCoord(position, size)).a;
    return half4(col, a);
}

// MARK: - 玻璃边缘描边

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

    float a = smoothstep(lineWidth, lineWidth * 0.35, inside);

    float v = clamp((p.y + halfSize.y) / max(halfSize.y * 2.0, 1.0), 0.0, 1.0);
    float lum = mix(1.0, 0.25, v);

    return half4(half3(1.0), half(a * intensity * lum));
}
