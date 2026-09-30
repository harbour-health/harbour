import CoreGraphics
import ImageIO
import Foundation

let output = CommandLine.arguments[1]
let context = CGContext(data: nil, width: 1024, height: 1024, bitsPerComponent: 8, bytesPerRow: 4096, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
context.setFillColor(CGColor(gray: 0, alpha: 1)); context.fill(CGRect(x: 0, y: 0, width: 1024, height: 1024))
for quarter in 0..<4 {
    context.saveGState(); context.translateBy(x: 512, y: 512); context.rotate(by: .pi / 15)
    context.setFillColor(CGColor(gray: 1, alpha: 1))
    context.addPath(CGPath(roundedRect: CGRect(x: quarter % 2 == 0 ? -310 : 65, y: quarter < 2 ? -310 : 65, width: 245, height: 245), cornerWidth: 65, cornerHeight: 65, transform: nil)); context.fillPath()
    context.restoreGState()
}
let destination = CGImageDestinationCreateWithURL(URL(fileURLWithPath: output) as CFURL, "public.png" as CFString, 1, nil)!
CGImageDestinationAddImage(destination, context.makeImage()!, nil)
guard CGImageDestinationFinalize(destination) else { fatalError("Could not write icon") }
