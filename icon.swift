// Renders Thock's 1024px app icon: a single mechanical keycap on a dark tile. Usage: swift icon.swift out.png
import AppKit

let size = 1024.0
let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { _ in
    // Background tile (macOS icon grid: 824px squircle-ish rounded rect centered in 1024).
    let tile = NSBezierPath(roundedRect: NSRect(x: 100, y: 100, width: 824, height: 824), xRadius: 185, yRadius: 185)
    NSGradient(starting: NSColor(calibratedRed: 0.16, green: 0.17, blue: 0.21, alpha: 1),
               ending: NSColor(calibratedRed: 0.07, green: 0.07, blue: 0.09, alpha: 1))!.draw(in: tile, angle: -90)

    // Keycap shadow on the tile.
    NSGraphicsContext.current!.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.55)
    shadow.shadowBlurRadius = 40
    shadow.shadowOffset = NSSize(width: 0, height: -24)
    shadow.set()
    // Keycap skirt (sides): wider, darker.
    let skirt = NSBezierPath(roundedRect: NSRect(x: 262, y: 250, width: 500, height: 480), xRadius: 80, yRadius: 80)
    NSColor(calibratedRed: 0.80, green: 0.36, blue: 0.14, alpha: 1).setFill()
    skirt.fill()
    NSGraphicsContext.current!.restoreGraphicsState()
    NSGradient(starting: NSColor(calibratedRed: 0.93, green: 0.47, blue: 0.20, alpha: 1),
               ending: NSColor(calibratedRed: 0.72, green: 0.30, blue: 0.10, alpha: 1))!.draw(in: skirt, angle: -90)

    // Keycap top (dished surface): inset and raised toward the top.
    let top = NSBezierPath(roundedRect: NSRect(x: 322, y: 350, width: 380, height: 350), xRadius: 60, yRadius: 60)
    NSGradient(starting: NSColor(calibratedRed: 1.00, green: 0.68, blue: 0.40, alpha: 1),
               ending: NSColor(calibratedRed: 0.96, green: 0.54, blue: 0.26, alpha: 1))!.draw(in: top, angle: -90)
    NSColor.white.withAlphaComponent(0.35).setStroke()
    top.lineWidth = 6
    top.stroke()

    // Legend on the keycap.
    let legend = NSAttributedString(string: "T", attributes: [
        .font: NSFont.systemFont(ofSize: 190, weight: .heavy),
        .foregroundColor: NSColor(calibratedRed: 0.35, green: 0.13, blue: 0.04, alpha: 0.85),
    ])
    let ls = legend.size()
    legend.draw(at: NSPoint(x: 512 - ls.width / 2, y: 525 - ls.height / 2))
    return true
}

let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1024, pixelsHigh: 1024, bitsPerSample: 8, samplesPerPixel: 4,
                           hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
image.draw(in: NSRect(x: 0, y: 0, width: size, height: size))
NSGraphicsContext.current = nil
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
