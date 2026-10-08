import AppKit
import LaunchpadCore
import SwiftUI

struct PageGridView: View {
    let items: [PageItem]
    let record: (String) -> AppRecord?
    let onLaunch: (String) -> Void
    let onOpenFolder: (UUID) -> Void

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 18), count: 7)

    var body: some View {
        LazyVGrid(columns: columns, spacing: 22) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                switch item {
                case .app(let bundleID):
                    if let app = record(bundleID) {
                        Button { onLaunch(bundleID) } label: { AppTile(record: app) }
                            .buttonStyle(.plain)
                    }
                case .folder(let folder):
                    Button { onOpenFolder(folder.id) } label: {
                        FolderTile(folder: folder, record: record)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

struct AppTile: View {
    let record: AppRecord

    var body: some View {
        VStack(spacing: 6) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: record.url.path))
                .resizable()
                .frame(width: 64, height: 64)
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

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                RoundedRectangle(cornerRadius: 16)
                    .fill(.white.opacity(0.18))
                    .frame(width: 64, height: 64)
                VStack(spacing: 3) {
                    ForEach(0..<2, id: \.self) { row in
                        HStack(spacing: 3) {
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
            Image(nsImage: NSWorkspace.shared.icon(forFile: app.url.path))
                .resizable()
                .frame(width: 22, height: 22)
        } else {
            Color.clear.frame(width: 22, height: 22)
        }
    }
}
