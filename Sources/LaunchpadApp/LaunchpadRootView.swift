import AppKit
import Combine
import LaunchpadCore
import SwiftUI

final class LaunchpadRootUIState: ObservableObject {
    enum FocusTarget: Hashable { case search, folderName }

    @Published var editingFolderName = false
    @Published var escapeCancelsRename = false
    @Published var folderDraft = ""
    @Published var focus: FocusTarget? = .search
}

struct LaunchpadRootView: View {
    @ObservedObject var model: LaunchpadModel
    @ObservedObject var ui: LaunchpadRootUIState
    var screen: NSScreen?
    var onHide: () -> Void

    var body: some View {
        ZStack {
            DesktopBackground(screen: screen)
            VStack(spacing: 24) {
                LaunchpadTextField(
                    text: $model.query,
                    placeholder: "搜索",
                    isFocused: ui.focus == .search,
                    onBeginEditing: { ui.focus = .search }
                )
                .padding(10)
                .frame(width: 280)
                .background(.white.opacity(0.14), in: RoundedRectangle(cornerRadius: 10))
                if let launchError = model.launchError {
                    Text(launchError).foregroundStyle(.white)
                }
                if model.isSearching {
                    ScrollView {
                        PageGridView(
                            items: model.searchResults.map { .app($0.bundleID) },
                            record: model.record(_:),
                            onLaunch: launch,
                            onOpenFolder: { _ in }
                        )
                    }
                } else if model.layout.pages.indices.contains(model.pageIndex) {
                    PageGridView(
                        items: model.layout.pages[model.pageIndex],
                        record: model.record(_:),
                        onLaunch: launch,
                        onOpenFolder: { model.openFolderID = $0 }
                    )
                }
                Spacer(minLength: 0)
                pageDots
            }
            .padding(36)
            if let folder = model.openFolderID.flatMap(model.folder(_:)), !model.isSearching {
                folderOverlay(folder)
            }
        }
        .background(ScrollWheelPageTurner(enabled: !model.isSearching && model.openFolderID == nil) { delta in
            if delta < 0 { model.showNextPage() } else { model.showPreviousPage() }
        })
        .onAppear { ui.focus = .search }
        .onExitCommand(perform: handleEscape)
        .onChange(of: ui.focus) { _, newFocus in
            guard ui.editingFolderName, newFocus != .folderName else { return }
            if ui.escapeCancelsRename {
                ui.escapeCancelsRename = false
                ui.editingFolderName = false
            } else {
                finishRename(save: true)
            }
        }
        .onKeyPress(.leftArrow) {
            guard model.openFolderID == nil, !model.isSearching, !ui.editingFolderName else { return .ignored }
            model.showPreviousPage()
            return .handled
        }
        .onKeyPress(.rightArrow) {
            guard model.openFolderID == nil, !model.isSearching, !ui.editingFolderName else { return .ignored }
            model.showNextPage()
            return .handled
        }
    }

    private var pageDots: some View {
        HStack(spacing: 8) {
            ForEach(model.layout.pages.indices, id: \.self) { index in
                Circle()
                    .fill(index == model.pageIndex ? Color.white : Color.white.opacity(0.35))
                    .frame(width: 8, height: 8)
                    .onTapGesture { model.pageIndex = index }
            }
        }
    }

    private func launch(_ bundleID: String) {
        if model.launch(bundleID) { onHide() }
    }

    private func handleEscape() {
        if ui.editingFolderName {
            ui.escapeCancelsRename = true
            ui.focus = .search
            return
        }
        if model.isSearching {
            model.query = ""
            return
        }
        if model.openFolderID != nil {
            model.openFolderID = nil
            return
        }
        onHide()
    }

    private func folderOverlay(_ folder: FolderItem) -> some View {
        ZStack {
            Color.black.opacity(0.35)
                .ignoresSafeArea()
                .onTapGesture {
                    guard !ui.editingFolderName else { return }
                    model.openFolderID = nil
                }
            VStack(spacing: 20) {
                if ui.editingFolderName {
                    LaunchpadTextField(
                        text: $ui.folderDraft,
                        placeholder: "文件夹",
                        isFocused: ui.focus == .folderName,
                        onBeginEditing: { ui.focus = .folderName },
                        onSubmit: { finishRename(save: true) }
                    )
                    .frame(width: 220)
                } else {
                    Text(folder.name)
                        .font(.title2)
                        .foregroundStyle(.white)
                        .onTapGesture {
                            ui.folderDraft = folder.name
                            ui.editingFolderName = true
                            ui.focus = .folderName
                        }
                }
                ScrollView {
                    PageGridView(
                        items: folder.bundleIDs.map { .app($0) },
                        record: model.record(_:),
                        onLaunch: launch,
                        onOpenFolder: { _ in }
                    )
                }
            }
            .padding(32)
        }
    }

    private func finishRename(save: Bool) {
        if save, let id = model.openFolderID {
            model.renameFolder(id: id, to: ui.folderDraft)
        }
        ui.editingFolderName = false
        ui.focus = .search
    }
}

private struct LaunchpadTextField: NSViewRepresentable {
    @Binding var text: String
    var placeholder: String
    var isFocused: Bool
    var onBeginEditing: (() -> Void)?
    var onSubmit: (() -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, onBeginEditing: onBeginEditing, onSubmit: onSubmit)
    }

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField()
        field.placeholderString = placeholder
        field.isBordered = false
        field.focusRingType = .none
        field.backgroundColor = .clear
        field.textColor = .white
        field.delegate = context.coordinator
        return field
    }

    func updateNSView(_ field: NSTextField, context: Context) {
        context.coordinator.onBeginEditing = onBeginEditing
        context.coordinator.onSubmit = onSubmit
        if field.stringValue != text {
            field.stringValue = text
        }
        if isFocused, let window = field.window, window.firstResponder != field {
            DispatchQueue.main.async {
                window.makeFirstResponder(field)
            }
        }
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        @Binding var text: String
        var onBeginEditing: (() -> Void)?
        var onSubmit: (() -> Void)?

        init(text: Binding<String>, onBeginEditing: (() -> Void)?, onSubmit: (() -> Void)?) {
            _text = text
            self.onBeginEditing = onBeginEditing
            self.onSubmit = onSubmit
        }

        func controlTextDidChange(_ obj: Notification) {
            guard let field = obj.object as? NSTextField else { return }
            text = field.stringValue
        }

        func controlTextDidBeginEditing(_ obj: Notification) {
            onBeginEditing?()
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                onSubmit?()
                return true
            }
            return false
        }
    }
}

private struct ScrollWheelPageTurner: NSViewRepresentable {
    var enabled: Bool
    var onPage: (Int) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        context.coordinator.monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { event in
            guard context.coordinator.enabled, event.phase == .began else { return event }
            guard abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY) else { return event }
            context.coordinator.onPage(event.scrollingDeltaX > 0 ? -1 : 1)
            return event
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.enabled = enabled
        context.coordinator.onPage = onPage
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        if let monitor = coordinator.monitor {
            NSEvent.removeMonitor(monitor)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        var monitor: Any?
        var enabled = false
        var onPage: (Int) -> Void = { _ in }
    }
}
