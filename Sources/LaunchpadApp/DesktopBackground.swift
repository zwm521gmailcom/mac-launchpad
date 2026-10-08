import AppKit
import SwiftUI

struct DesktopBackground: View {
    var screen: NSScreen?

    var body: some View {
        ZStack {
            if let image = desktopImage {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
                    .blur(radius: 28)
                Color.black.opacity(0.28)
            } else {
                Color.black.opacity(0.72)
            }
        }
        .ignoresSafeArea()
    }

    private var desktopImage: NSImage? {
        guard let screen,
              let url = NSWorkspace.shared.desktopImageURL(for: screen),
              let image = NSImage(contentsOf: url) else { return nil }
        return image
    }
}
