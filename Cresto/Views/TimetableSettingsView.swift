import SwiftUI
import SwiftData

/// 课表管理：开学日期 + 节数。改完直接生效。
struct TimetableSettingsView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @Query private var settingsList: [TimetableSettings]

    @State private var termStart = Date()
    @State private var periodCount = 12
    @State private var loaded = false
    @State private var confirmReimport = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Theme.cardGap) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("学期").cardLabel()
                        DatePicker("开学第一周的周一", selection: $termStart, displayedComponents: .date)
                            .font(.system(size: 14))
                            .environment(\.locale, Locale(identifier: "zh_CN"))
                        Text("当前第 \(currentWeek) 周")
                            .font(.system(size: 11.5))
                            .foregroundStyle(Theme.textTertiary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .cardSurface()

                    VStack(alignment: .leading, spacing: 12) {
                        Text("节次").cardLabel()
                        Stepper(value: $periodCount, in: 8...16) {
                            HStack {
                                Text("每天节数").font(.system(size: 14)).foregroundStyle(Theme.text)
                                Spacer()
                                Text("\(periodCount)")
                                    .font(.system(size: 14))
                                    .monospacedDigit()
                                    .foregroundStyle(Theme.textSecondary)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .cardSurface()

                    reimportCard
                }
                .padding(.horizontal, Theme.screenPadding)
                .padding(.vertical, 12)
            }
            .background(Theme.bg)
            .navigationTitle("课表管理")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }.foregroundStyle(Theme.textSecondary)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }
                        .fontWeight(.semibold)
                        .foregroundStyle(Theme.text)
                }
            }
            .tint(Theme.text)
        }
        .presentationBackground(Theme.bg)
        .onAppear(perform: load)
    }

    private var currentWeek: Int {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: termStart)
        let days = calendar.dateComponents([.day], from: start, to: calendar.startOfDay(for: Date())).day ?? 0
        return max(1, days / 7 + 1)
    }

undefined
        guard !loaded, let settings = settingsList.first else { return }
        termStart = settings.termStart
        periodCount = settings.periodCount
        loaded = true
    }

    private func save() {
        let settings = settingsList.first ?? {
            let created = TimetableSettings()
            context.insert(created)
            return created
        }()
        settings.termStart = termStart
        settings.periodCount = periodCount
        try? context.save()
        AppLog.info("更新课表设置：开学 \(termStart.formatted(.dateTime.year().month().day()))，\(periodCount) 节")
        dismiss()
    }
}
