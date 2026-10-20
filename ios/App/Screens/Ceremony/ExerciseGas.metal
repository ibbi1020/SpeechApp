#include <metal_stdlib>
using namespace metal;

static float exerciseHash(float2 p) {
    p = fract(p * float2(123.34, 456.21));
    p += dot(p, p + 45.32);
    return fract(p.x * p.y);
}

static float exerciseNoise(float2 p) {
    float2 i = floor(p);
    float2 f = fract(p);
    float2 u = f * f * (3.0 - 2.0 * f);
    return mix(
        mix(exerciseHash(i), exerciseHash(i + float2(1.0, 0.0)), u.x),
        mix(exerciseHash(i + float2(0.0, 1.0)), exerciseHash(i + float2(1.0, 1.0)), u.x),
        u.y
    );
}

static float2 exerciseRotate(float2 p) {
    return float2(0.80 * p.x - 0.60 * p.y, 0.60 * p.x + 0.80 * p.y);
}

static float exerciseFBM(float2 p) {
    float value = 0.0;
    float amplitude = 0.52;
    for (int octave = 0; octave < 5; octave++) {
        value += amplitude * exerciseNoise(p);
        p = exerciseRotate(p) * 1.92 + float2(9.7, 4.3);
        amplitude *= 0.5;
    }
    return value;
}

static float exerciseSmooth(float edge0, float edge1, float x) {
    float u = clamp((x - edge0) / (edge1 - edge0), 0.0, 1.0);
    return u * u * (3.0 - 2.0 * u);
}

/// Cloud-orb gas. Two close hues advect through warped noise.
/// `time` is the flow clock. `activity` is the speaking twist, already calmed.
/// `gray` pulls the result toward its own luminance.
[[ stitchable ]] half4 exerciseGas(
    float2 position,
    half4 color,
    float2 size,
    float time,
    float activity,
    float gray,
    half4 primary,
    half4 secondary
) {
    float2 uv = position / max(size, float2(1.0));
    float2 centered = uv - 0.5;
    float radius = length(centered);
    float edge = 1.0 - smoothstep(0.47, 0.5, radius);
    if (edge <= 0.0) {
        return half4(0.0);
    }

    float spin = time * 0.09;
    float cs = cos(spin);
    float sn = sin(spin);
    float2 spun = float2(cs * centered.x - sn * centered.y, sn * centered.x + cs * centered.y);
    float2 p = spun * 2.15;

    float2 warp = float2(
        exerciseFBM(p * 1.15 + float2(time * 0.34, -time * 0.24)),
        exerciseFBM(p * 1.22 + float2(-time * 0.27, time * 0.32) + float2(6.7, 2.9))
    );
    float2 curl = float2(
        sin(p.y * 2.4 + time * 0.68 + warp.y * 3.2),
        cos(p.x * 2.1 - time * 0.61 + warp.x * 3.0)
    );
    float amp = 0.81 + activity * 0.54;
    float2 warped = p + (warp - 0.5) * amp + curl * (0.03 + activity * 0.096);

    float broad = exerciseFBM(warped * 0.95 + float2(time * 0.16, -time * 0.12));
    float3 ink = mix(float3(primary.rgb), float3(secondary.rgb), exerciseSmooth(0.25, 0.75, broad));

    float luma = dot(ink, float3(0.2126, 0.7152, 0.0722));
    ink = mix(ink, float3(luma), clamp(gray, 0.0, 1.0));
    return half4(half3(ink), half(edge));
}
