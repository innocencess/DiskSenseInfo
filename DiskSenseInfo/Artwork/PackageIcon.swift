import AppKit
let source = NSImage(contentsOfFile: CommandLine.arguments[1])!
let base = URL(fileURLWithPath: CommandLine.arguments[2])
for size in [16,32,128,256,512] {
    for scale in [1,2] {
        let n = size * scale
        let rep = NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:n,pixelsHigh:n,bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0)!
        NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep:rep); NSGraphicsContext.current?.imageInterpolation = .high
        source.draw(in:NSRect(x:0,y:0,width:n,height:n),from:.zero,operation:.copy,fraction:1)
        NSGraphicsContext.restoreGraphicsState()
        let name = "icon_\(size)x\(size)" + (scale == 2 ? "@2x" : "") + ".png"
        try rep.representation(using:.png,properties:[:])!.write(to:base.appendingPathComponent(name))
    }
}
