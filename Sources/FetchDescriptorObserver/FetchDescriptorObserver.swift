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

    func makeCountObserver<R>(
        map: @escaping (Int) -> R
    ) -> FetchDescriptorCountObserver<T, R> {
        FetchDescriptorCountObserver(fetchDescriptor: self, map: map)
    }

    func makeCountObserver() -> FetchDescriptorCountObserver<T, Int> {
        FetchDescriptorCountObserver(fetchDescriptor: self, map: { $0 })
    }
}

public class FetchDescriptorObserver<T: PersistentModel, Result: Sendable> {
    /// When true, update events do not trigger a fetch; the observer still observes.
    public var isPaused: Bool {
        get { pauseController.isPaused }
        set { pauseController.isPaused = newValue }
    }

    private let observableQuery: FetchDescriptorObservableQuery<T, Result>
    private let pauseController = PauseController()

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
        let controller = pauseController

        let updates = makeUpdatesSequence(with: container, pauseController: controller)
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
                        let shouldFetch = controller.onUpdate()
                        if shouldFetch {
                            let results = try await fetch()
                            continuation.yield(results)
                        }
                    }
                    controller.streamDidFinish()
                    continuation.finish()
                } catch {
                    controller.streamDidFinish()
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
        with container: ModelContainer,
        pauseController: PauseController
    ) -> AsyncMerge2Sequence<AsyncMerge2Sequence<AsyncStream<Void>, AsyncStream<Void>>, AsyncStream<Void>> {
        let initialLoad = AsyncStream<Void>() { continuation in
            continuation.yield()
            continuation.finish()
        }
        let baseUpdates = merge(
            initialLoad,
            observableQuery.makeUpdatesStream(with: container)
        )
        let (resumeStream, resumeContinuation) = AsyncStream<Void>.makeStream()
        pauseController.resumeContinuation = resumeContinuation
        return merge(baseUpdates, resumeStream)
    }
}

public class FetchDescriptorCountObserver<T: PersistentModel, Result: Sendable> {
    /// When true, update events do not trigger a fetch; the observer still observes.
    public var isPaused: Bool {
        get { pauseController.isPaused }
        set { pauseController.isPaused = newValue }
    }
    
    private let observableQuery: FetchDescriptorCountObservableQuery<T, Result>
    private let pauseController = PauseController()

    public init(
        fetchDescriptor: FetchDescriptor<T>,
        map: @escaping (Int) -> Result
    ){
        self.observableQuery = FetchDescriptorCountObservableQuery(
            fetchDescriptor: fetchDescriptor,
            map: map
        )
    }

    /// Returns a stream of all values of the FetchDescriptor. Buffers the last value so that clients don't miss values before consumption.
    @MainActor
    public func values(_ container: ModelContainer) -> AsyncBufferSequence<AsyncThrowingStream<Result, any Error>> {
        let observableQuery = observableQuery
        let controller = pauseController

        let updates = makeUpdatesSequence(with: container, pauseController: controller)
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
                        let shouldFetch = controller.onUpdate()
                        if shouldFetch {
                            let results = try await fetch()
                            continuation.yield(results)
                        }
                    }
                    controller.streamDidFinish()
                    continuation.finish()
                } catch {
                    controller.streamDidFinish()
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
        with container: ModelContainer,
        pauseController: PauseController
    ) -> AsyncMerge2Sequence<AsyncMerge2Sequence<AsyncStream<Void>, AsyncStream<Void>>, AsyncStream<Void>> {
        let initialLoad = AsyncStream<Void>() { continuation in
            continuation.yield()
            continuation.finish()
        }
        let baseUpdates = merge(
            initialLoad,
            observableQuery.makeUpdatesStream(with: container)
        )
        let (resumeStream, resumeContinuation) = AsyncStream<Void>.makeStream()
        pauseController.resumeContinuation = resumeContinuation
        return merge(baseUpdates, resumeStream)
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

private struct FetchDescriptorCountObservableQuery<T: PersistentModel, Result>: ObservableQuery {
    let fetchDescriptor: FetchDescriptor<T>
    let map: (Int) -> Result

    func fetch(in container: ModelContainer) throws -> Result {
        let modelContext = ModelContext(container)
        let data = try modelContext.fetchCount(fetchDescriptor)
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

// MARK: - Pause / Resume

/// Handles pause and resume of observers
private final class PauseController {
    private var _isPaused = false
    var isPaused: Bool {
        get {
            _isPaused
        }
        set {
            _isPaused = newValue

            // ensure that pending updates are sent only if the AsyncStream is still emiting values.
            if !newValue, pendingUpdate, isStreamActive, let resumeContinuation {
                pendingUpdate = false
                resumeContinuation.yield()
            }
        }
    }
    var pendingUpdate = false
    var isStreamActive = true
    var resumeContinuation: AsyncStream<Void>.Continuation?

    /// Called when an update event is received. Returns true if the observer should fetch and yield.
    func onUpdate() -> Bool {
        if isPaused {
            pendingUpdate = true
            return false
        }
        return true
    }

    func streamDidFinish() {
        isStreamActive = false
        resumeContinuation?.finish()
        resumeContinuation = nil
    }
}
