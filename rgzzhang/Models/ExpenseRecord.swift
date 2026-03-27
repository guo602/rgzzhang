import Foundation
import SwiftData

@Model
final class ExpenseRecord: Identifiable {
    var id: UUID
    /// Expense date/time.
    var date: Date
    /// Expense amount (store as positive; UI can prefix `-`).
    var amount: Double
    var title: String
    /// Category (nullable to keep records even if category is deleted).
    @Relationship(deleteRule: .nullify)
    var category: Category?

    init(date: Date, amount: Double, title: String, category: Category?) {
        self.id = UUID()
        self.date = date
        self.amount = amount
        self.title = title
        self.category = category
    }
}

