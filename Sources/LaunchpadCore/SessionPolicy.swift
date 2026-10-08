import Foundation

public enum SessionPolicy {
    public static func layoutForShow(memory: Layout?, stored: Layout?, records: [AppRecord]) -> Layout {
        let base = memory ?? stored
        if let base {
            return LayoutEdit.reconcile(layout: base, records: records)
        }
        return LayoutEdit.fresh(records: records)
    }

    public static func launchFailureMessage(displayName: String) -> String {
        "无法打开\(displayName)"
    }
}
