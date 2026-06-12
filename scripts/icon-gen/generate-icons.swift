//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//
// Alternate app-icon generator for Spud.
//
// Reproduces the placeholder "potato" composition of the primary AppIcon
// (vertical warm gradient background, soft-shadowed cream ellipse body, a
// scatter of darker spots) and re-tints it per variant. Emits OPAQUE RGB PNGs
// with NO alpha channel (CGImageAlphaInfo.noneSkipLast) at the sizes iOS needs
// for loose-PNG alternate icons:
//
//   AppIcon-<Name>@2x.png   120x120   (iPhone @2x)
//   AppIcon-<Name>@3x.png   180x180   (iPhone @3x)
//   AppIcon-<Name>-1024.png 1024x1024 (picker preview)
//
// Run:  swift scripts/icon-gen/generate-icons.swift <output-dir>
//
// These are placeholder art, to be replaced with final icons later.

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

// MARK: - Palette model

struct RGB {
    let r: CGFloat
    let g: CGFloat
    let b: CGFloat

    init(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat) {
        self.r = r / 255
        self.g = g / 255
        self.b = b / 255
    }

    func color(_ space: CGColorSpace) -> CGColor {
        CGColor(colorSpace: space, components: [r, g, b, 1])!
    }
}

struct IconVariant {
    /// File basename: produces AppIcon-<name>@2x.png etc.
    let name: String
    /// Background gradient, top to bottom.
    let bgTop: RGB
    let bgBottom: RGB
    /// Potato body fill (top-to-bottom subtle gradient).
    let bodyTop: RGB
    let bodyBottom: RGB
    /// Spot color.
    let spot: RGB
}

/// Four variants on the potato motif. The primary (asset-catalog) icon is the
/// warm "default" gold; these are intentional re-tints so the set feels cohesive.
let variants: [IconVariant] = [
    // Midnight: deep blue / charcoal background, cool-grey potato.
    IconVariant(
        name: "Midnight",
        bgTop: RGB(40, 52, 78),
        bgBottom: RGB(16, 20, 34),
        bodyTop: RGB(214, 220, 232),
        bodyBottom: RGB(176, 186, 205),
        spot: RGB(70, 84, 116)
    ),
    // Forest: green background, warm tan potato.
    IconVariant(
        name: "Forest",
        bgTop: RGB(72, 130, 86),
        bgBottom: RGB(28, 74, 52),
        bodyTop: RGB(238, 224, 196),
        bodyBottom: RGB(214, 192, 152),
        spot: RGB(120, 96, 58)
    ),
    // Sunset: purple-to-orange background, cream potato.
    IconVariant(
        name: "Sunset",
        bgTop: RGB(126, 70, 150),
        bgBottom: RGB(226, 122, 78),
        bodyTop: RGB(248, 236, 214),
        bodyBottom: RGB(228, 204, 168),
        spot: RGB(150, 88, 96)
    ),
    // Mono: greyscale background, light-grey potato.
    IconVariant(
        name: "Mono",
        bgTop: RGB(120, 120, 124),
        bgBottom: RGB(58, 58, 62),
        bodyTop: RGB(232, 232, 234),
        bodyBottom: RGB(198, 198, 202),
        spot: RGB(120, 120, 126)
    ),
]

// MARK: - Drawing

let colorSpace = CGColorSpaceCreateDeviceRGB()

/// Draws one icon at `size` (square) and returns an opaque, alpha-free CGImage.
func renderIcon(_ v: IconVariant, size: CGFloat) -> CGImage {
    let pixels = Int(size)

    // Opaque RGB context, NO alpha channel: noneSkipLast => XRGB, 32-bit.
    guard let ctx = CGContext(
        data: nil,
        width: pixels,
        height: pixels,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
    ) else {
        fatalError("Could not create CGContext")
    }

    // 1. Vertical background gradient (top -> bottom).
    let bgGradient = CGGradient(
        colorsSpace: colorSpace,
        colors: [v.bgTop.color(colorSpace), v.bgBottom.color(colorSpace)] as CFArray,
        locations: [0, 1]
    )!
    // CG origin is bottom-left: start high (top) to low (bottom).
    ctx.drawLinearGradient(
        bgGradient,
        start: CGPoint(x: 0, y: size),
        end: CGPoint(x: 0, y: 0),
        options: []
    )

    // 2. Potato body: a wide ellipse, centered slightly above middle, with a
    //    soft drop shadow. Proportions mirror the primary icon (~0.62 wide,
    //    ~0.50 tall, nudged up).
    let bodyW = size * 0.62
    let bodyH = size * 0.50
    let bodyRect = CGRect(
        x: (size - bodyW) / 2,
        y: (size - bodyH) / 2 - size * 0.02,
        width: bodyW,
        height: bodyH
    )

    ctx.saveGState()

    // Soft shadow under the body. The context is opaque so the shadow blends
    // against the gradient rather than punching alpha.
    ctx.setShadow(
        offset: CGSize(width: 0, height: -size * 0.012),
        blur: size * 0.04,
        color: CGColor(colorSpace: colorSpace, components: [0, 0, 0, 0.28])!
    )

    // Clip to the ellipse and fill it with a subtle vertical body gradient.
    ctx.addEllipse(in: bodyRect)
    ctx.clip()
    let bodyGradient = CGGradient(
        colorsSpace: colorSpace,
        colors: [v.bodyTop.color(colorSpace), v.bodyBottom.color(colorSpace)] as CFArray,
        locations: [0, 1]
    )!
    ctx.drawLinearGradient(
        bodyGradient,
        start: CGPoint(x: 0, y: bodyRect.maxY),
        end: CGPoint(x: 0, y: bodyRect.minY),
        options: []
    )
    ctx.restoreGState()

    // 3. Spots: four small filled circles in a face-ish scatter, positioned
    //    relative to the body rect so they scale with size.
    ctx.setFillColor(v.spot.color(colorSpace))
    // (fractionX, fractionY within body rect, radius as fraction of bodyW)
    let spots: [(CGFloat, CGFloat, CGFloat)] = [
        (0.36, 0.58, 0.055),
        (0.62, 0.62, 0.045),
        (0.45, 0.34, 0.040),
        (0.58, 0.30, 0.035),
    ]
    for (fx, fy, fr) in spots {
        let cx = bodyRect.minX + bodyRect.width * fx
        // body rect fy measured from top; convert to CG bottom-left space.
        let cy = bodyRect.minY + bodyRect.height * (1 - fy)
        let r = bodyW * fr
        ctx.fillEllipse(in: CGRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2))
    }

    guard let image = ctx.makeImage() else {
        fatalError("Could not render image")
    }
    return image
}

/// Writes a CGImage to disk as a PNG with no alpha.
func writePNG(_ image: CGImage, to url: URL) {
    guard let dest = CGImageDestinationCreateWithURL(
        url as CFURL,
        UTType.png.identifier as CFString,
        1,
        nil
    ) else {
        fatalError("Could not create image destination at \(url.path)")
    }
    CGImageDestinationAddImage(dest, image, nil)
    if !CGImageDestinationFinalize(dest) {
        fatalError("Could not write PNG at \(url.path)")
    }
}

/// Writes a 1024 preview into an asset-catalog imageset
/// (`<catalog>/AppIconPreview-<Name>.imageset/`), creating the Contents.json.
func writePreviewImageset(_ image: CGImage, name: String, catalogDir: URL) {
    let setDir = catalogDir.appendingPathComponent("\(name).imageset", isDirectory: true)
    try? FileManager.default.createDirectory(at: setDir, withIntermediateDirectories: true)
    writePNG(image, to: setDir.appendingPathComponent("\(name).png"))

    let contents = """
        {
          "images" : [
            {
              "filename" : "\(name).png",
              "idiom" : "universal",
              "scale" : "1x"
            },
            {
              "idiom" : "universal",
              "scale" : "2x"
            },
            {
              "idiom" : "universal",
              "scale" : "3x"
            }
          ],
          "info" : {
            "author" : "xcode",
            "version" : 1
          }
        }

        """
    try? contents.data(using: .utf8)!.write(to: setDir.appendingPathComponent("Contents.json"))
}

// MARK: - Main

//
// usage: swift generate-icons.swift <loose-icons-dir> [<asset-catalog-dir>]
//
//   <loose-icons-dir>     gets the @2x/@3x bundle-root PNGs for each variant.
//   <asset-catalog-dir>   (optional) gets AppIconPreview-<Name>.imageset previews
//                         at 1024. Omit it to also dump 1024 PNGs into the loose dir.
//
// Note: AppIconPreview-Default.imageset (the primary "potato" icon's preview) is
// NOT produced here — it is a copy of AppIcon.appiconset/icon-1024.png and is
// maintained alongside the primary icon, not regenerated.

let args = CommandLine.arguments
guard args.count >= 2 else {
    FileHandle.standardError.write(
        Data("usage: swift generate-icons.swift <loose-icons-dir> [<asset-catalog-dir>]\n".utf8)
    )
    exit(2)
}

let outDir = URL(fileURLWithPath: args[1], isDirectory: true)
try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

let catalogDir: URL? = args.count >= 3
    ? URL(fileURLWithPath: args[2], isDirectory: true)
    : nil

for v in variants {
    // @2x = 120, @3x = 180 bundle-root alternates.
    let at2x = renderIcon(v, size: 120)
    let at3x = renderIcon(v, size: 180)
    writePNG(at2x, to: outDir.appendingPathComponent("AppIcon-\(v.name)@2x.png"))
    writePNG(at3x, to: outDir.appendingPathComponent("AppIcon-\(v.name)@3x.png"))

    // 1024 picker preview.
    let preview = renderIcon(v, size: 1024)
    if let catalogDir {
        writePreviewImageset(preview, name: "AppIconPreview-\(v.name)", catalogDir: catalogDir)
    } else {
        writePNG(preview, to: outDir.appendingPathComponent("AppIcon-\(v.name)-1024.png"))
    }
    print("wrote AppIcon-\(v.name) @2x/@3x + 1024 preview")
}

print("Done. Loose icons in \(outDir.path)" + (catalogDir.map { ", previews in \($0.path)" } ?? ""))
