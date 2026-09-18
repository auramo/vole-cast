import SwiftData
@testable import VoleCast

/// Creating more than one in-memory `ModelContainer` per process trips a trap
/// deep in SwiftData's CoreData-backed store, so every suite that needs a store
/// shares this one and gives each test its own `ModelContext` for isolation.
/// Suites using it must be `.serialized` to keep the shared store single-threaded.
@MainActor
enum TestContainer {
    static let shared = VoleCastModelContainer.makeInMemory()
}
