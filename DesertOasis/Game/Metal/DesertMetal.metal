#include <metal_stdlib>
using namespace metal;
#include <SceneKit/scn_metal>

// MARK: - Shared helpers

static inline float hash21(float2 p) {
    float3 p3 = fract(float3(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

static inline float noise2(float2 p) {
    float2 i = floor(p);
    float2 f = fract(p);
    float a = hash21(i);
    float b = hash21(i + float2(1, 0));
    float c = hash21(i + float2(0, 1));
    float d = hash21(i + float2(1, 1));
    float2 u = f * f * (3.0 - 2.0 * f);
    return mix(a, b, u.x) + (c - a) * u.y * (1.0 - u.x) + (d - b) * u.x * u.y;
}

static inline float fbm(float2 p) {
    float v = 0.0;
    float a = 0.5;
    for (int i = 0; i < 4; ++i) {
        v += a * noise2(p);
        p = p * 2.03 + float2(17.1, 9.7);
        a *= 0.5;
    }
    return v;
}

// MARK: - Procedural sky (SCNProgram on sky dome)

struct SkyVertexIn {
    float3 position [[attribute(SCNVertexSemanticPosition)]];
};

struct SkyVertexOut {
    float4 position [[position]];
    float3 localPos;
};

struct SkyUniforms {
    float3 zenithColor;
    float _pad0;
    float3 horizonColor;
    float _pad1;
    float3 sunDirection;
    float _pad2;
    float3 sunColor;
    float daylight;
    float timeOfDay;
    float stars;
    float sunDisk;
    float _pad3;
};

struct SkyNodeBuffer {
    float4x4 modelViewProjectionTransform;
};

vertex SkyVertexOut sky_vertex(SkyVertexIn in [[stage_in]],
                               constant SCNSceneBuffer& scn_frame [[buffer(0)]],
                               constant SkyNodeBuffer& scn_node [[buffer(1)]]) {
    SkyVertexOut out;
    out.position = scn_node.modelViewProjectionTransform * float4(in.position, 1.0);
    out.localPos = in.position;
    return out;
}

fragment float4 sky_fragment(SkyVertexOut in [[stage_in]],
                             constant SkyUniforms& uniforms [[buffer(0)]]) {
    float3 dir = normalize(in.localPos);
    float elev = dir.y;

    float h = saturate(1.0 - abs(elev) * 1.15);
    float zenithW = saturate(elev * 0.85 + 0.15);
    float3 sky = mix(uniforms.horizonColor, uniforms.zenithColor, zenithW);
    sky = mix(sky, uniforms.horizonColor * 1.15, h * h * 0.35);

    float3 sunDir = normalize(uniforms.sunDirection);
    float mu = saturate(dot(dir, sunDir));
    float glow = pow(mu, 12.0) * uniforms.daylight;
    float disc = smoothstep(0.9994, 0.99985, mu) * uniforms.sunDisk * uniforms.daylight;
    sky += uniforms.sunColor * (glow * 0.55 + disc * 1.4);

    float moonMu = saturate(dot(dir, -sunDir));
    sky += float3(0.55, 0.62, 0.85) * pow(moonMu, 40.0) * (1.0 - uniforms.daylight) * 0.35;

    if (uniforms.stars > 0.01) {
        float2 sp = dir.xz / max(0.05, abs(dir.y) + 0.35) * 48.0;
        float s = step(0.992, hash21(floor(sp)));
        float twinkle = 0.6 + 0.4 * sin(uniforms.timeOfDay * 40.0 + hash21(floor(sp)) * 20.0);
        sky += s * twinkle * uniforms.stars * float3(0.85, 0.9, 1.0);
    }

    return float4(sky, 1.0);
}

// MARK: - Atmosphere post (fog + heat haze + storm dust)

struct AtmosVertexIn {
    float4 position [[attribute(SCNVertexSemanticPosition)]];
};

struct AtmosVertexOut {
    float4 position [[position]];
    float2 uv;
};

vertex AtmosVertexOut atmosphere_vertex(AtmosVertexIn in [[stage_in]]) {
    AtmosVertexOut out;
    out.position = in.position;
    out.uv = float2((in.position.x + 1.0) * 0.5, 1.0 - (in.position.y + 1.0) * 0.5);
    return out;
}

fragment float4 atmosphere_fragment(AtmosVertexOut in [[stage_in]],
                                    constant float& fogStart [[buffer(0)]],
                                    constant float& fogEnd [[buffer(1)]],
                                    constant float3& fogColor [[buffer(2)]],
                                    constant float& time [[buffer(3)]],
                                    constant float& hazeStrength [[buffer(4)]],
                                    constant float& stormDust [[buffer(5)]],
                                    constant float& cameraNear [[buffer(6)]],
                                    constant float& cameraFar [[buffer(7)]],
                                    texture2d<float, access::sample> colorSampler [[texture(0)]],
                                    depth2d<float, access::sample> depthSampler [[texture(1)]]) {
    constexpr sampler s(coord::normalized, address::clamp_to_edge, filter::linear);

    float2 uv = in.uv;
    float depthRaw = depthSampler.sample(s, uv);

    // Reverse-Z clear / far ≈ 0 → sky pixels (dome writes no depth)
    bool isSky = depthRaw < 1.0e-4;

    float linearDepth = 0.0;
    if (!isSky) {
        float z = max(depthRaw, 1.0e-5);
        linearDepth = (cameraNear * cameraFar) / (cameraFar * z + cameraNear * (1.0 - z));
    }

    float2 hazeUV = uv;
    if (!isSky && hazeStrength > 0.001) {
        float mid = smoothstep(12.0, 55.0, linearDepth) * (1.0 - smoothstep(120.0, 220.0, linearDepth));
        float2 n = float2(
            fbm(uv * 18.0 + float2(time * 0.35, 0.0)),
            fbm(uv * 18.0 + float2(40.0, time * 0.28))
        );
        hazeUV += (n - 0.5) * 0.006 * hazeStrength * mid;
    }

    float4 color = colorSampler.sample(s, hazeUV);

    if (!isSky) {
        float fogFactor = saturate((linearDepth - fogStart) / max(0.001, fogEnd - fogStart));
        fogFactor = saturate(fogFactor + (1.0 - uv.y) * 0.08 * fogFactor);
        color.rgb = mix(color.rgb, fogColor, fogFactor);
    }

    if (stormDust > 0.001) {
        float grain = fbm(uv * 90.0 + float2(time * 2.5, time * 1.1));
        float streak = fbm(float2(uv.x * 4.0 + time * 1.8, uv.y * 40.0));
        float dust = mix(grain, streak, 0.45) * stormDust;
        float3 sand = float3(0.82, 0.68, 0.42);
        color.rgb = mix(color.rgb, sand, dust * (isSky ? 0.22 : 0.38));
        color.rgb *= 1.0 - stormDust * 0.12;
    }

    return color;
}
