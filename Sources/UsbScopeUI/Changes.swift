import Foundation
import UsbScopeCore

/// The presentation side of change tracking: the highlight style of a change.
///
/// The diff itself (`deviceKey`, `ChangeSet`, `diffSnapshots`) lives in
/// `UsbScopeCore`, because the hotplug watcher and the snapshot history use it
/// as well; only the mapping onto `Highlight` is a UI concern.
public func highlight(for tag: ChangeKind?) -> Highlight? {
    switch tag {
    case .added: .added
    case .removed: .removed
    case .changed: .changed
    case nil: nil
    }
}
