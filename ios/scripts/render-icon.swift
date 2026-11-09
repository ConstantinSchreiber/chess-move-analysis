// Renders the Tempo app icon (1024×1024 PNG) with SceneKit: a lathed gold pawn inside gold
// viewfinder brackets on a warm near-black field.
// Usage: swift ios/scripts/render-icon.swift <output.png>
import AppKit
import SceneKit

let output = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon.png"
let size = 1024

// MARK: Lathe geometry

/// Catmull-Rom resampling of a 2D profile for smooth silhouettes.
func smooth(_ points: [CGPoint], samples: Int = 6) -> [CGPoint] {
    guard points.count > 2 else { return points }
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

func lathe(_ profile: [CGPoint], segments: Int = 160) -> SCNGeometry {
    var vertices: [SCNVector3] = []
    var normals: [SCNVector3] = []
    var indices: [Int32] = []
    let n = profile.count
    // Profile normals (outward, perpendicular to the tangent).
    var profileNormals: [CGPoint] = []
    for i in 0..<n {
        let a = profile[max(i - 1, 0)], b = profile[min(i + 1, n - 1)]
        let tx = b.x - a.x, ty = b.y - a.y
        let len = max(hypot(tx, ty), 1e-6)
        profileNormals.append(CGPoint(x: ty / len, y: -tx / len))
    }
    for s in 0...segments {
        let angle = CGFloat(s) / CGFloat(segments) * 2 * .pi
        let c = cos(angle), sn = sin(angle)
        for i in 0..<n {
            let p = profile[i], q = profileNormals[i]
            vertices.append(SCNVector3(p.x * c, p.y, p.x * sn))
            normals.append(SCNVector3(q.x * c, q.y, q.x * sn))
        }
    }
    for s in 0..<segments {
        for i in 0..<(n - 1) {
            let a = Int32(s * n + i), b = Int32((s + 1) * n + i)
            indices += [a, a + 1, b, b, a + 1, b + 1]
        }
    }
    let element = SCNGeometryElement(indices: indices, primitiveType: .triangles)
    return SCNGeometry(sources: [SCNGeometrySource(vertices: vertices), SCNGeometrySource(normals: normals)], elements: [element])
}

func pawnProfile() -> [CGPoint] {
    var p: [CGPoint] = [
        CGPoint(x: 0.0, y: 0.0), CGPoint(x: 0.90, y: 0.0), CGPoint(x: 0.96, y: 0.05), CGPoint(x: 0.96, y: 0.14),
        CGPoint(x: 0.86, y: 0.22), CGPoint(x: 0.76, y: 0.27), CGPoint(x: 0.76, y: 0.33), CGPoint(x: 0.64, y: 0.40),
        CGPoint(x: 0.50, y: 0.54), CGPoint(x: 0.40, y: 0.76), CGPoint(x: 0.33, y: 1.00), CGPoint(x: 0.31, y: 1.15),
        CGPoint(x: 0.50, y: 1.21), CGPoint(x: 0.52, y: 1.27), CGPoint(x: 0.45, y: 1.33), CGPoint(x: 0.29, y: 1.37),
    ]
    p = smooth(p, samples: 5)
    // Spherical head.
    let center: CGFloat = 1.72, radius: CGFloat = 0.44
    let start = asin((p.last!.y - center) / radius)
    for k in 1...40 {
        let a = start + (CGFloat.pi / 2 - start) * CGFloat(k) / 40
        p.append(CGPoint(x: radius * cos(a), y: center + radius * sin(a)))
    }
    p[p.count - 1].x = 0
    return p
}

// MARK: Environment map (studio softboxes) for metallic reflections

func environmentImage() -> NSImage {
    let w = 1024, h = 512
    let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    ctx.setFillColor(CGColor(srgbRed: 0.025, green: 0.022, blue: 0.02, alpha: 1))
    ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
    func softbox(_ rect: CGRect, _ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat) {
        let colors = [CGColor(srgbRed: r, green: g, blue: b, alpha: a), CGColor(srgbRed: r, green: g, blue: b, alpha: 0)] as CFArray
        let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!, colors: colors, locations: [0, 1])!
        let c = CGPoint(x: rect.midX, y: rect.midY)
        ctx.drawRadialGradient(gradient, startCenter: c, startRadius: 0, endCenter: c, endRadius: max(rect.width, rect.height) / 2, options: [])
    }
    softbox(CGRect(x: 380, y: 300, width: 260, height: 160), 1, 0.93, 0.8, 1)
    softbox(CGRect(x: 90, y: 220, width: 160, height: 220), 1, 0.75, 0.4, 0.9)
    softbox(CGRect(x: 760, y: 200, width: 180, height: 240), 0.9, 0.85, 0.8, 0.7)
    return NSImage(cgImage: ctx.makeImage()!, size: NSSize(width: w, height: h))
}

// MARK: Scene

let scene = SCNScene()
scene.background.contents = NSColor.clear
scene.lightingEnvironment.contents = environmentImage()
scene.lightingEnvironment.intensity = 2.8

let gold = SCNMaterial()
gold.lightingModel = .physicallyBased
gold.diffuse.contents = NSColor(calibratedRed: 1.0, green: 0.76, blue: 0.40, alpha: 1)
gold.metalness.contents = 1.0
gold.roughness.contents = 0.2

let pawn = SCNNode(geometry: lathe(pawnProfile()))
pawn.geometry?.materials = [gold]
pawn.position = SCNVector3(0, -1.12, 0)
scene.rootNode.addChildNode(pawn)

let key = SCNNode()
key.light = SCNLight()
key.light!.type = .directional
key.light!.intensity = 900
key.light!.color = NSColor(calibratedRed: 1, green: 0.92, blue: 0.8, alpha: 1)
key.eulerAngles = SCNVector3(-0.6, 0.5, 0)
scene.rootNode.addChildNode(key)

let rim = SCNNode()
rim.light = SCNLight()
rim.light!.type = .directional
rim.light!.intensity = 1400
rim.light!.color = NSColor(calibratedRed: 1, green: 0.8, blue: 0.5, alpha: 1)
rim.eulerAngles = SCNVector3(-0.2, .pi * 0.85, 0)
scene.rootNode.addChildNode(rim)

let camera = SCNNode()
camera.camera = SCNCamera()
camera.camera!.fieldOfView = 26
camera.camera!.wantsHDR = true
camera.camera!.bloomIntensity = 0.35
camera.camera!.bloomThreshold = 0.85
camera.position = SCNVector3(0, 0.42, 8.8)
camera.look(at: SCNVector3(0, 0.0, 0))
scene.rootNode.addChildNode(camera)

let renderer = SCNRenderer(device: MTLCreateSystemDefaultDevice(), options: nil)
renderer.scene = scene
renderer.pointOfView = camera
let pieceImage = renderer.snapshot(atTime: 0, with: CGSize(width: size, height: size), antialiasingMode: .multisampling4X)

// MARK: Compose (Core Graphics, works headless)

let s = CGFloat(size)
let space = CGColorSpace(name: CGColorSpace.sRGB)!
let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                    bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
func gradient(_ stops: [(CGFloat, CGFloat, CGFloat, CGFloat)]) -> CGGradient {
    CGGradient(colorsSpace: space, colors: stops.map { CGColor(srgbRed: $0.0, green: $0.1, blue: $0.2, alpha: $0.3) } as CFArray,
               locations: nil)!
}
// Background: warm charcoal, lighter towards the top.
ctx.drawLinearGradient(gradient([(0.03, 0.03, 0.035, 1), (0.115, 0.10, 0.088, 1)]),
                       start: CGPoint(x: 0, y: 0), end: CGPoint(x: 0, y: s), options: [])
// Warm glow behind the piece.
ctx.drawRadialGradient(gradient([(0.95, 0.66, 0.28, 0.32), (0.95, 0.66, 0.28, 0)]),
                       startCenter: CGPoint(x: s / 2, y: s * 0.52), startRadius: 0,
                       endCenter: CGPoint(x: s / 2, y: s * 0.52), endRadius: s * 0.42, options: [])
// Viewfinder brackets.
let bracket = CGMutablePath()
let inset = s * 0.17, arm = s * 0.13, r = s * 0.06
for (cx, cy, dx, dy) in [(inset, inset, 1.0, 1.0), (s - inset, inset, -1.0, 1.0), (inset, s - inset, 1.0, -1.0), (s - inset, s - inset, -1.0, -1.0)] as [(CGFloat, CGFloat, CGFloat, CGFloat)] {
    bracket.move(to: CGPoint(x: cx, y: cy + dy * arm))
    bracket.addLine(to: CGPoint(x: cx, y: cy + dy * r))
    bracket.addArc(tangent1End: CGPoint(x: cx, y: cy), tangent2End: CGPoint(x: cx + dx * r, y: cy), radius: r)
    bracket.addLine(to: CGPoint(x: cx + dx * arm, y: cy))
}
ctx.addPath(bracket)
ctx.setLineWidth(s * 0.026)
ctx.setLineCap(.round)
ctx.setStrokeColor(CGColor(srgbRed: 0.93, green: 0.74, blue: 0.40, alpha: 1))
ctx.strokePath()

var rect = CGRect(x: 0, y: 0, width: s, height: s)
if let piece = pieceImage.cgImage(forProposedRect: &rect, context: nil, hints: nil) {
    ctx.draw(piece, in: CGRect(x: 0, y: s * 0.01, width: s, height: s))
}
let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: output))
print("wrote \(output)")
