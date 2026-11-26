import SwiftUI
import SwiftData
import UIKit

/// 新增 / 编辑订阅弹窗。
struct SubscriptionEditor: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    let subscription: Subscription?
    var initialPreset: SubscriptionPreset? = nil

    @State private var name: String
    @State private var priceText: String
    @State private var currency: SubscriptionCurrency
    @State private var cycle: BillingCycle
    @State private var nextCharge: Date
    @State private var payment: PaymentMethod
    @State private var category: SubscriptionCategory
    @State private var brand: BrandIcon
    @State private var remindEnabled: Bool
    @State private var remindDays: Int
    @State private var validation: String?

    init(subscription: Subscription?, initialPreset: SubscriptionPreset? = nil) {
        self.subscription = subscription
        self.initialPreset = initialPreset
        if let sub = subscription {
            _name = State(initialValue: sub.name)
            _priceText = State(initialValue: String(format: "%.2f", sub.price))
            _currency = State(initialValue: sub.currency)
            _cycle = State(initialValue: sub.cycle)
            _nextCharge = State(initialValue: sub.nextChargeDate)
            _payment = State(initialValue: sub.payment)
            _category = State(initialValue: sub.category)
            _brand = State(initialValue: sub.brand)
            _remindEnabled = State(initialValue: sub.remindEnabled)
            _remindDays = State(initialValue: sub.remindDaysBefore)
        } else if let preset = initialPreset {
            let calendar = Calendar.current
            _name = State(initialValue: preset.name)
            _priceText = State(initialValue: String(format: "%.2f", preset.price))
            _currency = State(initialValue: preset.currency)
            _cycle = State(initialValue: preset.cycle)
            _nextCharge = State(initialValue: calendar.date(
                byAdding: .month, value: 1, to: calendar.startOfDay(for: Date())
            ) ?? Date())
            _payment = State(initialValue: preset.payment)
            _category = State(initialValue: preset.category)
            _brand = State(initialValue: preset.brand)
            _remindEnabled = State(initialValue: true)
            _remindDays = State(initialValue: 3)
        } else {
            let calendar = Calendar.current
            _name = State(initialValue: "")
            _priceText = State(initialValue: "")
            _currency = State(initialValue: .USD)
            _cycle = State(initialValue: .monthly)
            _nextCharge = State(initialValue: calendar.date(
                byAdding: .month, value: 1, to: calendar.startOfDay(for: Date())
            ) ?? Date())
            _payment = State(initialValue: .visa)
            _category = State(initialValue: .other)
            _brand = State(initialValue: .generic)
            _remindEnabled = State(initialValue: true)
            _remindDays = State(initialValue: 3)
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: Theme.cardGap) {
                    presetBar
                    formCard
                    reminderCard
                    if let validation {
                        Text(validation)
                            .font(.system(size: 11.5))
                            .foregroundStyle(Color(hex: 0xF43F5E))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    saveButton
                }
                .padding(.horizontal, Theme.screenPadding)
                .padding(.vertical, 12)
            }
            .background(Theme.bg)
            .navigationTitle(subscription == nil ? "添加订阅" : "编辑订阅")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        dismiss()
                    } label: {
                        ReiconIcon(icon: .xmark, size: 11)
                            .foregroundStyle(Theme.text)
                            .frame(width: 28, height: 28)
                            .background(Circle().fill(Theme.surfaceRaised))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("关闭")
                }
            }
            .tint(Theme.ink)
        }
        .presentationBackground(Theme.bg)
    }

    // MARK: 预设胶囊

    private var presetBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 7) {
                ForEach(SubscriptionPreset.all) { preset in
                    Button {
                        apply(preset)
                    } label: {
                        HStack(spacing: 5) {
                            BrandLogo(brand: preset.brand, size: 14)
                            Text(preset.label)
                                .font(.system(size: 12))
                                .foregroundStyle(Theme.textSecondary)
                        }
                        .padding(.horizontal, 11)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(Theme.surfaceRaised))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("使用 \(preset.label) 预设")
                }
            }
            .padding(.vertical, 1)
        }
    }

    private func apply(_ preset: SubscriptionPreset) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        withAnimation(.snappy(duration: 0.2)) {
            name = preset.name
            priceText = String(format: "%.2f", preset.price)
            currency = preset.currency
            cycle = preset.cycle
            category = preset.category
            brand = preset.brand
            payment = preset.payment
        }
        validation = nil
    }

    // MARK: 表单

    private var formCard: some View {
        VStack(spacing: 0) {
            // 名称
            formRow("名称") {
                TextField("订阅名称", text: $name)
                    .font(.system(size: 13.5))
                    .foregroundStyle(Theme.text)
                    .multilineTextAlignment(.trailing)
                    .autocorrectionDisabled()
            }

            formDivider

            // 价格
            formRow("价格") {
                HStack(spacing: 8) {
                    TextField("0.00", text: $priceText)
                        .font(.system(size: 13.5))
                        .foregroundStyle(Theme.text)
                        .multilineTextAlignment(.trailing)
                        .keyboardType(.decimalPad)
                        .frame(maxWidth: 110)

                    HStack(spacing: 4) {
                        ForEach(SubscriptionCurrency.allCases) { item in
                            capsule(item.title, isOn: currency == item) {
                                currency = item
                            }
                        }
                    }
                }
            }

            formDivider

            // 周期
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

            // 下次扣费
            formRow("下次扣费") {
                DatePicker("", selection: $nextCharge, displayedComponents: .date)
                    .labelsHidden()
                    .datePickerStyle(.compact)
                    .environment(\.locale, Locale(identifier: "zh_CN"))
            }

            formDivider

            // 付款方式 + 分类
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("付款方式")
                        .font(.system(size: 13.5))
                        .foregroundStyle(Theme.text)
                    Spacer()
                    Menu {
                        ForEach(PaymentMethod.allCases) { item in
                            Button {
                                payment = item
                            } label: {
                                Text(payment == item ? "✓ \(item.title)" : item.title)
                            }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text(payment.title)
                                .font(.system(size: 13.5))
                                .foregroundStyle(Theme.textSecondary)
                            ReiconIcon(icon: .chevronDown, size: 9)
                                .foregroundStyle(Theme.textTertiary)
                        }
                    }
                }

                HStack {
                    Text("分类")
                        .font(.system(size: 13.5))
                        .foregroundStyle(Theme.text)
                    Spacer()
                    HStack(spacing: 4) {
                        ForEach(SubscriptionCategory.allCases) { item in
                            capsule(item.title, isOn: category == item) {
                                category = item
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 2)
            .padding(.vertical, 13)
        }
        .cardSurface()
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
                .font(.system(size: 11.5))
                .foregroundStyle(isOn ? Theme.bg : Theme.textSecondary)
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(Capsule().fill(isOn ? Theme.text : Theme.surfaceRaised))
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

    // MARK: 保存

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
        target.paymentRaw = payment.rawValue
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

// MARK: - 预设

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
        .init(id: "chatgpt", label: "ChatGPT", name: "ChatGPT Plus", price: 20,
              currency: .USD, cycle: .monthly, category: .ai, brand: .openai, payment: .visa),
        .init(id: "gemini", label: "Gemini", name: "Gemini Advanced", price: 19.99,
              currency: .USD, cycle: .monthly, category: .ai, brand: .gemini, payment: .visa),
        .init(id: "applemusic", label: "Apple Music", name: "Apple Music", price: 11,
              currency: .CNY, cycle: .monthly, category: .media, brand: .appleMusic, payment: .appleID),
        .init(id: "icloud", label: "iCloud+", name: "iCloud+", price: 21,
              currency: .CNY, cycle: .monthly, category: .cloud, brand: .apple, payment: .appleID),
        .init(id: "claude", label: "Claude", name: "Claude Pro", price: 20,
              currency: .USD, cycle: .monthly, category: .ai, brand: .claude, payment: .visa),
        .init(id: "deepseek", label: "DeepSeek", name: "DeepSeek", price: 20,
              currency: .CNY, cycle: .monthly, category: .ai, brand: .deepseek, payment: .alipay),
    ]
}