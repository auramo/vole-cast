import CoreData
import Foundation
import OSLog
import SwiftData

/// Folds the duplicates that sync delivers, as they arrive.
///
/// Two devices refreshing the same show close together each insert its new
/// episode, and with no unique constraints in a CloudKit store both copies
/// reach both devices. A refresh folds them, but only the refresh of that
/// show, and the copy usually lands just after this device's own refresh — so
/// it sat in Latest until the next one, up to `LibraryRefresh.staleAfter`
/// later. This folds it when it lands.
///
/// Built on the store's history: the episodes inserted since the last pass
/// name the shows worth folding, so an import costs a look at those shows and
/// not at every episode in the library.
@MainActor
enum SyncArrivals {
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "VoleCast",
        category: "sync"
    )

    /// With no token yet, how far back the first pass looks. A token can be
    /// missing because this is the first launch with it, or because the old one
    /// stopped working; either way a full history can run to every episode ever
    /// stored, and anything older than this a refresh will fold anyway.
    static let firstLookBack: TimeInterval = 24 * 60 * 60

    private static let tokenKey = "SyncArrivals.lastToken"

    /// Folds every show an episode has been inserted into since `token`, and
    /// hands back the token to start from next time.
    ///
    /// Any insert counts, not only imports. A local refresh has already folded
    /// its own show, so looking again finds nothing and costs little; telling
    /// an import apart would rest on an author name the framework does not
    /// promise.
    @discardableResult
    static func fold(in context: ModelContext, since token: DefaultHistoryToken?) -> DefaultHistoryToken? {
        var descriptor = HistoryDescriptor<DefaultHistoryTransaction>()
        if let token {
            descriptor.predicate = #Predicate { $0.token > token }
        } else {
            let cutoff = Date.now.addingTimeInterval(-firstLookBack)
            descriptor.predicate = #Predicate { $0.timestamp > cutoff }
        }

        let transactions: [DefaultHistoryTransaction]
        do {
            transactions = try context.fetchHistory(descriptor)
        } catch {
            // Most likely a token the store no longer recognises. Dropping it
            // makes the next pass fall back to `firstLookBack`.
            logger.error("Failed to read history: \(error)")
            return nil
        }
        guard let newest = transactions.last?.token else { return token }

        var inserted = Set<PersistentIdentifier>()
        for transaction in transactions {
            for change in transaction.changes {
                guard case let .insert(insert) = change else { continue }
                let id = insert.changedPersistentIdentifier
                if id.entityName == Schema.entityName(for: Episode.self) { inserted.insert(id) }
            }
        }
        guard !inserted.isEmpty else { return newest }

        // Fetched rather than looked up one by one: an identifier from history
        // can name an episode deleted since, and `model(for:)` would hand that
        // back as a fault rather than nothing.
        let arrived = (try? context.fetch(FetchDescriptor<Episode>(
            predicate: #Predicate { inserted.contains($0.persistentModelID) }
        ))) ?? []
        // Every copy of those episodes, fetched again rather than read off each
        // show: a show's relationship, once loaded, does not see what another
        // context has saved since — and an import is exactly that.
        let guids = Set(arrived.map(\.guid))
        let copies = (try? context.fetch(FetchDescriptor<Episode>(
            predicate: #Predicate { $0.podcast != nil && guids.contains($0.guid) }
        ))) ?? []
        let byShowAndGUID = Dictionary(grouping: copies) {
            ShowAndGUID(show: $0.podcast?.persistentModelID, guid: $0.guid)
        }

        var removed = 0
        for group in byShowAndGUID.values {
            removed += DuplicateSubscriptions.fold(copies: group, in: context)
        }
        if removed > 0 {
            // Saved straight away: this runs off any screen, so nothing else
            // would prompt a save soon.
            try? context.save()
            logger.notice("Folded \(removed) episode(s) that arrived twice.")
        }
        return newest
    }

    private struct ShowAndGUID: Hashable {
        let show: PersistentIdentifier?
        let guid: String
    }

    static func storedToken(in defaults: UserDefaults) -> DefaultHistoryToken? {
        guard let data = defaults.data(forKey: tokenKey) else { return nil }
        return try? JSONDecoder().decode(DefaultHistoryToken.self, from: data)
    }

    static func store(_ token: DefaultHistoryToken?, in defaults: UserDefaults) {
        guard let token, let data = try? JSONEncoder().encode(token) else {
            defaults.removeObject(forKey: tokenKey)
            return
        }
        defaults.set(data, forKey: tokenKey)
    }
}

/// Runs `SyncArrivals` once at launch and again after every change sync makes
/// to the store.
///
/// Waits a moment after each change because an import comes in bursts, and
/// one pass after the last of them does the work of all of them.
@MainActor
final class SyncArrivalWatcher {
    private let context: ModelContext
    private let storeURL: URL?
    private let defaults: UserDefaults
    private let delay: Duration

    private var observer: (any NSObjectProtocol)?
    private var pending: Task<Void, Never>?

    init(
        context: ModelContext,
        storeURL: URL?,
        defaults: UserDefaults = .standard,
        delay: Duration = .seconds(2)
    ) {
        self.context = context
        self.storeURL = storeURL
        self.defaults = defaults
        self.delay = delay
    }

    /// Registers before returning, not from inside a `Task`: one that has
    /// not started iterating yet misses whatever is posted in the meantime,
    /// and an import landing just after launch would go unfolded.
    func start() {
        guard observer == nil else { return }
        foldNow()
        observer = NotificationCenter.default.addObserver(
            forName: .NSPersistentStoreRemoteChange, object: nil, queue: .main
        ) { [weak self] note in
            let changed = note.userInfo?["storeURL"] as? URL
            MainActor.assumeIsolated {
                guard let self, self.concerns(changed) else { return }
                self.schedule()
            }
        }
    }

    isolated deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }

    /// Only this store. Any store in the process posts the same notification,
    /// and the test host runs the app's own alongside the tests' ones.
    private func concerns(_ changed: URL?) -> Bool {
        guard let storeURL, let changed else { return false }
        return changed.standardizedFileURL.path == storeURL.standardizedFileURL.path
    }

    private func schedule() {
        pending?.cancel()
        pending = Task { [weak self, delay] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            self?.foldNow()
        }
    }

    /// A save here is itself a change the store reports, so each fold is
    /// followed by one more pass. That one finds no inserts and stops.
    private func foldNow() {
        let token = SyncArrivals.fold(in: context, since: SyncArrivals.storedToken(in: defaults))
        SyncArrivals.store(token, in: defaults)
    }
}
