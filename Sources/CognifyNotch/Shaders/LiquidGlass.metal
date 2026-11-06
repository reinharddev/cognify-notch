#include <metal_stdlib>
using namespace metal;

// Small, static displacement on the sheen creates a liquid lens impression without sampling the desktop.
[[ stitchable ]]
float2 liquidRefraction(float2 position, float2 size, float amount) {
    float2 uv = position / max(size, float2(1.0));
    float2 centered = uv - float2(0.5);
    float radius = length(centered);
    float rim = smoothstep(0.12, 0.52, radius) * (1.0 - smoothstep(0.40, 0.76, radius));
    float2 wave = float2(sin((uv.y + uv.x * 0.28) * 18.0), cos((uv.x - uv.y * 0.22) * 15.0));
    return position + wave * amount * rim;
}
