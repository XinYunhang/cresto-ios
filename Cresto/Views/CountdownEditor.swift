import SwiftUI
import SwiftData
import UIKit

/// 倒数日新增 / 编辑弹窗（支持任意日期与多色强调色，无预设默认文案）。
struct CountdownEditor: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    let item: CountdownItem?

    @State private var title: String
    @State private var targetDate: Date
    @State private var accent: CountdownAccent
    @State private var validation: String?

    init(item: CountdownItem?) {
        self.item = item
        if let item {
            _title = State(initialValue: item.title)
            _targetDate = State(initialValue: item.targetDate)
            _accent = State(initialValue: item.accent)
        } else {
            let tomorrow = Calendar.current.date(byAdding: .day, value: 7, to: Date()) ?? Date()
            _title = State(initialValue: "")
            _targetDate = State(initialValue: tomorrow)
            _accent = State(initialValue: .indigo)
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
                    }
                    .cardSurface()

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
                            context.delete(item)
                            try? context.save()
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
    }

    private func save() {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            validation = "请填写倒数日名称"
            return
        }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        if let item {
            item.title = trimmed
            item.targetDate = targetDate
            item.accentRaw = accent.rawValue
        } else {
            let created = CountdownItem(title: trimmed, targetDate: targetDate, accent: accent)
            context.insert(created)
        }
        try? context.save()
        dismiss()
    }
}
