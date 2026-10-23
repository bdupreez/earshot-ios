#!/usr/bin/env swift
// Original Strike artwork: HellzYeahh and Earshot contributors, MIT.
// AI-assisted Core Graphics adaptation of upstream commit7581ec1e Android
// ic_launcher_foreground/background.xml (108-unit geometry, scale0.86).
// Run from repository root: swift ios/scripts/render-strike-icon.swift
import AppKit
import CoreGraphics
import Foundation

let directory = URL(fileURLWithPath: "ios/Earshot/Resources/Assets.xcassets/AppIcon.appiconset")
func color(_ hex: UInt32) -> CGColor {
    CGColor(red: CGFloat((hex >> 16) & 255)/255, green: CGFloat((hex >> 8) & 255)/255, blue: CGFloat(hex & 255)/255, alpha: 1)
}
func render(dark: Bool, monochrome: Bool = false, name: String) throws {
    guard let context = CGContext(data: nil, width: 1024, height: 1024, bitsPerComponent: 8, bytesPerRow: 4096, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { fatalError("Could not create RGB icon renderer") }
    context.translateBy(x: 0, y: 1024); context.scaleBy(x: 1024/108, y: -1024/108)
    func gradient(_ first: UInt32, _ last: UInt32, start: CGPoint, end: CGPoint) {
        let next = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [color(first), color(last)] as CFArray, locations: [0, 1])!
        context.drawLinearGradient(next, start: start, end: end, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    }
    gradient(monochrome ? 0 : dark ? 0x1F281C : 0xF4F5EE, monochrome ? 0 : dark ? 0x0A0D09 : 0xD5DBC8, start: .init(x: 54, y: 0), end: .init(x: 54, y: 108))
    context.translateBy(x: 54, y: 54); context.scaleBy(x: 0.86, y: 0.86); context.translateBy(x: -54, y: -54)
    func channel(left: Bool, band: Bool) {
        context.saveGState()
        if band {
            let clip = CGMutablePath(); clip.addRect(.init(x: 0, y: 0, width: 108, height: 108))
            clip.move(to: .init(x: 51.03, y: 18)); clip.addLine(to: .init(x: 42.5, y: 50)); clip.addLine(to: .init(x: 57.93, y: 50)); clip.addLine(to: .init(x: 67.53, y: 18)); clip.closeSubpath()
            context.addPath(clip); context.clip(using: .evenOdd)
            let path = CGMutablePath()
            if left { path.move(to: .init(x: 35, y: 62)); path.addLine(to: .init(x: 35, y: 56)); path.addArc(center: .init(x: 54, y: 56), radius: 19, startAngle: .pi, endAngle: .pi*1.5, clockwise: false) }
            else { path.move(to: .init(x: 54, y: 37)); path.addArc(center: .init(x: 54, y: 56), radius: 19, startAngle: .pi*1.5, endAngle: .pi*2, clockwise: false); path.addLine(to: .init(x: 73, y: 62)) }
            context.addPath(path); context.setLineWidth(6); context.setLineCap(.butt); context.replacePathWithStrokedPath(); context.clip()
        } else {
            context.addPath(CGPath(roundedRect: .init(x: left ? 30 : 68, y: 56, width: 10, height: 20), cornerWidth: 2.5, cornerHeight: 2.5, transform: nil)); context.clip()
        }
        gradient(monochrome ? 0xFFFFFF : left ? 0xFF8F45 : 0x4CC27F, monochrome ? 0xFFFFFF : left ? 0xF2541B : 0x1E8E55, start: .init(x: 54, y: 34), end: .init(x: 54, y: 76))
        context.restoreGState()
    }
    channel(left: true, band: true); channel(left: false, band: true); channel(left: true, band: false); channel(left: false, band: false)
    let bolt = CGMutablePath()
    let points: [(CGFloat, CGFloat)] = [(52,26),(62,26),(56,46),(64,46),(48,80),(52,56),(44,56)]
    bolt.move(to: .init(x: points[0].0, y: points[0].1)); for point in points.dropFirst() { bolt.addLine(to: .init(x: point.0, y: point.1)) }; bolt.closeSubpath()
    context.addPath(bolt); context.clip()
    gradient(monochrome ? 0xFFFFFF : dark ? 0xFFDB52 : 0x1C2316, monochrome ? 0xFFFFFF : dark ? 0xFFAE12 : 0x1C2316, start: .init(x: 54, y: 26), end: .init(x: 54, y: 80))
    let bitmap = NSBitmapImageRep(cgImage: context.makeImage()!)
    try bitmap.representation(using: .png, properties: [:])!.write(to: directory.appendingPathComponent(name))
}
try render(dark: false, name: "AppIcon.png")
try render(dark: true, name: "AppIcon-dark.png")
try render(dark: true, monochrome: true, name: "AppIcon-tinted.png")
print("Rendered three1024px opaque Strike adaptations; original artwork credited to upstream Earshot.")
