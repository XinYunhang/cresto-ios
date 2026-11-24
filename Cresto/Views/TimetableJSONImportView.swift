import SwiftUI
import SwiftData
import UIKit
import UniformTypeIdentifiers

/// 喜鹊课表导入：从剪贴板或 timetable.json 读取 → 预览合并结果 → 替换全部课程。
/// 转换规则见 Obsidian「12-喜鹊课表数据接入」。
struct TimetableJSONImportView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @Query private var settingsList: [TimetableSettings]

    @State private var plan: TimetableImportPlan?
    @State private var errorText: String?
    @State private var isFilePickerPresented = false
    @State private var isConfirmPresented = false

    private var settings: TimetableSettings? { settingsList.first }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Theme.cardGap) {
                    introCard
                    sourceCard
                    if let errorText { messageCard(errorText) }
                    if let plan { planCard(plan) }
                }
                .padding(.horizontal, Theme.screenPadding)
                .padding(.vertical, 12)
                .padding(.bottom, 30)
            }
            .background(Theme.bg)
            .navigationTitle("喜鹊课表导入")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                        .foregroundStyle(Theme.textSecondary)
                }
                if plan != nil {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("导入") { isConfirmPresented = true }
                            .fontWeight(.semibold)
                            .foregroundStyle(Theme.text)
                    }
                }
            }
            .tint(Theme.text)
        }
        .presentationBackground(Theme.bg)
        .fileImporter(
            isPresented: $isFilePickerPresented,
            allowedContentTypes: [.json]
        ) { result in
            handleFileResult(result)
        }
        .confirmationDialog(
            "用喜鹊课表替换全部课程？",
            isPresented: $isConfirmPresented,
            titleVisibility: .visible
        ) {
            Button("替换全部课程", role: .destructive) { performImport() }
            Button("取消", role: .cancel) {}
        } message: {
            Text("现有课程会被删除（导入前会自动存一份本地快照）。开学日期与作息保留当前设置。")
        }
    }

    // MARK: 说明

    private var introCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("怎么导入").cardLabel()

            step(1, "打开喜鹊课表 → 课表设置 → 复制当前课表 JSON")
            step(2, "回到这里点「从剪贴板粘贴」，或选择导出的 timetable.json")
            step(3, "核对课程、周次与教室，再点右上角「导入」")

            Text("只替换课程；开学日期与每节作息沿用 Cresto 当前的设置，不会被源文件覆盖。")
                .font(.system(size: 11.5))
                .lineSpacing(3)
                .foregroundStyle(Theme.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }

    private func step(_ index: Int, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 9) {
            Text("\(index)")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Theme.textSecondary)
                .frame(width: 17, height: 17)
                .background(Circle().fill(Theme.surfaceRaised))
            Text(text)
                .font(.system(size: 12.5))
                .lineSpacing(2)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: 数据来源

    private var sourceCard: some View {
        VStack(spacing: 8) {
            Button {
                loadFromClipboard()
            } label: {
                HStack(spacing: 8) {
                    ReiconIcon(icon: .checklist, size: 16)
                    Text("从剪贴板粘贴 JSON")
                    Spacer()
                }
                .font(.system(size: 13.5))
                .foregroundStyle(Theme.bg)
                .padding(.horizontal, 14)
                .frame(height: 46)
                .background(
                    RoundedRectangle(cornerRadius: AppRadius.item, style: .continuous)
                        .fill(Theme.text)
                )
            }
            .buttonStyle(.plain)

            Button {
                isFilePickerPresented = true
            } label: {
                HStack(spacing: 8) {
                    ReiconIcon(icon: .download, size: 16)
                    Text("选择 timetable.json 文件")
                    Spacer()
                }
                .font(.system(size: 13.5))
                .foregroundStyle(Theme.text)
                .padding(.horizontal, 14)
                .frame(height: 46)
                .background(
                    RoundedRectangle(cornerRadius: AppRadius.item, style: .continuous)
                        .fill(Theme.surface)
                )
            }
            .buttonStyle(.plain)
        }
    }

    private func messageCard(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12.5))
            .lineSpacing(3)
            .foregroundStyle(Theme.textSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            .cardSurface()
    }

    // MARK: 预览

    private func planCard(_ plan: TimetableImportPlan) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("导入预览").cardLabel()
                Spacer()
                Text("\(plan.courses.count) 门 · \(plan.slotCount) 个时段")
                    .font(.system(size: 11.5))
                    .monospacedDigit()
                    .foregroundStyle(Theme.textTertiary)
            }

            VStack(spacing: 7) {
                metaRow("学期", plan.semesterName.isEmpty ? "未命名" : plan.semesterName)
                if let settings {
                    metaRow("Cresto 学期", "\(dateText(settings.termStart)) 起 · \(settings.periodCount) 节")
                } else {
                    metaRow("Cresto 学期", "尚未设置，导入时按源文件兜底")
                }
                if let sourceStart = plan.sourceStartDate {
                    metaRow("源文件开学", sourceStart)
                }
                metaRow("总周数", "1-\(plan.totalWeeks) 周")
            }

            if let sourceStart = plan.sourceStartDate,
               let settings,
               dateText(settings.termStart) != sourceStart {
                Text("源文件开学日期与 Cresto 当前值不同。按笔记约定保留 \(dateText(settings.termStart))（学校真实开学周），不使用 \(sourceStart)。")
                    .font(.system(size: 11.5))
                    .lineSpacing(3)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !plan.warnings.isEmpty {
                VStack(alignment: .leading, spacing: 5) {
                    ForEach(plan.warnings, id: \.self) { warning in
                        Text("· \(warning)")
                            .font(.system(size: 11.5))
                            .lineSpacing(3)
                            .foregroundStyle(Theme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            Rectangle()
                .fill(Theme.stroke)
                .frame(height: 1)

            VStack(alignment: .leading, spacing: 0) {
                ForEach(plan.courses) { course in
                    courseRow(course)
                    if course.id != plan.courses.last?.id {
                        Rectangle()
                            .fill(Theme.stroke)
                            .frame(height: 1)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }

    private func metaRow(_ title: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(title)
                .font(.system(size: 12))
                .foregroundStyle(Theme.textTertiary)
            Spacer(minLength: 8)
            Text(value)
                .font(.system(size: 12))
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.trailing)
        }
    }

    private func courseRow(_ course: TimetableImportPlan.CoursePlan) -> some View {
        let tone = Theme.courseTone(course.shade)
        return HStack(alignment: .top, spacing: 10) {
            Circle()
                .fill(tone.fg)
                .frame(width: 9, height: 9)
                .padding(.top, 4)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(course.name)
                        .font(.system(size: 13.5, weight: .semibold))
                        .foregroundStyle(Theme.text)
                    if !course.teacher.isEmpty {
                        Text(course.teacher)
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.textTertiary)
                    }
                }
                ForEach(course.slots) { slot in
                    Text(slot.summary)
                        .font(.system(size: 11))
                        .lineSpacing(2)
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 9)
    }

    // MARK: 读取

    private func loadFromClipboard() {
        guard let text = UIPasteboard.general.string?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !text.isEmpty else {
            plan = nil
            errorText = "剪贴板里没有文本。先在喜鹊课表里复制当前课表 JSON。"
            return
        }
        parse(Data(text.utf8))
    }

    private func handleFileResult(_ result: Result<URL, Error>) {
        switch result {
        case .success(let url):
            let scoped = url.startAccessingSecurityScopedResource()
            defer {
                if scoped { url.stopAccessingSecurityScopedResource() }
            }
            do {
                parse(try Data(contentsOf: url))
            } catch {
                plan = nil
                errorText = "读取文件失败：\(error.localizedDescription)"
                AppLog.error("喜鹊课表文件读取失败：\(error.localizedDescription)")
            }
        case .failure(let error):
            plan = nil
            errorText = "选择文件失败：\(error.localizedDescription)"
        }
    }

    private func parse(_ data: Data) {
        do {
            let parsed = try TimetableJSONImporter.plan(from: data)
            plan = parsed
            errorText = nil
            AppLog.info("喜鹊课表解析：\(parsed.courses.count) 门 / \(parsed.slotCount) 个时段")
        } catch {
            plan = nil
            errorText = error.localizedDescription
            AppLog.error("喜鹊课表解析失败：\(error.localizedDescription)")
        }
    }

    // MARK: 入库

    private func performImport() {
        guard let plan else { return }
        do {
            let result = try XiqueerCourseImporter.apply(plan, in: context)
            AppLog.info("喜鹊课表导入完成：\(result.courseCount) 门 / \(result.slotCount) 个时段")
            dismiss()
        } catch {
            errorText = "导入失败：\(error.localizedDescription)"
            AppLog.error("喜鹊课表导入失败：\(error.localizedDescription)")
        }
    }

    private func dateText(_ date: Date) -> String {
        TimetableJSONImporter.string(from: date)
    }
}