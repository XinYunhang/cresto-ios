import SwiftUI
import SwiftData
import UIKit

/// 新增 / 编辑订阅弹窗（参考图 1 主信息色块风格：删除快捷预设、可视化图标选择网格、支持自定义付款方式 + USD/JPY 折算）。
struct SubscriptionEditor: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    @AppStorage("usdToCny") private var usdToCny = 7.25
    @AppStorage("jpyToCny") private var jpyToCny = 0.048

    let subscription: Subscription?
    var initialPreset: SubscriptionPreset? = nil

    @State private var name: String
    @State private var priceText: String
    @State private var currency: SubscriptionCurrency
    @State private var cycle: BillingCycle
    @State private var nextCharge: Date
    @State private var paymentTitle: String
    @State private var category: SubscriptionCategory
    @State private var brand: BrandIcon
    @State private var remindEnabled: Bool
    @State private var remindDays: Int
    @State private var validation: String?

    @State private var isIconPickerPresented = false
    @State private var isPaymentPickerPresented = false
    @State private var editingRateCurrency: SubscriptionCurrency?
    @State private var rateDraft = ""

    init(subscription: Subscription?, initialPreset: SubscriptionPreset? = nil) {
        self.subscription = subscription
        self.initialPreset = initialPreset
        if let sub = subscription {
            _name = State(initialValue: sub.name)
            _priceText = State(initialValue: sub.currency == .JPY ? String(format: "%.0f", sub.price) : String(format: "%.2f", sub.price))
            _currency = State(initialValue: sub.currency)
            _cycle = State(initialValue: sub.cycle)
            _nextCharge = State(initialValue: sub.nextChargeDate)
            _paymentTitle = State(initialValue: sub.paymentDisplayTitle)
            _category = State(initialValue: sub.category)
            _brand = State(initialValue: sub.brand)
            _remindEnabled = State(initialValue: sub.remindEnabled)
            _remindDays = State(initialValue: sub.remindDaysBefore)
        } else if let preset = initialPreset {
            let calendar = Calendar.current
            _name = State(initialValue: preset.name)
            _priceText = State(initialValue: preset.currency == .JPY ? String(format: "%.0f", preset.price) : String(format: "%.2f", preset.price))
            _currency = State(initialValue: preset.currency)
            _cycle = State(initialValue: preset.cycle)
            _nextCharge = State(initialValue: calendar.date(
                byAdding: .month, value: 1, to: calendar.startOfDay(for: Date())
            ) ?? Date())
            _paymentTitle = State(initialValue: preset.payment.title)
            _category = State(initialValue: preset.category)
            _brand = State(initialValue: preset.brand)
            _remindEnabled = State(initialValue: true)
            _remindDays = State(initialValue: 3)
        } else {
            let calendar = Calendar.current
            _name = State(initialValue: "")
            _priceText = State(initialValue: "")
            _currency = State(initialValue: .CNY)
            _cycle = State(initialValue: .monthly)
            _nextCharge = State(initialValue: calendar.date(
                byAdding: .month, value: 1, to: calendar.startOfDay(for: Date())
            ) ?? Date())
            _paymentTitle = State(initialValue: PaymentMethod.applePay.title)
            _category = State(initialValue: .other)
            _brand = State(initialValue: .generic)
            _remindEnabled = State(initialValue: true)
            _remindDays = State(initialValue: 3)
        }
    }

    private var parsedPrice: Double {
        Double(priceText.replacingOccurrences(of: ",", with: ".")) ?? 0
    }

    private var formattedNextCharge: String {
        let c = Calendar.current.dateComponents([.month, .day], from: nextCharge)
        return "\(c.month ?? 1)月\(c.day ?? 1)日扣费"
    }

    var body: some View {
        NavigationStack {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: Theme.cardGap) {
                    heroSummaryCard
                    formCard
                    reminderCard
                    if let validation {
                        Text(validation)
                            .font(.system(size: 11.5))
                            .foregroundStyle(Color(hex: 0xF43F5E))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    saveButton
                    if let subscription {
                        deleteButton(subscription)
                    }
                }
                .padding(.horizontal, Theme.screenPadding)
                .padding(.vertical, 12)
            }
            .background(Theme.bg)
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(subscription == nil ? "添加订阅" : "订阅详情")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                        .foregroundStyle(Theme.textSecondary)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }
                        .fontWeight(.semibold)
                        .foregroundStyle(Theme.brand)
                }
            }
            .tint(Theme.brand)
        }
        .presentationBackground(Theme.bg)
        .sheet(isPresented: $isIconPickerPresented) {
            BrandIconPickerSheet(selection: $brand)
        }
        .sheet(isPresented: $isPaymentPickerPresented) {
            PaymentMethodPickerSheet(selection: $paymentTitle)
        }
        .alert(rateAlertTitle, isPresented: Binding(
            get: { editingRateCurrency != nil },
            set: { if !$0 { editingRateCurrency = nil } }
        )) {
            TextField(editingRateCurrency == .JPY ? "4.80" : "7.25", text: $rateDraft)
                .keyboardType(.decimalPad)
            Button("保存") {
                if let value = Double(rateDraft.replacingOccurrences(of: ",", with: ".")), value > 0 {
                    if editingRateCurrency == .USD {
                        usdToCny = value
                    } else if editingRateCurrency == .JPY {
                        jpyToCny = value / 100.0
                    }
                }
                editingRateCurrency = nil
            }
            Button("取消", role: .cancel) { editingRateCurrency = nil }
        } message: {
            Text(rateAlertMessage)
        }
    }

    // MARK: 顶部主信息色块 Hero 卡（参考图 1）

    private var heroSummaryCard: some View {
        let tint = brand.tintColor
        let bgAlpha = colorScheme == .dark ? 0.22 : 0.13
        let pillAlpha = colorScheme == .dark ? 0.24 : 0.14
        let displayTitle = name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? (brand == .generic ? "新建订阅" : brand.displayName)
            : name
        let displayAmount: String = {
            guard parsedPrice > 0 else { return "\(currency.symbol)--" }
            if currency == .JPY {
                return "\(currency.symbol)\(String(format: "%.0f", parsedPrice))"
            }
            return "\(currency.symbol)\(String(format: "%.2f", parsedPrice))"
        }()

        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 13) {
                Button {
                    isIconPickerPresented = true
                } label: {
                    ZStack(alignment: .bottomTrailing) {
                        RoundedRectangle(cornerRadius: AppRadius.item, style: .continuous)
                            .fill(Theme.surface)
                            .frame(width: 52, height: 52)
                            .overlay {
                                BrandLogo(brand: brand, size: 34)
                            }
                        ReiconIcon(icon: .edit, size: 10)
                            .foregroundStyle(Color.white)
                            .frame(width: 18, height: 18)
                            .background(Circle().fill(tint))
                            .offset(x: 4, y: 4)
                    }
                }
                .buttonStyle(PressableStyle())
                .accessibilityLabel("选择订阅图标")

                VStack(alignment: .leading, spacing: 3) {
                    Text(displayTitle)
                        .font(.system(size: 19, weight: .bold))
                        .foregroundStyle(Theme.text)
                        .lineLimit(1)
                    Text("\(paymentTitle) · \(formattedNextCharge)")
                        .font(.system(size: 12, design: .rounded))
                        .foregroundStyle(Theme.textSecondary)
                }

                Spacer(minLength: 6)

                Text(displayAmount)
                    .font(.system(size: 23, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(tint)
            }

            HStack(spacing: 7) {
                heroPill(cycle.title, tint: tint, alpha: pillAlpha)
                heroPill(currency.title, tint: tint, alpha: pillAlpha)
                if (currency == .USD || currency == .JPY), parsedPrice > 0 {
                    let cnyValue = parsedPrice * (currency == .USD ? usdToCny : jpyToCny)
                    heroPill("≈ ¥\(String(format: "%.2f", cnyValue))", tint: tint, alpha: pillAlpha)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: AppRadius.card, style: .continuous)
                .fill(tint.opacity(bgAlpha))
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppRadius.card, style: .continuous)
                .strokeBorder(tint.opacity(0.22), lineWidth: 0.7)
        )
    }

    private func heroPill(_ text: String, tint: Color, alpha: Double) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(tint)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(Capsule().fill(tint.opacity(alpha)))
    }

    private var rateAlertTitle: String {
        editingRateCurrency == .JPY ? "100 JPY → CNY 参考汇率" : "1 USD → CNY 参考汇率"
    }

    private var rateAlertMessage: String {
        if editingRateCurrency == .JPY {
            return "当前 100 JPY = \(String(format: "%.2f", jpyToCny * 100)) CNY"
        }
        return "当前 1 USD = \(String(format: "%.2f", usdToCny)) CNY"
    }

    // MARK: 表单

    private var formCard: some View {
        VStack(spacing: 0) {
            formRow("图标") {
                Button {
                    isIconPickerPresented = true
                } label: {
                    HStack(spacing: 7) {
                        BrandLogo(brand: brand, size: 22)
                        Text(brand.displayName)
                            .font(.system(size: 13.5))
                            .foregroundStyle(Theme.textSecondary)
                        ReiconIcon(icon: .chevronRight, size: 11)
                            .foregroundStyle(Theme.textTertiary)
                    }
                }
                .buttonStyle(.plain)
            }

            formDivider

            formRow("名称") {
                TextField("订阅名称", text: $name)
                    .font(.system(size: 13.5))
                    .foregroundStyle(Theme.text)
                    .multilineTextAlignment(.trailing)
                    .autocorrectionDisabled()
            }

            formDivider

            formRow("价格") {
                HStack(spacing: 8) {
                    TextField(currency == .JPY ? "0" : "0.00", text: $priceText)
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(Theme.text)
                        .multilineTextAlignment(.trailing)
                        .keyboardType(.decimalPad)
                        .frame(maxWidth: 92)

                    HStack(spacing: 4) {
                        ForEach(SubscriptionCurrency.allCases) { item in
                            capsule(item.title, isOn: currency == item) {
                                currency = item
                            }
                        }
                    }
                }
            }

            if currency == .USD || currency == .JPY {
                formDivider
                exchangeRateRow
            }

            formDivider

            formRow("周期") {
                HStack(spacing: 4) {
                    ForEach(BillingCycle.allCases) { item in
                        capsule(item.shortTitle, isOn: cycle == item) {
                            cycle = item
                        }
                    }
                }
            }

            formDivider

            formRow("下次扣费") {
                DatePicker("", selection: $nextCharge, displayedComponents: .date)
                    .labelsHidden()
                    .datePickerStyle(.compact)
                    .environment(\.locale, Locale(identifier: "zh_CN"))
            }

            formDivider

            formRow("付款方式") {
                Button {
                    isPaymentPickerPresented = true
                } label: {
                    HStack(spacing: 5) {
                        Text(paymentTitle)
                            .font(.system(size: 13.5))
                            .foregroundStyle(Theme.textSecondary)
                        ReiconIcon(icon: .chevronRight, size: 11)
                            .foregroundStyle(Theme.textTertiary)
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .cardSurface()
    }

    private var exchangeRateRow: some View {
        let rateLabel: String = currency == .USD
            ? "1 USD = \(String(format: "%.2f", usdToCny)) CNY"
            : "100 JPY = \(String(format: "%.2f", jpyToCny * 100)) CNY"
        let converted = parsedPrice * (currency == .USD ? usdToCny : jpyToCny)

        return HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text("汇率折算")
                    .font(.system(size: 13.5))
                    .foregroundStyle(Theme.text)
                Text(rateLabel)
                    .font(.system(size: 11, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Theme.textTertiary)
            }
            Spacer(minLength: 6)
            if parsedPrice > 0 {
                Text("≈ ¥\(String(format: "%.2f", converted))")
                    .font(.system(size: 13.5, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Theme.brand)
            }
            Button {
                rateDraft = currency == .JPY
                    ? String(format: "%.2f", jpyToCny * 100)
                    : String(format: "%.2f", usdToCny)
                editingRateCurrency = currency
            } label: {
                Text("改汇率")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.brand)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Theme.brandSoft))
            }
            .buttonStyle(.plain)
        }
        .frame(minHeight: 52)
        .padding(.horizontal, 2)
    }

    private func formRow<Trailing: View>(_ label: String, @ViewBuilder trailing: () -> Trailing) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 13.5))
                .foregroundStyle(Theme.text)
            Spacer(minLength: 8)
            trailing()
        }
        .frame(minHeight: 52)
        .padding(.horizontal, 2)
    }

    private var formDivider: some View {
        Rectangle()
            .fill(Theme.stroke)
            .frame(height: 0.5)
    }

    private func capsule(_ title: String, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11.5, weight: isOn ? .medium : .regular))
                .foregroundStyle(isOn ? Color.white : Theme.textSecondary)
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(Capsule().fill(isOn ? Theme.brand : Theme.surfaceRaised))
        }
        .buttonStyle(.plain)
    }

    // MARK: 提醒卡

    private var reminderCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("提前 \(remindDays) 天写入待办")
                        .font(.system(size: 13.5))
                        .foregroundStyle(Theme.text)
                    Text("自动生成 #订阅 续费确认任务")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.textTertiary)
                }
                Spacer()
                Toggle("", isOn: $remindEnabled)
                    .labelsHidden()
                    .tint(SubPalette.green)
            }

            if remindEnabled {
                HStack(spacing: 5) {
                    ForEach([1, 3, 7], id: \.self) { days in
                        capsule("\(days) 天", isOn: remindDays == days) {
                            remindDays = days
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }

    // MARK: 保存 / 删除

    private var saveButton: some View {
        Button(action: save) {
            Text("保存订阅")
                .font(.system(size: 14.5, weight: .semibold))
                .foregroundStyle(Color.white)
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .background(
                    RoundedRectangle(cornerRadius: AppRadius.item, style: .continuous)
                        .fill(Theme.brand)
                )
        }
        .buttonStyle(PressableStyle())
        .padding(.top, 2)
    }

    private func deleteButton(_ sub: Subscription) -> some View {
        Button(role: .destructive) {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            SubscriptionReminderService.cancelPendingNotifications(for: sub)
            context.delete(sub)
            try? context.save()
            dismiss()
        } label: {
            Text("删除此订阅")
                .font(.system(size: 13))
                .foregroundStyle(Color.red)
                .padding(.vertical, 8)
        }
        .buttonStyle(.plain)
    }

    private func save() {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            validation = "请填写订阅名称"
            return
        }
        let cleaned = priceText.replacingOccurrences(of: ",", with: ".")
        guard let value = Double(cleaned), value > 0 else {
            validation = "请填写有效价格"
            return
        }

        let calendar = Calendar.current
        let target = subscription ?? Subscription()
        let oldChargeDay = calendar.startOfDay(for: target.nextChargeDate)
        let oldRemindEnabled = target.remindEnabled
        let oldRemindDays = target.remindDaysBefore

        target.name = trimmedName
        target.price = value
        target.currencyRaw = currency.rawValue
        target.cycleRaw = cycle.rawValue
        target.nextChargeDate = nextCharge
        target.anchorDay = max(1, calendar.component(.day, from: nextCharge))
        target.paymentRaw = paymentTitle
        target.categoryRaw = category.rawValue
        target.brandRaw = brand.rawValue
        target.remindEnabled = remindEnabled
        target.remindDaysBefore = remindDays

        if subscription == nil {
            context.insert(target)
        } else {
            let changedSchedule = !calendar.isDate(nextCharge, inSameDayAs: oldChargeDay)
                || remindEnabled != oldRemindEnabled
                || remindDays != oldRemindDays
            if changedSchedule {
                target.lastRemindedCycleKey = ""
            }
        }

        try? context.save()
        let all = (try? context.fetch(FetchDescriptor<Subscription>())) ?? []
        SubscriptionReminderService.sync(all, in: context)
        dismiss()
    }
}

// MARK: - 可视化品牌图标选择网格

private struct BrandIconPickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var selection: BrandIcon

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 10), count: 4)

    var body: some View {
        NavigationStack {
            ScrollView(.vertical, showsIndicators: false) {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(BrandIcon.allCases) { icon in
                        let isSelected = selection == icon
                        Button {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            selection = icon
                            dismiss()
                        } label: {
                            VStack(spacing: 8) {
                                BrandLogo(brand: icon, size: 32)
                                    .frame(width: 52, height: 52)
                                    .background(
                                        RoundedRectangle(cornerRadius: AppRadius.item, style: .continuous)
                                            .fill(isSelected ? Theme.brandSoft : Theme.surface)
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: AppRadius.item, style: .continuous)
                                            .strokeBorder(isSelected ? Theme.brand : Theme.stroke, lineWidth: isSelected ? 1.8 : 0.6)
                                    )

                                Text(icon.displayName)
                                    .font(.system(size: 11, weight: isSelected ? .semibold : .regular))
                                    .foregroundStyle(isSelected ? Theme.brand : Theme.textSecondary)
                                    .lineLimit(1)
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(PressableStyle())
                    }
                }
                .padding(.horizontal, Theme.screenPadding)
                .padding(.vertical, 16)
            }
            .background(Theme.bg)
            .navigationTitle("选择图标")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                        .foregroundStyle(Theme.brand)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationBackground(Theme.bg)
    }
}

// MARK: - 付款方式选择与自定义管理

private struct PaymentMethodPickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var selection: String

    @State private var customInput = ""
    @State private var customList: [String] = PaymentMethodStore.customMethods

    private var builtInTitles: [String] {
        PaymentMethod.allCases.map(\.title)
    }

    var body: some View {
        NavigationStack {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: Theme.cardGap) {
                    // 新增自定义付款方式
                    HStack(spacing: 8) {
                        TextField("输入自定义付款方式（如：招商储蓄卡）", text: $customInput)
                            .font(.system(size: 13.5))
                            .foregroundStyle(Theme.text)
                            .padding(.horizontal, 12)
                            .frame(height: 42)
                            .background(
                                RoundedRectangle(cornerRadius: AppRadius.item, style: .continuous)
                                    .fill(Theme.surfaceRaised)
                            )

                        Button {
                            if let added = PaymentMethodStore.add(customInput) {
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                customList = PaymentMethodStore.customMethods
                                selection = added
                                customInput = ""
                                dismiss()
                            }
                        } label: {
                            Text("添加")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(Color.white)
                                .padding(.horizontal, 14)
                                .frame(height: 42)
                                .background(
                                    RoundedRectangle(cornerRadius: AppRadius.item, style: .continuous)
                                        .fill(Theme.brand)
                                )
                        }
                        .buttonStyle(.plain)
                        .disabled(customInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                    .cardSurface()

                    // 内置方式
                    VStack(spacing: 0) {
                        ForEach(Array(builtInTitles.enumerated()), id: \.element) { index, title in
                            paymentRow(title: title, isCustom: false)
                            if index < builtInTitles.count - 1 {
                                Rectangle().fill(Theme.stroke).frame(height: 0.5)
                            }
                        }
                    }
                    .cardSurface(padding: 12)

                    // 自定义已保存列表
                    if !customList.isEmpty {
                        VStack(alignment: .leading, spacing: 0) {
                            Text("自定义方式")
                                .cardLabel()
                                .padding(.horizontal, 4)
                                .padding(.bottom, 6)

                            ForEach(Array(customList.enumerated()), id: \.element) { index, title in
                                paymentRow(title: title, isCustom: true)
                                if index < customList.count - 1 {
                                    Rectangle().fill(Theme.stroke).frame(height: 0.5)
                                }
                            }
                        }
                        .cardSurface(padding: 12)
                    }
                }
                .padding(.horizontal, Theme.screenPadding)
                .padding(.vertical, 12)
            }
            .background(Theme.bg)
            .navigationTitle("付款方式")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                        .foregroundStyle(Theme.brand)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationBackground(Theme.bg)
    }

    private func paymentRow(title: String, isCustom: Bool) -> some View {
        let isSelected = selection == title
        return HStack(spacing: 10) {
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                selection = title
                dismiss()
            } label: {
                HStack {
                    Text(title)
                        .font(.system(size: 14, weight: isSelected ? .semibold : .regular))
                        .foregroundStyle(isSelected ? Theme.brand : Theme.text)
                    Spacer()
                    if isSelected {
                        ReiconIcon(icon: .check, size: 14)
                            .foregroundStyle(Theme.brand)
                    }
                }
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isCustom {
                Button {
                    PaymentMethodStore.removeCustom(title)
                    customList = PaymentMethodStore.customMethods
                    if selection == title {
                        selection = PaymentMethod.applePay.title
                    }
                } label: {
                    ReiconIcon(icon: .trash, size: 14)
                        .foregroundStyle(Theme.textTertiary)
                        .padding(6)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 4)
    }
}

// MARK: - 预设（保留供空状态快速添加卡片使用）

struct SubscriptionPreset: Identifiable {
    let id: String
    let label: String
    let name: String
    let price: Double
    let currency: SubscriptionCurrency
    let cycle: BillingCycle
    let category: SubscriptionCategory
    let brand: BrandIcon
    let payment: PaymentMethod

    static let all: [SubscriptionPreset] = [
        .init(id: "gemini", label: "Gemini", name: "Gemini Advanced", price: 19.99,
              currency: .USD, cycle: .monthly, category: .ai, brand: .gemini, payment: .visa),
        .init(id: "qqmusic", label: "QQ音乐", name: "QQ音乐绿钻", price: 15,
              currency: .CNY, cycle: .monthly, category: .media, brand: .qqMusic, payment: .wechat),
        .init(id: "netease", label: "网易云音乐", name: "网易云黑胶", price: 15,
              currency: .CNY, cycle: .monthly, category: .media, brand: .neteaseMusic, payment: .alipay),
        .init(id: "jdbaitiao", label: "京东白条", name: "京东白条还款", price: 500,
              currency: .CNY, cycle: .monthly, category: .other, brand: .jdBaitiao, payment: .bankCard),
        .init(id: "applemusic", label: "Apple Music", name: "Apple Music", price: 11,
              currency: .CNY, cycle: .monthly, category: .media, brand: .appleMusic, payment: .applePay),
        .init(id: "icloud", label: "iCloud", name: "iCloud+", price: 21,
              currency: .CNY, cycle: .monthly, category: .cloud, brand: .icloud, payment: .applePay),
        .init(id: "bilibili", label: "哔哩哔哩", name: "哔哩哔哩大会员", price: 25,
              currency: .CNY, cycle: .monthly, category: .media, brand: .bilibili, payment: .alipay),
        .init(id: "baidu", label: "百度网盘", name: "百度网盘SVIP", price: 25,
              currency: .CNY, cycle: .monthly, category: .cloud, brand: .baiduNetdisk, payment: .alipay),
        .init(id: "chatgpt", label: "ChatGPT", name: "ChatGPT Plus", price: 20,
              currency: .USD, cycle: .monthly, category: .ai, brand: .openai, payment: .visa),
        .init(id: "claude", label: "Claude", name: "Claude Pro", price: 20,
              currency: .USD, cycle: .monthly, category: .ai, brand: .claude, payment: .visa),
    ]
}
