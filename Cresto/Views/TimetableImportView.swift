import SwiftUI
import SwiftData
import PhotosUI

/// 导入课表：选一张课表截图 → Vision 认字落格 → 逐条核对 → 入库。
struct TimetableImportView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var pickerItem: PhotosPickerItem?
    @State private var courses: [ImportedCourse] = []
    @State private var isWorking = false
    @State private var errorText: String?

    private var selectedCount: Int { courses.filter(\.isIncluded).count }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Theme.cardGap) {
                    introCard

                    PhotosPicker(selection: $pickerItem, matching: .images, photoLibrary: .shared()) {
                        HStack(spacing: 8) {
                            Image(systemName: "photo.on.rectangle.angled").font(.system(size: 14))
                            Text(courses.isEmpty ? "选择课表截图" : "换一张图")
                            Spacer()
                        }
                        .font(.system(size: 13.5))
                        .foregroundStyle(Theme.text)
                        .padding(.horizontal, 14)
                        .frame(height: 46)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(Color.white.opacity(0.05))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .strokeBorder(Theme.stroke, lineWidth: 1)
                        )
                    }

                    if isWorking { loadingCard }
                    if let errorText { errorCard(errorText) }
                    if !courses.isEmpty { reviewCard }
                }
                .padding(.horizontal, Theme.screenPadding)
                .padding(.vertical, 12)
            }
            .background(Theme.bg)
            .navigationTitle("导入课表")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }.foregroundStyle(Theme.textSecondary)
                }
                if !courses.isEmpty {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("导入 \(selectedCount)") { save() }
                            .fontWeight(.semibold)
                            .disabled(selectedCount == 0)
                    }
                }
            }
            .tint(Theme.ink)
        }
        .presentationBackground(Theme.bg)
        .onChange(of: pickerItem) { _, item in
            guard let item else { return }
            recognize(item)
        }
    }

    private var introCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("怎么识别").cardLabel()
            Text("认字之后，用表头的「周一…周日」定位列、左侧的节次定位行，再按坐标把课名放进格子里。识别不一定准，下面每一条都能改。")
                .font(.system(size: 12.5))
                .lineSpacing(4)
                .foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }

    private var loadingCard: some View {
        HStack(spacing: 10) {
            ProgressView().tint(Theme.text)
            Text("正在识别…").font(.system(size: 13)).foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }

    private func errorCard(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12.5))
            .foregroundStyle(Theme.textSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardSurface()
    }

    private var reviewCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("识别结果").cardLabel()
                Spacer()
                Text("\(selectedCount)/\(courses.count)")
                    .font(.system(size: 11.5))
                    .monospacedDigit()
                    .foregroundStyle(Theme.textTertiary)
            }
            .padding(.bottom, 10)

            ForEach($courses) { $course in
                row($course)
                if course.id != courses.last?.id {
                    Rectangle().fill(Color.white.opacity(0.05)).frame(height: 1)
                }
            }
        }
        .cardSurface()
    }

    private func row(_ course: Binding<ImportedCourse>) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Button {
                course.wrappedValue.isIncluded.toggle()
            } label: {
                Image(systemName: course.wrappedValue.isIncluded ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 17))
                    .foregroundStyle(course.wrappedValue.isIncluded ? Theme.ink : Theme.textTertiary)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 8) {
                TextField("课名", text: course.title)
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.text)

                HStack(spacing: 6) {
                    Menu {
                        ForEach(1...7, id: \.self) { day in
                            Button("周\(dayName(day))") { course.wrappedValue.weekday = day }
                        }
                    } label: {
                        pill("周\(dayName(course.wrappedValue.weekday))")
                    }

                    Menu {
                        ForEach(periodOptions, id: \.self) { range in
                            Button("第 \(range.lowerBound)-\(range.upperBound) 节") {
                                course.wrappedValue.startPeriod = range.lowerBound
                                course.wrappedValue.endPeriod = range.upperBound
                            }
                        }
                    } label: {
                        pill("第 \(course.wrappedValue.startPeriod)-\(course.wrappedValue.endPeriod) 节")
                    }

                    Spacer(minLength: 0)

                    Button {
                        let id = course.wrappedValue.id
                        courses.removeAll { $0.id == id }
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.textTertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.vertical, 9)
    }

    private func pill(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11))
            .foregroundStyle(Theme.textSecondary)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(Capsule().fill(Color.white.opacity(0.05)))
            .overlay(Capsule().strokeBorder(Theme.stroke, lineWidth: 1))
    }

    private var periodOptions: [ClosedRange<Int>] {
        [1...2, 3...4, 5...6, 7...8, 9...10, 11...12, 1...1, 2...2, 3...3, 4...4]
    }

    private func dayName(_ day: Int) -> String {
        ["一", "二", "三", "四", "五", "六", "日"][max(0, min(6, day - 1))]
    }

    // MARK: 识别

    private func recognize(_ item: PhotosPickerItem) {
        Task {
            isWorking = true
            errorText = nil
            courses = []
            do {
                guard let data = try await item.loadTransferable(type: Data.self) else {
                    throw OCRError.invalidImage
                }
                courses = try await TimetableOCR.recognize(imageData: data)
            } catch {
                errorText = error.localizedDescription
            }
            isWorking = false
        }
    }

    // MARK: 入库

    private func save() {
        let picked = courses.filter(\.isIncluded)
        guard !picked.isEmpty else { return }

        // 同名课程合成一门，多个时间段挂上去
        let groups = Dictionary(grouping: picked, by: { $0.title })

        let existing = (try? context.fetch(FetchDescriptor<Course>())) ?? []
        var byName: [String: Course] = [:]
        for course in existing {
            if byName[course.name] == nil { byName[course.name] = course }
        }

        for (title, list) in groups {
            let target: Course
            if let found = byName[title] {
                target = found
            } else {
                target = Course(name: title, shade: shade(for: title))
                context.insert(target)
                byName[title] = target
            }

            for item in list {
                let slot = CourseSlot(
                    weekday: item.weekday,
                    startPeriod: item.startPeriod,
                    endPeriod: item.endPeriod,
                    weekStart: 1,
                    weekEnd: 20
                )
                slot.course = target
                target.slots.append(slot)
                context.insert(slot)
            }

            if target.location.isEmpty {
                target.location = list.first?.location ?? ""
            }
        }

        try? context.save()
        dismiss()
    }

    private func shade(for title: String) -> Int {
        title.unicodeScalars.reduce(0) { $0 + Int($1.value) } % 5
    }
}
