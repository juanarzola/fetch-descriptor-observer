//  FetchDescriptorObserver.swift
//
//  Created by Juan Arzola on 10/6/24.
//  Copyright © 2024 Juan Arzola. All rights reserved.
//

import SwiftData
import SwiftUI
import AsyncAlgorithms

public extension FetchDescriptor {
    func makeObserver<R>(
        map: @escaping ([T]) -> R
    ) -> FetchDescriptorObserver<T, R> {
        FetchDescriptorObserver(fetchDescriptor: self, map: map)
    }
    func makeObserver() -> FetchDescriptorObserver<T, Void> {
        makeObserver(map: { _ in })
    }
}

public class FetchDescriptorObserver<T: PersistentModel, Result: Sendable> {
    private let observableQuery: FetchDescriptorObservableQuery<T, Result>

    public init(
        fetchDescriptor: FetchDescriptor<T>,
        map: @escaping ([T]) -> Result
    ){
        self.observableQuery = FetchDescriptorObservableQuery(
            fetchDescriptor: fetchDescriptor,
            map: map
        )
    }

    /// Returns a stream of all values of the FetchDescriptor. Buffers the last value so that clients don't miss values before consumption.
    @MainActor
    public func values(_ container: ModelContainer) -> AsyncBufferSequence<AsyncThrowingStream<Result, any Error>> {
        let observableQuery = observableQuery

        // if there's no updatesSequence yet
        let updates = makeUpdatesSequence(with: container)
        return AsyncThrowingStream<Result, Error> { (continuation) in
            let task = Task {
                nonisolated func fetch() async throws -> Result {
                    let results = try observableQuery.fetch(in: container)
                    return results
                }
                do {
                    for try await _ in updates {
                        if Task.isCancelled {
                            break
                        }
                        let results = try await fetch()
                        continuation.yield(results)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in
                task.cancel()
            }
        }
        .buffer(policy: .bufferingLatest(1))
    }

    @MainActor
    private func makeUpdatesSequence(
        with container: ModelContainer
    ) ->  AsyncMerge2Sequence<AsyncStream<Void>, AsyncStream<Void>> {
        let initialLoad = AsyncStream<Void>() { continuation in
            continuation.yield()
            continuation.finish()
        }
        let allUpdates = merge(
            // first update is the initial load
            initialLoad,
            observableQuery
                .makeUpdatesStream(with: container)
        )
        return allUpdates
    }
}

private struct FetchDescriptorObservableQuery<T: PersistentModel, Result>: ObservableQuery {
    let fetchDescriptor: FetchDescriptor<T>
    let map: ([T]) -> Result
    func fetch(in container: ModelContainer) throws -> Result {
        let modelContext = ModelContext(container)
        let data = try modelContext.fetch(fetchDescriptor)
        let res = map(data)
        return res
    }

    @MainActor
    func makeUpdatesStream(with container: ModelContainer) -> AsyncStream<Void> {
        container.mainContextUpdates(relevantTo: FetchDescriptor<T>.self )
    }
}

private protocol ObservableQuery {
    associatedtype Result
    /// synchronously load results for the query
    func fetch(in container: ModelContainer) throws -> Result
    /// Return an async stream that emits when the query needs to be updated
    @MainActor func makeUpdatesStream(with container: ModelContainer) -> AsyncStream<Void>
}
