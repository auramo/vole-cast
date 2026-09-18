import Foundation
import OSLog
import SwiftData

/// Central place that defines the SwiftData schema and builds containers.
///
/// The store is local only. The model is nonetheless CloudKit-compatible (every
/// property optional or defaulted, relationships optional with inverses, no
/// unique constraints), so turning sync on later is a configuration change plus
/// an entitlement, not a migration of everyone's data.
enum VoleCastModelContainer {
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "VoleCast",
        category: "persistence"
    )

    static let schema = Schema([
        Podcast.self,
        Episode.self,
    ])

    /// The app's on-disk container. A failure here means the device is in no
    /// state to run the app, so there is nothing useful to fall back to.
    static func makeStore() -> ModelContainer {
        do {
            let configuration = ModelConfiguration(
                schema: schema,
                isStoredInMemoryOnly: false,
                cloudKitDatabase: .none
            )
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            logger.error("Failed to open the store: \(error)")
            fatalError("Failed to create the VoleCast model container: \(error)")
        }
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
