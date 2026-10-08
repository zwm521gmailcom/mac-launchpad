import AppKit
import SwiftUI

@main
final class AppDelegate: NSObject, NSApplicationDelegate {
    private static var retained: AppDelegate?
    private var window: NSWindow?
    private let model = LaunchpadModel()
    private let rootUI = LaunchpadRootUIState()

    static func main() {
        let delegate = AppDelegate()
        retained = delegate
        let app = NSApplication.shared
        app.delegate = delegate
        app.setActivationPolicy(.regular)
        app.run()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        showWindow()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showWindow()
        return true
    }

    private func showWindow() {
        let screen = screenUnderMouse() ?? NSScreen.main ?? NSScreen.screens[0]
        let root = LaunchpadRootView(model: model, ui: rootUI, screen: screen, onHide: { [weak self] in
            self?.window?.orderOut(nil)
        })
        if let window {
            window.setFrame(screen.frame, display: true)
            window.contentView = NSHostingView(rootView: root)
        } else {
            let window = KeyableBorderlessWindow(
                contentRect: screen.frame,
                styleMask: [.borderless],
                backing: .buffered,
                defer: false,
                screen: screen
            )
            window.isOpaque = false
            window.backgroundColor = .clear
            window.level = .popUpMenu
            window.hasShadow = false
            window.collectionBehavior = [.canJoinAllSpaces]
            window.contentView = NSHostingView(rootView: root)
            self.window = window
        }
        model.windowDidShow()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func screenUnderMouse() -> NSScreen? {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first { $0.frame.contains(mouse) }
    }
}

final class KeyableBorderlessWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}
