import Foundation
import SwiftData

private let defaultCategorySeeds: [(name: String, iconName: String, iconBackgroundHex: String, sortOrder: Int)] = [
    (name: "交通", iconName: "bus.fill", iconBackgroundHex: "#0A84FF", sortOrder: 0),
    (name: "饮食", iconName: "fork.knife", iconBackgroundHex: "#FF9500", sortOrder: 1),
    (name: "购物", iconName: "cart.fill", iconBackgroundHex: "#AF52DE", sortOrder: 2),
    (name: "娱乐", iconName: "film.fill", iconBackgroundHex: "#FF9F0A", sortOrder: 3)
]

/// Seed built-in categories at app startup so UI always has options.
func seedDefaultCategoriesIfNeeded(modelContext: ModelContext) {
    do {
        var current = try modelContext.fetch(FetchDescriptor<Category>())

        // Only override built-in metadata when there is no existing category data.
        // This preserves user-edited built-in category icon/color/sort order.
        let shouldOverrideBuiltins = current.isEmpty

        // Migrate old built-in category name: 餐饮 -> 饮食
        let oldName = "餐饮"
        let newName = "饮食"
        if let oldCategory = current.first(where: { $0.name == oldName }) {
            if let existingNew = current.first(where: { $0.name == newName }) {
                modelContext.delete(oldCategory)
                current.removeAll { $0 === oldCategory }
                _ = existingNew
            } else {
                oldCategory.name = newName
            }
        }

        // Index by name for quick check.
        var byName: [String: Category] = [:]
        current.forEach { byName[$0.name] = $0 }

        // Add missing + update icon/bg/sort for built-ins.
        for seed in defaultCategorySeeds {
            if let existing = byName[seed.name] {
                guard shouldOverrideBuiltins else { continue }
                existing.iconName = seed.iconName
                existing.iconBackgroundHex = seed.iconBackgroundHex
                existing.sortOrder = seed.sortOrder
            } else {
                modelContext.insert(
                    Category(
                        name: seed.name,
                        iconName: seed.iconName,
                        iconBackgroundHex: seed.iconBackgroundHex,
                        sortOrder: seed.sortOrder
                    )
                )
            }
        }

        try modelContext.save()

        // Debug log so you can confirm seeding in Xcode console.
        let after = try modelContext.fetch(FetchDescriptor<Category>())
        print("Seed categories ok, count: \(after.count)")
    } catch {
        print("Seed categories failed: \(error)")
    }
}

