import AppKit
import Combine
import CoreGraphics
import LaunchpadCore
import SwiftUI

struct PageGridView: View {
    let items: [PageItem]
    let record: (String) -> AppRecord?
    var dragEnabled: Bool
    let onLaunch: (String) -> Void
    let onOpenFolder: (UUID) -> Void
    var reportsFolderFrames: Bool = false
    var gesturesEnabled: Bool = true
    var reportsIconFrames: Bool = true
    var suppressedIndex: Int? = nil
    var columnCount: Int = 7
    var iconSide: CGFloat = 64
    var columnSpacing: CGFloat = 20
    var rowSpacing: CGFloat = 22
    var onDragChanged: (Int, CGPoint) -> Void
    var onDragEnded: (Int, CGPoint) -> Void

    private var columns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: columnSpacing), count: max(columnCount, 1))
    }

    var body: some View {
        LazyVGrid(columns: columns, spacing: rowSpacing) {
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                tile(index: index, item: item)
                    .opacity(suppressedIndex == index ? 0 : 1)
                    .background {
                        if reportsIconFrames {
                            frameReader(index: index, item: item)
                        }
                    }
            }
        }
        .background {
            if reportsFolderFrames {
                GeometryReader { proxy in
                    Color.clear.preference(
                        key: FolderGridFrameKey.self,
                        value: proxy.frame(in: .named("launchpad"))
                    )
                }
            }
        }
    }

    @ViewBuilder
    private func tile(index: Int, item: PageItem) -> some View {
        if gesturesEnabled {
            PressableTile(dragEnabled: dragEnabled, onActivate: { activate(item) }) { point in
                onDragChanged(index, point)
            } label: {
                tileLabel(item)
            }
        } else {
            tileLabel(item)
        }
    }

    @ViewBuilder
    private func tileLabel(_ item: PageItem) -> some View {
        switch item {
        case .app(let bundleID):
            if let app = record(bundleID) { AppTile(record: app, iconSide: iconSide) } else { EmptyView() }
        case .folder(let folder):
            FolderTile(folder: folder, record: record, iconSide: iconSide)
        }
    }

    private func activate(_ item: PageItem) {
        switch item {
        case .app(let bundleID): onLaunch(bundleID)
        case .folder(let folder): onOpenFolder(folder.id)
        }
    }

    private func frameReader(index: Int, item: PageItem) -> some View {
        GeometryReader { proxy in
            let cell = proxy.frame(in: .named("launchpad"))
            let side = iconSide
            let icon = CGRect(x: cell.midX - side / 2, y: cell.minY, width: side, height: side)
            let cellValue = [GridCell(
                index: index,
                bundleID: { if case .app(let bundleID) = item { return bundleID }; return nil }(),
                folderID: { if case .folder(let folder) = item { return folder.id }; return nil }(),
                iconFrame: icon,
                cellFrame: cell
            )]
            Group {
                if reportsFolderFrames {
                    Color.clear.preference(key: FolderIconFrameKey.self, value: cellValue)
                } else {
                    Color.clear.preference(key: MainIconFrameKey.self, value: cellValue)
                }
            }
        }
    }
}

struct MainIconFrameKey: PreferenceKey {
    static var defaultValue: [GridCell] = []
    static func reduce(value: inout [GridCell], nextValue: () -> [GridCell]) {
        value.append(contentsOf: nextValue())
    }
}

struct FolderGridFrameKey: PreferenceKey {
    static var defaultValue: CGRect = .null
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) { value = nextValue() }
}

struct FolderIconFrameKey: PreferenceKey {
    static var defaultValue: [GridCell] = []
    static func reduce(value: inout [GridCell], nextValue: () -> [GridCell]) {
        value.append(contentsOf: nextValue())
    }
}

private final class PressableTileThreshold: ObservableObject {
    var passedThreshold = false
}

private struct PressableTile<Label: View>: View {
    var dragEnabled: Bool
    var onActivate: () -> Void
    var onDrag: (CGPoint) -> Void
    @ViewBuilder var label: () -> Label
    @StateObject private var threshold = PressableTileThreshold()

    var body: some View {
        if dragEnabled {
            label().gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .named("launchpad"))
                    .onChanged { value in
                        guard hypot(value.translation.width, value.translation.height) >= 8 else { return }
                        threshold.passedThreshold = true
                        onDrag(value.location)
                    }
                    .onEnded { _ in
                        if !threshold.passedThreshold { onActivate() }
                        threshold.passedThreshold = false
                    }
            )
        } else {
            label().onTapGesture(perform: onActivate)
        }
    }
}

struct AppTile: View {
    let record: AppRecord
    var iconSide: CGFloat = 64

    var body: some View {
        VStack(spacing: 6) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: record.url.path))
                .resizable()
                .frame(width: iconSide, height: iconSide)
            Text(record.displayName)
                .font(.caption)
                .lineLimit(1)
                .foregroundStyle(.white)
        }
        .frame(maxWidth: .infinity)
    }
}

struct FolderTile: View {
    let folder: FolderItem
    let record: (String) -> AppRecord?
    var iconSide: CGFloat = 64

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                RoundedRectangle(cornerRadius: iconSide * 0.25)
                    .fill(.white.opacity(0.18))
                    .frame(width: iconSide, height: iconSide)
                VStack(spacing: max(2, iconSide * 0.05)) {
                    ForEach(0..<2, id: \.self) { row in
                        HStack(spacing: max(2, iconSide * 0.05)) {
                            ForEach(0..<2, id: \.self) { column in
                                miniIcon(at: row * 2 + column)
                            }
                        }
                    }
                }
            }
            Text(folder.name)
                .font(.caption)
                .lineLimit(1)
                .foregroundStyle(.white)
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func miniIcon(at index: Int) -> some View {
        if folder.bundleIDs.indices.contains(index), let app = record(folder.bundleIDs[index]) {
            let side = iconSide * 0.34
            Image(nsImage: NSWorkspace.shared.icon(forFile: app.url.path))
                .resizable()
                .frame(width: side, height: side)
        } else {
            Color.clear.frame(width: iconSide * 0.34, height: iconSide * 0.34)
        }
    }
}
