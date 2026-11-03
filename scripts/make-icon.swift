import AppKit

let directory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
for (points, scale) in [(16,1),(16,2),(32,1),(32,2),(128,1),(128,2),(256,1),(256,2),(512,1),(512,2)] {
    let pixels = points * scale
    let image = NSImage(size: NSSize(width: pixels, height: pixels))
    image.lockFocus()
    let context = NSGraphicsContext.current!.cgContext
    context.scaleBy(x: CGFloat(pixels) / 1024, y: CGFloat(pixels) / 1024)
    NSColor(calibratedRed: 0.06, green: 0.37, blue: 0.82, alpha: 1).setFill()
    NSBezierPath(roundedRect: NSRect(x: 50,y: 50,width: 924,height: 924), xRadius: 210,yRadius: 210).fill()
    NSColor.white.setStroke()
    let film = NSBezierPath(roundedRect: NSRect(x: 228,y: 240,width: 568,height: 544), xRadius: 36,yRadius: 36)
    film.lineWidth = 32; film.stroke()
    NSColor.white.setFill()
    for x in [252, 728] { for y in stride(from: 282, through: 714, by: 88) {
        NSBezierPath(roundedRect: NSRect(x: x,y: y,width: 44,height: 44),xRadius: 8,yRadius: 8).fill()
    } }
    for (y, width) in [(662, 304), (540, 236), (418, 168)] {
        NSBezierPath(roundedRect: NSRect(x: 360,y: y,width: width,height: 40),xRadius: 20,yRadius: 20).fill()
    }
    image.unlockFocus()
    let bitmap = NSBitmapImageRep(data: image.tiffRepresentation!)!
    let suffix = scale == 2 ? "@2x" : ""
    try bitmap.representation(using: .png, properties: [:])!.write(to: directory.appendingPathComponent("icon_\(points)x\(points)\(suffix).png"))
}
