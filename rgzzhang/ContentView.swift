import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        ZStack {
            // 避免各页面底色穿透到顶部状态栏/灵动岛区域
            Color(.systemBackground)
                .ignoresSafeArea()

            TabView {
                AccountingPageView()
                    .tabItem {
                        Label("记账", systemImage: "book.fill")
                    }
                HistoryPageView()
                    .tabItem {
                        Label("历史", systemImage: "calendar")
                    }
                StatsPageView()
                    .tabItem {
                        Label("统计", systemImage: "chart.bar.fill")
                    }
                SettingsPageView()
                    .tabItem {
                        Label("设置", systemImage: "gearshape.fill")
                    }
            }
            .tint(Color.indigo)
        }
        .task {
            seedDefaultCategoriesIfNeeded(modelContext: modelContext)
        }
    }
}

// 统一主配色：渐变紫（用于顶部安全区/月份汇总与语音入口卡片）
private let brandPurpleGradient = LinearGradient(
    gradient: Gradient(colors: [
        Color(red: 76 / 255, green: 88 / 255, blue: 250 / 255),  // indigo-ish
        Color(red: 124 / 255, green: 58 / 255, blue: 237 / 255), // violet-ish
    ]),
    startPoint: .topLeading,
    endPoint: .bottomTrailing
)

private struct AccountingPageView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \ExpenseRecord.date, order: .reverse) private var records: [ExpenseRecord]
    @Query(sort: \Category.sortOrder, order: .forward) private var categories: [Category]
    @AppStorage("currencyCode") private var currencyCode: String = "CNY"

    @State private var amountText: String = ""
    @State private var titleText: String = ""
    @State private var selectedDate: Date = Date()
    @State private var selectedCategoryID: UUID?
    @State private var showManualEntrySheet = false

    var body: some View {
        ZStack(alignment: .top) {
            Color(.systemBackground)
                .frame(height: 210)
                .frame(maxWidth: .infinity)
                .ignoresSafeArea(edges: .top)

            ScrollView {
                VStack(spacing: 14) {
                    ZStack(alignment: .topLeading) {
                        RoundedRectangle(cornerRadius: 28, style: .continuous)
                            .fill(Color(.systemBackground))
                            .frame(height: 210)

                        VStack(alignment: .leading, spacing: 10) {
                            HStack(spacing: 6) {
                                Text(formatMonthYear(Date()))
                                    .font(.system(size: 22, weight: .semibold))
                                    .foregroundStyle(.primary)
                                Image(systemName: "calendar")
                                    .foregroundStyle(.secondary)
                                    .font(.system(size: 14, weight: .regular))
                            }

                            Text("共支出")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)

                            HStack(alignment: .firstTextBaseline, spacing: 3) {
                                Text(currencySymbol(for: currencyCode))
                                    .font(.title3.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                Text(formatAmountNumber(monthTotal))
                                    .font(.system(size: 44, weight: .bold))
                                    .foregroundStyle(.primary)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 64)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.bottom, 6)

                    HStack(spacing: 12) {
                        ActionCard(
                            icon: "mic.fill",
                            title: "长按语音输入",
                            subtitle: "松手后自动识别金额与分类",
                            tint: Color(red: 92 / 255, green: 80 / 255, blue: 250 / 255),
                            inverted: true
                        )
                        Button {
                            showManualEntrySheet = true
                        } label: {
                            ActionCard(
                                icon: "keyboard",
                                title: "手动输入",
                                subtitle: "金额、标题、时间、分类",
                                tint: Color(red: 92 / 255, green: 80 / 255, blue: 250 / 255),
                                inverted: false
                            )
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 16)

                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("今日记录")
                                .font(.headline)
                            Spacer()
                            Text("共 \(todayRecords.count) 笔")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        if todayRecords.isEmpty {
                            Text("今天还没有记录")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .padding(.vertical, 12)
                        } else {
                            VStack(spacing: 8) {
                                ForEach(todayRecords) { record in
                                    let cat = record.category
                                    let tint = Color(hex: cat?.iconBackgroundHex ?? "#A0A0A0")
                                    RecordRow(
                                        icon: cat?.iconName ?? "tag",
                                        title: record.title,
                                        meta: "\(formatTimeOnly(record.date)) · \(cat?.name ?? "未分类")",
                                        amount: "-\(formatMoney(record.amount, currencyCode: currencyCode))",
                                        color: tint
                                    )
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                }
                .padding(.bottom, 16)
            }
            .ignoresSafeArea(edges: .top)
        }
        .background(Color(.systemGray6))
        .task {
            seedDefaultCategoriesIfNeeded(modelContext: modelContext)
        }
        .onChange(of: categories.count) { _, _ in
            if selectedCategoryID == nil {
                selectedCategoryID = categories.first?.id
            }
        }
        .sheet(isPresented: $showManualEntrySheet) {
            ManualEntrySheetView(
                categories: categories,
                selectedCategoryID: $selectedCategoryID,
                selectedDate: $selectedDate,
                amountText: $amountText,
                titleText: $titleText,
                onSave: {
                    if saveExpense() {
                        showManualEntrySheet = false
                    }
                }
            )
        }
    }

    private var monthRange: (start: Date, end: Date) {
        let cal = Calendar.current
        let now = Date()
        let start = cal.date(from: DateComponents(year: cal.component(.year, from: now), month: cal.component(.month, from: now)))!
        let end = cal.date(byAdding: .month, value: 1, to: start)!
        return (start, end)
    }

    private var monthRecords: [ExpenseRecord] {
        records.filter { $0.date >= monthRange.start && $0.date < monthRange.end }
    }

    private var monthTotal: Double {
        monthRecords.reduce(0) { $0 + $1.amount }
    }

    private var todayRecords: [ExpenseRecord] {
        let cal = Calendar.current
        let start = cal.startOfDay(for: Date())
        let end = cal.date(byAdding: .day, value: 1, to: start)!
        return records.filter { $0.date >= start && $0.date < end }
    }

    private var selectedCategory: Category? {
        guard let selectedCategoryID else { return categories.first }
        return categories.first(where: { $0.id == selectedCategoryID })
    }

    private func saveExpense() -> Bool {
        guard let amount = parseAmount(amountText),
              amount > 0,
              let category = selectedCategory
        else { return false }

        let title = titleText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return false }

        let record = ExpenseRecord(
            date: selectedDate,
            amount: amount,
            title: title,
            category: category
        )
        modelContext.insert(record)

        do {
            try modelContext.save()
        } catch {
            // 这里不弹窗，避免打断输入流程；生产环境建议加错误提示
            print("保存记账失败：\(error)")
            return false
        }

        // 清空表单
        amountText = ""
        titleText = ""
        selectedDate = Date()
        return true
    }
}

private struct ManualEntrySheetView: View {
    let categories: [Category]
    @Binding var selectedCategoryID: UUID?
    @Binding var selectedDate: Date
    @Binding var amountText: String
    @Binding var titleText: String
    let onSave: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var showCategoryPicker = false

    private var selectedCategory: Category? {
        guard let selectedCategoryID else { return categories.first }
        return categories.first(where: { $0.id == selectedCategoryID })
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    WhiteSection(title: "手动记账") {
                        VStack(spacing: 10) {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("金额")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                TextField("例如 68.00", text: $amountText)
                                    .keyboardType(.decimalPad)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 10)
                                    .background(.white)
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color(.systemGray5)))
                            }

                            VStack(alignment: .leading, spacing: 6) {
                                Text("标题")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                TextField("例如 午餐", text: $titleText)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 10)
                                    .background(.white)
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color(.systemGray5)))
                            }

                            VStack(alignment: .leading, spacing: 6) {
                                Text("时间")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                HStack(spacing: 8) {
                                    Image(systemName: "calendar")
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                        .frame(width: 18)

                                    DatePicker(
                                        "选择时间",
                                        selection: $selectedDate,
                                        displayedComponents: [.date, .hourAndMinute]
                                    )
                                    .labelsHidden()
                                    .datePickerStyle(.compact)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 10)
                                .background(.white)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color(.systemGray5)))
                            }

                            VStack(alignment: .leading, spacing: 6) {
                                Text("分类")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                if categories.isEmpty {
                                    HStack(spacing: 10) {
                                        ZStack {
                                            Circle()
                                                .fill(Color(.systemGray5))
                                            Image(systemName: "tag")
                                                .font(.system(size: 14, weight: .semibold))
                                                .foregroundStyle(.secondary)
                                        }
                                        .frame(width: 26, height: 26)

                                        Text("请先在“设置”里添加分类")
                                            .font(.subheadline)
                                            .foregroundStyle(.secondary)

                                        Spacer()
                                    }
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 10)
                                    .background(.white)
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color(.systemGray5)))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                } else {
                                    Button {
                                        showCategoryPicker = true
                                    } label: {
                                        HStack(spacing: 10) {
                                            if let cat = selectedCategory {
                                                let tint = Color(hex: cat.iconBackgroundHex)
                                                ZStack {
                                                    Circle()
                                                        .fill(tint.opacity(0.18))
                                                    Image(systemName: cat.iconName)
                                                        .font(.system(size: 14, weight: .semibold))
                                                        .foregroundStyle(tint)
                                                }
                                                .frame(width: 26, height: 26)
                                            } else {
                                                ZStack {
                                                    Circle()
                                                        .fill(Color(.systemGray5))
                                                    Image(systemName: "tag")
                                                        .font(.system(size: 14, weight: .semibold))
                                                        .foregroundStyle(.secondary)
                                                }
                                                .frame(width: 26, height: 26)
                                            }

                                            Text(selectedCategory?.name ?? "请选择分类")
                                                .foregroundStyle(.primary)

                                            Spacer()

                                            Image(systemName: "chevron.right")
                                                .font(.system(size: 13, weight: .semibold))
                                                .foregroundStyle(.tertiary)
                                        }
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 10)
                                    .background(.white)
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color(.systemGray5)))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                }
                            }

                            Button("保存记账") {
                                onSave()
                            }
                            .fontWeight(.semibold)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 11)
                            .background(brandPurpleGradient)
                            .foregroundStyle(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .disabled(parseAmount(amountText) == nil || titleText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || categories.isEmpty)
                        }
                    }
                    .padding(.horizontal, 16)
                }
                .padding(.top, 8)
                .padding(.bottom, 16)
            }
            .navigationTitle("手动记账")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
            }
        }
        .sheet(isPresented: $showCategoryPicker) {
            CategoryPickerSheetView(
                title: "选择分类",
                categories: categories,
                selectedCategoryID: $selectedCategoryID
            )
        }
    }
}

private struct CategoryPickerSheetView: View {
    let title: String
    let categories: [Category]
    @Binding var selectedCategoryID: UUID?
    let allowsAllOption: Bool
    @Environment(\.dismiss) private var dismiss
    @State private var searchText: String = ""

    init(
        title: String,
        categories: [Category],
        selectedCategoryID: Binding<UUID?>,
        allowsAllOption: Bool = false
    ) {
        self.title = title
        self.categories = categories
        self._selectedCategoryID = selectedCategoryID
        self.allowsAllOption = allowsAllOption
    }

    private var filtered: [Category] {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return categories }
        return categories.filter { $0.name.localizedCaseInsensitiveContains(trimmed) }
    }

    var body: some View {
        NavigationStack {
            List {
                if allowsAllOption {
                    Button {
                        selectedCategoryID = nil
                        dismiss()
                    } label: {
                        HStack(spacing: 12) {
                            ZStack {
                                Circle()
                                    .fill(Color(.systemGray5).opacity(0.18))
                                Image(systemName: "line.3.horizontal.decrease.circle")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(Color(.systemGray3))
                            }
                            .frame(width: 30, height: 30)

                            Text("全部")
                                .foregroundStyle(.primary)

                            Spacer()

                            if selectedCategoryID == nil {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundStyle(Color.indigo)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }

                ForEach(filtered) { cat in
                    Button {
                        selectedCategoryID = cat.id
                        dismiss()
                    } label: {
                        HStack(spacing: 12) {
                            let tint = Color(hex: cat.iconBackgroundHex)
                            ZStack {
                                Circle()
                                    .fill(tint.opacity(0.18))
                                Image(systemName: cat.iconName)
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(tint)
                            }
                            .frame(width: 30, height: 30)

                            Text(cat.name)
                                .foregroundStyle(.primary)

                            Spacer()

                            if selectedCategoryID == cat.id {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundStyle(Color.indigo)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "搜索分类")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

private struct HistoryPageView: View {
    @Query(sort: \ExpenseRecord.date, order: .reverse) private var records: [ExpenseRecord]
    @Query(sort: \Category.sortOrder, order: .forward) private var categories: [Category]
    @AppStorage("currencyCode") private var currencyCode: String = "CNY"

    @State private var selectedCategoryID: UUID? = nil
    @State private var searchOpen = false
    @State private var searchText: String = ""
    @State private var showCategoryFilterDialog = false

    private struct MonthGroup: Identifiable {
        let id: Date // 月份起始日（每天 00:00）用作唯一标识
        let items: [ExpenseRecord]
    }

    // 粘性置顶：冻结当前滚动到顶部的“灰色月份栏”
    @State private var pinnedMonthID: Date? = nil
    // 这个高度要尽量贴近月份灰色条的实际高度（用于占位和判断何时冻结）
    private let pinnedMonthHeaderHeight: CGFloat = 48

    private struct MonthHeaderPosition: Equatable {
        let id: Date
        let minY: CGFloat
    }

    private struct MonthHeaderPositionKey: PreferenceKey {
        static var defaultValue: [MonthHeaderPosition] = []

        static func reduce(value: inout [MonthHeaderPosition], nextValue: () -> [MonthHeaderPosition]) {
            value.append(contentsOf: nextValue())
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                if searchOpen {
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(.secondary)
                        TextField("名称或金额", text: $searchText)
                            .textInputAutocapitalization(.never)
                            .disableAutocorrection(true)
                            .frame(maxWidth: .infinity)
                        Button("取消") {
                            searchText = ""
                            searchOpen = false
                        }
                        .foregroundStyle(.indigo)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(.systemGray4)))
                    .transition(.opacity.combined(with: .move(edge: .top)))
                } else {
                    Text("历史账单")
                        .font(.title2.bold())

                    HStack(spacing: 10) {
                        Button {
                            showCategoryFilterDialog = true
                        } label: {
                            HStack(spacing: 6) {
                                let tint = selectedCategory.map { Color(hex: $0.iconBackgroundHex) }
                                ZStack {
                                    RoundedRectangle(cornerRadius: 9)
                                        .fill((tint ?? Color(.systemGray5)).opacity(selectedCategory == nil ? 1 : 0.2))
                                    Image(systemName: selectedCategory?.iconName ?? "line.3.horizontal.decrease.circle")
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundStyle(tint ?? .secondary)
                                }
                                .frame(width: 28, height: 28)

                                Text(selectedCategory?.name ?? "全部")
                                Image(systemName: "chevron.down")
                                    .font(.caption2)
                            }
                            .font(.subheadline.weight(.medium))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(.systemGray4)))
                        }
                        .buttonStyle(.plain)
                        .confirmationDialog("筛选分类", isPresented: $showCategoryFilterDialog, titleVisibility: .visible) {
                            Button("全部") {
                                selectedCategoryID = nil
                            }
                            ForEach(categories) { cat in
                                Button(cat.name) {
                                    selectedCategoryID = cat.id
                                }
                            }
                        }

                        Button {
                            searchText = ""
                            searchOpen = true
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "magnifyingglass")
                                Text("搜索")
                            }
                            .font(.subheadline.weight(.medium))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(.systemGray4)))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
            .padding(.bottom, 12)
            .background(.white)

            if !searchOpen {
                if monthGroups.isEmpty {
                    Text("暂无数据")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 20)
                        .frame(maxWidth: .infinity, alignment: .center)
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 12) {
                            ForEach(monthGroups) { group in
                                let mTotal = group.items.reduce(0) { $0 + $1.amount }

                                VStack(alignment: .leading, spacing: 10) {
                                    HStack {
                                        Text(formatMonthYear(group.id))
                                            .font(.subheadline.bold())
                                        Spacer()
                                        Text(monthHeaderSummaryText(mTotal))
                                            .font(.caption.weight(.medium))
                                            .foregroundStyle(.secondary)
                                    }
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 8)
                                    .background(Color(.systemGray5))
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(.systemGray4)))
                                    // 冻结的月份条：隐藏原位置的那一条（由 overlay 版本接管视觉）
                                    .opacity(group.id == pinnedMonthID ? 0 : 1)
                                    .background(
                                        GeometryReader { geo in
                                            Color.clear
                                                .preference(
                                                    key: MonthHeaderPositionKey.self,
                                                    value: [
                                                        MonthHeaderPosition(
                                                            id: group.id,
                                                            minY: geo.frame(in: .named("historyMonthScroll")).minY
                                                        )
                                                    ]
                                                )
                                        }
                                    )

                                    ForEach(group.items) { record in
                                        let cat = record.category
                                        let tint = Color(hex: cat?.iconBackgroundHex ?? "#A0A0A0")
                                        HistoryRow(
                                            icon: cat?.iconName ?? "tag",
                                            title: record.title,
                                            time: formatMonthDayTime(record.date),
                                            amount: "-\(formatMoney(record.amount, currencyCode: currencyCode))",
                                            tint: tint
                                        )
                                        .padding(.horizontal, 16)
                                    }
                                }
                            }
                        }
                        .padding(.top, 0)
                        .padding(.bottom, 10)
                    }
                    .coordinateSpace(name: "historyMonthScroll")
                    .onPreferenceChange(MonthHeaderPositionKey.self) { positions in
                        guard !positions.isEmpty else { return }

                        let threshold = pinnedMonthHeaderHeight
                        let candidates = positions.filter { $0.minY <= threshold }

                        if let best = candidates.max(by: { $0.minY < $1.minY }) {
                            pinnedMonthID = best.id
                        } else {
                            pinnedMonthID = positions.min(by: { $0.minY < $1.minY })?.id
                        }
                    }
                    .onAppear {
                        pinnedMonthID = monthGroups.first?.id
                    }
                    .overlay(alignment: .top) {
                        // 只显示冻结的月份条
                        if let pinnedID = pinnedMonthID,
                           let pinnedGroup = monthGroups.first(where: { $0.id == pinnedID }) {
                            let pinnedTotal = pinnedGroup.items.reduce(0) { $0 + $1.amount }

                            HStack {
                                Text(formatMonthYear(pinnedID))
                                    .font(.subheadline.bold())
                                Spacer()
                                Text(monthHeaderSummaryText(pinnedTotal))
                                    .font(.caption.weight(.medium))
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(Color(.systemGray5))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(.systemGray4)))
                            .padding(.top, 0)
                            .frame(maxWidth: .infinity)
                            .allowsHitTesting(false)
                        }
                    }
                }
            } else {
                ScrollView {
                    if searchTrimmed.isEmpty {
                        Text("请输入关键词")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .padding(.vertical, 20)
                    } else if searchMatchedRecords.isEmpty {
                        Text("没有符合条件的记录")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .padding(.vertical, 20)
                    } else {
                        LazyVStack(alignment: .leading, spacing: 8) {
                            ForEach(searchMatchedRecords) { record in
                                let cat = record.category
                                let tint = Color(hex: cat?.iconBackgroundHex ?? "#A0A0A0")
                                HistoryRow(
                                    icon: cat?.iconName ?? "tag",
                                    title: record.title,
                                    time: formatMonthDayTime(record.date),
                                    amount: "-\(formatMoney(record.amount, currencyCode: currencyCode))",
                                    tint: tint
                                )
                            }
                        }
                        .padding(16)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color(.systemGray6))
    }

    private var selectedCategory: Category? {
        guard let selectedCategoryID else { return nil }
        return categories.first(where: { $0.id == selectedCategoryID })
    }

    private var categoryFilteredRecords: [ExpenseRecord] {
        guard let selectedCategoryID else { return records }
        return records.filter { $0.category?.id == selectedCategoryID }
    }

    private func cleanedAmountSearchText(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "元", with: "")
            // 语音输入/手动输入可能包含币种符号，尽量统一剔除便于解析与包含匹配
            .replacingOccurrences(of: "¥", with: "")
            .replacingOccurrences(of: "$", with: "")
            .replacingOccurrences(of: "€", with: "")
            .replacingOccurrences(of: ",", with: "")
    }

    private func monthStart(for date: Date) -> Date {
        let cal = Calendar.current
        let comps = DateComponents(year: cal.component(.year, from: date), month: cal.component(.month, from: date))
        return cal.date(from: comps) ?? date
    }

    private var searchTrimmed: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func monthHeaderSummaryText(_ amount: Double) -> String {
        if let cat = selectedCategory {
            return "\(cat.name)：\(formatMoney(amount, currencyCode: currencyCode))"
        }
        return "支出：\(formatMoney(amount, currencyCode: currencyCode))"
    }

    private var monthGroups: [MonthGroup] {
        let grouped = Dictionary(grouping: categoryFilteredRecords) { monthStart(for: $0.date) }
        return grouped.keys
            .sorted(by: >)
            .map { key in
                MonthGroup(
                    id: key,
                    items: (grouped[key] ?? []).sorted(by: { $0.date > $1.date })
                )
            }
    }

    private var searchMatchedRecords: [ExpenseRecord] {
        guard !searchTrimmed.isEmpty else { return [] }

        let trimmed = searchTrimmed
        let numericCandidate = cleanedAmountSearchText(trimmed)
        let queryAmount = numericCandidate.isEmpty ? nil : parseAmount(numericCandidate)

        // 搜索与“分类筛选”无关：始终在全部记录里匹配
        return records.filter { rec in
            // 1) 标题匹配
            if rec.title.localizedCaseInsensitiveContains(trimmed) { return true }

            // 2) 金额数字匹配
            guard let queryAmount else {
                // 允许纯数字“部分命中”，如输入 "68" 命中 "68.00"
                let formatted = formatAmountNumber(rec.amount).replacingOccurrences(of: ",", with: "")
                return !numericCandidate.isEmpty && formatted.contains(numericCandidate)
            }

            // 精确匹配（浮点容差）
            if abs(rec.amount - queryAmount) < 0.005 { return true }

            // 部分匹配（如输入 "68" 命中 "68.00"）
            let formatted = formatAmountNumber(rec.amount).replacingOccurrences(of: ",", with: "")
            return !numericCandidate.isEmpty && formatted.contains(numericCandidate)
        }
    }

}

private struct StatsPageView: View {
    @Query(sort: \ExpenseRecord.date, order: .reverse) private var records: [ExpenseRecord]
    @Query(sort: \Category.sortOrder, order: .forward) private var categories: [Category]
    @AppStorage("currencyCode") private var currencyCode: String = "CNY"

    private enum StatsPeriod: String {
        case month
        case quarter
        case year
    }

    private enum TrendChartType: String {
        case bar
        case pie
    }

    @State private var period: StatsPeriod = .month
    @State private var trendChartType: TrendChartType = .bar

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Text("支出统计")
                    .font(.title2.bold())
                    .foregroundStyle(.primary)
                Text("了解你的消费趋势与结构")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 12)
            .padding(.horizontal, 20)
            .padding(.bottom, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.systemBackground))
            .overlay(
                Divider()
                    .background(Color(.systemGray4)),
                alignment: .bottom
            )

            ScrollView {
                VStack(spacing: 16) {
                    HStack(spacing: 8) {
                        periodButton(title: "月", active: period == .month)
                        periodButton(title: "季度", active: period == .quarter)
                        periodButton(title: "年", active: period == .year)
                    }
                    .padding(8)
                    .background(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(Color(.systemGray5), lineWidth: 1)
                    )

                    // 趋势图（按区间分桶求和）
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("趋势图")
                                .font(.headline)
                                .foregroundStyle(.primary)
                            Spacer()
                            HStack(spacing: 6) {
                                chartTypeButton(title: "柱状", type: .bar)
                                chartTypeButton(title: "饼状", type: .pie)
                            }
                        }

                        if trendChartType == .pie {
                            if pieItems.isEmpty {
                                Text("暂无数据")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .padding(.vertical, 10)
                            } else {
                                VStack(spacing: 10) {
                                    PieChart(items: pieItems)
                                        .frame(height: 150)

                                    VStack(spacing: 10) {
                                        ForEach(pieItems, id: \.title) { item in
                                            HStack(spacing: 8) {
                                                Circle()
                                                    .fill(item.color)
                                                    .frame(width: 8, height: 8)
                                                Text(item.title)
                                                    .font(.subheadline)
                                                    .foregroundStyle(.secondary)
                                                Spacer()
                                                Text("\(Int((item.ratio * 100).rounded()))%")
                                                    .font(.subheadline.weight(.medium))
                                                    .foregroundStyle(.primary)
                                                Text(formatMoney(item.value, currencyCode: currencyCode))
                                                    .font(.subheadline)
                                                    .foregroundStyle(.secondary)
                                            }
                                        }
                                    }
                                }
                            }
                        } else {
                            HStack(alignment: .bottom, spacing: 8) {
                                ForEach(Array(trendBuckets.enumerated()), id: \.offset) { idx, sum in
                                    Bar(
                                        h: trendBarHeight(sum: sum),
                                        c: Color.indigo.opacity(trendBarOpacity(index: idx))
                                    )
                                }
                            }
                            .frame(height: 176, alignment: .bottom)

                            HStack {
                                ForEach(Array(trendLabels.enumerated()), id: \.offset) { idx, label in
                                    Text(label)
                                    if idx < trendLabels.count - 1 {
                                        Spacer()
                                    }
                                }
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                    }
                    .padding(16)
                    .background(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(Color(.systemGray5), lineWidth: 1)
                    )

                    // 分布图
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("分布图")
                                .font(.headline)
                                .foregroundStyle(.primary)
                            Spacer()
                            Text("分类降序")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        if distributionItems.isEmpty {
                            Text("暂无数据")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .padding(.vertical, 10)
                        } else {
                            VStack(spacing: 12) {
                                ForEach(distributionItems, id: \.title) { item in
                                    DistributionItem(
                                        title: item.title,
                                        value: formatMoney(item.value, currencyCode: currencyCode),
                                        ratio: item.ratio,
                                        color: item.color
                                    )
                                }
                            }
                        }
                    }
                    .padding(16)
                    .background(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(Color(.systemGray5), lineWidth: 1)
                    )
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
            }
            .background(Color(.systemGray6))
        }
    }

    @ViewBuilder
    private func periodButton(title: String, active: Bool) -> some View {
        Button {
            switch title {
            case "月": period = .month
            case "季度": period = .quarter
            default: period = .year
            }
        } label: {
            Text(title)
                .font(.subheadline.weight(active ? .semibold : .regular))
                .foregroundStyle(active ? .white : Color(.systemGray))
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity)
                .background(active ? Color.indigo : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    private var range: (start: Date, end: Date) {
        let cal = Calendar.current
        let now = Date()
        switch period {
        case .month:
            let start = cal.date(from: DateComponents(year: cal.component(.year, from: now), month: cal.component(.month, from: now)))!
            let end = cal.date(byAdding: .month, value: 1, to: start)!
            return (start, end)
        case .quarter:
            let month = cal.component(.month, from: now)
            let quarter = (month - 1) / 3
            let startMonth = quarter * 3 + 1
            let start = cal.date(from: DateComponents(year: cal.component(.year, from: now), month: startMonth))!
            let end = cal.date(byAdding: .month, value: 3, to: start)!
            return (start, end)
        case .year:
            let start = cal.date(from: DateComponents(year: cal.component(.year, from: now)))!
            let end = cal.date(byAdding: .year, value: 1, to: start)!
            return (start, end)
        }
    }

    private var recordsInRange: [ExpenseRecord] {
        records.filter { $0.date >= range.start && $0.date < range.end }
    }

    private var totalInRange: Double {
        recordsInRange.reduce(0) { $0 + $1.amount }
    }

    private var trendBuckets: [Double] {
        let bucketCount = 8
        let totalInterval = range.end.timeIntervalSince(range.start)
        guard totalInterval > 0 else { return Array(repeating: 0, count: bucketCount) }

        let step = totalInterval / Double(bucketCount)
        var buckets = Array(repeating: 0.0, count: bucketCount)

        for rec in recordsInRange {
            let elapsed = rec.date.timeIntervalSince(range.start)
            let idx = min(bucketCount - 1, max(0, Int(elapsed / step)))
            buckets[idx] += rec.amount
        }
        return buckets
    }

    private var trendLabels: [String] {
        let labelCount = 5
        let totalInterval = range.end.timeIntervalSince(range.start)
        guard totalInterval > 0 else { return Array(repeating: "", count: labelCount) }

        return (0..<labelCount).map { i in
            let t = Double(i) / Double(labelCount - 1)
            let date = range.start.addingTimeInterval(totalInterval * t)
            return formatMonthSlashDay(date)
        }
    }

    private func trendBarHeight(sum: Double) -> CGFloat {
        let minH: CGFloat = 48
        let maxH: CGFloat = 160
        let maxSum = trendBuckets.max() ?? 0
        // 没有任何数据时，避免用“固定高度柱子”造成误导
        guard maxSum > 0 else { return 0 }
        // 0 支出天不显示柱子
        guard sum > 0 else { return 0 }
        let ratio = CGFloat(sum / maxSum)
        return minH + (maxH - minH) * ratio
    }

    private func trendBarOpacity(index: Int) -> Double {
        // 用 index 做视觉梯度，避免在小数据时出现“全一样”的柱子
        let bucketCount = max(trendBuckets.count, 1)
        return 0.2 + 0.8 * Double(index) / Double(max(1, bucketCount - 1))
    }

    fileprivate struct DistributionItemModel {
        let title: String
        let value: Double
        let ratio: CGFloat
        let color: Color
    }

    private var distributionItems: [DistributionItemModel] {
        guard totalInRange > 0 else { return [] }

        var sums: [UUID?: Double] = [:]
        for rec in recordsInRange {
            sums[rec.category?.id, default: 0] += rec.amount
        }

        let byID: [UUID: Category] = Dictionary(uniqueKeysWithValues: categories.map { ($0.id, $0) })

        return sums
            .map { (catIDOpt, value) -> DistributionItemModel in
                if let catID = catIDOpt, let cat = byID[catID] {
                    return DistributionItemModel(
                        title: cat.name,
                        value: value,
                        ratio: CGFloat(value / totalInRange),
                        color: Color(hex: cat.iconBackgroundHex)
                    )
                }
                return DistributionItemModel(
                    title: "未分类",
                    value: value,
                    ratio: CGFloat(value / totalInRange),
                    color: Color(hex: "#A0A0A0")
                )
            }
            .sorted { $0.value > $1.value }
            .prefix(4)
            .map { $0 }
    }

    private var pieItems: [DistributionItemModel] {
        guard totalInRange > 0 else { return [] }

        var sums: [UUID?: Double] = [:]
        for rec in recordsInRange {
            sums[rec.category?.id, default: 0] += rec.amount
        }

        let byID: [UUID: Category] = Dictionary(uniqueKeysWithValues: categories.map { ($0.id, $0) })

        return sums
            .map { (catIDOpt, value) -> DistributionItemModel in
                if let catID = catIDOpt, let cat = byID[catID] {
                    return DistributionItemModel(
                        title: cat.name,
                        value: value,
                        ratio: CGFloat(value / totalInRange),
                        color: Color(hex: cat.iconBackgroundHex)
                    )
                }
                return DistributionItemModel(
                    title: "未分类",
                    value: value,
                    ratio: CGFloat(value / totalInRange),
                    color: Color(hex: "#A0A0A0")
                )
            }
            .sorted { $0.value > $1.value }
    }

    @ViewBuilder
    private func chartTypeButton(title: String, type: TrendChartType) -> some View {
        Button {
            trendChartType = type
        } label: {
            Text(title)
                .font(.caption.weight(trendChartType == type ? .semibold : .regular))
                .foregroundStyle(trendChartType == type ? .white : .secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(trendChartType == type ? Color.indigo : Color(.systemGray6))
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }
}

private struct DistributionItem: View {
    let title: String
    let value: String
    let ratio: CGFloat
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                    .font(.subheadline)
                    .foregroundStyle(Color(.systemGray))
                Spacer()
                Text(value)
                    .font(.subheadline)
                    .foregroundStyle(Color(.systemGray))
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 999)
                        .fill(Color(.systemGray5))
                        .frame(height: 8)
                    RoundedRectangle(cornerRadius: 999)
                        .fill(color)
                        .frame(width: geo.size.width * ratio, height: 8)
                }
            }
            .frame(height: 8)
        }
    }
}

private struct PieChart: View {
    let items: [StatsPageView.DistributionItemModel]

    var body: some View {
        GeometryReader { geo in
            let size = min(geo.size.width, geo.size.height)
            let lineWidth = size * 0.34

            ZStack {
                ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                    let start = startFraction(for: index)
                    let end = start + Double(item.ratio)

                    Circle()
                        .trim(from: start, to: end)
                        .stroke(
                            item.color,
                            style: StrokeStyle(lineWidth: lineWidth, lineCap: .butt, lineJoin: .round)
                        )
                        .rotationEffect(.degrees(-90))
                }
            }
            .frame(width: size, height: size)
            .position(x: geo.size.width / 2, y: geo.size.height / 2)
        }
    }

    private func startFraction(for index: Int) -> Double {
        guard index > 0 else { return 0 }
        return items[..<index].reduce(0) { $0 + Double($1.ratio) }
    }
}

private struct SettingsPageView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Category.sortOrder, order: .forward) private var categories: [Category]
    @Query(sort: \ExpenseRecord.date, order: .reverse) private var records: [ExpenseRecord]
    @AppStorage("currencyCode") private var currencyCode: String = "CNY"

    @State private var categoryEditorRoute: CategoryEditorSheetRoute?

    @State private var pendingDeleteCategory: Category?
    @State private var showDeleteAlert = false
    @State private var showClearAllRecordsAlert = false
    @State private var clearAllRecordsConfirmText = ""
    @State private var showClearSuccessAlert = false

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Text("设置")
                    .font(.title2.bold())
                    .foregroundStyle(.primary)
                Text("偏好、分类与数据管理")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 12)
            .padding(.horizontal, 20)
            .padding(.bottom, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.systemBackground))
            .overlay(
                Divider()
                    .background(Color(.systemGray4)),
                alignment: .bottom
            )

            ScrollView {
                VStack(spacing: 16) {
                    // 货币单位
                    VStack(alignment: .leading, spacing: 12) {
                        Text("货币单位")
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(.primary)

                        VStack(spacing: 8) {
                            currencyOption(
                                code: "CNY",
                                text: "人民币 (CNY)",
                                selected: currentCurrencyCode == "CNY"
                            )
                            currencyOption(
                                code: "USD",
                                text: "美元 (USD)",
                                selected: currentCurrencyCode == "USD"
                            )
                            currencyOption(
                                code: "EUR",
                                text: "欧元 (EUR)",
                                selected: currentCurrencyCode == "EUR"
                            )
                        }
                    }
                    .padding(16)
                    .background(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16).stroke(Color(.systemGray4), lineWidth: 1)
                    )

                    // 分类管理
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("分类管理")
                                .font(.headline.weight(.semibold))
                                .foregroundStyle(.primary)
                            Spacer()
                            Button {
                                categoryEditorRoute = CategoryEditorSheetRoute(category: nil)
                            } label: {
                                Text("新增")
                                    .font(.subheadline.weight(.medium))
                                    .foregroundStyle(Color.indigo)
                            }
                        }

                        VStack(spacing: 8) {
                            if categories.isEmpty {
                                Text("暂无分类，请先添加")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .padding(.vertical, 10)
                            } else {
                                ForEach(categories) { category in
                                    categoryRow(category)
                                }
                            }
                        }
                    }
                    .padding(16)
                    .background(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16).stroke(Color(.systemGray4), lineWidth: 1)
                    )

                    // 数据管理
                    VStack(alignment: .leading, spacing: 12) {
                        Text("数据管理")
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(.primary)

                        VStack(spacing: 8) {
                            let emerald600 = Color(red: 5 / 255, green: 150 / 255, blue: 105 / 255)
                            Button {
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: "square.and.arrow.down")
                                    Text("导出 CSV 数据")
                                        .font(.subheadline.weight(.medium))
                                }
                                .foregroundStyle(.white)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(emerald600)
                            .clipShape(RoundedRectangle(cornerRadius: 12))

                            let rose50 = Color(red: 255 / 255, green: 241 / 255, blue: 242 / 255)
                            let rose600 = Color(red: 225 / 255, green: 29 / 255, blue: 72 / 255)
                            let rose200 = Color(red: 254 / 255, green: 205 / 255, blue: 211 / 255)

                            Button {
                                clearAllRecordsConfirmText = ""
                                showClearAllRecordsAlert = true
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: "trash")
                                    Text("清理所有数据")
                                        .font(.subheadline.weight(.medium))
                                }
                                .foregroundStyle(rose600)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(rose50)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12).stroke(rose200, lineWidth: 1)
                            )
                        }
                    }
                    .padding(16)
                    .background(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16).stroke(Color(.systemGray4), lineWidth: 1)
                    )
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
            }
            .background(Color(.systemGray6))
        }
        .task {
            seedDefaultCategoriesIfNeeded(modelContext: modelContext)
        }
        .sheet(item: $categoryEditorRoute) { route in
            CategoryEditorSheet(
                category: route.category,
                mode: route.category == nil ? .create : .edit
            )
        }
        .alert(
            "删除分类？",
            isPresented: $showDeleteAlert,
            presenting: pendingDeleteCategory
        ) { category in
            Button("取消", role: .cancel) {}
            Button("删除", role: .destructive) {
                modelContext.delete(category)
                do {
                    try modelContext.save()
                } catch {
                    print("删除分类失败：\(error)")
                }
            }
        } message: { _ in
            Text("删除后该分类将不会用于新记录，但已有记录会保留并变为“未分类”。")
        }
        .alert("确认清理所有历史数据", isPresented: $showClearAllRecordsAlert) {
            TextField("请输入“删除”确认", text: $clearAllRecordsConfirmText)
                .textInputAutocapitalization(.never)
                .disableAutocorrection(true)
            Button("取消", role: .cancel) {
                clearAllRecordsConfirmText = ""
            }
            Button("确认清理", role: .destructive) {
                clearAllExpenseRecords()
                clearAllRecordsConfirmText = ""
            }
            .disabled(clearAllRecordsConfirmText.trimmingCharacters(in: .whitespacesAndNewlines) != "删除")
        } message: {
            Text("此操作不可恢复。请输入“删除”后可清空所有记账记录。")
        }
        .alert("删除成功", isPresented: $showClearSuccessAlert) {
            Button("知道了", role: .cancel) {}
        } message: {
            Text("所有记账记录已清理完成。")
        }
    }

    private var currentCurrencyCode: String {
        normalizedCurrencyCode(currencyCode)
    }

    @ViewBuilder
    private func currencyOption(code: String, text: String, selected: Bool) -> some View {
        let borderColor: Color = selected ? Color.indigo.opacity(0.35) : Color(.systemGray4)
        let bg: Color = selected ? Color.indigo.opacity(0.08) : .white
        let iconColor: Color = selected ? Color.indigo : Color(.systemGray3)

        Button {
            currencyCode = code
        } label: {
            HStack {
                Text(text)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                Spacer()
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(iconColor)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(bg)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(borderColor, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func categoryRow(_ category: Category) -> some View {
        let tint = Color(hex: category.iconBackgroundHex)
        HStack {
            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 12)
                    .fill(tint.opacity(0.2))
                    .frame(width: 42, height: 42)
                    .overlay(
                        Image(systemName: category.iconName)
                            .font(.title3)
                            .foregroundStyle(tint)
                    )
                Text(category.name)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
            }
            Spacer()

            HStack(spacing: 16) {
                Button {
                    categoryEditorRoute = CategoryEditorSheetRoute(category: category)
                } label: {
                    Image(systemName: "square.and.pencil")
                }
                .foregroundStyle(Color(.systemGray3))

                Button {
                    pendingDeleteCategory = category
                    showDeleteAlert = true
                } label: {
                    Image(systemName: "trash")
                }
                .foregroundStyle(Color(.systemGray3))
            }
        }
        .padding(12)
        .background(.white)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(.systemGray4), lineWidth: 1))
    }

    private func clearAllExpenseRecords() {
        for record in records {
            modelContext.delete(record)
        }

        do {
            try modelContext.save()
            showClearSuccessAlert = true
        } catch {
            print("清理所有记账记录失败：\(error)")
        }
    }
}

private enum CategoryEditorMode {
    case create
    case edit
}

private struct CategoryEditorSheetRoute: Identifiable {
    let id: UUID
    let category: Category?

    init(category: Category?) {
        self.category = category
        self.id = category?.id ?? UUID()
    }
}

// MARK: - Data formatting helpers

private enum CachedFormatters {
    static let decimal2: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        formatter.locale = Locale.current
        return formatter
    }()

    static let monthYear: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy年M月"
        return formatter
    }()

    static let timeOnly: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    static let monthDayTime: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M月d日 HH:mm"
        return formatter
    }()

    static let monthSlashDay: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "M/d"
        return formatter
    }()
}

private func parseAmount(_ text: String) -> Double? {
    let cleaned = text
        .trimmingCharacters(in: .whitespacesAndNewlines)
        // 手动输入/语音识别时可能包含不同币种符号，统一剔除便于解析。
        .replacingOccurrences(of: "¥", with: "")
        .replacingOccurrences(of: "$", with: "")
        .replacingOccurrences(of: "€", with: "")
        .replacingOccurrences(of: ",", with: "")

    guard !cleaned.isEmpty else { return nil }
    return Double(cleaned)
}

private func formatMoney(_ amount: Double, currencyCode: String) -> String {
    let num = CachedFormatters.decimal2.string(from: NSNumber(value: amount)) ?? String(format: "%.2f", amount)
    return "\(currencySymbol(for: currencyCode))\(num)"
}

private func formatAmountNumber(_ amount: Double) -> String {
    CachedFormatters.decimal2.string(from: NSNumber(value: amount)) ?? String(format: "%.2f", amount)
}

private func normalizedCurrencyCode(_ code: String) -> String {
    switch code.uppercased() {
    case "CNY": return "CNY"
    case "USD": return "USD"
    case "EUR": return "EUR"
    default: return "CNY"
    }
}

private func currencySymbol(for currencyCode: String) -> String {
    switch normalizedCurrencyCode(currencyCode) {
    case "CNY": return "¥"
    case "USD": return "$"
    case "EUR": return "€"
    default: return "¥"
    }
}

private func formatMonthYear(_ date: Date) -> String {
    CachedFormatters.monthYear.string(from: date)
}

private func formatTimeOnly(_ date: Date) -> String {
    CachedFormatters.timeOnly.string(from: date)
}

private func formatMonthDayTime(_ date: Date) -> String {
    CachedFormatters.monthDayTime.string(from: date)
}

private func formatMonthSlashDay(_ date: Date) -> String {
    CachedFormatters.monthSlashDay.string(from: date)
}

// MARK: - Category editor

private let categoryIconCandidates: [String] = [
    "fork.knife",
    "bus.fill",
    "cart.fill",
    "film.fill",
    "mug.fill",
    "tram.fill",
    "figure.walk",
    "book.fill",
    "gamecontroller.fill",
    "heart.fill",
    "leaf.fill",
    "tshirt.fill",
    "car.fill",
    "creditcard.fill"
]

private let categoryColorCandidates: [String] = [
    "#FF3B30", "#FF9500", "#FFCC00", "#34C759", "#0A84FF", "#64D2FF",
    "#5E5CE6", "#AF52DE", "#FF2D55", "#FF9F0A", "#8E8E93"
]

private struct CategoryEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \Category.sortOrder, order: .forward) private var categories: [Category]

    let category: Category?
    let mode: CategoryEditorMode

    @State private var name: String
    @State private var iconName: String
    @State private var iconBackgroundHex: String

    init(category: Category?, mode: CategoryEditorMode) {
        self.category = category
        self.mode = mode
        _name = State(initialValue: category?.name ?? "")
        _iconName = State(initialValue: category?.iconName ?? "tag")
        _iconBackgroundHex = State(initialValue: category?.iconBackgroundHex ?? "#FF9500")
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("分类名称")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        TextField("例如 餐饮", text: $name)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .background(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color(.systemGray5)))
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Text("选择图标")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 4), spacing: 10) {
                            ForEach(categoryIconCandidates, id: \.self) { icon in
                                Button {
                                    iconName = icon
                                } label: {
                                    ZStack {
                                        RoundedRectangle(cornerRadius: 12)
                                            .fill(Color(hex: iconBackgroundHex).opacity(0.18))
                                            .frame(height: 44)
                                        Image(systemName: icon)
                                            .font(.title3)
                                            .foregroundStyle(Color(hex: iconBackgroundHex))
                                    }
                                    .overlay(alignment: .topTrailing) {
                                        if iconName == icon {
                                            Image(systemName: "checkmark.circle.fill")
                                                .font(.caption)
                                                .foregroundStyle(.indigo)
                                                .padding(2)
                                        }
                                    }
                                }
                            }
                        }

                        TextField("自定义 SF Symbols 图标名（可选）", text: $iconName)
                            .font(.subheadline)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .background(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color(.systemGray5)))
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Text("选择图标背景色")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 6), spacing: 10) {
                            ForEach(categoryColorCandidates, id: \.self) { hex in
                                Button {
                                    iconBackgroundHex = hex
                                } label: {
                                    ZStack {
                                        Circle()
                                            .fill(Color(hex: hex))
                                            .frame(width: 26, height: 26)
                                        if iconBackgroundHex == hex {
                                            Image(systemName: "checkmark")
                                                .font(.caption2.bold())
                                                .foregroundStyle(.white)
                                        }
                                    }
                                }
                            }
                        }
                    }

                    Button {
                        save()
                    } label: {
                        Text(mode == .create ? "保存新分类" : "保存修改")
                            .fontWeight(.semibold)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(brandPurpleGradient)
                            .foregroundStyle(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || iconName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                .padding(16)
            }
            .navigationTitle(mode == .create ? "新增分类" : "编辑分类")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
            }
        }
    }

    private func save() {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }

        if let category {
            category.name = trimmedName
            category.iconName = iconName
            category.iconBackgroundHex = iconBackgroundHex
        } else {
            let nextSort = (categories.map { $0.sortOrder }.max() ?? 0) + 1
            modelContext.insert(
                Category(
                    name: trimmedName,
                    iconName: iconName,
                    iconBackgroundHex: iconBackgroundHex,
                    sortOrder: nextSort
                )
            )
        }

        do {
            try modelContext.save()
        } catch {
            print("保存分类失败：\(error)")
        }

        dismiss()
    }
}

private struct ActionCard: View {
    let icon: String
    let title: String
    let subtitle: String
    let tint: Color
    let inverted: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: icon)
                .font(.title3.bold())
                .foregroundStyle(inverted ? .white : tint)
            Text(title)
                .font(.headline)
                .foregroundStyle(inverted ? .white : .primary)
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(inverted ? .white.opacity(0.9) : .secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 112, alignment: .leading)
        .padding(14)
        .background {
            if inverted {
                brandPurpleGradient
            } else {
                Color.white
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(inverted ? .clear : Color(.systemGray5)))
    }
}

private struct WhiteSection<Content: View>: View {
    let title: String
    var subtitle: String?
    var trailing: String?
    @ViewBuilder var content: Content

    init(title: String, subtitle: String? = nil, trailing: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.subtitle = subtitle
        self.trailing = trailing
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(title).font(.headline)
                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if let trailing {
                    Text(trailing)
                        .font(.subheadline)
                        .foregroundStyle(.indigo)
                }
            }
            content
        }
        .padding(14)
        .background(.white)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color(.systemGray5)))
    }
}

private struct RecordRow: View {
    let icon: String
    let title: String
    let meta: String
    let amount: String
    let color: Color

    var body: some View {
        HStack {
            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 9)
                    .fill(color.opacity(0.2))
                    .frame(width: 36, height: 36)
                    .overlay(Image(systemName: icon).foregroundStyle(color))
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.subheadline.weight(.medium))
                    Text(meta).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            Text(amount).font(.subheadline.weight(.semibold))
        }
        .padding(12)
        .background(.white)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(.systemGray5)))
    }
}

private struct HistoryRow: View {
    let icon: String
    let title: String
    let time: String
    let amount: String
    let tint: Color

    var body: some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 12)
                .fill(tint.opacity(0.2))
                .frame(width: 44, height: 44)
                .overlay(Image(systemName: icon).font(.title3).foregroundStyle(tint))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(time).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text(amount).font(.subheadline.weight(.semibold))
        }
        .padding(10)
        .background(.white)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(.systemGray5)))
    }
}

private struct Bar: View {
    let h: CGFloat
    let c: Color
    var body: some View {
        RoundedRectangle(cornerRadius: 4)
            .fill(c)
            .frame(width: 26, height: h)
    }
}

#Preview {
    ContentView()
}
