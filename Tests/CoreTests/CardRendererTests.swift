import Testing
import Foundation
import AppKit
@testable import Core

@Suite("CardRenderer")
struct CardRendererTests {
    @Test("renders card with correct dimensions")
    func correctSize() throws {
        let image = try CardRenderer.render(
            title: "Test Title",
            domain: "example.com",
            imageData: nil
        )
        #expect(image.size.width == 512)
        #expect(image.size.height == 512)
    }

    @Test("renders card with image data")
    func withImage() throws {
        // Create a simple 100x50 red image as PNG
        let bitmapRep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: 100, pixelsHigh: 50,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
            isPlanar: false, colorSpaceName: .deviceRGB,
            bytesPerRow: 0, bitsPerPixel: 0
        )!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmapRep)
        NSColor.red.setFill()
        NSRect(x: 0, y: 0, width: 100, height: 50).fill()
        NSGraphicsContext.restoreGraphicsState()
        let pngData = bitmapRep.representation(using: .png, properties: [:])!

        let image = try CardRenderer.render(
            title: "With Image",
            domain: "example.com",
            imageData: pngData
        )
        #expect(image.size.width == 512)
        #expect(image.size.height == 512)
    }

    @Test("renders card with long title")
    func longTitle() throws {
        let longTitle = String(repeating: "Very Long Title ", count: 20)
        let image = try CardRenderer.render(
            title: longTitle,
            domain: "example.com",
            imageData: nil
        )
        #expect(image.size.width == 512)
    }
}
