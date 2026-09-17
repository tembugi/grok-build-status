#!/usr/bin/env swift
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Retina drag-to-Applications backdrop: 540×380 pt at 2x.
let pointWidth = 540
let pointHeight = 380
let scale = 2
let pixelWidth = pointWidth * scale
let pixelHeight = pointHeight * scale

guard CommandLine.arguments.count >= 2 else {
    fputs("usage: render-dmg-background.swift <out.png>\n", stderr)
    exit(1)
}
let outURL = URL(fileURLWithPath: CommandLine.arguments[1])

let colorSpace = CGColorSpaceCreateDeviceRGB()
guard let ctx = CGContext(
    data: nil,
    width: pixelWidth,
    height: pixelHeight,
    bitsPerComponent: 8,
    bytesPerRow: 0,
    space: colorSpace,
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
) else {
    fputs("error: could not create bitmap\n", stderr)
    exit(1)
}

ctx.scaleBy(x: CGFloat(scale), y: CGFloat(scale))

let top = CGColor(srgbRed: 0.965, green: 0.965, blue: 0.972, alpha: 1)
let bottom = CGColor(srgbRed: 0.925, green: 0.925, blue: 0.933, alpha: 1)
var colors: [CGColor] = [top, bottom]
let gradient = CGGradient(colorsSpace: colorSpace, colors: colors as CFArray, locations: [0, 1])!
ctx.drawLinearGradient(
    gradient,
    start: CGPoint(x: 0, y: CGFloat(pointHeight)),
    end: CGPoint(x: 0, y: 0),
    options: []
)

// Finder icon centers at {150, 180} and {390, 180} in this window.
let arrowCenter = CGPoint(x: 270, y: CGFloat(pointHeight) - 180)
ctx.saveGState()
ctx.translateBy(x: arrowCenter.x, y: arrowCenter.y)
ctx.setStrokeColor(CGColor(srgbRed: 0.62, green: 0.62, blue: 0.65, alpha: 1))
ctx.setLineWidth(5)
ctx.setLineCap(.round)
ctx.setLineJoin(.round)
let chevron = CGMutablePath()
chevron.move(to: CGPoint(x: -18, y: 22))
chevron.addLine(to: CGPoint(x: 16, y: 0))
chevron.addLine(to: CGPoint(x: -18, y: -22))
ctx.addPath(chevron)
ctx.strokePath()
ctx.restoreGState()

guard let image = ctx.makeImage() else {
    fputs("error: could not make image\n", stderr)
    exit(1)
}

let dest = CGImageDestinationCreateWithURL(outURL as CFURL, UTType.png.identifier as CFString, 1, nil)
guard let dest else {
    fputs("error: could not write \(outURL.path)\n", stderr)
    exit(1)
}
let dpi: [CFString: Any] = [
    kCGImagePropertyDPIWidth: 144,
    kCGImagePropertyDPIHeight: 144,
    kCGImagePropertyPixelWidth: pixelWidth,
    kCGImagePropertyPixelHeight: pixelHeight,
]
CGImageDestinationAddImage(dest, image, [
    kCGImagePropertyPNGDictionary: dpi,
] as CFDictionary)
guard CGImageDestinationFinalize(dest) else {
    fputs("error: could not finalize \(outURL.path)\n", stderr)
    exit(1)
}
