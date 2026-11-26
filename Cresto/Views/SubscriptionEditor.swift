import SwiftUI
import SwiftData
import UIKit

/// 新增 / 编辑订阅弹窗（币种切换与 USD / JPY 汇率折算仅在此详情/添加页展示）。
struct SubscriptionEditor: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @AppStorage("usdToCny") private var usdToCny = 7.25
    @AppStorage("jpyToCny") private var jpyToCny = 0.048

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
            _payment = State(initialValue: sub.payment)
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
            _payment = State(initialValue: preset.payment)
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
            _payment = State(initialValue: .alipay)
            _category = State(initialValue: .other)
            _brand = State(initialValue: .generic)
            _remindEnabled = State(initialValue: true)
            _remindDays = State(initialValue: 3)
        }
    }

    private var parsedPrice: Double {
        Double(priceText.replacingOccurrences(of: ",", with: ".")) ?? 0
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
                    if let subscription {
                        deleteButton(subscription)
                    }
                }
                .padding(.horizontal, Theme.screenPadding)
                .padding(.vertical, 12)
            }
            .background(Theme.bg)
            .navigationTitle(subscription == nil ? "添加订阅" : "订阅详情")
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
            .tint(Theme.brand)
        }
        .presentationBackground(Theme.bg)
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
            Button("取消", role: .cancel) {
                editingRateCurrency = nil
            }
        } message: {
            Text(rateAlertMessage)
        }
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

    // MARK: 预设胶囊

    private var presetBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 7) {
                ForEach(SubscriptionPreset.all) { preset in
                    Button {
                        apply(preset)
                    } label: {
                        HStack(spacing: 6) {
                            BrandLogo(brand: preset.brand, size: 15)
                            Text(preset.label)
                                .font(.system(size: 12))
                                .foregroundStyle(Theme.textSecondary)
                        }
                        .padding(.horizontal, 11)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(Theme.surface))
                        .overlay(Capsule().strokeBorder(Theme.stroke, lineWidth: 0.5))
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
            priceText = preset.currency == .JPY ? String(format: "%.0f", preset.price) : String(format: "%.2f", preset.price)
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
            // 名称 + 可点击切换图标预览
            formRow("名称") {
                HStack(spacing: 8) {
                    Menu {
                        ForEach(BrandIcon.allCases) { icon in
                            Button {
                                brand = icon
                            } label: {
                                Label { Text(iconLabel(icon)) } icon: { BrandLogo(brand: icon, size: 16) }
                            }
                        }
                    } label: {
                        BrandLogo(brand: brand, size: 22)
                    }

                    TextField("订阅名称", text: $name)
                        .font(.system(size: 13.5))
                        .foregroundStyle(Theme.text)
                        .multilineTextAlignment(.trailing)
                        .autocorrectionDisabled()
                }
            }

            formDivider

            // 价格与币种（CNY / USD / JPY）
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

            // 汇率折算行（仅在订阅详情 / 添加页且币种为 USD / JPY 时显示）
            if currency == .USD || currency == .JPY {
                formDivider
                exchangeRateRow
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

            // 付款方式
            formRow("付款方式") {
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

    private func iconLabel(_ icon: BrandIcon) -> String {
        switch icon {
        case .gemini: return "Gemini"
        case .qqMusic: return "QQ音乐"
        case .neteaseMusic: return "网易云音乐"
        case .jdBaitiao: return "京东白条"
        case .appleMusic: return "Apple Music"
        case .icloud: return "iCloud"
        case .bilibili: return "哔哩哔哩"
        case .baiduNetdisk: return "百度网盘"
        case .openai: return "ChatGPT"
        case .claude: return "Claude"
        case .deepseek: return "DeepSeek"
        case .google: return "Google"
        case .apple: return "Apple"
        case .generic: return "通用卡片"
        }
    }
}

// MARK: - 预设（含全部指定品牌图标）

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
              currency: .CNY, cycle: .monthly, category: .other, brand: .jdBaitiao, payment: .other),
        .init(id: "applemusic", label: "Apple Music", name: "Apple Music", price: 11,
              currency: .CNY, cycle: .monthly, category: .media, brand: .appleMusic, payment: .appleID),
        .init(id: "icloud", label: "iCloud", name: "iCloud+", price: 21,
              currency: .CNY, cycle: .monthly, category: .cloud, brand: .icloud, payment: .appleID),
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
