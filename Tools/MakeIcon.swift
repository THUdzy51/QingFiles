import AppKit
let output = CommandLine.arguments[1]
let image = NSImage(size: NSSize(width: 1024, height: 1024))
image.lockFocus()
let rect = NSRect(x: 70, y: 70, width: 884, height: 884)
NSColor(srgbRed: 0.0, green: 0.36, blue: 0.78, alpha: 1).setFill()
NSBezierPath(roundedRect: rect, xRadius: 204, yRadius: 204).fill()
let folder = NSBezierPath()
folder.move(to: NSPoint(x: 222, y: 352)); folder.line(to: NSPoint(x: 222, y: 686))
folder.curve(to: NSPoint(x: 256, y: 720), controlPoint1: NSPoint(x: 222, y: 710), controlPoint2: NSPoint(x: 234, y: 720))
folder.line(to: NSPoint(x: 430, y: 720)); folder.line(to: NSPoint(x: 490, y: 656)); folder.line(to: NSPoint(x: 768, y: 656))
folder.curve(to: NSPoint(x: 802, y: 622), controlPoint1: NSPoint(x: 792, y: 656), controlPoint2: NSPoint(x: 802, y: 646))
folder.line(to: NSPoint(x: 802, y: 352)); folder.close()
NSColor(srgbRed: 0.64, green: 0.79, blue: 0.98, alpha: 1).setFill(); folder.fill()
NSColor(srgbRed: 0.97, green: 0.98, blue: 1.0, alpha: 1).setFill()
NSBezierPath(roundedRect: NSRect(x: 190, y: 290, width: 644, height: 332), xRadius: 48, yRadius: 48).fill()
NSColor(srgbRed: 0.0, green: 0.44, blue: 0.89, alpha: 1).setFill()
NSBezierPath(roundedRect: NSRect(x: 240, y: 338, width: 212, height: 236), xRadius: 22, yRadius: 22).fill()
NSColor(srgbRed: 0.80, green: 0.88, blue: 0.98, alpha: 1).setFill()
NSBezierPath(roundedRect: NSRect(x: 484, y: 338, width: 298, height: 236), xRadius: 22, yRadius: 22).fill()
NSColor.white.withAlphaComponent(0.8).setFill()
for y in [510, 453, 396] { NSBezierPath(roundedRect: NSRect(x: 270, y: y, width: 146, height: 13), xRadius: 6, yRadius: 6).fill() }
NSColor(srgbRed: 0.12, green: 0.36, blue: 0.66, alpha: 0.55).setFill()
for y in [510, 453, 396] { NSBezierPath(roundedRect: NSRect(x: 520, y: y, width: 210, height: 13), xRadius: 6, yRadius: 6).fill() }
image.unlockFocus()
let rep = NSBitmapImageRep(data: image.tiffRepresentation!)!
try rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: output))
