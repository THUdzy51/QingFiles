import Foundation
let folder = URL(fileURLWithPath: CommandLine.arguments[1])
let destination = URL(fileURLWithPath: CommandLine.arguments[2])
func lengthBytes(_ value: Int) -> Data {
    var big = UInt32(value).bigEndian
    return withUnsafeBytes(of: &big) { Data($0) }
}
var chunks = Data()
for (type, file) in [("icp4", "icon_16x16.png"), ("icp5", "icon_32x32.png"), ("ic07", "icon_128x128.png"), ("ic08", "icon_256x256.png"), ("ic09", "icon_512x512.png"), ("ic10", "icon_512x512@2x.png"), ("ic11", "icon_16x16@2x.png"), ("ic12", "icon_32x32@2x.png"), ("ic13", "icon_128x128@2x.png"), ("ic14", "icon_256x256@2x.png")] {
    let png = try Data(contentsOf: folder.appendingPathComponent(file))
    chunks.append(Data(type.utf8)); chunks.append(lengthBytes(png.count + 8)); chunks.append(png)
}
var data = Data("icns".utf8)
data.append(lengthBytes(chunks.count + 8)); data.append(chunks)
try data.write(to: destination)
