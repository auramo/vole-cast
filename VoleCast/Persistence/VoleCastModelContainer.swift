import Foundation
import OSLog
import SwiftData

/// Central place that defines the SwiftData schema and builds containers.
///
/// The store is mirrored to the user's private iCloud database, so a show
/// subscribed to on one device appears on the other and an episode paused on
/// one can be finished on the other. The model was written CloudKit-compatible
/// from the start — every property optional or defaulted, relationships
/// optional with inverses, no unique constraints — so switching mirroring on
/// adopted the existing store rather than migrating anyone's data.
///
/// ## How sync is wired
///
/// Almost none of it is here. The container identifier lives in
/// `Config/VoleCast.entitlements` as `iCloud.$(ORG_IDENTIFIER).VoleCast` and is
/// never named in Swift — `.automatic` reads it from there. The remote
/// notifications background mode in `Config/Info.plist` is what lets another
/// device's changes arrive while the app is open rather than at the next
/// launch. There is no sync code, no sync UI and no account handling: iOS
/// mirrors the store when the device is signed in and does not when it isn't.
///
/// What sync cannot do is keep two devices from subscribing to the same show
/// at the same moment — see `DuplicateSubscriptions`, which cleans up after
/// that at launch.
///
/// Changing the model means changing the CloudKit schema, which is append-only
/// in production: fields can be added, never removed. Deploy the new schema in
/// the CloudKit console before releasing a version that depends on it. A build
/// whose schema has not been deployed syncs nothing for App Store users while
/// working perfectly in development.
enum VoleCastModelContainer {
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "VoleCast",
        category: "persistence"
    )

    static let schema = Schema([
        Podcast.self,
        Episode.self,
    ])

    /// The app's on-disk container, mirrored to iCloud when it can be.
    ///
    /// A mirrored container can fail to build for reasons the listener can do
    /// nothing about — an entitlement that did not survive signing, a container
    /// missing from this environment — and that failure would happen on every
    /// launch, for good. So it falls back to the same store without mirroring:
    /// losing sync is recoverable, an app that will not open is not. The same
    /// file either way, so nothing is lost by the demotion and the next launch
    /// may well pick sync back up.
    ///
    /// A plain local store failing is different. That means the device is in no
    /// state to run the app, so it still traps.
    static func makeStore(syncsWithCloudKit: Bool = true) -> ModelContainer {
        if syncsWithCloudKit {
            do {
                return try makeStore(cloudKitDatabase: .automatic)
            } catch {
                logger.error("iCloud sync unavailable, using a local store: \(error)")
            }
        }
        do {
            return try makeStore(cloudKitDatabase: .none)
        } catch {
            logger.error("Failed to open the store: \(error)")
            fatalError("Failed to create the VoleCast model container: \(error)")
        }
    }

    private static func makeStore(
        cloudKitDatabase: ModelConfiguration.CloudKitDatabase
    ) throws -> ModelContainer {
        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false,
            cloudKitDatabase: cloudKitDatabase
        )
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    /// An ephemeral in-memory container for previews and tests.
    static func makeInMemory() -> ModelContainer {
        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: true
        )
        do {
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            fatalError("Failed to create the in-memory VoleCast model container: \(error)")
        }
    }
}
