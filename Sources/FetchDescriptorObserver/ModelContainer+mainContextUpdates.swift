//
//  ModelContext+Updates.swift
//  FetchDescriptorObserver
//
//  Created by Juan Arzola on 10/6/24.
//
import SwiftData
import Foundation
@preconcurrency import Combine

extension ModelContainer {
    /**
     * An AsyncStream that observes updates in the mainContext.
     * @return An `AsyncStream` that emits an element each time there's an update in the main context for any `PersistentModel`s relevant to the  fetch descriptor that fetches `PersistentModel`s of type `T`.
     */
    @MainActor
    internal func mainContextUpdates<T: PersistentModel>(
        relevantTo fetchDescriptorType: FetchDescriptor<T>.Type
    ) -> AsyncStream<Void> {
        return AsyncStream<Void> { continuation in
            let mainContext = mainContext
            let publisher = {
                // willSave only started working in iOS 18
                if #available(iOS 18, *) {
                    NotificationCenter.default.publisher(for: ModelContext.willSave, object: mainContext)
                } else {
                    NotificationCenter.default.publisher(for: Notification.Name("NSObjectsChangedInManagingContextNotification"), object: mainContext)
                }
            }()
            let cancellable = publisher.sink { _ in
                continuation.finish()
            } receiveValue: { notification in
                guard let modelContext = notification.object as? ModelContext else {
                    return
                }
                let deleted = modelContext.deletedModelsArray
                let updated = modelContext.changedModelsArray
                let inserted = modelContext.insertedModelsArray
                let allUpdates = deleted + updated + inserted
                let names = ["\(T.self)"]
                let isRelevantUpdate = allUpdates.contains(where: { object in
                    names.contains { object.persistentModelID.entityName == $0 }
                })
                if isRelevantUpdate {
                    continuation.yield()
                }
            }
            continuation.onTermination = { a in
                cancellable.cancel()
            }
        }
    }
}
