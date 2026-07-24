import SceneKit
import Metal
import UIKit
import simd

/// Metal sky program + depth-aware fog / heat-haze / storm-dust SCNTechnique.
final class MetalAtmosphere {

    private(set) var technique: SCNTechnique?
    private let skyProgram = SCNProgram()
    private var skyUniforms = SkyUniforms()
    private var elapsed: Float = 0

    private var dustRoot = SCNNode()
    private var dustSystem: SCNParticleSystem?
    private weak var sceneRoot: SCNNode?

    struct SkyUniforms {
        var zenithColor = SIMD3<Float>(0.35, 0.62, 0.92)
        var _pad0: Float = 0
        var horizonColor = SIMD3<Float>(0.78, 0.72, 0.62)
        var _pad1: Float = 0
        var sunDirection = SIMD3<Float>(0.3, 0.7, -0.4)
        var _pad2: Float = 0
        var sunColor = SIMD3<Float>(1.0, 0.92, 0.7)
        var daylight: Float = 1
        var timeOfDay: Float = 0.4
        var stars: Float = 0
        var sunDisk: Float = 1
        var _pad3: Float = 0
    }

    init() {
        skyProgram.vertexFunctionName = "sky_vertex"
        skyProgram.fragmentFunctionName = "sky_fragment"
        skyProgram.isOpaque = true
        skyProgram.handleBinding(ofBufferNamed: "uniforms", frequency: .perFrame) { [weak self] stream, _, _, _ in
            guard let self else { return }
            var u = self.skyUniforms
            stream.writeBytes(&u, count: MemoryLayout<SkyUniforms>.stride)
        }

        technique = Self.makeTechnique()
    }

    // MARK: - Sky material

    func applySkyProgram(to material: SCNMaterial) {
        material.program = skyProgram
        material.lightingModel = .constant
        material.writesToDepthBuffer = false
        material.readsFromDepthBuffer = false
        material.cullMode = .front
        material.isDoubleSided = true
    }

    // MARK: - Technique on cameras

    func attach(to camera: SCNCamera) {
        camera.technique = technique
    }

    func attachDust(to sceneRoot: SCNNode) {
        self.sceneRoot = sceneRoot
        dustRoot.name = "sandstorm_dust"
        if dustRoot.parent == nil {
            sceneRoot.addChildNode(dustRoot)
        }
        if dustSystem == nil {
            let p = SCNParticleSystem()
            p.particleSize = 0.55
            p.particleSizeVariation = 0.35
            p.particleLifeSpan = 2.8
            p.particleLifeSpanVariation = 1.2
            p.particleVelocity = 6
            p.particleVelocityVariation = 4
            p.spreadingAngle = 25
            p.birthRate = 0
            p.loops = true
            p.emitterShape = SCNBox(width: 40, height: 14, length: 40, chamferRadius: 0)
            p.birthDirection = .constant
            p.emittingDirection = SCNVector3(1, 0.08, 0.15)
            p.particleColor = UIColor(red: 0.78, green: 0.64, blue: 0.4, alpha: 0.22)
            p.particleColorVariation = SCNVector4(0.08, 0.06, 0.04, 0.1)
            p.blendMode = .alpha
            p.isLocal = false
            p.orientationMode = .billboardScreenAligned
            p.sortingMode = .distance
            p.particleImage = Self.softDustImage()
            dustRoot.addParticleSystem(p)
            dustSystem = p
        }
    }

    // MARK: - Per-frame

    func update(
        deltaTime: Float,
        timeOfDay: Float,
        daylightFactor: Float,
        skyColor: UIColor,
        fogColor: UIColor,
        fogStart: Float,
        fogEnd: Float,
        stormIntensity: Float,
        sunNode: SCNNode?,
        playerPosition: SCNVector3?,
        isDaytime: Bool,
        cameraNear: Float = 0.2,
        cameraFar: Float = 500
    ) {
        elapsed += deltaTime

        var zr: CGFloat = 0, zg: CGFloat = 0, zb: CGFloat = 0, za: CGFloat = 0
        skyColor.getRed(&zr, green: &zg, blue: &zb, alpha: &za)
        var fr: CGFloat = 0, fg: CGFloat = 0, fb: CGFloat = 0, fa: CGFloat = 0
        fogColor.getRed(&fr, green: &fg, blue: &fb, alpha: &fa)

        let zenith = SIMD3<Float>(Float(zr) * 0.75, Float(zg) * 0.85, min(1, Float(zb) * 1.05))
        let horizon = SIMD3<Float>(Float(fr), Float(fg), Float(fb))

        var sunDir = SIMD3<Float>(0.25, 0.75, -0.4)
        if let sunNode {
            let m = sunNode.worldTransform
            sunDir = SIMD3<Float>(-m.m31, -m.m32, -m.m33)
            let len = max(0.001, simd_length(sunDir))
            sunDir /= len
        }

        skyUniforms.zenithColor = zenith
        skyUniforms.horizonColor = horizon
        skyUniforms.sunDirection = sunDir
        skyUniforms.sunColor = SIMD3<Float>(1.0, 0.9 + 0.08 * daylightFactor, 0.65 + 0.2 * daylightFactor)
        skyUniforms.daylight = daylightFactor
        skyUniforms.timeOfDay = timeOfDay
        skyUniforms.stars = max(0, 1 - daylightFactor * 1.35)
        skyUniforms.sunDisk = skyDetailsSunDisk

        let haze = isDaytime ? max(0.15, daylightFactor) * (0.55 + stormIntensity * 0.35) : 0.05
        let dust = stormIntensity

        technique?.setValue(NSNumber(value: fogStart), forKeyPath: "fogStart")
        technique?.setValue(NSNumber(value: fogEnd), forKeyPath: "fogEnd")
        technique?.setValue(
            NSValue(scnVector3: SCNVector3(horizon.x, horizon.y, horizon.z)),
            forKeyPath: "fogColor"
        )
        technique?.setValue(NSNumber(value: elapsed), forKeyPath: "time")
        technique?.setValue(NSNumber(value: haze), forKeyPath: "hazeStrength")
        technique?.setValue(NSNumber(value: dust), forKeyPath: "stormDust")
        technique?.setValue(NSNumber(value: cameraNear), forKeyPath: "cameraNear")
        technique?.setValue(NSNumber(value: cameraFar), forKeyPath: "cameraFar")

        if let playerPosition {
            dustRoot.position = SCNVector3(playerPosition.x, playerPosition.y + 4, playerPosition.z)
        }
        dustSystem?.birthRate = CGFloat(dust * 220)
        dustSystem?.particleVelocity = CGFloat(5 + dust * 10)
        dustRoot.isHidden = dust < 0.02
    }

    /// When sky details setting is off, hide the procedural sun disc (glow remains mild).
    var skyDetailsSunDisk: Float = 1

    // MARK: - Technique dictionary

    private static func makeTechnique() -> SCNTechnique? {
        let dict: [String: Any] = [
            "passes": [
                "scene_pass": [
                    "draw": "DRAW_SCENE",
                    "inputs": [:],
                    "outputs": [
                        "color": "color_scene",
                        "depth": "depth_scene"
                    ],
                    "colorStates": [
                        "clear": true,
                        "clearColor": "sceneBackground"
                    ]
                ],
                "atmosphere_pass": [
                    "draw": "DRAW_QUAD",
                    "program": "doesntexist",
                    "metalVertexShader": "atmosphere_vertex",
                    "metalFragmentShader": "atmosphere_fragment",
                    "inputs": [
                        "colorSampler": "color_scene",
                        "depthSampler": "depth_scene"
                    ],
                    "outputs": [
                        "color": "COLOR"
                    ]
                ]
            ],
            "sequence": ["scene_pass", "atmosphere_pass"],
            "targets": [
                "color_scene": ["type": "color"],
                "depth_scene": ["type": "depth"]
            ],
            "symbols": [
                "fogStart": ["semantic": "float"],
                "fogEnd": ["semantic": "float"],
                "fogColor": ["semantic": "vec3"],
                "time": ["semantic": "float"],
                "hazeStrength": ["semantic": "float"],
                "stormDust": ["semantic": "float"],
                "cameraNear": ["semantic": "float"],
                "cameraFar": ["semantic": "float"]
            ]
        ]
        return SCNTechnique(dictionary: dict)
    }

    private static func softDustImage() -> UIImage {
        let dim: CGFloat = 64
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: dim, height: dim))
        return renderer.image { ctx in
            let c = ctx.cgContext
            c.clear(CGRect(x: 0, y: 0, width: dim, height: dim))
            let center = CGPoint(x: dim * 0.5, y: dim * 0.5)
            for i in 0..<10 {
                let t = CGFloat(i) / 9
                let r = dim * 0.48 * (1 - t * 0.85)
                UIColor.white.withAlphaComponent(pow(1 - t, 1.8) * 0.7).setFill()
                c.fillEllipse(in: CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2))
            }
        }
    }
}

// MARK: - Shared material modifiers

enum MetalMaterialShaders {
    /// Sand glitter / micro-specular on vertex-colored terrain.
    static let terrainSurface = """
    #pragma body
    float3 n = normalize(_surface.normal);
    float3 v = normalize(_surface.view);
    float ndotv = max(0.0, dot(n, v));
    float fres = pow(1.0 - ndotv, 3.0);
    float spark = fract(sin(dot(_surface.position.xz, float2(12.9898, 78.233))) * 43758.5453);
    spark = smoothstep(0.82, 0.98, spark) * fres;
    // Warm sand sparkle; quieter on darker rock (low luminance vertex color)
    float lum = dot(_surface.diffuse.rgb, float3(0.3, 0.5, 0.2));
    _surface.diffuse.rgb += spark * lum * float3(0.35, 0.28, 0.14);
    _surface.emission.rgb += spark * 0.15 * float3(1.0, 0.9, 0.6);
    """

    /// Fresnel water tint for oasis surface.
    static let waterSurface = """
    #pragma body
    float3 n = normalize(_surface.normal);
    float3 v = normalize(_surface.view);
    float ndotv = max(0.0, dot(n, v));
    float fres = pow(1.0 - ndotv, 2.4);
    float3 deep = float3(0.05, 0.26, 0.40);
    float3 shallow = float3(0.28, 0.68, 0.82);
    float3 sky = float3(0.80, 0.90, 0.98);
    _surface.diffuse.rgb = mix(deep, shallow, fres * 0.7 + 0.15);
    _surface.reflective.rgb = mix(_surface.reflective.rgb, sky, fres * 0.85);
    _surface.specular.rgb = float3(0.95, 0.98, 1.0) * (0.4 + fres * 0.7);
    _surface.shininess = mix(_surface.shininess, 1.0, fres);
    _surface.transparent.a = mix(0.48, 0.22, fres);
    """
}
