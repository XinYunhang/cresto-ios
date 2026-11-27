import SwiftUI
import SwiftData
import UIKit

/// 倒数日新增 / 编辑弹窗（支持任意日期、指定主页展示与预留分享/保存图片按键）。
struct CountdownEditor: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @Query private var allCountdowns: [CountdownItem]

    let item: CountdownItem?

    @State private var title: String
    @State private var targetDate: Date
    @State private var accent: CountdownAccent
    @State private var isPinnedToHome: Bool
    @State private var validation: String?
    @State private var isSharePlaceholderPresented = false

    init(item: CountdownItem?) {
        self.item = item
        if let item {
            _title = State(initialValue: item.title)
            _targetDate = State(initialValue: item.targetDate)
            _accent = State(initialValue: item.accent)
            _isPinnedToHome = State(initialValue: item.isPinnedToHome)
        } else {
            let tomorrow = Calendar.current.date(byAdding: .day, value: 7, to: Date()) ?? Date()
            _title = State(initialValue: "")
            _targetDate = State(initialValue: tomorrow)
            _accent = State(initialValue: .indigo)
            _isPinnedToHome = State(initialValue: false)
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: Theme.cardGap) {
                    VStack(spacing: 0) {
                        HStack {
                            Text("名称")
                                .font(.system(size: 13.5))
                                .foregroundStyle(Theme.text)
                            Spacer(minLength: 10)
                            TextField("如：考研、生日、旅行", text: $title)
                                .font(.system(size: 13.5))
                                .foregroundStyle(Theme.text)
                                .multilineTextAlignment(.trailing)
                        }
                        .frame(minHeight: 52)

                        Rectangle().fill(Theme.stroke).frame(height: 0.5)

                        HStack {
                            Text("目标日期")
                                .font(.system(size: 13.5))
                                .foregroundStyle(Theme.text)
                            Spacer()
                            DatePicker("", selection: $targetDate, displayedComponents: .date)
                                .labelsHidden()
                                .datePickerStyle(.compact)
                                .environment(\.locale, Locale(identifier: "zh_CN"))
                        }
                        .frame(minHeight: 52)

                        Rectangle().fill(Theme.stroke).frame(height: 0.5)

                        HStack {
                            Text("强调色")
                                .font(.system(size: 13.5))
                                .foregroundStyle(Theme.text)
                            Spacer()
                            HStack(spacing: 10) {
                                ForEach(CountdownAccent.allCases) { option in
                                    Button {
                                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                        accent = option
                                    } label: {
                                        Circle()
                                            .fill(option.color)
                                            .frame(width: 22, height: 22)
                                            .overlay {
                                                if accent == option {
                                                    Circle()
                                                        .strokeBorder(Theme.bg, lineWidth: 2)
                                                        .padding(3)
                                                }
                                            }
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityLabel(option.title)
                                }
                            }
                        }
                        .frame(minHeight: 52)

                        Rectangle().fill(Theme.stroke).frame(height: 0.5)

                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("在主页展示")
                                    .font(.system(size: 13.5))
                                    .foregroundStyle(Theme.text)
                                Text("置顶到首页右上角倒数日卡片")
                                    .font(.system(size: 11))
                                    .foregroundStyle(Theme.textTertiary)
                            }
                            Spacer()
                            Toggle("", isOn: $isPinnedToHome)
                                .labelsHidden()
                                .tint(accent.color)
                        }
                        .frame(minHeight: 56)
                    }
                    .cardSurface()

                    // 预留：倒数日分享 / 保存图片卡片入口
                    Button {
                        isSharePlaceholderPresented = true
                    } label: {
                        HStack(spacing: 8) {
                            ReiconIcon(icon: .share, size: 15)
                                .foregroundStyle(accent.color)
                            Text("生成分享卡片并保存图片")
                                .font(.system(size: 13.5, weight: .medium))
                                .foregroundStyle(Theme.text)
                            Spacer()
                            Text("预留")
                                .font(.system(size: 10.5))
                                .foregroundStyle(Theme.textTertiary)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Capsule().fill(Theme.surfaceRaised))
                        }
                        .padding(.horizontal, 14)
                        .frame(height: 48)
                        .cardElevation(radius: AppRadius.item)
                    }
                    .buttonStyle(PressableStyle())

                    if let validation {
                        Text(validation)
                            .font(.system(size: 11.5))
                            .foregroundStyle(Color(hex: 0xF43F5E))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    Button(action: save) {
                        Text("保存倒数日")
                            .font(.system(size: 14.5, weight: .semibold))
                            .foregroundStyle(Color.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 48)
                            .background(
                                RoundedRectangle(cornerRadius: AppRadius.item, style: .continuous)
                                    .fill(accent.color)
                            )
                    }
                    .buttonStyle(PressableStyle())

                    if let item {
                        Button(role: .destructive) {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            let deletedTitle = item.title
                            context.delete(item)
                            Persistence.save(context, source: "删除倒数日")
                            AppLog.info("删除倒数日：\(deletedTitle)")
                            dismiss()
                        } label: {
                            Text("删除倒数日")
                                .font(.system(size: 13))
                                .foregroundStyle(Color.red)
                                .padding(.vertical, 10)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, Theme.screenPadding)
                .padding(.vertical, 12)
            }
            .background(Theme.bg)
            .navigationTitle(item == nil ? "添加倒数日" : "编辑倒数日")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        isSharePlaceholderPresented = true
                    } label: {
                        ReiconIcon(icon: .share, size: 15)
                            .foregroundStyle(Theme.text)
                    }
                    .accessibilityLabel("分享或保存图片")
                }
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
        }
        .presentationBackground(Theme.bg)
        .alert("倒数日分享卡片", isPresented: $isSharePlaceholderPresented) {
            Button("好的", role: .cancel) {}
        } message: {
            Text("分享与保存高清纪念图片界面已预留入口，将在后续版本上线。")
        }
    }

    private func save() {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            validation = "请填写倒数日名称"
            return
        }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()

        if isPinnedToHome {
            for existing in allCountdowns where existing.id != item?.id {
                existing.isPinnedToHome = false
            }
        }

        if let item {
            item.title = trimmed
            item.targetDate = targetDate
            item.accentRaw = accent.rawValue
            item.isPinnedToHome = isPinnedToHome
        } else {
            let created = CountdownItem(
                title: trimmed,
                targetDate: targetDate,
                accent: accent,
                isPinnedToHome: isPinnedToHome
            )
            context.insert(created)
        }
        Persistence.save(context, source: "保存倒数日")
        AppLog.info((item == nil ? "新建倒数日：" : "编辑倒数日：") + trimmed)
        dismiss()
    }
}
