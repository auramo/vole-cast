import Foundation
import SwiftData
import Testing
@testable import VoleCast

/// On disk rather than in memory: history, which this is built on, is only
/// kept by a real store. Each test gets its own file, so none of them share.
@MainActor
struct SyncArrivalsTests {

    private func storeURL() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appending(path: "arrivals.store")
    }

    private func container(at url: URL) throws -> ModelContainer {
        let schema = VoleCastModelContainer.schema
        return try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)]
        )
    }

    private func defaults() -> UserDefaults {
        let name = "SyncArrivalsTests.\(UUID().uuidString)"
        return UserDefaults(suiteName: name)!
    }

    @discardableResult
    private func show(_ context: ModelContext, _ identity: String, guids: [String]) throws -> Podcast {
        let show = Podcast()
        show.feedIdentity = identity
        context.insert(show)
        for guid in guids {
            insertCopy(of: guid, into: show, createdAt: Date(timeIntervalSince1970: 1000), in: context)
        }
        try context.save()
        return show
    }

    private func insertCopy(
        of guid: String,
        into show: Podcast,
        createdAt: Date,
        in context: ModelContext
    ) {
        let episode = Episode(guid: guid, title: "Episode \(guid)", audioURL: "https://x.example.com/\(guid).mp3")
        episode.createdAt = createdAt
        episode.podcast = show
        context.insert(episode)
    }

    /// What another device's refresh delivers: a second copy of an episode
    /// this device already has, written by someone other than this context.
    private func arrive(_ guid: String, inShow identity: String, at url: URL) throws {
        let other = ModelContext(try container(at: url))
        let shows = try other.fetch(FetchDescriptor<Podcast>(predicate: #Predicate { $0.feedIdentity == identity }))
        let show = try #require(shows.first)
        insertCopy(of: guid, into: show, createdAt: Date(timeIntervalSince1970: 9000), in: other)
        try other.save()
    }

    private func count(_ guid: String, at url: URL) throws -> Int {
        try ModelContext(try container(at: url))
            .fetchCount(FetchDescriptor<Episode>(predicate: #Predicate { $0.guid == guid }))
    }

    // MARK: - Folding what arrived

    @Test func foldsACopyThatArrivedBySync() throws {
        let url = try storeURL()
        let context = ModelContext(try container(at: url))
        try show(context, "a.example.com", guids: ["a1"])
        let token = SyncArrivals.fold(in: context, since: nil)

        try arrive("a1", inShow: "a.example.com", at: url)
        SyncArrivals.fold(in: context, since: token)

        #expect(try count("a1", at: url) == 1)
    }

    /// Only shows that something arrived in are looked at, which is what makes
    /// this cheap enough to run on every import.
    @Test func leavesShowsNothingArrivedInAlone() throws {
        let url = try storeURL()
        let context = ModelContext(try container(at: url))
        let quiet = try show(context, "q.example.com", guids: ["q1"])
        insertCopy(of: "q1", into: quiet, createdAt: Date(timeIntervalSince1970: 5000), in: context)
        try show(context, "b.example.com", guids: ["b1"])
        let token = try #require(try context.fetchHistory(HistoryDescriptor<DefaultHistoryTransaction>()).last?.token)

        try arrive("b1", inShow: "b.example.com", at: url)
        SyncArrivals.fold(in: context, since: token)

        #expect(try count("b1", at: url) == 1)
        #expect(try count("q1", at: url) == 2)
    }

    @Test func withNothingNewHandsBackTheTokenItWasGiven() throws {
        let url = try storeURL()
        let context = ModelContext(try container(at: url))
        try show(context, "c.example.com", guids: ["c1"])
        let token = try #require(SyncArrivals.fold(in: context, since: nil))

        #expect(SyncArrivals.fold(in: context, since: token) == token)
    }

    @Test func theTokenSurvivesBeingStored() throws {
        let url = try storeURL()
        let context = ModelContext(try container(at: url))
        try show(context, "d.example.com", guids: ["d1"])
        let token = try #require(SyncArrivals.fold(in: context, since: nil))
        let defaults = defaults()

        SyncArrivals.store(token, in: defaults)

        #expect(SyncArrivals.storedToken(in: defaults) == token)
    }

    // MARK: - Watching

    /// End to end: a save from another container is what the store reports as
    /// a remote change, as it does for an import from iCloud.
    @Test func theWatcherFoldsAfterARemoteChange() async throws {
        let url = try storeURL()
        let context = ModelContext(try container(at: url))
        try show(context, "e.example.com", guids: ["e1"])
        let watcher = SyncArrivalWatcher(
            context: context, storeURL: url, defaults: defaults(), delay: .milliseconds(100)
        )
        watcher.start()

        try arrive("e1", inShow: "e.example.com", at: url)

        var folded = false
        for _ in 0..<40 where !folded {
            try await Task.sleep(for: .milliseconds(100))
            folded = try count("e1", at: url) == 1
        }
        #expect(folded)
    }

    /// The test host runs the app's own store in the same process, and its
    /// changes must not set off a watcher on another store.
    @Test func theWatcherIgnoresOtherStores() async throws {
        let url = try storeURL()
        let context = ModelContext(try container(at: url))
        try show(context, "f.example.com", guids: ["f1"])
        let defaults = defaults()
        let watcher = SyncArrivalWatcher(
            context: context, storeURL: try storeURL(), defaults: defaults, delay: .milliseconds(50)
        )
        watcher.start()
        let stored = SyncArrivals.storedToken(in: defaults)

        try arrive("f1", inShow: "f.example.com", at: url)
        try await Task.sleep(for: .milliseconds(600))

        #expect(try count("f1", at: url) == 2)
        #expect(SyncArrivals.storedToken(in: defaults) == stored)
    }
}
