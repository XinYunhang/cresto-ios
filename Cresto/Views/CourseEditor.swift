import SwiftUI
import SwiftData
import UIKit

// MARK: - 课程详情页（点击课程先看详情：色块主信息 + 排课信息 + 上课周次 + 编辑/本周停课/删除）

struct CourseDetailSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    let course: Course
    let slot: CourseSlot
    let displayWeek: Int

    @State private var isEditing = false

    private var tone: CourseTone { Theme.courseTone(course.shade) }
    private var resolvedLocation: String {
        let loc = slot.location.isEmpty ? course.location : slot.location
        return loc.isEmpty ? "未填写" : loc
    }

    var body: some View {
        NavigationStack {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: Theme.cardGap) {
                    heroCard
                    scheduleInfoCard
                    weeksGridCard
                    actionButtons
                }
                .padding(.horizontal, Theme.screenPadding)
                .padding(.vertical, 12)
            }
            .background(Theme.bg)
            .navigationTitle("课程详情")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                        .fontWeight(.medium)
                        .foregroundStyle(Theme.text)
                }
            }
        }
        .presentationBackground(Theme.bg)
        .sheet(isPresented: $isEditing) {
            CourseEditor(course: course, slot: slot)
        }
    }

    // MARK: 顶部主信息色块卡

    private var heroCard: some View {
        let teacherLocation = [course.teacher, resolvedLocation == "未填写" ? "" : resolvedLocation]
            .filter { !$0.isEmpty }
            .joined(separator: " · ")

        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 8) {
                Text(course.name)
                    .font(.system(size: 21, weight: .bold))
                    .foregroundStyle(tone.fg)
                    .lineLimit(2)
                Spacer()
                Circle()
                    .fill(tone.fg.opacity(0.45))
                    .frame(width: 9, height: 9)
                    .padding(.top, 6)
            }

            if !teacherLocation.isEmpty {
                Text(teacherLocation)
                    .font(.system(size: 13))
                    .foregroundStyle(tone.fg.opacity(0.78))
            }

            HStack(spacing: 7) {
                heroPill("周\(TimetableMath.weekdayName(slot.weekday)) \(slot.startPeriod)-\(slot.endPeriod) 节")
                heroPill(slot.weekSummaryText())
            }
            .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: AppRadius.card, style: .continuous)
                .fill(tone.bg)
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppRadius.card, style: .continuous)
                .strokeBorder(tone.fg.opacity(0.14), lineWidth: 0.6)
        )
    }

    private func heroPill(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11.5, weight: .medium, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(tone.fg)
            .padding(.horizontal, 10)
            .padding(.vertical, 4.5)
            .background(Capsule().fill(tone.fg.opacity(0.11)))
    }

    // MARK: 排课信息卡（无作息时间，仅保留星期/节次/教师/教室/周次）

    private var scheduleInfoCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("排课信息")
                .cardLabel()
                .padding(.bottom, 8)

            infoRow(icon: .calendar, label: "星期", value: "周\(TimetableMath.weekdayName(slot.weekday))")
            rowDivider
            infoRow(icon: .clock, label: "节次", value: "\(slot.startPeriod)-\(slot.endPeriod) 节")
            rowDivider
            infoRow(icon: .edit, label: "教师", value: course.teacher.isEmpty ? "未填写" : course.teacher)
            rowDivider
            infoRow(icon: .gridCells, label: "教室", value: resolvedLocation)
            rowDivider
            infoRow(icon: .repeatArrows, label: "周次", value: slot.weekSummaryText())
        }
        .cardSurface()
    }

    private func infoRow(icon: Reicon, label: String, value: String) -> some View {
        HStack(spacing: 10) {
            ReiconIcon(icon: icon, size: 14)
                .foregroundStyle(Theme.textTertiary)
                .frame(width: 18)
            Text(label)
                .font(.system(size: 13.5))
                .foregroundStyle(Theme.textSecondary)
            Spacer(minLength: 10)
            Text(value)
                .font(.system(size: 13.5, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(Theme.text)
                .lineLimit(1)
        }
        .frame(minHeight: 42)
    }

    private var rowDivider: some View {
        Rectangle().fill(Theme.stroke).frame(height: 0.5).padding(.leading, 28)
    }

    // MARK: 上课周次格子卡

    private var weeksGridCard: some View {
        let active = slot.activeWeeks()

        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("上课周次")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textSecondary)
                Spacer()
                Text("当前显示第 \(displayWeek) 周")
                    .font(.system(size: 11.5, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Theme.textTertiary)
            }

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 10), spacing: 6) {
                ForEach(1...20, id: \.self) { week in
                    let isOn = active.contains(week)
                    let isCurrent = week == displayWeek
                    Text("\(week)")
                        .font(.system(size: 11.5, weight: isOn ? .semibold : .regular, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(isOn ? Color.white : Theme.textTertiary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 28)
                        .background(
                            RoundedRectangle(cornerRadius: AppRadius.grid, style: .continuous)
                                .fill(isOn ? Theme.text.opacity(0.68) : Theme.surfaceRaised)
                        )
                        .overlay {
                            if isCurrent {
                                RoundedRectangle(cornerRadius: AppRadius.grid, style: .continuous)
                                    .strokeBorder(Theme.brand, lineWidth: 1.8)
                            }
                        }
                }
            }

            Text("编辑时可单独增删某几周；「本周停课」只移除第 \(displayWeek) 周。")
                .font(.system(size: 11, design: .rounded))
                .foregroundStyle(Theme.textTertiary)
        }
        .cardSurface()
    }

    // MARK: 底部操作键

    private var actionButtons: some View {
        VStack(spacing: Theme.cardGap) {
            Button {
                isEditing = true
            } label: {
                HStack(spacing: 6) {
                    ReiconIcon(icon: .edit, size: 15)
                    Text("编辑本节")
                }
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

            if slot.isActive(inWeek: displayWeek) {
                Button {
                    skipCurrentWeek()
                } label: {
                    VStack(spacing: 2) {
                        Text("本周停课")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(Theme.text)
                        Text("只从「\(course.name)」移除第 \(displayWeek) 周")
                            .font(.system(size: 11, design: .rounded))
                            .foregroundStyle(Theme.textTertiary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
                    .cardElevation(radius: AppRadius.item)
                }
                .buttonStyle(PressableStyle())
            }

            Button(role: .destructive) {
                deleteCourse()
            } label: {
                Text("删除整门课程")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Color(hex: 0xEF4444))
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .cardElevation(radius: AppRadius.item)
            }
            .buttonStyle(PressableStyle())
        }
        .padding(.top, 2)
    }

    private func skipCurrentWeek() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        var weeks = slot.activeWeeks()
        weeks.remove(displayWeek)
        slot.setActiveWeeks(weeks)
        try? context.save()
        AppLog.info("本周停课：\(course.name) 移除第 \(displayWeek) 周")
        dismiss()
    }

    private func deleteCourse() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        context.delete(course)
        try? context.save()
        AppLog.info("删除课程：\(course.name)")
        dismiss()
    }
}

// MARK: - 课程添加 / 编辑页（规范 NavigationStack + 单行节次 + 手动/自动配色 + 周次点选）

struct CourseEditor: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    let course: Course?
    let slot: CourseSlot?

    @State private var name: String
    @State private var teacher: String
    @State private var location: String
    @State private var weekday: Int
    @State private var startPeriod: Int
    @State private var endPeriod: Int
    @State private var activeWeeks: Set<Int>
    @State private var selectedShade: Int?

    @FocusState private var nameFocused: Bool

    private let weekTotal = 20

    init(course: Course?, slot: CourseSlot?) {
        self.course = course
        self.slot = slot
        _name = State(initialValue: course?.name ?? "")
        _teacher = State(initialValue: course?.teacher ?? "")
        _location = State(initialValue: slot?.location ?? course?.location ?? "")
        _weekday = State(initialValue: slot?.weekday ?? TimetableMath.todayWeekday)
        _startPeriod = State(initialValue: slot?.startPeriod ?? 1)
        _endPeriod = State(initialValue: slot?.endPeriod ?? 2)
        _activeWeeks = State(initialValue: slot?.activeWeeks() ?? Set(1...20))
        _selectedShade = State(initialValue: course?.shade)
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: Theme.cardGap) {
                    basicInfoCard
                    timeCard
                    weeksCard
                    colorCard

                    Button(action: save) {
                        HStack(spacing: 6) {
                            ReiconIcon(icon: .check, size: 15)
                            Text(course == nil ? "添加课程" : "保存修改")
                        }
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
                    .disabled(!canSave)
                    .opacity(canSave ? 1 : 0.45)

                    if course != nil, slot != nil {
                        Button {
                            addAnotherTime()
                        } label: {
                            HStack(spacing: 6) {
                                ReiconIcon(icon: .add, size: 14)
                                Text("为这门课增加其他时段")
                            }
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.textSecondary)
                            .padding(.vertical, 8)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, Theme.screenPadding)
                .padding(.vertical, 12)
            }
            .background(Theme.bg)
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(course == nil ? "添加课程" : "编辑课程")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                        .foregroundStyle(Theme.textSecondary)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }
                        .fontWeight(.semibold)
                        .foregroundStyle(canSave ? Theme.brand : Theme.textTertiary)
                        .disabled(!canSave)
                }
            }
        }
        .presentationBackground(Theme.bg)
        .onAppear {
            if course == nil { nameFocused = true }
        }
    }

    // MARK: 基本信息

    private var basicInfoCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("基本信息").cardLabel()

            fieldBox(label: "课程名", placeholder: "输入课程名称", text: $name, isFocused: true)
            fieldBox(label: "教师", placeholder: "选填", text: $teacher, isFocused: false)
            fieldBox(label: "教室", placeholder: "选填", text: $location, isFocused: false)
        }
        .cardSurface()
    }

    private func fieldBox(label: String, placeholder: String, text: Binding<String>, isFocused: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.system(size: 11.5))
                .foregroundStyle(Theme.textTertiary)

            Group {
                if isFocused {
                    TextField(placeholder, text: text)
                        .focused($nameFocused)
                } else {
                    TextField(placeholder, text: text)
                }
            }
            .font(.system(size: 14.5))
            .foregroundStyle(Theme.text)
            .padding(.horizontal, 13)
            .frame(height: 44)
            .background(
                RoundedRectangle(cornerRadius: AppRadius.item, style: .continuous)
                    .fill(Theme.surfaceRaised)
            )
        }
    }

    // MARK: 时间（单行不换行节次 + 无具体作息时间）

    private var timeCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("时间").cardLabel()
                .padding(.bottom, 6)

            HStack {
                Text("星期")
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.text)
                Spacer()
                Menu {
                    ForEach(1...7, id: \.self) { day in
                        Button("周\(TimetableMath.weekdayName(day))") {
                            weekday = day
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text("周\(TimetableMath.weekdayName(weekday))")
                            .font(.system(size: 14, weight: .semibold))
                            .fixedSize(horizontal: true, vertical: false)
                        ReiconIcon(icon: .chevronDown, size: 11)
                            .foregroundStyle(Theme.textTertiary)
                    }
                    .foregroundStyle(Theme.text)
                }
            }
            .frame(minHeight: 48)

            Rectangle().fill(Theme.stroke).frame(height: 0.5)

            HStack(spacing: 8) {
                Text("节次")
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.text)
                Spacer(minLength: 8)

                Menu {
                    ForEach(1...12, id: \.self) { p in
                        Button("第 \(p) 节") {
                            startPeriod = p
                            if endPeriod < p { endPeriod = p }
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text("第 \(startPeriod) 节")
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                            .fixedSize(horizontal: true, vertical: false)
                        ReiconIcon(icon: .chevronDown, size: 10)
                            .foregroundStyle(Theme.textTertiary)
                    }
                    .foregroundStyle(Theme.text)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(Theme.surfaceRaised))
                }

                Text("—")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textTertiary)

                Menu {
                    ForEach(startPeriod...12, id: \.self) { p in
                        Button("第 \(p) 节") {
                            endPeriod = p
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text("第 \(endPeriod) 节")
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                            .fixedSize(horizontal: true, vertical: false)
                        ReiconIcon(icon: .chevronDown, size: 10)
                            .foregroundStyle(Theme.textTertiary)
                    }
                    .foregroundStyle(Theme.text)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(Theme.surfaceRaised))
                }
            }
            .frame(minHeight: 50)
        }
        .cardSurface()
    }

    // MARK: 周次（快捷按钮 + 1-20 可点选网格）

    private var weeksCard: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack {
                Text("周次").cardLabel()
                Spacer()
                Text("共 \(activeWeeks.count) 周")
                    .font(.system(size: 11.5, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Theme.textTertiary)
            }

            HStack(spacing: 7) {
                quickWeekButton("全选") { activeWeeks = Set(1...weekTotal) }
                quickWeekButton("清空") { activeWeeks = [] }
                quickWeekButton("单周") { activeWeeks = Set((1...weekTotal).filter { $0 % 2 == 1 }) }
                quickWeekButton("双周") { activeWeeks = Set((1...weekTotal).filter { $0 % 2 == 0 }) }
                Spacer()
            }

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 10), spacing: 6) {
                ForEach(1...weekTotal, id: \.self) { week in
                    let isOn = activeWeeks.contains(week)
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        if isOn {
                            activeWeeks.remove(week)
                        } else {
                            activeWeeks.insert(week)
                        }
                    } label: {
                        Text("\(week)")
                            .font(.system(size: 11.5, weight: isOn ? .semibold : .regular, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(isOn ? Color.white : Theme.textTertiary)
                            .frame(maxWidth: .infinity)
                            .frame(height: 29)
                            .background(
                                RoundedRectangle(cornerRadius: AppRadius.grid, style: .continuous)
                                    .fill(isOn ? Theme.brand : Theme.surfaceRaised)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }

            Text(formattedWeekSummary)
                .font(.system(size: 11, design: .rounded))
                .foregroundStyle(Theme.textTertiary)
        }
        .cardSurface()
    }

    private func quickWeekButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            action()
        } label: {
            Text(title)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(Theme.textSecondary)
                .padding(.horizontal, 11)
                .padding(.vertical, 5)
                .background(Capsule().fill(Theme.surfaceRaised))
        }
        .buttonStyle(.plain)
    }

    private var formattedWeekSummary: String {
        let sorted = activeWeeks.sorted()
        guard let first = sorted.first else { return "未选择周次" }
        var ranges: [String] = []
        var s = first
        var e = first
        for w in sorted.dropFirst() {
            if w == e + 1 { e = w }
            else {
                ranges.append(s == e ? "\(s)" : "\(s)-\(e)")
                s = w; e = w
            }
        }
        ranges.append(s == e ? "\(s)" : "\(s)-\(e)")
        return ranges.joined(separator: ", ") + " 周"
    }

    // MARK: 配色（支持自动选色或手动选 9 套莫兰迪色）

    private var colorCard: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack {
                Text("配色").cardLabel()
                Spacer()
                Button {
                    selectedShade = nil
                } label: {
                    Text(selectedShade == nil ? "✓ 系统自动" : "改回系统自动")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(selectedShade == nil ? Theme.brand : Theme.textTertiary)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(selectedShade == nil ? Theme.brandSoft : Theme.surfaceRaised))
                }
                .buttonStyle(.plain)
            }

            HStack(spacing: 0) {
                ForEach(0..<9, id: \.self) { index in
                    let tone = Theme.courseTone(index)
                    let isOn = selectedShade == index
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        selectedShade = index
                    } label: {
                        Circle()
                            .fill(tone.bg)
                            .frame(width: 28, height: 28)
                            .overlay(
                                Circle()
                                    .strokeBorder(isOn ? tone.fg : tone.fg.opacity(0.22), lineWidth: isOn ? 2 : 0.6)
                            )
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .cardSurface()
    }

    // MARK: 保存

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let resolvedShade = selectedShade ?? CourseShade.next(for: trimmed, in: context)

        let target: Course
        if let course {
            target = course
            target.name = trimmed
            target.teacher = teacher
            if selectedShade != nil { target.shade = resolvedShade }
        } else {
            target = Course(
                name: trimmed,
                teacher: teacher,
                location: location,
                shade: resolvedShade
            )
            context.insert(target)
        }

        let targetSlot: CourseSlot
        if let slot {
            targetSlot = slot
        } else {
            targetSlot = CourseSlot()
            targetSlot.course = target
            target.slots.append(targetSlot)
            context.insert(targetSlot)
        }

        targetSlot.weekday = weekday
        targetSlot.startPeriod = startPeriod
        targetSlot.endPeriod = max(startPeriod, endPeriod)
        targetSlot.location = location
        targetSlot.setActiveWeeks(activeWeeks)

        try? context.save()
        AppLog.info("保存课程：\(trimmed) 周\(TimetableMath.weekdayName(weekday)) \(startPeriod)-\(endPeriod) 节")
        dismiss()
    }

    private func addAnotherTime() {
        guard let course else {
            save()
            return
        }
        let newSlot = CourseSlot(
            weekday: weekday == 7 ? 1 : weekday + 1,
            startPeriod: startPeriod,
            endPeriod: max(startPeriod, endPeriod),
            location: location
        )
        newSlot.setActiveWeeks(activeWeeks)
        newSlot.course = course
        course.slots.append(newSlot)
        context.insert(newSlot)
        try? context.save()
        AppLog.info("给 \(course.name) 添加了另一个时间段")
        dismiss()
    }
}

/// 新课程的颜色：避开已经用过的
enum CourseShade {
    static func next(for name: String, in context: ModelContext) -> Int {
        let used = Set(((try? context.fetch(FetchDescriptor<Course>())) ?? []).map(\.shade))
        for index in 0..<9 where !used.contains(index) {
            return index
        }
        return abs(name.hashValue) % 9
    }
}
