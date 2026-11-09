import SwiftUI
import SceneKit
import Observation

/// Renders the 3D hero scene once, off the main thread, and caches the image on disk so later
/// launches show it instantly. (A live SCNView would compile shaders on the main thread.)
@Observable
@MainActor
final class HeroRenderer {
    static let shared = HeroRenderer()
    private(set) var image: UIImage?
    private var rendering = false
    private static let version = 3

    func load(size: CGSize) {
        guard image == nil, !rendering, size.width > 0, size.height > 0 else { return }
        rendering = true
        let scale = UITraitCollection.current.displayScale
        let pixelSize = CGSize(width: (size.width * scale).rounded(), height: (size.height * scale).rounded())
        let url = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("hero-v\(Self.version)-\(Int(pixelSize.width))x\(Int(pixelSize.height)).jpg")
        Task.detached(priority: .utility) {
            var result: UIImage?
            if let data = try? Data(contentsOf: url), let cached = UIImage(data: data, scale: scale) {
                result = cached
            } else if let rendered = HeroScene.render(pixelSize: pixelSize) {
                result = UIImage(cgImage: rendered.cgImage!, scale: scale, orientation: .up)
                try? rendered.jpegData(compressionQuality: 0.9)?.write(to: url, options: .atomic)
            }
            await MainActor.run {
                withAnimation(.easeOut(duration: 0.8)) { self.image = result }
                self.rendering = false
            }
        }
    }
}

enum HeroScene {
    static func make() -> SCNScene {
        let scene = SCNScene()
        scene.background.contents = UIColor(red: 0.039, green: 0.043, blue: 0.055, alpha: 1)
        scene.lightingEnvironment.contents = environment()
        scene.lightingEnvironment.intensity = 1.4
        scene.fogStartDistance = 9
        scene.fogEndDistance = 22
        scene.fogColor = UIColor(red: 0.039, green: 0.043, blue: 0.055, alpha: 1)

        let root = scene.rootNode
        root.addChildNode(board())

        let black = material(diffuse: UIColor(white: 0.035, alpha: 1), roughness: 0.22, clearCoat: true)
        let ivory = material(diffuse: UIColor(red: 0.86, green: 0.80, blue: 0.70, alpha: 1), roughness: 0.32, clearCoat: true)
        let gold = material(diffuse: UIColor(red: 1.0, green: 0.76, blue: 0.40, alpha: 1), roughness: 0.2, metal: true)

        // (piece, material, file, rank) on a board with 1-unit squares centred at the origin.
        let layout: [(Profile, SCNMaterial, Double, Double)] = [
            (.king, gold, 4, 3.6),
            (.queen, black, 3, 5),
            (.bishop, black, 5.6, 5.4),
            (.pawn, black, 2, 4.3),
            (.pawn, black, 6.6, 4.1),
            (.rook, black, 0.6, 6.4),
            (.pawn, ivory, 3.3, 2.1),
            (.bishop, ivory, 1.4, 1.6),
            (.pawn, ivory, 5.7, 1.9),
            (.queen, ivory, 7.2, 1.2),
            (.rook, ivory, -0.2, 0.4),
        ]
        for (profile, mat, file, rank) in layout {
            let node = piece(profile, material: mat)
            node.position = SCNVector3(Float(file) - 3.5, 0.06, 3.5 - Float(rank))
            node.scale = SCNVector3(0.36, 0.36, 0.36)
            node.eulerAngles.y = Float.random(in: 0...(2 * .pi))
            root.addChildNode(node)
        }

        // Warm key light from above right, cool-ish rim from behind, faint fill.
        let key = SCNNode()
        key.light = SCNLight()
        key.light!.type = .spot
        key.light!.intensity = 1600
        key.light!.color = UIColor(red: 1, green: 0.84, blue: 0.62, alpha: 1)
        key.light!.spotInnerAngle = 18
        key.light!.spotOuterAngle = 62
        key.light!.castsShadow = true
        key.light!.shadowRadius = 6
        key.light!.shadowSampleCount = 8
        key.light!.shadowColor = UIColor(white: 0, alpha: 0.7)
        key.position = SCNVector3(2.5, 6.5, 1.5)
        key.look(at: SCNVector3(0.5, 0, -0.5))
        root.addChildNode(key)

        let rim = SCNNode()
        rim.light = SCNLight()
        rim.light!.type = .directional
        rim.light!.intensity = 650
        rim.light!.color = UIColor(red: 1, green: 0.78, blue: 0.5, alpha: 1)
        rim.eulerAngles = SCNVector3(-0.35, .pi * 0.92, 0)
        root.addChildNode(rim)

        let fill = SCNNode()
        fill.light = SCNLight()
        fill.light!.type = .ambient
        fill.light!.intensity = 40
        fill.light!.color = UIColor(red: 0.6, green: 0.65, blue: 0.8, alpha: 1)
        root.addChildNode(fill)

        let camera = SCNNode()
        camera.name = "camera"
        camera.camera = SCNCamera()
        camera.camera!.fieldOfView = 34
        camera.camera!.wantsHDR = true
        camera.camera!.bloomIntensity = 0.45
        camera.camera!.bloomThreshold = 0.9
        camera.camera!.bloomBlurRadius = 10
        camera.camera!.vignettingIntensity = 0.6
        camera.camera!.vignettingPower = 1.2
        camera.camera!.wantsDepthOfField = true
        camera.camera!.focusDistance = 6.1
        camera.camera!.fStop = 1.6
        camera.camera!.apertureBladeCount = 7
        camera.camera!.wantsExposureAdaptation = false
        camera.position = SCNVector3(1.4, 2.6, 5.9)
        camera.look(at: SCNVector3(0.35, 0.55, -0.6))
        root.addChildNode(camera)

        return scene
    }

    static func render(pixelSize: CGSize) -> UIImage? {
        guard let device = MTLCreateSystemDefaultDevice() else { return nil }
        let scene = make()
        let renderer = SCNRenderer(device: device, options: nil)
        renderer.scene = scene
        renderer.pointOfView = scene.rootNode.childNode(withName: "camera", recursively: false)
        return renderer.snapshot(atTime: 0, with: pixelSize, antialiasingMode: .multisampling4X)
    }

    // MARK: Pieces

    enum Profile { case pawn, rook, bishop, queen, king }

    private static func piece(_ profile: Profile, material: SCNMaterial) -> SCNNode {
        let node = SCNNode(geometry: lathe(points(for: profile)))
        node.geometry?.materials = [material]
        switch profile {
        case .rook:
            for i in 0..<6 {
                let merlon = SCNNode(geometry: SCNBox(width: 0.26, height: 0.2, length: 0.2, chamferRadius: 0.03))
                merlon.geometry?.materials = [material]
                let angle = Float(i) / 6 * 2 * .pi
                merlon.position = SCNVector3(0.58 * cos(angle), 2.4, 0.58 * sin(angle))
                merlon.eulerAngles.y = -angle
                node.addChildNode(merlon)
            }
        case .king:
            let vertical = SCNNode(geometry: SCNBox(width: 0.13, height: 0.5, length: 0.13, chamferRadius: 0.03))
            vertical.position = SCNVector3(0, 3.62, 0)
            let horizontal = SCNNode(geometry: SCNBox(width: 0.38, height: 0.13, length: 0.13, chamferRadius: 0.03))
            horizontal.position = SCNVector3(0, 3.68, 0)
            for part in [vertical, horizontal] {
                part.geometry?.materials = [material]
                node.addChildNode(part)
            }
        default:
            break
        }
        return node
    }

    private static let base: [CGPoint] = [
        CGPoint(x: 0, y: 0), CGPoint(x: 0.98, y: 0), CGPoint(x: 1.03, y: 0.05), CGPoint(x: 1.03, y: 0.16),
        CGPoint(x: 0.93, y: 0.24), CGPoint(x: 0.80, y: 0.29), CGPoint(x: 0.80, y: 0.36), CGPoint(x: 0.68, y: 0.42),
    ]

    private static func points(for profile: Profile) -> [CGPoint] {
        func ball(on points: [CGPoint], center: CGFloat, radius: CGFloat) -> [CGPoint] {
            var p = points
            let start = asin(max(-1, min(1, (p.last!.y - center) / radius)))
            for k in 1...24 {
                let a = start + (CGFloat.pi / 2 - start) * CGFloat(k) / 24
                p.append(CGPoint(x: radius * cos(a), y: center + radius * sin(a)))
            }
            p[p.count - 1].x = 0
            return p
        }
        switch profile {
        case .pawn:
            let body = smooth(base + [
                CGPoint(x: 0.52, y: 0.56), CGPoint(x: 0.40, y: 0.78), CGPoint(x: 0.33, y: 1.0), CGPoint(x: 0.31, y: 1.15),
                CGPoint(x: 0.50, y: 1.21), CGPoint(x: 0.52, y: 1.27), CGPoint(x: 0.45, y: 1.33), CGPoint(x: 0.29, y: 1.37),
            ])
            return ball(on: body, center: 1.72, radius: 0.44)
        case .rook:
            return smooth(base + [
                CGPoint(x: 0.62, y: 0.52), CGPoint(x: 0.56, y: 0.85), CGPoint(x: 0.53, y: 1.35), CGPoint(x: 0.56, y: 1.6),
                CGPoint(x: 0.70, y: 1.68), CGPoint(x: 0.73, y: 1.74), CGPoint(x: 0.66, y: 1.80), CGPoint(x: 0.64, y: 2.1),
                CGPoint(x: 0.72, y: 2.14), CGPoint(x: 0.72, y: 2.30), CGPoint(x: 0.45, y: 2.31), CGPoint(x: 0.0, y: 2.31),
            ], samples: 3)
        case .bishop:
            let body = smooth(base + [
                CGPoint(x: 0.6, y: 0.52), CGPoint(x: 0.47, y: 0.85), CGPoint(x: 0.39, y: 1.25), CGPoint(x: 0.35, y: 1.65),
                CGPoint(x: 0.38, y: 1.78), CGPoint(x: 0.62, y: 1.84), CGPoint(x: 0.64, y: 1.9), CGPoint(x: 0.48, y: 1.96),
                CGPoint(x: 0.36, y: 2.0), CGPoint(x: 0.45, y: 2.14), CGPoint(x: 0.53, y: 2.35), CGPoint(x: 0.5, y: 2.56),
                CGPoint(x: 0.39, y: 2.76), CGPoint(x: 0.24, y: 2.9), CGPoint(x: 0.1, y: 2.98),
            ])
            return ball(on: body, center: 3.07, radius: 0.12)
        case .queen:
            let body = smooth(base + [
                CGPoint(x: 0.62, y: 0.52), CGPoint(x: 0.48, y: 0.95), CGPoint(x: 0.38, y: 1.55), CGPoint(x: 0.34, y: 2.05),
                CGPoint(x: 0.37, y: 2.24), CGPoint(x: 0.63, y: 2.31), CGPoint(x: 0.65, y: 2.37), CGPoint(x: 0.45, y: 2.45),
                CGPoint(x: 0.41, y: 2.53), CGPoint(x: 0.5, y: 2.75), CGPoint(x: 0.62, y: 3.0), CGPoint(x: 0.66, y: 3.08),
                CGPoint(x: 0.5, y: 3.14), CGPoint(x: 0.3, y: 3.22), CGPoint(x: 0.14, y: 3.3),
            ])
            return ball(on: body, center: 3.42, radius: 0.14)
        case .king:
            return smooth(base + [
                CGPoint(x: 0.62, y: 0.52), CGPoint(x: 0.48, y: 0.95), CGPoint(x: 0.38, y: 1.55), CGPoint(x: 0.35, y: 2.1),
                CGPoint(x: 0.38, y: 2.3), CGPoint(x: 0.65, y: 2.38), CGPoint(x: 0.67, y: 2.44), CGPoint(x: 0.46, y: 2.52),
                CGPoint(x: 0.42, y: 2.6), CGPoint(x: 0.5, y: 2.86), CGPoint(x: 0.58, y: 3.1), CGPoint(x: 0.55, y: 3.2),
                CGPoint(x: 0.38, y: 3.29), CGPoint(x: 0.18, y: 3.36), CGPoint(x: 0, y: 3.39),
            ])
        }
    }

    /// Catmull-Rom resampling for smooth silhouettes.
    private static func smooth(_ points: [CGPoint], samples: Int = 5) -> [CGPoint] {
        var out: [CGPoint] = []
        for i in 0..<(points.count - 1) {
            let p0 = points[max(i - 1, 0)], p1 = points[i], p2 = points[i + 1], p3 = points[min(i + 2, points.count - 1)]
            for s in 0..<samples {
                let t = CGFloat(s) / CGFloat(samples), t2 = t * t, t3 = t2 * t
                func f(_ a: CGFloat, _ b: CGFloat, _ c: CGFloat, _ d: CGFloat) -> CGFloat {
                    0.5 * (2 * b + (-a + c) * t + (2 * a - 5 * b + 4 * c - d) * t2 + (-a + 3 * b - 3 * c + d) * t3)
                }
                out.append(CGPoint(x: max(0, f(p0.x, p1.x, p2.x, p3.x)), y: f(p0.y, p1.y, p2.y, p3.y)))
            }
        }
        out.append(points.last!)
        return out
    }

    private static func lathe(_ profile: [CGPoint], segments: Int = 72) -> SCNGeometry {
        var vertices: [SCNVector3] = []
        var normals: [SCNVector3] = []
        var indices: [Int32] = []
        let n = profile.count
        var profileNormals: [CGPoint] = []
        for i in 0..<n {
            let a = profile[max(i - 1, 0)], b = profile[min(i + 1, n - 1)]
            let tx = b.x - a.x, ty = b.y - a.y
            let len = max(hypot(tx, ty), 1e-6)
            profileNormals.append(CGPoint(x: ty / len, y: -tx / len))
        }
        for s in 0...segments {
            let angle = Float(s) / Float(segments) * 2 * .pi
            let c = cos(angle), sn = sin(angle)
            for i in 0..<n {
                let p = profile[i], q = profileNormals[i]
                vertices.append(SCNVector3(Float(p.x) * c, Float(p.y), Float(p.x) * sn))
                normals.append(SCNVector3(Float(q.x) * c, Float(q.y), Float(q.x) * sn))
            }
        }
        for s in 0..<segments {
            for i in 0..<(n - 1) {
                let a = Int32(s * n + i), b = Int32((s + 1) * n + i)
                indices += [a, a + 1, b, b, a + 1, b + 1]
            }
        }
        return SCNGeometry(sources: [SCNGeometrySource(vertices: vertices), SCNGeometrySource(normals: normals)],
                           elements: [SCNGeometryElement(indices: indices, primitiveType: .triangles)])
    }

    // MARK: Materials & board

    private static func material(diffuse: UIColor, roughness: CGFloat, metal: Bool = false, clearCoat: Bool = false) -> SCNMaterial {
        let m = SCNMaterial()
        m.lightingModel = .physicallyBased
        m.diffuse.contents = diffuse
        m.metalness.contents = metal ? 1.0 : 0.0
        m.roughness.contents = roughness
        if clearCoat {
            m.clearCoat.contents = 1.0
            m.clearCoatRoughness.contents = 0.08
        }
        return m
    }

    private static func board() -> SCNNode {
        let size = 512
        let image = UIGraphicsImageRenderer(size: CGSize(width: size, height: size)).image { ctx in
            let s = CGFloat(size) / 8
            for rank in 0..<8 {
                for file in 0..<8 {
                    let light = (rank + file) % 2 == 0
                    (light ? UIColor(red: 0.47, green: 0.39, blue: 0.30, alpha: 1)
                           : UIColor(red: 0.17, green: 0.12, blue: 0.09, alpha: 1)).setFill()
                    ctx.fill(CGRect(x: CGFloat(file) * s, y: CGFloat(rank) * s, width: s, height: s))
                }
            }
        }
        let box = SCNBox(width: 8.6, height: 0.12, length: 8.6, chamferRadius: 0.04)
        let top = SCNMaterial()
        top.lightingModel = .physicallyBased
        top.diffuse.contents = image
        top.diffuse.contentsTransform = SCNMatrix4Translate(SCNMatrix4MakeScale(8.6 / 8, 8.6 / 8, 1), -0.0375, -0.0375, 0)
        top.diffuse.wrapS = .clampToBorder
        top.diffuse.wrapT = .clampToBorder
        top.diffuse.borderColor = UIColor(red: 0.09, green: 0.06, blue: 0.045, alpha: 1)
        top.roughness.contents = 0.28
        top.metalness.contents = 0.0
        let side = SCNMaterial()
        side.lightingModel = .physicallyBased
        side.diffuse.contents = UIColor(red: 0.09, green: 0.06, blue: 0.045, alpha: 1)
        side.roughness.contents = 0.4
        box.materials = [side, side, side, side, top, side]
        let node = SCNNode(geometry: box)
        node.position = SCNVector3(0, 0, 0)
        return node
    }

    /// Procedural studio environment so lacquer and gold pick up soft highlights.
    private static func environment() -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: 512, height: 256)).image { ctx in
            UIColor(red: 0.02, green: 0.02, blue: 0.025, alpha: 1).setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 512, height: 256))
            let cg = ctx.cgContext
            func softbox(_ center: CGPoint, _ radius: CGFloat, _ color: UIColor) {
                let colors = [color.cgColor, color.withAlphaComponent(0).cgColor] as CFArray
                let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1])!
                cg.drawRadialGradient(gradient, startCenter: center, startRadius: 0, endCenter: center, endRadius: radius, options: [])
            }
            softbox(CGPoint(x: 300, y: 60), 70, UIColor(red: 1, green: 0.9, blue: 0.75, alpha: 1))
            softbox(CGPoint(x: 90, y: 100), 50, UIColor(red: 1, green: 0.72, blue: 0.4, alpha: 0.8))
            softbox(CGPoint(x: 440, y: 110), 45, UIColor(red: 0.8, green: 0.8, blue: 0.85, alpha: 0.5))
        }
    }
}
