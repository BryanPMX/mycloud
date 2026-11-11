// Export the code-native Mynube mark. Run from the repository root on macOS:
// CLANG_MODULE_CACHE_PATH=/private/tmp/mycloud-brand-cache swift scripts/render-brand.swift
import AppKit
import Foundation

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
func exportMark(_ size: Int, _ relative: String) throws {
    let context = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8,
        bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    context.setFillColor(CGColor(red: 185.0/255, green: 79.0/255, blue: 56.0/255, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: size, height: size))
    context.translateBy(x: 0, y: CGFloat(size))
    context.scaleBy(x: CGFloat(size)/36, y: -CGFloat(size)/36)
    context.setFillColor(CGColor(gray: 1, alpha: 1))
    context.move(to: CGPoint(x: 11, y: 25.5))
    context.addCurve(to: CGPoint(x: 5.8, y: 20.4), control1: CGPoint(x: 8.1, y: 25.5), control2: CGPoint(x: 5.8, y: 23.2))
    context.addCurve(to: CGPoint(x: 10, y: 15.3), control1: CGPoint(x: 5.8, y: 17.9), control2: CGPoint(x: 7.6, y: 15.8))
    context.addCurve(to: CGPoint(x: 17.5, y: 9.4), control1: CGPoint(x: 10.9, y: 11.6), control2: CGPoint(x: 13.9, y: 9.4))
    context.addCurve(to: CGPoint(x: 24.7, y: 15.1), control1: CGPoint(x: 21, y: 9.4), control2: CGPoint(x: 24, y: 11.8))
    context.addCurve(to: CGPoint(x: 30.2, y: 20.4), control1: CGPoint(x: 27.8, y: 15.4), control2: CGPoint(x: 30.2, y: 17.7))
    context.addCurve(to: CGPoint(x: 24.7, y: 25.5), control1: CGPoint(x: 30.2, y: 23.2), control2: CGPoint(x: 27.8, y: 25.5))
    context.closePath(); context.fillPath()
    let rep = NSBitmapImageRep(cgImage: context.makeImage()!)
    let destination = root.appendingPathComponent(relative)
    try rep.representation(using: .png, properties: [:])!.write(to: destination)
}
let iconFolder = "flutter_app/ios/Runner/Assets.xcassets/AppIcon.appiconset/"
let json = try JSONSerialization.jsonObject(with: Data(contentsOf: root.appendingPathComponent(iconFolder + "Contents.json"))) as! [String: Any]
for image in json["images"] as! [[String: String]] {
    guard let filename = image["filename"], let size = image["size"], let scale = image["scale"] else { continue }
    let points = Double(size.split(separator: "x")[0])!
    let multiplier = Double(scale.replacingOccurrences(of: "x", with: ""))!
    try exportMark(Int(points * multiplier), iconFolder + filename)
}
for (density, size) in [("mdpi",48),("hdpi",72),("xhdpi",96),("xxhdpi",144),("xxxhdpi",192)] {
    try exportMark(size, "flutter_app/android/app/src/main/res/mipmap-\(density)/ic_launcher.png")
}
try exportMark(32, "flutter_app/web/favicon.png")
for size in [192, 512] {
    try exportMark(size, "flutter_app/web/icons/Icon-\(size).png")
    try exportMark(size, "flutter_app/web/icons/Icon-maskable-\(size).png")
}
print("Exported Mynube icons for iOS, Android and web.")
