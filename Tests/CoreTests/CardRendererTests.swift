import Testing
import Foundation
import AppKit
@testable import Core

@Suite("CardRenderer")
struct CardRendererTests {
    @Test("renders card with no image")
    func noImage() throws {
        let image = try CardRenderer.render(
            domain: "example.com",
            imageData: nil,
            faviconData: nil
        )
        #expect(image.size.width == 512)
        #expect(image.size.height == 512)
    }

    @Test("renders card with landscape image — width is max")
    func landscapeImage() throws {
        let bitmapRep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: 200, pixelsHigh: 100,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
            isPlanar: false, colorSpaceName: .deviceRGB,
            bytesPerRow: 0, bitsPerPixel: 0
        )!
        let pngData = bitmapRep.representation(using: .png, properties: [:])!

        let image = try CardRenderer.render(
            domain: "example.com",
            imageData: pngData,
            faviconData: nil
        )
        #expect(image.size.width == 512)
        #expect(image.size.height <= 512)
    }

    @Test("renders card with portrait image — height is max")
    func portraitImage() throws {
        let bitmapRep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: 100, pixelsHigh: 300,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
            isPlanar: false, colorSpaceName: .deviceRGB,
            bytesPerRow: 0, bitsPerPixel: 0
        )!
        let pngData = bitmapRep.representation(using: .png, properties: [:])!

        let image = try CardRenderer.render(
            domain: "example.com",
            imageData: pngData,
            faviconData: nil
        )
        #expect(image.size.width <= 512)
        #expect(image.size.height == 512)
    }
}
