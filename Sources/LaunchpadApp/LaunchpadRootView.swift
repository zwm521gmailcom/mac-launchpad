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
    var bottomBarFrame: CGRect = .zero
    var folderGridFrame: CGRect = .null
    var dragFrom: (page: Int, index: Int)?
    var folderDragIndex: Int?
    var dragMonitor: Any?
    var edgeTask: Task<Void, Never>?
    var edgeDirection: Int?
    var transientPage = false

    enum PointerMode { case idle, pending, paging, lifting, locked }

    @Published var pointerMode: PointerMode = .idle
    @Published var contentOffset: CGFloat = 0
    @Published var restOffset: CGFloat = 0
    @Published var liftedPage: Int?
    @Published var liftedIndex: Int?
    @Published var liftPoint: CGPoint?
    var pageWidth: CGFloat = 0

    private var pointerStart = CGPoint.zero
    private var panOriginPage = 0
    private var panAnchorOffset: CGFloat = 0
    private var pendingIndex: Int?
    private var pickupTask: Task<Void, Never>?
    private var velocityX: CGFloat = 0
    private var lastSample = CGPoint.zero
    private var lastSampleTime: TimeInterval = 0
    private var panGeneration = 0
    private var ignoringPointer = false

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
        let edge = GridHit.edge(at: point, in: rootBounds, inset: 56)
        guard edge != edgeDirection else { return }
        edgeDirection = edge
        edgeTask?.cancel()
        guard let edge else { return }
        scheduleEdgeTurn(edge, model: model, delay: 280_000_000)
    }

    func scheduleEdgeTurn(_ edge: Int, model: LaunchpadModel, delay: UInt64) {
        edgeTask?.cancel()
        edgeTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: delay)
            guard !Task.isCancelled, self.edgeDirection == edge else { return }
            self.turn(edge, model: model)
        }
    }

    func turn(_ edge: Int, model: LaunchpadModel) {
        let beforePage = model.pageIndex
        let beforeTransient = transientPage
        if edge < 0 {
            if model.pageIndex > 0 {
                if transientPage {
                    transientPage = false
                    model.pageIndex = max(0, model.layout.pages.count - 1)
                } else {
                    model.showPreviousPage()
                }
            }
        } else if model.pageIndex + 1 < model.layout.pages.count {
            model.showNextPage()
        } else if !transientPage {
            transientPage = true
            model.pageIndex = model.layout.pages.count
        }
        if model.pageIndex != beforePage || transientPage != beforeTransient {
            scheduleEdgeTurn(edge, model: model, delay: 420_000_000)
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

    func setPageWidth(_ width: CGFloat, page: Int) {
        guard width > 1, abs(width - pageWidth) > 0.5 else { return }
        pageWidth = width
        guard pointerMode != .paging else { return }
        alignOffset(to: page)
    }

    func alignOffset(to page: Int) {
        guard pageWidth > 1 else { return }
        let dest = -CGFloat(page) * pageWidth
        guard abs(restOffset - dest) > 0.5 || abs(contentOffset - dest) > 0.5 else { return }
        restOffset = dest
        contentOffset = dest
    }

    func shouldIgnore(_ event: NSEvent) -> Bool {
        guard let content = event.window?.contentView else { return false }
        var view = content.hitTest(event.locationInWindow)
        while let current = view {
            if current is NSTextField || current is NSSlider { return true }
            view = current.superview
        }
        return bottomBarFrame.contains(pointer(event))
    }

    func pointerDown(at point: CGPoint, model: LaunchpadModel) {
        panGeneration += 1
        ignoringPointer = false
        pointerStart = point
        panOriginPage = model.pageIndex
        pendingIndex = cellIndex(at: point)
        velocityX = 0
        lastSample = point
        lastSampleTime = ProcessInfo.processInfo.systemUptime
        pointerMode = .pending
        pickupTask?.cancel()
        guard let index = pendingIndex else { return }
        pickupTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 420_000_000)
            guard !Task.isCancelled, self.pointerMode == .pending else { return }
            self.beginLift(index: index, at: point, model: model)
        }
    }

    func pointerDragged(to point: CGPoint, model: LaunchpadModel) {
        guard !ignoringPointer else { return }
        switch pointerMode {
        case .pending:
            let dx = point.x - pointerStart.x
            let dy = point.y - pointerStart.y
            if abs(dx) > 12, abs(dx) > abs(dy) {
                pickupTask?.cancel()
                // 从当前画面接着拖，避免翻页动画还没结束时被鼠标一带就跳页。
                panAnchorOffset = restOffset - dx
                panOriginPage = pageIndex(for: restOffset, pageCount: model.layout.pages.count)
                contentOffset = restOffset
                pointerMode = .paging
                updatePan(to: point, model: model)
            } else if abs(dy) > 16, abs(dy) > abs(dx) {
                pickupTask?.cancel()
                pointerMode = .locked
            }
        case .paging:
            updatePan(to: point, model: model)
        case .lifting:
            liftPoint = point
            follow(point, model: model)
        case .idle, .locked:
            break
        }
    }

    func pointerUp(at point: CGPoint, model: LaunchpadModel) -> String? {
        pickupTask?.cancel()
        defer { pendingIndex = nil }
        if ignoringPointer {
            ignoringPointer = false
            pointerMode = .idle
            return nil
        }
        switch pointerMode {
        case .paging:
            endPan(model: model)
        case .lifting:
            let moved = hypot(point.x - pointerStart.x, point.y - pointerStart.y)
            liftedPage = nil
            liftedIndex = nil
            liftPoint = nil
            if moved < 8 {
                cancelLift()
            } else {
                finishDrag(at: point, model: model)
            }
            pointerMode = .idle
        case .pending:
            let bundleID = (pendingIndex ?? cellIndex(at: point)).flatMap { bundleIDToOpen(at: $0, model: model) }
            pointerMode = .idle
            return bundleID
        case .idle, .locked:
            pointerMode = .idle
        }
        return nil
    }

    func beginIgnoringPointer() {
        panGeneration += 1
        pickupTask?.cancel()
        ignoringPointer = true
        pointerMode = .idle
    }

    func pageIndex(for offset: CGFloat, pageCount: Int) -> Int {
        guard pageWidth > 1, pageCount > 0 else { return 0 }
        let raw = Int(round(-offset / pageWidth))
        return min(max(0, raw), pageCount - 1)
    }

    func cellIndex(at point: CGPoint) -> Int? {
        mainCells.first { $0.cellFrame.contains(point) }?.index
    }

    func beginLift(index: Int, at point: CGPoint, model: LaunchpadModel) {
        guard model.layout.pages.indices.contains(model.pageIndex),
              model.layout.pages[model.pageIndex].indices.contains(index) else { return }
        pointerMode = .lifting
        dragFrom = (model.pageIndex, index)
        liftedPage = model.pageIndex
        liftedIndex = index
        liftPoint = point
    }

    func cancelLift() {
        edgeTask?.cancel()
        edgeDirection = nil
        dragFrom = nil
        transientPage = false
    }

    func bundleIDToOpen(at index: Int, model: LaunchpadModel) -> String? {
        guard model.layout.pages.indices.contains(model.pageIndex),
              model.layout.pages[model.pageIndex].indices.contains(index) else { return nil }
        switch model.layout.pages[model.pageIndex][index] {
        case .app(let bundleID):
            return bundleID
        case .folder(let folder):
            model.openFolderID = folder.id
            return nil
        }
    }

    func updatePan(to point: CGPoint, model: LaunchpadModel) {
        let now = ProcessInfo.processInfo.systemUptime
        let dt = now - lastSampleTime
        if dt > 0.001, lastSampleTime > 0 {
            velocityX = (point.x - lastSample.x) / CGFloat(dt)
        }
        lastSample = point
        lastSampleTime = now
        let width = pageWidth
        guard width > 1 else { return }
        let dx = point.x - pointerStart.x
        var proposed = panAnchorOffset + dx
        let minOffset = -CGFloat(max(0, model.layout.pages.count - 1)) * width
        if proposed > 0 {
            proposed *= 0.33
        } else if proposed < minOffset {
            proposed = minOffset + (proposed - minOffset) * 0.33
        }
        contentOffset = proposed
    }

    func endPan(model: LaunchpadModel) {
        let width = pageWidth
        guard width > 1 else {
            pointerMode = .idle
            return
        }
        let last = max(0, model.layout.pages.count - 1)
        let anchor = -CGFloat(panOriginPage) * width
        let travel = contentOffset - anchor
        var target = panOriginPage
        if travel < -width * 0.28 || velocityX < -800 {
            target += 1
        } else if travel > width * 0.28 || velocityX > 800 {
            target -= 1
        }
        let landed = pageIndex(for: contentOffset, pageCount: model.layout.pages.count)
        if abs(landed - panOriginPage) > 1 { target = landed }
        target = min(max(0, target), last)
        let dest = -CGFloat(target) * width
        restOffset = contentOffset
        pointerMode = .idle
        let generation = panGeneration
        DispatchQueue.main.async {
            guard self.panGeneration == generation, self.pointerMode == .idle else { return }
            self.restOffset = dest
            self.contentOffset = dest
            if model.pageIndex != target {
                model.pageIndex = target
            }
        }
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
            VStack(spacing: 24) {
                LaunchpadTextField(
                    text: $model.query,
                    placeholder: "搜索",
                    isFocused: false,
                    readsOnly: true
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
                            columnCount: model.gridMetrics.columns,
                            iconSide: model.gridMetrics.icon,
                            onDragChanged: { _, _ in },
                            onDragEnded: { _, _ in }
                        )
                    }
                    .frame(maxHeight: .infinity)
                } else {
                    pageStrip
                        .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
                }
                bottomBar
            }
            .padding(EdgeInsets(top: 28 + menuBarInset, leading: 36, bottom: 36 + dockInset, trailing: 36))
            if let folder = model.openFolderID.flatMap(model.folder(_:)), !model.isSearching {
                folderOverlay(folder)
            }
            if let preview = liftPreview {
                preview.allowsHitTesting(false)
            }
        }
        .background {
            DesktopBackground(screen: screen)
        }
        .frame(width: screen?.frame.width, height: screen?.frame.height, alignment: .topLeading)
        .clipped()
        .overlay {
            GeometryReader { geo in
                let controlWidth = SizeControlBox.preferredSize.width + 32
                let controlHeight = SizeControlBox.preferredSize.height + 16
                sizeControl
                    .position(
                        x: 52 + controlWidth / 2,
                        y: geo.size.height - (dockInset + 36) - controlHeight / 2
                    )
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
        .background(ScrollWheelPageTurner(enabled: pagingEnabled && ui.pointerMode != .paging && ui.pointerMode != .lifting) { delta in
            if delta < 0 { model.showNextPage() } else { model.showPreviousPage() }
        })
        .background(DesktopPointerMonitor(enabled: pagingEnabled, ui: ui, model: model, onLaunch: launch))
        .background(SearchTypingMonitor(enabled: !ui.editingFolderName, model: model, onEscape: handleEscape))
        .onAppear { ui.focus = .search }
        .onChange(of: model.pageIndex) { _, newPage in
            guard ui.pointerMode != .paging, ui.pageWidth > 1 else { return }
            let dest = -CGFloat(newPage) * ui.pageWidth
            guard abs(ui.restOffset - dest) > 0.5 || abs(ui.contentOffset - dest) > 0.5 else { return }
            ui.restOffset = dest
            ui.contentOffset = dest
        }
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
            guard pagingEnabled, ui.pointerMode != .paging, ui.pointerMode != .lifting else { return .ignored }
            model.showPreviousPage()
            return .handled
        }
        .onKeyPress(.rightArrow) {
            guard pagingEnabled, ui.pointerMode != .paging, ui.pointerMode != .lifting else { return .ignored }
            model.showNextPage()
            return .handled
        }
    }

    private var menuBarInset: CGFloat {
        guard let screen else { return 0 }
        return max(0, screen.frame.maxY - screen.visibleFrame.maxY)
    }

    private var dockInset: CGFloat {
        guard let screen else { return 80 }
        let measured = max(0, screen.visibleFrame.minY - screen.frame.minY)
        return max(measured, 72)
    }

    private var pagingEnabled: Bool {
        !model.isSearching && model.openFolderID == nil && !ui.editingFolderName
    }

    private var pageStrip: some View {
        let pages = model.layout.pages
        let slotCount = max(1, pages.count + (ui.transientPage ? 1 : 0))
        return GeometryReader { geo in
            let width = max(geo.size.width, 1)
            let metrics = model.gridMetrics
            let contentH = metrics.icon + GridMetrics.labelBlock
            let rowSpacing = metrics.rows > 1
                ? max(12, (geo.size.height - CGFloat(metrics.rows) * contentH) / CGFloat(metrics.rows - 1))
                : 12
            HStack(spacing: 0) {
                ForEach(0..<slotCount, id: \.self) { index in
                    PageGridView(
                        items: pages.indices.contains(index) ? pages[index] : [],
                        record: model.record(_:),
                        dragEnabled: false,
                        onLaunch: launch,
                        onOpenFolder: { model.openFolderID = $0 },
                        reportsFolderFrames: false,
                        gesturesEnabled: false,
                        reportsIconFrames: index == model.pageIndex,
                        suppressedIndex: ui.liftedPage == index ? ui.liftedIndex : nil,
                        columnCount: metrics.columns,
                        iconSide: metrics.icon,
                        rowSpacing: rowSpacing,
                        onDragChanged: { _, _ in },
                        onDragEnded: { _, _ in }
                    )
                    .frame(width: width, height: geo.size.height, alignment: .top)
                    .clipped()
                }
            }
            .frame(width: width * CGFloat(slotCount), height: geo.size.height, alignment: .topLeading)
            .offset(x: ui.pointerMode == .paging ? ui.contentOffset : ui.restOffset)
            .animation(ui.pointerMode == .paging ? nil : .spring(response: 0.36, dampingFraction: 0.86), value: ui.restOffset)
            .frame(width: width, height: geo.size.height, alignment: .topLeading)
            .clipped()
            .preference(key: PageBoxKey.self, value: CGSize(width: width, height: geo.size.height))
        }
        .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
        .onPreferenceChange(MainIconFrameKey.self) { ui.mainCells = $0 }
        .onPreferenceChange(PageBoxKey.self) { size in
            ui.setPageWidth(size.width, page: model.pageIndex)
            let reflow = ui.pointerMode != .paging && ui.pointerMode != .lifting
            model.refit(width: size.width, height: size.height, reflow: reflow)
        }
    }

    private var liftPreview: AnyView? {
        guard ui.pointerMode == .lifting,
              let page = ui.liftedPage,
              let index = ui.liftedIndex,
              let point = ui.liftPoint,
              model.layout.pages.indices.contains(page),
              model.layout.pages[page].indices.contains(index) else { return nil }
        let item = model.layout.pages[page][index]
        return AnyView(previewTile(item).position(x: point.x, y: point.y + 16))
    }

    @ViewBuilder
    private func previewTile(_ item: PageItem) -> some View {
        Group {
            switch item {
            case .app(let bundleID):
                if let app = model.record(bundleID) { AppTile(record: app, iconSide: model.gridMetrics.icon) }
            case .folder(let folder):
                FolderTile(folder: folder, record: model.record(_:), iconSide: model.gridMetrics.icon)
            }
        }
        .frame(width: 96)
        .scaleEffect(1.12)
        .shadow(color: .black.opacity(0.35), radius: 16, y: 8)
    }

    private var bottomBar: some View {
        ZStack {
            pageDots
        }
        .frame(maxWidth: .infinity, minHeight: 36, alignment: .center)
        .padding(.top, 8)
        .background {
            GeometryReader { proxy in
                Color.clear.preference(
                    key: BottomBarKey.self,
                    value: proxy.frame(in: .named("launchpad"))
                )
            }
        }
        .onPreferenceChange(BottomBarKey.self) { ui.bottomBarFrame = $0 }
    }

    private var sizeControl: some View {
        SizeControl(
            value: Binding(
                get: { model.iconSide },
                set: { model.setIconSide($0) }
            ),
            range: GridMetrics.minimumIcon...GridMetrics.maximumIcon
        )
        .frame(width: SizeControlBox.preferredSize.width, height: SizeControlBox.preferredSize.height)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.black.opacity(0.45), in: Capsule())
    }

    private var pageDots: some View {
        let extra = model.pageIndex >= model.layout.pages.count ? 1 : 0
        let dotCount = model.layout.pages.count + extra
        let highlighted: Int = {
            if ui.pointerMode == .paging, ui.pageWidth > 1 {
                return min(max(0, Int(round(-ui.contentOffset / ui.pageWidth))), max(0, dotCount - 1))
            }
            return model.pageIndex
        }()
        return HStack(spacing: 8) {
            ForEach(0..<dotCount, id: \.self) { index in
                Circle()
                    .fill(index == highlighted ? Color.white : Color.white.opacity(0.35))
                    .frame(width: 8, height: 8)
                    .onTapGesture {
                        guard ui.pointerMode != .paging else { return }
                        model.pageIndex = index
                    }
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
                    columnCount: model.gridMetrics.columns,
                    iconSide: model.gridMetrics.icon,
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

private final class CaretTextField: NSTextField {
    override func becomeFirstResponder() -> Bool {
        let ok = super.becomeFirstResponder()
        if ok, let editor = currentEditor() as? NSTextView {
            editor.selectedRange = NSRange(location: stringValue.utf16.count, length: 0)
        }
        return ok
    }
}

private struct LaunchpadTextField: NSViewRepresentable {
    @Binding var text: String
    var placeholder: String
    var isFocused: Bool
    var readsOnly: Bool = false
    var onBeginEditing: (() -> Void)?
    var onSubmit: (() -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, onBeginEditing: onBeginEditing, onSubmit: onSubmit)
    }

    func makeNSView(context: Context) -> NSTextField {
        let field = CaretTextField()
        field.placeholderString = placeholder
        field.isBordered = false
        field.focusRingType = .none
        field.backgroundColor = .clear
        field.textColor = .white
        field.delegate = context.coordinator
        field.maximumNumberOfLines = 1
        field.cell?.wraps = false
        field.cell?.isScrollable = true
        field.setContentHuggingPriority(.init(1), for: .horizontal)
        field.setContentCompressionResistancePriority(.init(1), for: .horizontal)
        field.isEditable = !readsOnly
        field.isSelectable = !readsOnly
        field.refusesFirstResponder = readsOnly
        return field
    }

    func updateNSView(_ field: NSTextField, context: Context) {
        context.coordinator.onBeginEditing = onBeginEditing
        context.coordinator.onSubmit = onSubmit
        field.isEditable = !readsOnly
        field.isSelectable = !readsOnly
        field.refusesFirstResponder = readsOnly
        field.textColor = .white
        // 正在编辑时不要回写文字，也不要重新聚焦，否则每个字都会被全选，下一个字把前一个替掉。
        let editing = !readsOnly && (context.coordinator.editingLocally || field.currentEditor() != nil)
        if !editing, field.stringValue != text {
            field.stringValue = text
        }
        guard isFocused, let window = field.window else { return }
        let editor = field.currentEditor()
        if editor != nil || window.firstResponder === field || window.firstResponder === editor { return }
        DispatchQueue.main.async {
            guard field.currentEditor() == nil, window.firstResponder !== field else { return }
            window.makeFirstResponder(field)
        }
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        @Binding var text: String
        var onBeginEditing: (() -> Void)?
        var onSubmit: (() -> Void)?
        var editingLocally = false

        init(text: Binding<String>, onBeginEditing: (() -> Void)?, onSubmit: (() -> Void)?) {
            _text = text
            self.onBeginEditing = onBeginEditing
            self.onSubmit = onSubmit
        }

        func controlTextDidChange(_ obj: Notification) {
            guard let field = obj.object as? NSTextField else { return }
            editingLocally = true
            text = field.stringValue
            DispatchQueue.main.async { [weak self] in
                self?.editingLocally = false
            }
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
            guard context.coordinator.enabled else { return event }
            // 惯性滚动不要连翻。触控板在 began 时常常还没有位移，真正的左右量在 changed 上。
            guard event.momentumPhase.isEmpty else { return event }
            let coordinator = context.coordinator
            let horizontal = abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY)
                && abs(event.scrollingDeltaX) > 8
            switch event.phase {
            case .began:
                coordinator.pagedThisGesture = false
                if horizontal { coordinator.page(event) }
            case .changed:
                if horizontal { coordinator.page(event) }
            case .ended, .cancelled:
                coordinator.pagedThisGesture = false
            default:
                if horizontal { coordinator.pageDiscrete(event) }
            }
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
        var pagedThisGesture = false
        var lastDiscretePage = Date.distantPast

        func page(_ event: NSEvent) {
            guard !pagedThisGesture else { return }
            pagedThisGesture = true
            onPage(event.scrollingDeltaX > 0 ? -1 : 1)
        }

        func pageDiscrete(_ event: NSEvent) {
            let now = Date()
            guard now.timeIntervalSince(lastDiscretePage) > 0.35 else { return }
            lastDiscretePage = now
            onPage(event.scrollingDeltaX > 0 ? -1 : 1)
        }
    }
}

private struct SearchTypingMonitor: NSViewRepresentable {
    var enabled: Bool
    var model: LaunchpadModel
    var onEscape: () -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        context.coordinator.monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            context.coordinator.handle(event)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.enabled = enabled
        context.coordinator.model = model
        context.coordinator.onEscape = onEscape
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
        weak var model: LaunchpadModel?
        var onEscape: () -> Void = {}

        func handle(_ event: NSEvent) -> NSEvent? {
            guard enabled, event.window?.isKeyWindow == true, let model else { return event }
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            if flags.contains(.command) || flags.contains(.control) || flags.contains(.option) {
                return event
            }
            switch event.keyCode {
            case 53:
                onEscape()
                return nil
            case 51:
                if !model.query.isEmpty {
                    model.query.removeLast()
                }
                return nil
            case 123, 124, 125, 126:
                return event
            default:
                break
            }
            guard let text = event.characters, !text.isEmpty else { return event }
            let printable = text.unicodeScalars.allSatisfy {
                !CharacterSet.controlCharacters.contains($0) && !CharacterSet.newlines.contains($0)
            }
            guard printable else { return nil }
            model.query.append(text)
            return nil
        }
    }
}

final class SizeControlBox: NSView {
    static let preferredSize = NSSize(width: 248, height: 36)

    let slider = NSSlider()
    private let smallLabel = NSTextField(labelWithString: "小")
    private let largeLabel = NSTextField(labelWithString: "大")

    override var intrinsicContentSize: NSSize { Self.preferredSize }

    override init(frame frameRect: NSRect) {
        super.init(frame: NSRect(origin: .zero, size: Self.preferredSize))
        for label in [smallLabel, largeLabel] {
            label.textColor = .white
            label.font = .systemFont(ofSize: 16, weight: .semibold)
            label.alignment = .center
            label.drawsBackground = false
            label.isBezeled = false
            label.isEditable = false
            label.isSelectable = false
            label.wantsLayer = true
            addSubview(label)
        }
        slider.controlSize = .regular
        slider.isContinuous = true
        addSubview(slider)
    }

    required init?(coder: NSCoder) { nil }

    override func layout() {
        super.layout()
        let labelWidth: CGFloat = 32
        let gap: CGFloat = 8
        let height = bounds.height
        smallLabel.frame = NSRect(x: 0, y: 0, width: labelWidth, height: height)
        largeLabel.frame = NSRect(x: bounds.width - labelWidth, y: 0, width: labelWidth, height: height)
        let sliderX = labelWidth + gap
        let sliderWidth = max(40, bounds.width - labelWidth * 2 - gap * 2)
        slider.frame = NSRect(x: sliderX, y: 0, width: sliderWidth, height: height)
    }
}

private struct SizeControl: NSViewRepresentable {
    @Binding var value: CGFloat
    var range: ClosedRange<CGFloat>

    func makeCoordinator() -> Coordinator { Coordinator(value: $value) }

    func makeNSView(context: Context) -> SizeControlBox {
        let box = SizeControlBox()
        box.slider.minValue = range.lowerBound
        box.slider.maxValue = range.upperBound
        box.slider.doubleValue = value
        box.slider.target = context.coordinator
        box.slider.action = #selector(Coordinator.changed(_:))
        return box
    }

    func updateNSView(_ box: SizeControlBox, context: Context) {
        box.slider.minValue = range.lowerBound
        box.slider.maxValue = range.upperBound
        context.coordinator.value = $value
        if abs(box.slider.doubleValue - Double(value)) > 0.5 {
            box.slider.doubleValue = Double(value)
        }
        box.needsLayout = true
    }

    final class Coordinator: NSObject {
        var value: Binding<CGFloat>
        init(value: Binding<CGFloat>) { self.value = value }

        @objc func changed(_ slider: NSSlider) {
            value.wrappedValue = CGFloat(slider.doubleValue)
        }
    }
}

private struct BottomBarKey: PreferenceKey {
    static var defaultValue: CGRect = .zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) { value = nextValue() }
}

private struct PageBoxKey: PreferenceKey {
    static var defaultValue: CGSize = .zero
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) { value = nextValue() }
}

private struct DesktopPointerMonitor: NSViewRepresentable {
    var enabled: Bool
    var ui: LaunchpadRootUIState
    var model: LaunchpadModel
    var onLaunch: (String) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        context.coordinator.monitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .leftMouseDragged, .leftMouseUp]
        ) { event in
            context.coordinator.handle(event)
            return event
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.enabled = enabled
        context.coordinator.ui = ui
        context.coordinator.model = model
        context.coordinator.onLaunch = onLaunch
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
        weak var ui: LaunchpadRootUIState?
        weak var model: LaunchpadModel?
        var onLaunch: (String) -> Void = { _ in }

        func handle(_ event: NSEvent) {
            guard let ui, let model else { return }
            if !enabled {
                if ui.pointerMode == .paging || ui.pointerMode == .lifting {
                    ui.pointerMode = .idle
                    ui.alignOffset(to: model.pageIndex)
                }
                return
            }
            let point = ui.pointer(event)
            switch event.type {
            case .leftMouseDown:
                if ui.shouldIgnore(event) {
                    ui.beginIgnoringPointer()
                } else {
                    ui.pointerDown(at: point, model: model)
                }
            case .leftMouseDragged:
                ui.pointerDragged(to: point, model: model)
            case .leftMouseUp:
                if let bundleID = ui.pointerUp(at: point, model: model) {
                    onLaunch(bundleID)
                }
            default:
                break
            }
        }
    }
}
