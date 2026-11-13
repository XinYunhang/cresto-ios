import SwiftUI
import SwiftData

/// 课程编辑页。点列表/网格里的任意课程进来是「编辑」，悬浮 + 进来是「添加」。
/// 周次用 1–20 的格子可视化，上方可调起止周和单双周。
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
    @State private var weekStart: Int
    @State private var weekEnd: Int
    @State private var parity: WeekParity
    @State private var showWeeks = false
    @State private var showPeriods = false

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
        _weekStart = State(initialValue: slot?.weekStart ?? 1)
        _weekEnd = State(initialValue: slot?.weekEnd ?? 20)
        _parity = State(initialValue: slot?.parity ?? .all)
    }

    private var tone: CourseTone { Theme.courseTone(course?.shade ?? 0) }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            ScrollView {
                VStack(spacing: 12) {
                    nameField
                    attributes
                    addAnother
                    if course != nil { deleteButton }
                }
                .padding(.horizontal, Theme.screenPadding)
                .padding(.bottom, 30)
            }
        }
        .background(Theme.bg)
        .presentationBackground(Theme.bg)
        .onAppear {
            if course == nil { nameFocused = true }
        }
    }

    // MARK: 顶栏

    private var topBar: some View {
        HStack {
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Theme.text)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(Theme.surface))
            }
            .buttonStyle(.plain)

            Spacer()
            Text(course == nil ? "添加课程" : "编辑课程")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Theme.text)
            Spacer()

            Button(action: save) {
                Image(systemName: "checkmark")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Theme.bg)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(Theme.text))
            }
            .buttonStyle(.plain)
            .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            .opacity(name.trimmingCharacters(in: .whitespaces).isEmpty ? 0.4 : 1)
        }
        .padding(.horizontal, Theme.screenPadding)
        .padding(.top, 6)
        .padding(.bottom, 14)
    }

    // MARK: 名称

    private var nameField: some View {
        HStack(spacing: 11) {
            Circle()
                .fill(tone.fg)
                .frame(width: 13, height: 13)
            TextField("课程名称", text: $name)
                .font(.system(size: 16))
                .foregroundStyle(Theme.text)
                .focused($nameFocused)
                .submitLabel(.done)
        }
        .padding(.horizontal, 15)
        .frame(height: 58)
        .background(
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .fill(Theme.surface)
        )
    }

    // MARK: 周数 / 节数 / 教室 / 老师

    private var attributes: some View {
        VStack(spacing: 0) {
            // 周数
            Button {
                withAnimation(.snappy(duration: 0.2)) { showWeeks.toggle() }
            } label: {
                HStack {
                    Text("周数").font(.system(size: 15)).foregroundStyle(Theme.text)
                    Spacer()
                    Text(weekSummary).font(.system(size: 14)).foregroundStyle(Theme.textTertiary)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.textTertiary)
                        .rotationEffect(.degrees(showWeeks ? 90 : 0))
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 17)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if showWeeks {
                weekEditor
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)
            }

            divider

            // 节数
            Button {
                withAnimation(.snappy(duration: 0.2)) { showPeriods.toggle() }
            } label: {
                HStack {
                    Text("节数").font(.system(size: 15)).foregroundStyle(Theme.text)
                    Spacer()
                    Text("周\(TimetableMath.weekdayName(weekday)) \(startPeriod)-\(endPeriod) 节")
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.textTertiary)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.textTertiary)
                        .rotationEffect(.degrees(showPeriods ? 90 : 0))
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 17)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if showPeriods {
                periodEditor
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)
            }

            divider

            inlineField("教室", text: $location, placeholder: "选填")
            divider
            inlineField("老师", text: $teacher, placeholder: "选填")
        }
        .background(
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .fill(Theme.surface)
        )
    }

    private var divider: some View {
        Rectangle()
            .fill(Theme.stroke)
            .frame(height: 1)
            .padding(.leading, 16)
    }

    private var weekSummary: String {
        var text = "\(weekStart)-\(weekEnd) 周"
        if parity != .all { text += " · \(parity.title)" }
        return text
    }

    private var weekEditor: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                stepper("起始", value: $weekStart, range: 1...weekTotal)
                stepper("结束", value: $weekEnd, range: max(weekStart, 1)...weekTotal)
            }

            Picker("单双周", selection: $parity) {
                ForEach(WeekParity.allCases) { item in
                    Text(item.title).tag(item)
                }
            }
            .pickerStyle(.segmented)

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 5), count: 10), spacing: 5) {
                ForEach(1...weekTotal, id: \.self) { week in
                    let active = isActive(week)
                    Text("\(week)")
                        .font(.system(size: 11, weight: active ? .medium : .regular))
                        .foregroundStyle(active ? Theme.text : Theme.textTertiary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 27)
                        .background(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(active ? Theme.text.opacity(0.12) : Color.clear)
                        )
                }
            }
        }
    }

    private var periodEditor: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 5) {
                ForEach(1...7, id: \.self) { day in
                    let isOn = weekday == day
                    Button {
                        weekday = day
                    } label: {
                        Text(TimetableMath.weekdayName(day))
                            .font(.system(size: 12))
                            .foregroundStyle(isOn ? Theme.bg : Theme.textSecondary)
                            .frame(maxWidth: .infinity)
                            .frame(height: 32)
                            .background(
                                RoundedRectangle(cornerRadius: 9, style: .continuous)
                                    .fill(isOn ? Theme.text : Theme.surfaceRaised)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }

            HStack(spacing: 10) {
                stepper("第", value: $startPeriod, range: 1...16)
                stepper("到", value: $endPeriod, range: max(startPeriod, 1)...16)
            }
        }
    }

    private func stepper(_ title: String, value: Binding<Int>, range: ClosedRange<Int>) -> some View {
        HStack(spacing: 8) {
            Text(title).font(.system(size: 12.5)).foregroundStyle(Theme.textSecondary)
            Stepper(value: value, in: range) {
                Text("\(value.wrappedValue)")
                    .font(.system(size: 13))
                    .monospacedDigit()
                    .foregroundStyle(Theme.text)
            }
            .fixedSize()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func inlineField(_ title: String, text: Binding<String>, placeholder: String) -> some View {
        HStack {
            Text(title).font(.system(size: 15)).foregroundStyle(Theme.text)
            Spacer()
            TextField(placeholder, text: text)
                .font(.system(size: 14))
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.trailing)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 15)
    }

    private func isActive(_ week: Int) -> Bool {
        guard week >= weekStart, week <= weekEnd else { return false }
        switch parity {
        case .all: return true
        case .odd: return week % 2 == 1
        case .even: return week % 2 == 0
        }
    }

    // MARK: 其他时间 / 删除

    private var addAnother: some View {
        Button {
            addAnotherTime()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "plus").font(.system(size: 13, weight: .medium))
                Text("添加其他时间")
            }
            .font(.system(size: 14))
            .foregroundStyle(Theme.textSecondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var deleteButton: some View {
        Button {
            deleteCourse()
        } label: {
            Text("删除这门课")
                .font(.system(size: 14))
                .foregroundStyle(Theme.textSecondary)
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Theme.surface)
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: 动作

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }

        let target: Course
        if let course {
            target = course
            target.name = trimmed
            target.teacher = teacher
        } else {
            target = Course(
                name: trimmed,
                teacher: teacher,
                location: location,
                shade: CourseShade.next(for: trimmed, in: context)
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
        targetSlot.weekStart = weekStart
        targetSlot.weekEnd = max(weekStart, weekEnd)
        targetSlot.parity = parity
        targetSlot.location = location

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
            endPeriod: endPeriod,
            weekStart: weekStart,
            weekEnd: weekEnd,
            parity: parity,
            location: location
        )
        newSlot.course = course
        course.slots.append(newSlot)
        context.insert(newSlot)
        try? context.save()
        AppLog.info("给 \(course.name) 添加了另一个时间段")
        dismiss()
    }

    private func deleteCourse() {
        guard let slot else { return }
        let owner = slot.course
        context.delete(slot)
        if let owner, owner.slots.count <= 1 {
            context.delete(owner)
        }
        try? context.save()
        AppLog.info("删除课程：\(owner?.name ?? "")")
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
