// Génère l'icône d'app d'UpKeepy (squircle macOS + dégradé + flèche « up »).
// Rendu vectoriel via Core Graphics → PNG à toutes les tailles d'un .iconset.
//
//   swift Tools/make-icon.swift
//   iconutil -c icns AppIcon.iconset -o Resources/AppIcon.icns
//
import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

// MARK: - Palette

// Dégradé « frais » : menthe en haut-gauche → bleu en bas-droite.
let topColor    = CGColor(red: 0.28, green: 0.87, blue: 0.66, alpha: 1) // #48DEA8
let bottomColor = CGColor(red: 0.15, green: 0.39, blue: 0.92, alpha: 1) // #2563EB

let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!

// MARK: - Géométrie

func sgn(_ x: Double) -> Double { x < 0 ? -1 : (x > 0 ? 1 : 0) }

/// Superellipse (squircle Apple-like), n ≈ 5.
func squirclePath(in rect: CGRect, n: Double = 5) -> CGPath {
    let path = CGMutablePath()
    let cx = Double(rect.midX), cy = Double(rect.midY)
    let a = Double(rect.width) / 2, b = Double(rect.height) / 2
    let steps = 720
    for i in 0...steps {
        let t = Double(i) / Double(steps) * 2 * .pi
        let ct = cos(t), st = sin(t)
        let x = cx + a * sgn(ct) * pow(abs(ct), 2 / n)
        let y = cy + b * sgn(st) * pow(abs(st), 2 / n)
        let p = CGPoint(x: x, y: y)
        if i == 0 { path.move(to: p) } else { path.addLine(to: p) }
    }
    path.closeSubpath()
    return path
}

// MARK: - Rendu

func renderIcon(size: Int) -> CGImage {
    let s = CGFloat(size)
    let ctx = CGContext(data: nil, width: size, height: size,
                        bitsPerComponent: 8, bytesPerRow: 0, space: sRGB,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.setShouldAntialias(true)
    ctx.interpolationQuality = .high

    // Le squircle occupe ~80 % du canvas, marge transparente autour (norme macOS).
    let inset = s * 0.095
    let rect = CGRect(x: inset, y: inset, width: s - 2 * inset, height: s - 2 * inset)
    let path = squirclePath(in: rect)

    // Ombre portée douce.
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -s * 0.015),
                  blur: s * 0.05,
                  color: CGColor(red: 0, green: 0, blue: 0, alpha: 0.28))
    ctx.addPath(path)
    ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
    ctx.fillPath()
    ctx.restoreGState()

    // Dégradé principal (clippé au squircle).
    ctx.saveGState()
    ctx.addPath(path)
    ctx.clip()
    let gradient = CGGradient(colorsSpace: sRGB,
                              colors: [topColor, bottomColor] as CFArray,
                              locations: [0, 1])!
    ctx.drawLinearGradient(gradient,
                           start: CGPoint(x: rect.minX, y: rect.maxY),
                           end: CGPoint(x: rect.maxX, y: rect.minY),
                           options: [])

    // Reflet supérieur subtil (gloss).
    let gloss = CGGradient(colorsSpace: sRGB,
                           colors: [CGColor(red: 1, green: 1, blue: 1, alpha: 0.22),
                                    CGColor(red: 1, green: 1, blue: 1, alpha: 0)] as CFArray,
                           locations: [0, 1])!
    ctx.drawLinearGradient(gloss,
                           start: CGPoint(x: rect.midX, y: rect.maxY),
                           end: CGPoint(x: rect.midX, y: rect.midY + rect.height * 0.05),
                           options: [])
    ctx.restoreGState()

    // Flèche « up » blanche, épaisse et arrondie.
    let cx = rect.midX
    let tipY = rect.maxY - rect.height * 0.24
    let baseY = rect.minY + rect.height * 0.24
    let headHalf = rect.width * 0.205
    let headY = tipY - rect.height * 0.205

    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -s * 0.008),
                  blur: s * 0.012,
                  color: CGColor(red: 0, green: 0, blue: 0, alpha: 0.18))
    ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
    ctx.setLineWidth(rect.width * 0.135)
    ctx.setLineCap(.round)
    ctx.setLineJoin(.round)
    // Hampe.
    ctx.move(to: CGPoint(x: cx, y: baseY))
    ctx.addLine(to: CGPoint(x: cx, y: tipY))
    ctx.strokePath()
    // Chevron.
    ctx.move(to: CGPoint(x: cx - headHalf, y: headY))
    ctx.addLine(to: CGPoint(x: cx, y: tipY))
    ctx.addLine(to: CGPoint(x: cx + headHalf, y: headY))
    ctx.strokePath()
    ctx.restoreGState()

    return ctx.makeImage()!
}

func writePNG(_ image: CGImage, to url: URL) {
    guard let dest = CGImageDestinationCreateWithURL(
        url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
        fatalError("Impossible de créer le PNG : \(url.lastPathComponent)")
    }
    CGImageDestinationAddImage(dest, image, nil)
    CGImageDestinationFinalize(dest)
}

// MARK: - Génération de l'iconset

let fm = FileManager.default
let root = URL(fileURLWithPath: fm.currentDirectoryPath)
let iconset = root.appendingPathComponent("AppIcon.iconset")
try? fm.removeItem(at: iconset)
try! fm.createDirectory(at: iconset, withIntermediateDirectories: true)

// (nom de fichier, taille en pixels)
let entries: [(String, Int)] = [
    ("icon_16x16.png", 16),     ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),     ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),  ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),  ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),  ("icon_512x512@2x.png", 1024),
]

for (name, size) in entries {
    let image = renderIcon(size: size)
    writePNG(image, to: iconset.appendingPathComponent(name))
    print("  ✓ \(name) (\(size)px)")
}
print("Iconset généré : \(iconset.path)")
