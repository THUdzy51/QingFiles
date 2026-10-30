import AppKit
let output = CommandLine.arguments[1]
let image = NSImage(size: NSSize(width: 1024, height: 1024))
image.lockFocus()
let rect = NSRect(x: 70, y: 70, width: 884, height: 884)
NSColor(srgbRed: 0.10, green: 0.43, blue: 0.40, alpha: 1).setFill()
NSBezierPath(roundedRect: rect, xRadius: 204, yRadius: 204).fill()
let folder = NSBezierPath()
folder.move(to: NSPoint(x: 222, y: 352)); folder.line(to: NSPoint(x: 222, y: 686))
folder.curve(to: NSPoint(x: 256, y: 720), controlPoint1: NSPoint(x: 222, y: 710), controlPoint2: NSPoint(x: 234, y: 720))
folder.line(to: NSPoint(x: 430, y: 720)); folder.line(to: NSPoint(x: 490, y: 656)); folder.line(to: NSPoint(x: 768, y: 656))
folder.curve(to: NSPoint(x: 802, y: 622), controlPoint1: NSPoint(x: 792, y: 656), controlPoint2: NSPoint(x: 802, y: 646))
folder.line(to: NSPoint(x: 802, y: 352)); folder.close()
NSColor(srgbRed: 0.65, green: 0.88, blue: 0.80, alpha: 1).setFill(); folder.fill()
NSColor(srgbRed: 0.95, green: 0.99, blue: 0.97, alpha: 1).setFill()
NSBezierPath(roundedRect: NSRect(x: 190, y: 290, width: 644, height: 332), xRadius: 48, yRadius: 48).fill()
NSColor(srgbRed: 0.16, green: 0.56, blue: 0.50, alpha: 1).setFill()
NSBezierPath(roundedRect: NSRect(x: 240, y: 338, width: 212, height: 236), xRadius: 22, yRadius: 22).fill()
NSColor(srgbRed: 0.77, green: 0.90, blue: 0.85, alpha: 1).setFill()
NSBezierPath(roundedRect: NSRect(x: 484, y: 338, width: 298, height: 236), xRadius: 22, yRadius: 22).fill()
NSColor.white.withAlphaComponent(0.8).setFill()
for y in [510, 453, 396] { NSBezierPath(roundedRect: NSRect(x: 270, y: y, width: 146, height: 13), xRadius: 6, yRadius: 6).fill() }
NSColor(srgbRed: 0.18, green: 0.52, blue: 0.46, alpha: 0.55).setFill()
for y in [510, 453, 396] { NSBezierPath(roundedRect: NSRect(x: 520, y: y, width: 210, height: 13), xRadius: 6, yRadius: 6).fill() }
image.unlockFocus()
let rep = NSBitmapImageRep(data: image.tiffRepresentation!)!
try rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: output))
