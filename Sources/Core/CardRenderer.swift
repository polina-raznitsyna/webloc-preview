import AppKit
import CoreGraphics
import Foundation

public enum CardRendererError: Error {
    case noGraphicsContext
}

public struct CardRenderer {
    private static let cardSize: CGFloat = 512
    private static let cornerRadius: CGFloat = 32
    private static let imageCornerRadius: CGFloat = 16
    private static let padding: CGFloat = 24
    private static let textBottomPadding: CGFloat = 24
    private static let titleFontSize: CGFloat = 28
    private static let domainFontSize: CGFloat = 18
    private static let domainColor = NSColor(calibratedRed: 0.55, green: 0.55, blue: 0.55, alpha: 1.0)

    public static func render(
        title: String,
        domain: String,
        imageData: Data?
    ) throws -> NSImage {
        let size = NSSize(width: cardSize, height: cardSize)
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

        // Calculate text area at bottom
        let titleFont = NSFont.systemFont(ofSize: titleFontSize, weight: .bold)
        let domainFont = NSFont.systemFont(ofSize: domainFontSize, weight: .regular)

        let textX = padding
        let textWidth = cardSize - padding * 2

        // Domain
        let domainAttr: [NSAttributedString.Key: Any] = [
            .font: domainFont,
            .foregroundColor: domainColor,
        ]
        let domainStr = NSAttributedString(string: domain, attributes: domainAttr)
        let domainHeight = domainStr.boundingRect(
            with: NSSize(width: textWidth, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin]
        ).height

        let domainY = textBottomPadding

        // Title (max 2 lines)
        let titleParagraphStyle = NSMutableParagraphStyle()
        titleParagraphStyle.lineBreakMode = .byTruncatingTail
        let titleAttr: [NSAttributedString.Key: Any] = [
            .font: titleFont,
            .foregroundColor: NSColor.black,
            .paragraphStyle: titleParagraphStyle,
        ]
        let titleStr = NSAttributedString(string: title, attributes: titleAttr)
        let lineHeight = titleFont.ascender - titleFont.descender + titleFont.leading
        let maxTitleHeight = lineHeight * 2
        let titleY = domainY + domainHeight + 4

        // Draw domain
        domainStr.draw(in: NSRect(x: textX, y: domainY, width: textWidth, height: domainHeight + 4))

        // Draw title (clipped to 2 lines)
        let titleRect = NSRect(x: textX, y: titleY, width: textWidth, height: maxTitleHeight)
        context.saveGState()
        context.clip(to: titleRect)
        titleStr.draw(in: NSRect(x: textX, y: titleY, width: textWidth, height: maxTitleHeight + lineHeight))
        context.restoreGState()

        // Image area: from above title to top padding
        let imageAreaY = titleY + maxTitleHeight + 8
        let imageAreaTop = cardSize - padding
        let imageAreaHeight = imageAreaTop - imageAreaY
        let imageAreaWidth = cardSize - padding * 2
        let imageAreaRect = NSRect(x: padding, y: imageAreaY, width: imageAreaWidth, height: imageAreaHeight)

        if let imageData = imageData, let sourceImage = NSImage(data: imageData) {
            let sourceSize = sourceImage.size
            guard sourceSize.width > 0 && sourceSize.height > 0 else {
                image.unlockFocus()
                return image
            }

            // Aspect fit
            let scaleX = imageAreaWidth / sourceSize.width
            let scaleY = imageAreaHeight / sourceSize.height
            let scale = min(scaleX, scaleY)
            let drawWidth = sourceSize.width * scale
            let drawHeight = sourceSize.height * scale
            let drawX = imageAreaRect.midX - drawWidth / 2
            let drawY = imageAreaRect.midY - drawHeight / 2
            let drawRect = NSRect(x: drawX, y: drawY, width: drawWidth, height: drawHeight)

            // Clip to rounded rect for image
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
