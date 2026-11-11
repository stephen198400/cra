import SwiftUI

/// This fork's mark: the From icon, in resources/brand.
struct BrandMark: View {
    var size: CGFloat = 48
    var mono = false

    private static let colour: NSImage? = load("cra-mark@2x")

    private static func load(_ name: String) -> NSImage? {
        guard let url = Bundle.main.url(forResource: name, withExtension: "png", subdirectory: "brand") else { return nil }
        return NSImage(contentsOf: url)
    }

    var body: some View {
        if let img = BrandMark.colour {
            Image(nsImage: img)
                .resizable()
                .interpolation(.high)
                .frame(width: size, height: size)
                .accessibilityLabel("From")
        }
    }
}
