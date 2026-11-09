import UIKit
import CoreVideo

/// A simple 8-bit RGBA bitmap (row 0 = top) with the few operations recognition needs.
struct RGBAImage {
    let width: Int
    let height: Int
    var pixels: [UInt8]

    init(width: Int, height: Int, pixels: [UInt8]) {
        self.width = width
        self.height = height
        self.pixels = pixels
    }

    /// Renders `image` upright (EXIF orientation applied), downscaled so its longest side ≤ `maxSide`.
    init?(image: UIImage, maxSide: CGFloat) {
        let size = image.size
        guard size.width > 0, size.height > 0 else { return nil }
        let scale = min(1, maxSide / max(size.width * image.scale, size.height * image.scale)) * image.scale
        let w = max(1, Int((size.width * scale).rounded())), h = max(1, Int((size.height * scale).rounded()))
        var pixels = [UInt8](repeating: 0, count: w * h * 4)
        let ok = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                          space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                          bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return false }
            context.interpolationQuality = .high
            UIGraphicsPushContext(context)
            // UIKit drawing flips into a top-left origin and applies the image orientation.
            context.translateBy(x: 0, y: CGFloat(h))
            context.scaleBy(x: 1, y: -1)
            image.draw(in: CGRect(x: 0, y: 0, width: w, height: h))
            UIGraphicsPopContext()
            return true
        }
        guard ok else { return nil }
        self.init(width: w, height: h, pixels: pixels)
    }

    func cgImage() -> CGImage? {
        let data = Data(pixels) as CFData
        guard let provider = CGDataProvider(data: data) else { return nil }
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
                       space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
    }

    func uiImage() -> UIImage {
        cgImage().map { UIImage(cgImage: $0) } ?? UIImage()
    }

    /// BGRA pixel buffer of the image at its own size (for Core ML image inputs).
    func pixelBuffer() -> CVPixelBuffer? {
        guard let image = cgImage() else { return nil }
        return Self.makeBuffer(size: width) { context in
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
    }

    /// The `letterbox.crop` region resized to `nw × nh` and placed at `(ox, oy)` on a black square
    /// of `letterbox.target` pixels. Parts of the crop outside the image stay black.
    func letterboxedPixelBuffer(_ letterbox: Letterbox) -> CVPixelBuffer? {
        guard let image = cgImage() else { return nil }
        let s = CGFloat(letterbox.target)
        return Self.makeBuffer(size: letterbox.target) { context in
            context.setFillColor(CGColor(gray: 0, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: s, height: s))
            // Work in top-down coordinates like the rest of the pipeline.
            context.translateBy(x: 0, y: s)
            context.scaleBy(x: 1, y: -1)
            context.clip(to: CGRect(x: letterbox.ox, y: letterbox.oy, width: letterbox.nw, height: letterbox.nh))
            let rect = CGRect(x: CGFloat(letterbox.ox) - letterbox.crop.minX * letterbox.sx,
                              y: CGFloat(letterbox.oy) - letterbox.crop.minY * letterbox.sy,
                              width: CGFloat(width) * letterbox.sx, height: CGFloat(height) * letterbox.sy)
            context.interpolationQuality = .high
            // CGContext.draw puts the image's first row at the rect's max-y; flip locally so it lands on top.
            context.saveGState()
            context.translateBy(x: 0, y: rect.minY + rect.maxY)
            context.scaleBy(x: 1, y: -1)
            context.draw(image, in: rect)
            context.restoreGState()
        }
    }

    /// Uniformly rescaled copy (high-quality filtering), e.g. before warping a very large board.
    func scaled(by factor: CGFloat) -> RGBAImage? {
        guard let image = cgImage() else { return nil }
        let w = max(1, Int((CGFloat(width) * factor).rounded())), h = max(1, Int((CGFloat(height) * factor).rounded()))
        var out = [UInt8](repeating: 0, count: w * h * 4)
        let ok = out.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                          space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                          bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return false }
            context.interpolationQuality = .high
            context.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        return ok ? RGBAImage(width: w, height: h, pixels: out) : nil
    }

    private static func makeBuffer(size: Int, draw: (CGContext) -> Void) -> CVPixelBuffer? {
        var buffer: CVPixelBuffer?
        let attrs = [kCVPixelBufferCGImageCompatibilityKey: true, kCVPixelBufferCGBitmapContextCompatibilityKey: true] as CFDictionary
        guard CVPixelBufferCreate(kCFAllocatorDefault, size, size, kCVPixelFormatType_32BGRA, attrs, &buffer) == kCVReturnSuccess,
              let buffer else { return nil }
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        guard let context = CGContext(data: CVPixelBufferGetBaseAddress(buffer), width: size, height: size, bitsPerComponent: 8,
                                      bytesPerRow: CVPixelBufferGetBytesPerRow(buffer), space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
        else { return nil }
        draw(context)
        return buffer
    }

    /// Perspective-corrects the quadrilateral `quad` (TL, TR, BR, BL in pixels) into a `size`×`size` image.
    /// Output pixel centres map through the homography; sampling is bilinear with edge clamping.
    func warped(quad: [CGPoint], size: Int) -> RGBAImage {
        let s = Double(size)
        let h = Homography(from: [(0, 0), (s, 0), (s, s), (0, s)], to: quad.map { (Double($0.x), Double($0.y)) })
        var out = [UInt8](repeating: 255, count: size * size * 4)
        let w = width, hgt = height
        pixels.withUnsafeBufferPointer { src in
            out.withUnsafeMutableBufferPointer { dst in
                for y in 0..<size {
                    for x in 0..<size {
                        let (u, v) = h.apply(Double(x) + 0.5, Double(y) + 0.5)
                        let fx = min(max(u - 0.5, 0), Double(w - 1)), fy = min(max(v - 0.5, 0), Double(hgt - 1))
                        let x0 = Int(fx), y0 = Int(fy)
                        let x1 = min(x0 + 1, w - 1), y1 = min(y0 + 1, hgt - 1)
                        let ax = fx - Double(x0), ay = fy - Double(y0)
                        let o = (y * size + x) * 4
                        for c in 0..<3 {
                            let p00 = Double(src[(y0 * w + x0) * 4 + c]), p10 = Double(src[(y0 * w + x1) * 4 + c])
                            let p01 = Double(src[(y1 * w + x0) * 4 + c]), p11 = Double(src[(y1 * w + x1) * 4 + c])
                            let top = p00 + (p10 - p00) * ax, bottom = p01 + (p11 - p01) * ax
                            dst[o + c] = UInt8(min(255, max(0, (top + (bottom - top) * ay).rounded())))
                        }
                    }
                }
            }
        }
        return RGBAImage(width: size, height: size, pixels: out)
    }
}

/// 3×3 projective transform estimated from four point correspondences.
struct Homography {
    private let m: [Double]

    init(from src: [(Double, Double)], to dst: [(Double, Double)]) {
        // Solve A·h = b for the 8 unknowns (h33 = 1).
        var a = [[Double]](repeating: [Double](repeating: 0, count: 9), count: 8)
        for i in 0..<4 {
            let (x, y) = src[i], (u, v) = dst[i]
            a[2 * i] = [x, y, 1, 0, 0, 0, -u * x, -u * y, u]
            a[2 * i + 1] = [0, 0, 0, x, y, 1, -v * x, -v * y, v]
        }
        for col in 0..<8 {
            let pivot = (col..<8).max { abs(a[$0][col]) < abs(a[$1][col]) }!
            a.swapAt(col, pivot)
            let p = a[col][col]
            guard abs(p) > 1e-12 else { continue }
            for k in col..<9 { a[col][k] /= p }
            for row in 0..<8 where row != col {
                let f = a[row][col]
                if f != 0 { for k in col..<9 { a[row][k] -= f * a[col][k] } }
            }
        }
        m = (0..<8).map { a[$0][8] } + [1]
    }

    func apply(_ x: Double, _ y: Double) -> (Double, Double) {
        let w = m[6] * x + m[7] * y + m[8]
        return ((m[0] * x + m[1] * y + m[2]) / w, (m[3] * x + m[4] * y + m[5]) / w)
    }
}
