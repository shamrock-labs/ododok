#!/usr/bin/env swift
import AppKit
import CoreGraphics

// Usage: swift tools/make_app_icon.swift <output.png> <source-mascot-png>
// The checked-in app icon is intentionally independent from runtime mascot assets.

let args = CommandLine.arguments
guard args.count > 2 else {
    fatalError("usage: swift tools/make_app_icon.swift <output.png> <source-mascot-png>")
}
let outPath = args[1]
let srcPath = args[2]

let size: CGFloat = 1024
let width = Int(size), height = Int(size)

guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
      let ctx = CGContext(data: nil,
                          width: width, height: height,
                          bitsPerComponent: 8, bytesPerRow: 0,
                          space: colorSpace,
                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
else { fatalError("ctx") }

func rgb(_ r: Int, _ g: Int, _ b: Int, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat(r)/255, green: CGFloat(g)/255, blue: CGFloat(b)/255, alpha: a)
}

// === Background: warm cream → peach gradient (앱 butter 톤과 어울림) ===
let grad = CGGradient(colorsSpace: colorSpace,
                      colors: [rgb(255, 240, 220), rgb(255, 198, 162)] as CFArray,
                      locations: [0, 1])!
ctx.drawLinearGradient(grad,
                       start: CGPoint(x: 0, y: size),
                       end: CGPoint(x: 0, y: 0),
                       options: [])

// === Load mascot PNG ===
let srcURL = URL(fileURLWithPath: srcPath)
guard let nsImg = NSImage(contentsOf: srcURL),
      let cgImg = nsImg.cgImage(forProposedRect: nil, context: nil, hints: nil)
else { fatalError("cannot load source image at \(srcPath)") }

let srcW = CGFloat(cgImg.width)
let srcH = CGFloat(cgImg.height)

// Fit mascot to ~80% of canvas (iOS will mask corners; keep safe margin)
let targetMax: CGFloat = size * 0.82
let scale = targetMax / max(srcW, srcH)
let drawW = srcW * scale
let drawH = srcH * scale
// Center horizontally, sit slightly below vertical center so the head reads on home screen
let drawX = (size - drawW) / 2
let drawY = (size - drawH) / 2 - size * 0.02

// Subtle drop shadow under mascot
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -14),
              blur: 28,
              color: rgb(80, 40, 20, 0.25))
ctx.draw(cgImg, in: CGRect(x: drawX, y: drawY, width: drawW, height: drawH))
ctx.restoreGState()

// === Export ===
guard let outImg = ctx.makeImage() else { fatalError("image") }
let rep = NSBitmapImageRep(cgImage: outImg)
guard let data = rep.representation(using: .png, properties: [:]) else { fatalError("png") }
try data.write(to: URL(fileURLWithPath: outPath))
print("wrote \(outPath) (\(data.count) bytes) from \(srcPath)")
