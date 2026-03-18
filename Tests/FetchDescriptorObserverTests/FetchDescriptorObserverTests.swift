import XCTest
import SwiftData
@testable import FetchDescriptorObserver

@Model
final class Item {
    var name: String

    init(name: String) {
        self.name = name
    }
}

@MainActor
final class FetchDescriptorObserverTests: XCTestCase {
    private func makeContainer() throws -> ModelContainer {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: Item.self, configurations: configuration)
    }

    // MARK: - Tests

    func testObserverEmitsInitialAndSubsequentUpdates() async throws {
        let container = try makeContainer()
        let context = container.mainContext

        let descriptor = FetchDescriptor<Item>(sortBy: [SortDescriptor(\Item.name)])
        let observer = descriptor.makeObserver { items in
            items.map(\.name)
        }
        let valuesSequence = observer.values(container)

        var collected: [[String]] = []
        let task = Task {
            for try await value in valuesSequence {
                guard !Task.isCancelled else { return }

                collected.append(value)
                if collected.count >= 2 {
                    return
                }
            }
        }

        // Initial empty value.
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(collected.first, [String]())

        // Insert one item and save – this should be observed as the second value.
        context.insert(Item(name: "first"))
        try context.save()

        try await Task.sleep(for: .milliseconds(100))
        XCTAssertGreaterThanOrEqual(collected.count, 2)
        XCTAssertEqual(collected[1], ["first"])

        task.cancel()
    }

    func testObserverPauseSkipsUpdatesUntilResume() async throws {
        let container = try makeContainer()
        let context = container.mainContext

        let descriptor = FetchDescriptor<Item>(sortBy: [SortDescriptor(\Item.name)])
        let observer = descriptor.makeObserver { items in
            items.map(\.name)
        }

        let valuesSequence = observer.values(container)

        // Initial item so that we can observe a non-empty initial value.
        context.insert(Item(name: "initial"))
        try context.save()

        // Collect first value (initial load).
        var collectedTaskValues: [Array<String>] = []
        let task = Task {
            for try await value in valuesSequence {
                guard !Task.isCancelled else { return }

                collectedTaskValues.append(value)
                if collectedTaskValues.count >= 3 {
                    return
                }
            }
        }

        // Allow the initial value to be observed.
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(collectedTaskValues.first, ["initial"])

        // Pause and perform an update; it should NOT be observed yet.
        observer.isPaused = true
        context.insert(Item(name: "while-paused"))
        try context.save()

        try await Task.sleep(for: .milliseconds(50))
        XCTAssertFalse(collectedTaskValues.contains(where: { $0.contains("while-paused") }))

        let countBeforeResume = collectedTaskValues.count

        // Resume; the pending update should trigger exactly one new value.
        observer.isPaused = false

        try await Task.sleep(for: .milliseconds(100))
        let countAfterResume = collectedTaskValues.count

        // Exactly one additional emission after resuming.
        XCTAssertEqual(countAfterResume, countBeforeResume + 1)

        // That emission reflects the while-paused change.
        let newValues = collectedTaskValues.suffix(countAfterResume - countBeforeResume)
        XCTAssertEqual(newValues.count, 1)
        XCTAssertTrue(newValues.contains(where: { $0.contains("while-paused") }))

        task.cancel()
    }

    func testCountObserverPauseAndResume() async throws {
        let container = try makeContainer()
        let context = container.mainContext

        let descriptor = FetchDescriptor<Item>()
        let observer = descriptor.makeCountObserver()

        let valuesSequence = observer.values(container)

        var counts: [Int] = []
        let task = Task {
            for try await value in valuesSequence {
                guard !Task.isCancelled else { return }
                counts.append(value)
                if counts.count >= 3 {
                    return
                }
            }
        }

        // Initial count (0).
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(counts.first, 0)

        // Insert one item; should be observed.
        context.insert(Item(name: "one"))
        try context.save()

        try await Task.sleep(for: .milliseconds(50))
        XCTAssertTrue(counts.contains(1))

        // Pause and insert another item; count should not change yet.
        observer.isPaused = true
        context.insert(Item(name: "two"))
        try context.save()

        try await Task.sleep(for: .milliseconds(50))
        XCTAssertFalse(counts.contains(2))

        // Resume; now we should see the updated count.
        observer.isPaused = false

        try await Task.sleep(for: .milliseconds(100))
        XCTAssertTrue(counts.contains(2))

        task.cancel()
    }
}
