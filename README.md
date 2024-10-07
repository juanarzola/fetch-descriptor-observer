# FetchDescriptorObserver

Safely performs `SwiftData` fetches in the background (at the global executor) as a result of
updates in the main viewContext for a `FetchDescriptor`. 

The `PersistentModel` of these fetches can be mapped to a sendable before sending to the main thread.

Use this when you would have used the `@Query` macro, but need to process the data from the PersistentModels in the background
before converting the result to a sendable for the UI.

Sample usage:

```swift
@MainActor
@Observable class ItemTypesObservable {
    // value displayed in the UI
    private(set) var counts: [ItemType: Int] = [:]
    private(set) var error: Error? = nil
    
    // observer of all items. Don't forget @ObservationIgnored. This could also have been 
    // created at the `updates` function, if you need arguments.
    @ObservationIgnored private let observer = FetchDescriptor<Item>(predicate: .true)
        .makeObserver {
            $0.grouped(by: \.itemType).mapValues { $0.count }
        }

    public func updates(_ container: ModelContainer) async {
        do {
            for try await counts in observer.values(container) {
                self.counts = counts
            }
        } catch {
            self.error = error
        }
    }
}

struct ItemTypesView: View {
    @State private var itemTypes = ItemTypesObservable()
    @Environment(\.modelContext) private var modelContext
    var body: some View {
        List {
            let counts = itemTypes.counts
            ForEach(Array(counts.keys), id: \.self) { key in
                let count = counts[key]
                LabeledContent("\(key.description)", value: "\(count ?? 0)")
            }
        }
        .task {
            // keep the observable up-to-date. Automatically cancels when the view disappears, restarts on re-appearance.
            await itemTypes.updates(modelContext.container)
        }
    }
}

```
