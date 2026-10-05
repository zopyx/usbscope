import Foundation

/// Application-facing collection boundary.
///
/// The domain builder and storage adapter remain in Core; UI consumers use this
/// service instead of reaching into individual OS sources. The synchronous
/// methods are for the offscreen renderer and the hotplug callback, while the
/// async methods keep normal refresh work off the main actor.
public struct SnapshotCollectionService: Sendable {
    private let metadataCache: StableMetadataCache

    public init(metadataCache: StableMetadataCache = SnapshotBuilder.stableMetadataCache) {
        self.metadataCache = metadataCache
    }

    public func collectSynchronously(
        profile: SnapshotCollectionProfile = .full,
        progress: @escaping @Sendable (SnapshotStage, Int, Int) -> Void = { _, _, _ in }
    ) -> Snapshot {
        SnapshotBuilder.collect(includeConflictWarnings: true,
                                metadataCache: metadataCache,
                                profile: profile,
                                progress: progress)
    }

    public func collect(
        profile: SnapshotCollectionProfile = .full,
        progress: @escaping @Sendable (SnapshotStage, Int, Int) -> Void = { _, _, _ in }
    ) async -> Snapshot {
        await Task.detached(priority: .userInitiated) {
            collectSynchronously(profile: profile, progress: progress)
        }.value
    }

    public func inventorySynchronously() -> StorageInventory {
        StorageSource().inventoryResult()
    }

    public func inventory() async -> StorageInventory {
        await Task.detached(priority: .userInitiated) {
            inventorySynchronously()
        }.value
    }
}
