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
            let forcedUpdatePublisher = NotificationCenter.default.publisher(
                for: ModelContainer.mainContextForcedUpdate,
                object: self
            ).receive(on: DispatchQueue.main)

            if #available(iOS 18, *) {
                let updatesPublisher = NotificationCenter.default.publisher(for: ModelContext.didSave, object: mainContext)
                let cancellable = updatesPublisher.merge(with: forcedUpdatePublisher).sink { _ in
                    continuation.finish()
                } receiveValue: { (notification) in
                    if notification.name == ModelContainer.mainContextForcedUpdate {
                        continuation.yield()
                        return
                    }

                    /// ModelContext.NotificationKey.deletedIdentifiers doesn't work. Notifications actually send those deleted identifiers under "deleted".
                    /// I can only guess it's a bug, so prioritize using the official API, but fallback to the debugged one.
                    let userInfo = notification.userInfo ?? [:]
                    let deleted = userInfo[ModelContext.NotificationKey.deletedIdentifiers] as? [PersistentIdentifier] ?? userInfo["deleted"] as? [PersistentIdentifier] ?? []
                    let updated = userInfo[ModelContext.NotificationKey.updatedIdentifiers] as? [PersistentIdentifier] ?? userInfo["updated"] as? [PersistentIdentifier] ?? []
                    let inserted = userInfo[ModelContext.NotificationKey.insertedIdentifiers] as? [PersistentIdentifier] ?? userInfo["inserted"] as? [PersistentIdentifier] ?? []
                    let allUpdates = deleted + updated + inserted

                    let names = ["\(T.self)"]
                    let isRelevantUpdate = allUpdates.contains(where: { persistentModelID in
                        names.contains { persistentModelID.entityName == $0 }
                    })
                    if isRelevantUpdate {
                        continuation.yield()
                    }
                }
                continuation.onTermination = { _ in
                    cancellable.cancel()
                }
            } else {
                let updatesPublisher = NotificationCenter.default.publisher(
                    for: Notification.Name("NSObjectsChangedInManagingContextNotification"),
                    object: mainContext
                )
                let cancellable = updatesPublisher.merge(with: forcedUpdatePublisher).sink { _ in
                    continuation.finish()
                } receiveValue: { (notification) in
                    if notification.name == ModelContainer.mainContextForcedUpdate {
                        continuation.yield()
                        return
                    }
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
                continuation.onTermination = { _ in
                    cancellable.cancel()
                }
            }
        }
    }

    public func postForcedMainContextUpdate() {
        NotificationCenter.default.post(
            name: ModelContainer.mainContextForcedUpdate,
            object: self
        )
    }

    public static let mainContextForcedUpdate = Notification.Name("__MainContextForcedUpdate")
}
