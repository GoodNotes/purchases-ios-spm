import Foundation
import Testing

@testable import RevenueCat

struct CacheConcurrencyTests {
    @Test @MainActor
    func mainThreadCanReadWhileBackgroundWriteWaitsForIt() async throws {
        let suite = "RevenueCatConcurrencyTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("cached", forKey: "value")
        let cache = SynchronizedUserDefaults(userDefaults: defaults)
        let writeEntered = AsyncStream<Void>.makeStream()
        let writeCompleted = AsyncStream<Bool>.makeStream()
        let mainReadCompleted = DispatchSemaphore(value: 0)

        DispatchQueue.global().async {
            var mainReadFinished = false
            cache.write { _ in
                writeEntered.continuation.yield(())
                writeEntered.continuation.finish()
                // Model UserDefaults waiting for a main-thread notification handler.
                // The timeout releases the writer so the old implementation fails without hanging.
                mainReadFinished = mainReadCompleted.wait(timeout: .now() + 2) == .success
            }
            writeCompleted.continuation.yield(mainReadFinished)
            writeCompleted.continuation.finish()
        }

        for await _ in writeEntered.stream {
            #expect(cache.read { $0.string(forKey: "value") } == "cached")
            mainReadCompleted.signal()
        }
        for await mainReadFinished in writeCompleted.stream {
            #expect(mainReadFinished)
        }
    }

    @Test
    func concurrentCustomCacheUpdatesRetainEveryIncrement() async throws {
        let suite = "RevenueCatConcurrencyTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let cache = DeviceCache(sandboxEnvironmentDetector: BundleSandboxEnvironmentDetector(), userDefaults: defaults)
        let key = CounterKey()

        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<100 {
                group.addTask {
                    cache.update(key: key, default: 0) { $0 += 1 }
                }
            }
        }

        let count: Int? = cache.value(for: key)
        #expect(count == 100)
    }

    private struct CounterKey: DeviceCacheKeyType {
        let rawValue = "concurrency-counter"
    }
}
