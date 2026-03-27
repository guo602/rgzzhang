import SwiftUI
import SwiftData

@main
struct rgzzhangApp: App {
    private let container: ModelContainer

    init() {
        do {
            container = try ModelContainer(for: Category.self, ExpenseRecord.self)
            seedDefaultCategoriesIfNeeded(modelContext: container.mainContext)
        } catch {
            // If container setup fails, the app cannot function properly.
            // Using a fatalError here will surface the issue immediately.
            fatalError("Failed to create SwiftData container: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(container)
    }
}
