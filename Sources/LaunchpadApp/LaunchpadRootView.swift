import AppKit
import Combine
import CoreGraphics
import LaunchpadCore
import SwiftUI

final class LaunchpadRootUIState: ObservableObject {
    enum FocusTarget: Hashable { case search, folderName }

    @Published var editingFolderName = false
    @Published var escapeCancelsRename = false
    @Published var folderDraft = ""
    @Published var focus: FocusTarget? = .search

    var mainCells: [GridCell] = []
    var folderCells: [GridCell] = []
    var rootBounds: CGRect = .zero
    var folderGridFrame: CGRect = .null
    var dragFrom: (page: Int, index: Int)?
    var folderDragIndex: Int?
    var dragMonitor: Any?
    var edgeTask: Task<Void, Never>?
    var edgeDirection: Int?
    var transientPage = false

    func dragChanged(index: Int, point: CGPoint, inFolder: Bool, model: LaunchpadModel) {
        guard dragMonitor == nil else { return }
        if inFolder {
            folderDragIndex = index
        } else if model.layout.pages.indices.contains(model.pageIndex) {
            dragFrom = (model.pageIndex, index)
        }
        dragMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDragged, .leftMouseUp]) { [weak self] event in
            guard let self else { return event }
            let point = self.pointer(event)
            if event.type == .leftMouseUp { self.finishDrag(at: point, model: model) }
            else { self.follow(point, model: model) }
            return event
        }
    }

    func pointer(_ event: NSEvent) -> CGPoint {
        let location = event.locationInWindow
        let height = event.window?.contentView?.bounds.height ?? rootBounds.height
        return CGPoint(x: location.x, y: height - location.y)
    }

    func follow(_ point: CGPoint, model: LaunchpadModel) {
        guard folderDragIndex == nil else { return }
        let edge = GridHit.edge(at: point, in: rootBounds)
        guard edge != edgeDirection else { return }
        edgeDirection = edge
        edgeTask?.cancel()
        guard let edge else { return }
        edgeTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard !Task.isCancelled else { return }
            self.turn(edge, model: model)
        }
    }

    func turn(_ edge: Int, model: LaunchpadModel) {
        if edge < 0 {
            guard model.pageIndex > 0 else { return }
            if transientPage {
                transientPage = false
                model.pageIndex = max(0, model.layout.pages.count - 1)
            } else {
                model.showPreviousPage()
            }
            return
        }
        if model.pageIndex + 1 < model.layout.pages.count {
            model.showNextPage()
        } else if !transientPage {
            transientPage = true
            model.pageIndex = model.layout.pages.count
        }
    }

    func finishDrag(at point: CGPoint, model: LaunchpadModel) {
        guard dragFrom != nil || folderDragIndex != nil else { return }
        if let dragMonitor { NSEvent.removeMonitor(dragMonitor) }
        self.dragMonitor = nil
        edgeTask?.cancel()
        if let index = folderDragIndex, let folderID = model.openFolderID {
            if !folderGridFrame.contains(point),
               let folder = model.folder(folderID),
               folder.bundleIDs.indices.contains(index) {
                model.moveOut(bundleID: folder.bundleIDs[index], folderID: folderID)
            } else if case .insert(let displayedIndex) = GridHit.drop(
                at: point, cells: folderCells, draggedIsApp: true, allowsNewFolder: false
            ) {
                let target = DragIndex.afterRemoval(fromIndex: index, displayedIndex: displayedIndex, sameList: true)
                model.reorderFolderMember(folderID: folderID, fromIndex: index, indexAfterRemoval: target)
            }
        } else if let origin = dragFrom, model.layout.pages.indices.contains(origin.page) {
            let item = model.layout.pages[origin.page][origin.index]
            let draggedIsApp = { if case .app = item { return true }; return false }()
            let drop = GridHit.drop(at: point, cells: mainCells, draggedIsApp: draggedIsApp, allowsNewFolder: true)
            switch drop {
            case .makeFolder(let target):
                if case .app(let dragged) = item { model.makeFolder(dragged: dragged, onto: target) }
            case .addToFolder(let folderID):
                if case .app(let dragged) = item { model.addToFolder(bundleID: dragged, folderID: folderID) }
            case .insert(let displayedIndex):
                let toPage = min(model.pageIndex, model.layout.pages.count)
                let target = DragIndex.afterRemoval(
                    fromIndex: origin.index,
                    displayedIndex: displayedIndex,
                    sameList: origin.page == toPage
                )
                model.reorder(fromPage: origin.page, fromIndex: origin.index, toPage: toPage, indexAfterRemoval: target)
            }
        }
        dragFrom = nil
        folderDragIndex = nil
        edgeDirection = nil
        if transientPage, model.pageIndex >= model.layout.pages.count {
            model.pageIndex = max(0, model.layout.pages.count - 1)
        }
        transientPage = false
    }
}

private struct RootBoundsKey: PreferenceKey {
    static var defaultValue: CGRect = .zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) { value = nextValue() }
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
                            dragEnabled: false,
                            onLaunch: launch,
                            onOpenFolder: { _ in },
                            reportsFolderFrames: false,
                            onDragChanged: { _, _ in },
                            onDragEnded: { _, _ in }
                        )
                    }
                } else {
                    PageGridView(
                        items: model.layout.pages.indices.contains(model.pageIndex)
                            ? model.layout.pages[model.pageIndex]
                            : [],
                        record: model.record(_:),
                        dragEnabled: !model.isSearching,
                        onLaunch: launch,
                        onOpenFolder: { model.openFolderID = $0 },
                        reportsFolderFrames: false,
                        onDragChanged: { index, point in
                            ui.dragChanged(index: index, point: point, inFolder: false, model: model)
                        },
                        onDragEnded: { _, _ in }
                    )
                    .onPreferenceChange(MainIconFrameKey.self) { ui.mainCells = $0 }
                }
                Spacer(minLength: 0)
                pageDots
            }
            .padding(36)
            if let folder = model.openFolderID.flatMap(model.folder(_:)), !model.isSearching {
                folderOverlay(folder)
            }
        }
        .coordinateSpace(name: "launchpad")
        .background {
            GeometryReader { proxy in
                Color.clear.preference(
                    key: RootBoundsKey.self,
                    value: proxy.frame(in: .named("launchpad"))
                )
            }
        }
        .onPreferenceChange(RootBoundsKey.self) { ui.rootBounds = $0 }
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
        let dotCount = model.layout.pages.count + (model.pageIndex >= model.layout.pages.count ? 1 : 0)
        return HStack(spacing: 8) {
            ForEach(0..<dotCount, id: \.self) { index in
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
                PageGridView(
                    items: folder.bundleIDs.map { .app($0) },
                    record: model.record(_:),
                    dragEnabled: true,
                    onLaunch: launch,
                    onOpenFolder: { _ in },
                    reportsFolderFrames: true,
                    onDragChanged: { index, point in
                        ui.dragChanged(index: index, point: point, inFolder: true, model: model)
                    },
                    onDragEnded: { _, _ in }
                )
                .onPreferenceChange(FolderIconFrameKey.self) { ui.folderCells = $0 }
                .onPreferenceChange(FolderGridFrameKey.self) { ui.folderGridFrame = $0 }
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
