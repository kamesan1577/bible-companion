import AppKit
let size = NSSize(width: 1024, height: 1024)
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1024, pixelsHigh: 1024, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
let context = NSGraphicsContext(bitmapImageRep: rep)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = context
NSColor(calibratedRed: 0.965, green: 0.953, blue: 0.925, alpha: 1).setFill()
NSBezierPath(rect: NSRect(origin: .zero, size: size)).fill()
let ink = NSColor(calibratedRed: 0.18, green: 0.17, blue: 0.15, alpha: 1)
let gold = NSColor(calibratedRed: 0.57, green: 0.43, blue: 0.23, alpha: 1)
let book = NSBezierPath()
book.move(to: NSPoint(x: 224, y: 288)); book.line(to: NSPoint(x: 224, y: 700))
book.curve(to: NSPoint(x: 512, y: 662), controlPoint1: NSPoint(x: 324, y: 738), controlPoint2: NSPoint(x: 424, y: 727))
book.curve(to: NSPoint(x: 800, y: 700), controlPoint1: NSPoint(x: 600, y: 727), controlPoint2: NSPoint(x: 700, y: 738))
book.line(to: NSPoint(x: 800, y: 288))
book.curve(to: NSPoint(x: 512, y: 260), controlPoint1: NSPoint(x: 698, y: 321), controlPoint2: NSPoint(x: 600, y: 314))
book.curve(to: NSPoint(x: 224, y: 288), controlPoint1: NSPoint(x: 424, y: 314), controlPoint2: NSPoint(x: 326, y: 321)); book.close()
ink.setStroke(); book.lineWidth = 28; book.lineJoinStyle = .round; book.stroke()
let spine = NSBezierPath(); spine.move(to: NSPoint(x:512,y:275));spine.line(to:NSPoint(x:512,y:648));gold.setStroke();spine.lineWidth=16;spine.stroke()
for y in [440.0, 505, 570] {
 for x in [285.0, 575] { let line = NSBezierPath();line.move(to:NSPoint(x:x,y:y));line.line(to:NSPoint(x:x+164,y:y-10));line.lineWidth=12;line.lineCapStyle = .round;gold.setStroke();line.stroke() }
}
NSGraphicsContext.restoreGraphicsState()
try rep.representation(using:.png,properties:[:])!.write(to:URL(fileURLWithPath:CommandLine.arguments[1]))
