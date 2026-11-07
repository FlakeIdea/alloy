// Draws Alloy's 1024×1024 app icon: a geometric A split down the middle into bright silver and darker steel, two
// metals joined into one, on a flat near-black tile. One shape, no effects, so it reads at 16 px.
// Usage: swift scripts/make-icon.swift <output.png>
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let size = 1024
let space = CGColorSpace(name: CGColorSpace.displayP3)!
let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(colorSpace: space, components: [CGFloat(hex >> 16 & 0xFF) / 255, CGFloat(hex >> 8 & 0xFF) / 255,
                                            CGFloat(hex & 0xFF) / 255, alpha])!
}

// Tile on Apple's icon grid: 824 pt body inside a 1024 canvas.
let tile = CGPath(roundedRect: CGRect(x: 100, y: 100, width: 824, height: 824), cornerWidth: 186, cornerHeight: 186, transform: nil)
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -8), blur: 20, color: color(0x000000, 0.25))
ctx.addPath(tile); ctx.setFillColor(color(0x141416)); ctx.fillPath()
ctx.restoreGState()

// The mark: a solid triangle with the two counters (above and below the crossbar) cut out, filled even-odd so there
// are no seams, then painted in two tones either side of the centre line. Coordinates have y pointing up.
let apex = CGPoint(x: 512, y: 790), footY: CGFloat = 255, outerFoot: CGFloat = 230, legWidth: CGFloat = 104
let slope = outerFoot / (apex.y - footY)               // x per unit of height along a leg
func innerLeft(_ y: CGFloat) -> CGPoint { CGPoint(x: apex.x - outerFoot + legWidth + slope * (y - footY), y: y) }
func innerRight(_ y: CGFloat) -> CGPoint { CGPoint(x: 2 * apex.x - innerLeft(y).x, y: y) }
let innerApex = CGPoint(x: apex.x, y: footY + (outerFoot - legWidth) / slope)
let barLow: CGFloat = 352, barHigh: CGFloat = 414
let mark = CGMutablePath()
mark.addLines(between: [CGPoint(x: apex.x - outerFoot, y: footY), apex, CGPoint(x: apex.x + outerFoot, y: footY)])
mark.closeSubpath()
mark.addLines(between: [innerLeft(barHigh), innerApex, innerRight(barHigh)])
mark.closeSubpath()
mark.addLines(between: [innerLeft(footY), innerLeft(barLow), innerRight(barLow), innerRight(footY)])
mark.closeSubpath()

func paint(half: CGRect, top: UInt32, bottom: UInt32) {
    ctx.saveGState()
    ctx.addPath(mark); ctx.clip(using: .evenOdd)
    ctx.clip(to: half)
    let gradient = CGGradient(colorsSpace: space, colors: [color(top), color(bottom)] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: apex.y), end: CGPoint(x: 0, y: footY), options: [])
    ctx.restoreGState()
}
paint(half: CGRect(x: 0, y: 0, width: apex.x, height: CGFloat(size)), top: 0xFFFFFF, bottom: 0xD6D8DE)
paint(half: CGRect(x: apex.x, y: 0, width: apex.x, height: CGFloat(size)), top: 0xB4B7BF, bottom: 0x7F838C)

let out = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "AppIcon.png")
let dest = CGImageDestinationCreateWithURL(out as CFURL, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(dest, ctx.makeImage()!, nil)
guard CGImageDestinationFinalize(dest) else { fatalError("Could not write \(out.path)") }
print("Wrote \(out.path)")
