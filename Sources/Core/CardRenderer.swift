import AppKit
import CoreGraphics
import Foundation

public enum CardRendererError: Error {
    case noGraphicsContext
}

public struct CardRenderer {
    private static let iconSize: CGFloat = 512
    private static let scale: CGFloat = 2

    // All values in points (multiplied by scale when rendering)
    private static let canvasMargin: CGFloat = 24    // grey space between card and canvas edge
    private static let cardCornerRadius: CGFloat = 20
    private static let imageCornerRadius: CGFloat = 10
    private static let cardPadding: CGFloat = 14     // uniform padding inside card around image
    private static let footerSpacing: CGFloat = 12   // space between image and footer
    private static let footerHeight: CGFloat = 24    // height of favicon+domain row
    private static let faviconSize: CGFloat = 24
    private static let faviconCornerRadius: CGFloat = 4
    private static let faviconGap: CGFloat = 8       // horizontal gap between favicon and domain
    private static let domainFontSize: CGFloat = 20
    private static let domainColor = NSColor(calibratedRed: 0.4, green: 0.4, blue: 0.4, alpha: 1.0)

    public static func render(
        domain: String,
        imageData: Data?,
        faviconData: Data?
    ) throws -> NSImage {
        let px = Int(iconSize * scale)
        let s = scale

        guard let bitmapRep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: px, pixelsHigh: px,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
            isPlanar: false, colorSpaceName: .deviceRGB,
            bytesPerRow: 0, bitsPerPixel: 0
        ) else { throw CardRendererError.noGraphicsContext }

        guard let ctx = NSGraphicsContext(bitmapImageRep: bitmapRep) else {
            throw CardRendererError.noGraphicsContext
        }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = ctx
        let cg = ctx.cgContext
        cg.interpolationQuality = .high
        cg.setShouldAntialias(true)

        let canvas = CGFloat(px)
        cg.clear(CGRect(x: 0, y: 0, width: canvas, height: canvas))

        // All in pixel coords
        let margin = canvasMargin * s
        let pad = cardPadding * s
        let footH = footerHeight * s
        let footSp = footerSpacing * s
        let cr = cardCornerRadius * s
        let ir = imageCornerRadius * s

        // Max card size = canvas - 2 * margin
        let maxCard = canvas - margin * 2
        // Inside card: pad + image + pad + footerSpacing + footerHeight + pad
        // So maxImageW = maxCard - 2*pad, maxImageH = maxCard - 2*pad - footSp - footH
        let maxImgW = maxCard - pad * 2
        let maxImgH = maxCard - pad * 2 - footSp - footH

        // Source image
        let sourceImage = imageData.flatMap { NSImage(data: $0) }
        let sourceSize = sourceImage.flatMap { img -> NSSize? in
            guard let rep = img.representations.first, rep.pixelsWide > 0 else { return img.size }
            return NSSize(width: rep.pixelsWide, height: rep.pixelsHigh)
        } ?? NSSize(width: 1, height: 1)

        let aspect = sourceSize.width / sourceSize.height
        var imgW: CGFloat
        var imgH: CGFloat

        if sourceImage != nil {
            // Fit image preserving aspect ratio within maxImgW x maxImgH
            if aspect >= 1 {
                // Landscape: fill width
                imgW = maxImgW
                imgH = imgW / aspect
                if imgH > maxImgH {
                    imgH = maxImgH
                    imgW = imgH * aspect
                }
            } else {
                // Portrait: fill height
                imgH = maxImgH
                imgW = imgH * aspect
                if imgW > maxImgW {
                    imgW = maxImgW
                    imgH = imgW / aspect
                }
            }
        } else {
            imgW = maxImgW * 0.6
            imgH = imgW
        }

        // Card wraps tightly: uniform padding on all sides
        let cardW = imgW + pad * 2
        let cardH = imgH + pad * 2 + footSp + footH
        let cardX = (canvas - cardW) / 2
        let cardY = (canvas - cardH) / 2

        // Shadow
        cg.saveGState()
        let shadowRect = CGRect(x: cardX, y: cardY, width: cardW, height: cardH)
        cg.setShadow(offset: CGSize(width: 0, height: -2 * s), blur: 10 * s,
                     color: NSColor.black.withAlphaComponent(0.1).cgColor)
        cg.setFillColor(NSColor.white.cgColor)
        cg.addPath(CGPath(roundedRect: shadowRect, cornerWidth: cr, cornerHeight: cr, transform: nil))
        cg.fillPath()
        cg.restoreGState()

        // Card background
        let cardRect = CGRect(x: cardX, y: cardY, width: cardW, height: cardH)
        cg.setFillColor(NSColor.white.cgColor)
        cg.addPath(CGPath(roundedRect: cardRect, cornerWidth: cr, cornerHeight: cr, transform: nil))
        cg.fillPath()

        // Image: top area (above footer)
        let imgX = cardX + pad
        let imgY = cardY + pad + footH + footSp
        let imgRect = CGRect(x: imgX, y: imgY, width: imgW, height: imgH)

        if let sourceImage = sourceImage {
            cg.saveGState()
            cg.addPath(CGPath(roundedRect: imgRect, cornerWidth: ir, cornerHeight: ir, transform: nil))
            cg.clip()
            sourceImage.draw(in: imgRect, from: .zero, operation: .sourceOver, fraction: 1.0)
            cg.restoreGState()
        } else {
            cg.saveGState()
            cg.setFillColor(NSColor(calibratedWhite: 0.92, alpha: 1.0).cgColor)
            cg.addPath(CGPath(roundedRect: imgRect, cornerWidth: ir, cornerHeight: ir, transform: nil))
            cg.fillPath()
            cg.restoreGState()
        }

        // Footer: favicon + domain, left-aligned at bottom of card
        let footerY = cardY + pad
        let footerX = cardX + pad

        let favSz = faviconSize * s
        if let faviconData = faviconData, let favicon = NSImage(data: faviconData) {
            let favRect = NSRect(
                x: footerX,
                y: footerY + (footH - favSz) / 2,
                width: favSz, height: favSz
            )
            cg.saveGState()
            cg.addPath(CGPath(roundedRect: favRect, cornerWidth: faviconCornerRadius * s, cornerHeight: faviconCornerRadius * s, transform: nil))
            cg.clip()
            favicon.draw(in: favRect, from: .zero, operation: .sourceOver, fraction: 1.0)
            cg.restoreGState()
        }

        let domainFont = NSFont.systemFont(ofSize: domainFontSize * s, weight: .medium)
        let domainAttr: [NSAttributedString.Key: Any] = [
            .font: domainFont,
            .foregroundColor: domainColor,
        ]
        let domainStr = NSAttributedString(string: domain, attributes: domainAttr)
        let hasFav = faviconData != nil
        let domainTextX = footerX + (hasFav ? favSz + faviconGap * s : 0)
        let domainTextY = footerY + (footH - domainStr.size().height) / 2
        domainStr.draw(at: NSPoint(x: domainTextX, y: domainTextY))

        NSGraphicsContext.restoreGraphicsState()

        let icon = NSImage(size: NSSize(width: iconSize, height: iconSize))
        icon.addRepresentation(bitmapRep)
        return icon
    }
}
