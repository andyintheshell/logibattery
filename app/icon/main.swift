//  icon/main.swift
//  Renders LogiBattery's app icon into a macOS .iconset directory.
//
//  The icon is the app's own thesis, at icon scale: a battery whose fill is
//  split into the same three runs the menu bar draws - charge proven solid,
//  charge guessed translucent, charge gone left as bare track. If the icon
//  shows a plain full battery it is advertising a precision the gauge cannot
//  deliver, which is the one thing this whole project refuses to do.
//
//  Every size is drawn natively from the same 1024-unit geometry rather than
//  downscaled from one big render, so the small icons stay crisp. That does
//  mean the terminal nub is sub-pixel below ~32px; it degrades to a soft smudge,
//  which is the correct thing for a detail that small to do.
//
//  Usage: iconmaker <out.iconset> [--preview <dir>]
//  Then:  iconutil --convert icns <out.iconset>

import AppKit

// MARK: - Geometry, in units of a 1024x1024 canvas

/// macOS app icons sit on a rounded square that is 824 of the 1024 units, with
/// the remaining margin reserved for the drop shadow.
private let squircle = NSRect(x: 100, y: 100, width: 824, height: 824)
private let squircleRadius: CGFloat = 185

private let body = NSRect(x: 162, y: 337, width: 620, height: 350)
private let bodyRadius: CGFloat = 98
private let nub = NSRect(x: 806, y: 424, width: 56, height: 176)
private let nubRadius: CGFloat = 26

/// The gap between the battery's shell and its fill.
private let fillInset: CGFloat = 18

/// Fractions of the fill, mirroring the menu bar's bar. All three are on show
/// because the distinction between them is the point.
private let provenShare: CGFloat = 0.60
private let guessedShare: CGFloat = 0.22

/// Pinstripes across the guessed run. On a dark backdrop a translucent green
/// just looks like *less* green - the exact misreading the menu bar avoids by
/// putting its translucent run on a light track. Stripes keep the run at full
/// brightness while still reading as "there is charge here, but not this much
/// of it is accounted for".
private let stripeWidth: CGFloat = 11
private let stripePeriod: CGFloat = 30

// MARK: - Colour

/// `systemGreen` in dark appearance. Pinned rather than resolved at draw time
/// because the icon's own background is dark and a catalog colour would shift
/// with the user's theme - an app icon must not change with a setting.
private let green = NSColor(srgbRed: 0x30 / 255, green: 0xD1 / 255,
                            blue: 0x58 / 255, alpha: 1)

private let white = NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 1)
private let black = NSColor(srgbRed: 0, green: 0, blue: 0, alpha: 1)

private let backdropTop = NSColor(srgbRed: 0.231, green: 0.251, blue: 0.294, alpha: 1)
private let backdropBottom = NSColor(srgbRed: 0.078, green: 0.086, blue: 0.102, alpha: 1)

private let greenTop = green.blended(withFraction: 0.20, of: white) ?? green
private let greenBottom = green.blended(withFraction: 0.14, of: black) ?? green

// MARK: - Drawing

private func drawIcon() {
    // Backdrop. The shadowed fill and the gradient are separate passes because
    // NSGradient does not honour NSShadow; filling the path with a plain colour
    // under the shadow and then painting the gradient over it does.
    let shape = NSBezierPath(roundedRect: squircle, xRadius: squircleRadius,
                             yRadius: squircleRadius)
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = black.withAlphaComponent(0.34)
    shadow.shadowBlurRadius = 24
    shadow.shadowOffset = NSSize(width: 0, height: -10)
    shadow.set()
    black.setFill()
    shape.fill()
    NSGraphicsContext.restoreGraphicsState()

    NSGradient(colors: [backdropTop, backdropBottom])?
        .draw(in: shape, angle: -90)

    // Battery shell and its terminal. Both are bare track: white at low alpha
    // over the backdrop reads as "no charge known here".
    white.withAlphaComponent(0.11).setFill()
    NSBezierPath(roundedRect: body, xRadius: bodyRadius, yRadius: bodyRadius).fill()
    white.withAlphaComponent(0.15).setFill()
    NSBezierPath(roundedRect: nub, xRadius: nubRadius, yRadius: nubRadius).fill()

    // The fill, clipped so the runs keep the shell's inner corner radius.
    let inner = body.insetBy(dx: fillInset, dy: fillInset)
    let clip = NSBezierPath(roundedRect: inner, xRadius: bodyRadius - fillInset,
                            yRadius: bodyRadius - fillInset)
    let gradient = NSGradient(colors: [greenTop, greenBottom])
    NSGraphicsContext.saveGraphicsState()
    clip.addClip()

    let provenWidth = inner.width * provenShare
    gradient?.draw(in: NSRect(x: inner.minX, y: inner.minY,
                              width: provenWidth, height: inner.height), angle: -90)

    // The guessed run: full-brightness green, then striped back to let the
    // track through. Drawn solid first so the stripes read as texture over
    // green rather than as a separate, dimmer band.
    let guessed = NSRect(x: inner.minX + provenWidth, y: inner.minY,
                         width: inner.width * guessedShare, height: inner.height)
    gradient?.draw(in: guessed, angle: -90)

    NSGraphicsContext.saveGraphicsState()
    NSBezierPath(rect: guessed).addClip()
    let stripes = NSBezierPath()
    stripes.lineWidth = stripeWidth
    // Start one full height to the left so the diagonal covers the corners.
    var offset = -guessed.height
    while offset < guessed.width + guessed.height {
        stripes.move(to: NSPoint(x: guessed.minX + offset, y: guessed.minY))
        stripes.line(to: NSPoint(x: guessed.minX + offset - guessed.height,
                                 y: guessed.maxY))
        offset += stripePeriod
    }
    black.withAlphaComponent(0.40).setStroke()
    stripes.stroke()
    NSGraphicsContext.restoreGraphicsState()

    NSGraphicsContext.restoreGraphicsState()

    // A hairline so the shell still has an edge against the backdrop when the
    // whole thing is 16 pixels wide.
    let outline = NSBezierPath(roundedRect: body, xRadius: bodyRadius,
                               yRadius: bodyRadius)
    outline.lineWidth = 3
    white.withAlphaComponent(0.09).setStroke()
    outline.stroke()
}

/// Draws at `pixels` square, scaling the 1024-unit geometry to fit.
private func render(pixels: Int) -> Data? {
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .calibratedRGB, bytesPerRow: 0, bitsPerPixel: 0),
        let context = NSGraphicsContext(bitmapImageRep: rep)
    else { return nil }

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    let scale = NSAffineTransform()
    scale.scale(by: CGFloat(pixels) / 1024)
    scale.concat()
    drawIcon()
    NSGraphicsContext.restoreGraphicsState()

    return rep.representation(using: .png, properties: [:])
}

// MARK: - Output

/// A complete macOS icon set. The @2x entries repeat pixel sizes already
/// rendered above, so each size is drawn once and shared.
private let slots: [(file: String, pixels: Int)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024),
]

let arguments = CommandLine.arguments
guard arguments.count > 1 else {
    FileHandle.standardError.write(
        Data("usage: iconmaker <out.iconset> [--preview <dir>]\n".utf8))
    exit(2)
}
let directory = URL(fileURLWithPath: arguments[1])
let previewDirectory = arguments.firstIndex(of: "--preview").flatMap {
    arguments.count > $0 + 1 ? URL(fileURLWithPath: arguments[$0 + 1]) : nil
}

do {
    try FileManager.default.createDirectory(at: directory,
                                            withIntermediateDirectories: true)
    if let previewDirectory {
        try FileManager.default.createDirectory(at: previewDirectory,
                                                withIntermediateDirectories: true)
    }
} catch {
    FileHandle.standardError.write(Data("\(error)\n".utf8))
    exit(1)
}

var rendered: [Int: Data] = [:]
var previewed: Set<Int> = []
for slot in slots {
    let png: Data
    if let cached = rendered[slot.pixels] {
        png = cached
    } else {
        guard let fresh = render(pixels: slot.pixels) else {
            FileHandle.standardError.write(
                Data("failed to render \(slot.pixels)px\n".utf8))
            exit(1)
        }
        png = fresh
        rendered[slot.pixels] = fresh
    }
    try png.write(to: directory.appendingPathComponent(slot.file))

    // One preview per distinct pixel count, not per iconset slot: the @2x
    // entries just repeat sizes already rendered.
    if let previewDirectory, previewed.insert(slot.pixels).inserted {
        try png.write(to: previewDirectory
            .appendingPathComponent("icon-\(slot.pixels).png"))
    }
}

print("iconset: \(directory.path) (\(rendered.count) distinct sizes)")
if let previewDirectory {
    print("previews: \(previewDirectory.path)")
}
