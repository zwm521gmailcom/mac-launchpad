import AppKit
import SwiftUI

struct DesktopBackground: View {
    var screen: NSScreen?

    var body: some View {
        Color.clear
            .overlay {
                if let image = desktopImage {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFill()
                        .blur(radius: 28)
                } else {
                    Color.black.opacity(0.72)
                }
            }
            .overlay {
                Color.black.opacity(desktopImage == nil ? 0 : 0.28)
            }
            .clipped()
            .ignoresSafeArea()
    }

    private var desktopImage: NSImage? {
        guard let screen,
              let url = NSWorkspace.shared.desktopImageURL(for: screen),
              let image = NSImage(contentsOf: url) else { return nil }
        return image
    }
}
