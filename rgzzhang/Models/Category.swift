import Foundation
import SwiftData

@Model
final class Category: Identifiable {
    var id: UUID
    var name: String
    /// SF Symbols system image name, e.g. `"fork.knife"`.
    var iconName: String
    /// Hex string for background color, e.g. `"#FF3B30"`.
    var iconBackgroundHex: String
    /// Ordering in lists.
    var sortOrder: Int

    init(name: String, iconName: String, iconBackgroundHex: String, sortOrder: Int = 0) {
        self.id = UUID()
        self.name = name
        self.iconName = iconName
        self.iconBackgroundHex = iconBackgroundHex
        self.sortOrder = sortOrder
    }
}

