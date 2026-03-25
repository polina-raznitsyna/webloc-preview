import AppKit
import CoreGraphics
import Foundation

public enum CardRendererError: Error {
    case noGraphicsContext
}

public struct CardRenderer {
    private static let maxSize: CGFloat = 512
    private static let cornerRadius: CGFloat = 32
    private static let imageCornerRadius: CGFloat = 16
    private static let padding: CGFloat = 24
    private static let domainBarHeight: CGFloat = 40
    private static let domainFontSize: CGFloat = 16
    private static let faviconSize: CGFloat = 16
    private static let domainColor = NSColor(calibratedRed: 0.55, green: 0.55, blue: 0.55, alpha: 1.0)

    public static func render(
        domain: String,
        imageData: Data?,
        faviconData: Data?
    ) throws -> NSImage {
        // Determine image dimensions
        let sourceImage = imageData.flatMap { NSImage(data: $0) }
        let sourceSize = sourceImage?.size ?? NSSize(width: 1, height: 1)

        // Calculate card size: wrap image, max 512px on any side
        // Image area = card minus padding and domain bar
        let availableForImage = maxSize - padding * 2
        let domainTotalHeight = padding + domainBarHeight

        let imgAspect = sourceSize.width / sourceSize.height
        let cardWidth: CGFloat
        let cardHeight: CGFloat
        let imgDrawWidth: CGFloat
        let imgDrawHeight: CGFloat

        if sourceImage != nil {
            if imgAspect >= 1 {
                // Landscape or square: fit to max width
                imgDrawWidth = availableForImage
                imgDrawHeight = imgDrawWidth / imgAspect
                cardWidth = maxSize
                cardHeight = min(maxSize, imgDrawHeight + padding * 2 + domainTotalHeight)
            } else {
                // Portrait: fit to max height
                let maxImgHeight = maxSize - padding * 2 - domainTotalHeight
                imgDrawHeight = maxImgHeight
                imgDrawWidth = imgDrawHeight * imgAspect
                cardWidth = min(maxSize, imgDrawWidth + padding * 2)
                cardHeight = maxSize
            }
        } else {
            cardWidth = maxSize
            cardHeight = maxSize
            imgDrawWidth = 0
            imgDrawHeight = 0
        }

        let size = NSSize(width: cardWidth, height: cardHeight)
        let image = NSImage(size: size)

        image.lockFocus()
        guard let context = NSGraphicsContext.current?.cgContext else {
            image.unlockFocus()
            throw CardRendererError.noGraphicsContext
        }

        // White background with rounded corners
        let cardRect = CGRect(origin: .zero, size: size)
        let cardPath = NSBezierPath(roundedRect: cardRect, xRadius: cornerRadius, yRadius: cornerRadius)
        NSColor.white.setFill()
        cardPath.fill()

        // Light shadow
        context.setShadow(offset: CGSize(width: 0, height: -1), blur: 4,
                          color: NSColor.black.withAlphaComponent(0.08).cgColor)

        // Domain bar at bottom: favicon + domain text
        let domainFont = NSFont.systemFont(ofSize: domainFontSize, weight: .regular)
        let domainAttr: [NSAttributedString.Key: Any] = [
            .font: domainFont,
            .foregroundColor: domainColor,
        ]
        let domainStr = NSAttributedString(string: domain, attributes: domainAttr)

        // Center domain bar horizontally
        let domainTextSize = domainStr.size()
        let hasFavicon = faviconData != nil
        let faviconSpace: CGFloat = hasFavicon ? (faviconSize + 6) : 0
        let totalDomainWidth = faviconSpace + domainTextSize.width
        let domainStartX = (cardWidth - totalDomainWidth) / 2
        let domainY = padding

        // Draw favicon
        if let faviconData = faviconData, let favicon = NSImage(data: faviconData) {
            let faviconRect = NSRect(
                x: domainStartX,
                y: domainY + (domainTextSize.height - faviconSize) / 2,
                width: faviconSize,
                height: faviconSize
            )
            favicon.draw(in: faviconRect, from: .zero, operation: .sourceOver, fraction: 1.0)
        }

        // Draw domain text
        let domainTextX = domainStartX + faviconSpace
        domainStr.draw(at: NSPoint(x: domainTextX, y: domainY))

        // Draw image centered above domain bar
        if let sourceImage = sourceImage {
            let imgX = (cardWidth - imgDrawWidth) / 2
            let imgY = padding + domainBarHeight
            let drawRect = NSRect(x: imgX, y: imgY, width: imgDrawWidth, height: imgDrawHeight)

            context.saveGState()
            let imgPath = NSBezierPath(roundedRect: drawRect, xRadius: imageCornerRadius, yRadius: imageCornerRadius)
            imgPath.addClip()
            sourceImage.draw(in: drawRect, from: .zero, operation: .sourceOver, fraction: 1.0)
            context.restoreGState()
        }

        image.unlockFocus()
        return image
    }
}
