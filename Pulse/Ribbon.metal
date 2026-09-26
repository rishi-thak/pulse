#include <metal_stdlib>
#include <SwiftUI/SwiftUI.h>
using namespace metal;

// The sample drawn as a luminous sheet. Every fold parameter has a visible
// counterpart: pitch tints it, stretch spreads its layers, texture shatters
// it, and the filter blurs and cools it.

static float hash21(float2 p) {
    p = fract(p * float2(123.34, 456.21));
    p += dot(p, p + 45.32);
    return fract(p.x * p.y);
}

static float3 hsv2rgb(float3 c) {
    float3 p = abs(fract(c.xxx + float3(0.0, 2.0 / 3.0, 1.0 / 3.0)) * 6.0 - 3.0);
    return c.z * mix(float3(1.0), clamp(p - 1.0, 0.0, 1.0), c.y);
}

static float peakAt(device const float *peaks, int count, float u) {
    if (count < 1) return 0.0;
    float f = clamp(u, 0.0, 0.9999) * float(count);
    int i = int(f);
    int j = min(i + 1, count - 1);
    return mix(peaks[i], peaks[j], fract(f));
}

static float smoothPeak(device const float *peaks, int count, float u, float radius) {
    if (radius <= 0.0005) return peakAt(peaks, count, u);
    float sum = 0.0;
    for (int k = -4; k <= 4; k++) {
        sum += peakAt(peaks, count, u + float(k) * radius * 0.25);
    }
    return sum / 9.0;
}

[[ stitchable ]] half4 ribbon(float2 position, half4 color,
                              float4 bounds, float4 rect,
                              float time, float fold, float level,
                              float hue, float rate, float texture, float filterAmount,
                              float2 trim, float recording, float drawsBackground,
                              device const float *peaks, int peakCount,
                              device const float *heads, int headCount)
{
    float width = max(rect.z - rect.x, 1.0);
    float height = max(rect.w - rect.y, 1.0);
    float u = (position.x - rect.x) / width;
    float v = (position.y - rect.y) / height;

    // Stage: near-black with a slow breathing glow that follows the output level.
    float3 rgb = float3(0.0);
    if (drawsBackground > 0.0) {
        float2 centered = (position.xy - bounds.zw * 0.5) / bounds.zw;
        float vignette = 1.0 - dot(centered, centered) * 1.1;
        rgb = float3(0.018, 0.012, 0.02) * vignette;
        rgb += hsv2rgb(float3(hue, 0.7, 1.0)) * (0.02 + level * 0.06) * exp(-dot(centered, centered) * 4.0);

        // Fine grid that fades in with fold, so the sheet reads as a surface.
        float2 grid = fract(position.xy / 24.0);
        float gridLine = smoothstep(0.96, 1.0, max(grid.x, grid.y));
        rgb += gridLine * 0.03 * (0.3 + fold);
    }

    // Texture shatters the image into displaced horizontal slivers.
    float shatter = texture;
    if (shatter > 0.0) {
        float band = floor(v * 36.0);
        float r = hash21(float2(band, floor(time * 16.0)));
        u += (r - 0.5) * shatter * 0.09 * step(0.55, r);
    }

    float centerY = 0.5;

    // Amplitude, softened by the filter and stepped by texture.
    float a = smoothPeak(peaks, peakCount, u, filterAmount * 0.04);
    a *= (1.0 - filterAmount * 0.3);
    if (shatter > 0.0) {
        float levels = 3.0 + (1.0 - shatter) * 24.0;
        a = floor(a * levels) / levels + sin(time * 40.0 + u * 90.0) * shatter * 0.05;
    }
    a = max(a, 0.0) * 0.44 * (1.0 + level * 0.3);

    float d = abs(v - centerY);
    float depth = a > 0.0005 ? d / a : 10.0;   // 0 at the spine, 1 at the edge

    // Layered rings inside the sheet, spreading apart as time stretches.
    float layerCount = 3.0 + 7.0 * rate;
    float layers = 0.5 + 0.5 * sin(depth * 6.2832 * layerCount - time * 1.6);
    float inside = 1.0 - smoothstep(a - 0.003, a + 0.003, d);
    float rim = smoothstep(0.0, 0.05, 1.0 - depth) * (1.0 - smoothstep(0.05, 0.22, 1.0 - depth));
    float glow = exp(-max(d - a, 0.0) * height * 0.09) * 0.55;

    bool inTrim = u >= trim.x && u <= trim.y;
    float sat = mix(0.25, 0.85, inTrim ? 1.0 : 0.0);
    float bright = inTrim ? 1.0 : 0.3;
    float coolHue = mix(hue, 0.62, filterAmount * 0.6);

    float3 body = hsv2rgb(float3(coolHue, sat, 1.0)) * (0.35 + 0.65 * layers);
    float3 spine = hsv2rgb(float3(coolHue, sat * 0.5, 1.0));
    float3 sheet = mix(body, spine, exp(-depth * 4.0) * 0.6);
    sheet = mix(sheet, float3(1.0), rim * 0.8);

    rgb += sheet * inside * bright;
    rgb += hsv2rgb(float3(coolHue, sat, 1.0)) * glow * bright;

    // Playheads: bright beams with a coloured halo. hue < 0 means white.
    for (int i = 0; i < headCount / 2; i++) {
        float pos = heads[i * 2];
        float headHue = heads[i * 2 + 1];
        float dx = (u - pos) * width;
        float beam = exp(-dx * dx / 18.0);
        float halo = exp(-abs(dx) / 34.0) * 0.35;
        float3 tint = headHue < -1.5 ? float3(0.55, 0.9, 1.0)
                    : headHue < 0.0 ? float3(1.0)
                    : hsv2rgb(float3(headHue, 0.7, 1.0));
        float verticalMask = smoothstep(-0.08, 0.02, v) * smoothstep(1.08, 0.98, v);
        rgb += tint * (beam * 0.9 + halo) * verticalMask;
    }

    // Recording: a red sweep rolls across the stage.
    if (recording > 0.0) {
        float sweep = fract(time * 0.35);
        rgb += float3(1.0, 0.2, 0.25) * exp(-abs(u - sweep) * 30.0) * 0.4;
    }

    // Film grain, heavier with texture.
    if (drawsBackground > 0.0) {
        rgb += (hash21(position.xy + fract(time) * 7.0) - 0.5) * (0.025 + shatter * 0.14);
    }

    return half4(half3(clamp(rgb, 0.0, 1.0)), 1.0h);
}
