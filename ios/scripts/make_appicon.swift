// Renders the MitiMaiti app icon: opaque 1024x1024, #0D0D2B gradient
// background with a centered rose->gold gradient heart. Matches SplashView.
// Run: swift make_appicon.swift <output.png>
import AppKit

let size = 1024
let args = CommandLine.arguments
let outPath = args.count > 1 ? args[1] : "AppIcon.png"

func rgb(_ hex: UInt32) -> CGColor {
    CGColor(red: CGFloat((hex >> 16) & 0xFF) / 255.0,
            green: CGFloat((hex >> 8) & 0xFF) / 255.0,
            blue: CGFloat(hex & 0xFF) / 255.0,
            alpha: 1.0)
}

let cs = CGColorSpace(name: CGColorSpace.sRGB)!
guard let ctx = CGContext(
    data: nil, width: size, height: size, bitsPerComponent: 8,
    bytesPerRow: 0, space: cs,
    bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
) else { fatalError("ctx") }

let W = CGFloat(size)

// Background: subtle vertical gradient (splash colors), fully opaque.
let bg = CGGradient(colorsSpace: cs,
                    colors: [rgb(0x161633), rgb(0x0D0D2B), rgb(0x0A0A22)] as CFArray,
                    locations: [0.0, 0.55, 1.0])!
ctx.drawLinearGradient(bg, start: CGPoint(x: 0, y: W),
                       end: CGPoint(x: 0, y: 0), options: [])

// Heart path, centered, ~56% of canvas.
let s = W * 0.56
let cx = W / 2
let cy = W / 2 - W * 0.02
let p = CGMutablePath()
// Parametric heart, sampled — gives a clean rounded silhouette.
let steps = 720
for i in 0...steps {
    let t = CGFloat(i) / CGFloat(steps) * 2 * .pi
    let x = 16 * pow(sin(t), 3)
    let y = 13 * cos(t) - 5 * cos(2*t) - 2 * cos(3*t) - cos(4*t)
    let px = cx + (x / 32) * s
    let py = cy + (y / 32) * s
    if i == 0 { p.move(to: CGPoint(x: px, y: py)) }
    else { p.addLine(to: CGPoint(x: px, y: py)) }
}
p.closeSubpath()

// Soft outer glow (kept subtle so it stays icon-clean).
ctx.saveGState()
ctx.addPath(p)
ctx.setShadow(offset: .zero, blur: 60,
              color: CGColor(red: 0.71, green: 0.20, blue: 0.42, alpha: 0.55))
ctx.setFillColor(rgb(0xB5336A))
ctx.fillPath()
ctx.restoreGState()

// Rose -> gold diagonal gradient fill, clipped to the heart.
ctx.saveGState()
ctx.addPath(p)
ctx.clip()
let heartGrad = CGGradient(colorsSpace: cs,
                           colors: [rgb(0xB5336A), rgb(0xC9527E), rgb(0xD4A853)] as CFArray,
                           locations: [0.0, 0.5, 1.0])!
ctx.drawLinearGradient(heartGrad,
                        start: CGPoint(x: cx - s/2, y: cy + s/2),
                        end: CGPoint(x: cx + s/2, y: cy - s/2),
                        options: [])
ctx.restoreGState()

guard let img = ctx.makeImage() else { fatalError("img") }
let rep = NSBitmapImageRep(cgImage: img)
rep.size = NSSize(width: size, height: size)
guard let png = rep.representation(using: .png, properties: [:]) else { fatalError("png") }
try! png.write(to: URL(fileURLWithPath: outPath))
print("wrote \(outPath) (\(size)x\(size), opaque)")
