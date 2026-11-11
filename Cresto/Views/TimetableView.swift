import SwiftUI
import SwiftData

/// 周课表。行 = 节次，列 = 星期，块 = 一门课的一段课。
/// 数据模型和 WakeUp / LightTable 一个路子：课程信息 + 若干时间块。
struct TimetableView: View {
    @Environment(\.modelContext) private var context

    @Query private var courses: [Course]
    @Query private var settingsList: [TimetableSettings]

    @State private var week: Int?
    @State private var isImportPresented = false
    @State private var isEditorPresented = false
    @State private var editingCourse: Course?
    @State private var editingSlot: CourseSlot?

    private let timeColumn: CGFloat = 32
    private let rowHeight: CGFloat = 58

    private var settings: TimetableSettings? { settingsList.first }
    private var periodCount: Int { max(settings?.periodCount ?? 12, 8) }
    private var currentWeek: Int { week ?? settings?.weekNumber() ?? 1 }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: Theme.cardGap) {
                header
                weekBar
                gridCard
                if courses.isEmpty { emptyState }
            }
            .padding(.horizontal, Theme.screenPadding)
            .padding(.bottom, 132)
        }
        .sheet(isPresented: $isEditorPresented, onDismiss: {
            editingCourse = nil
            editingSlot = nil
        }) {
            CourseEditor(course: editingCourse, slot: editingSlot)
        }
    }

    // MARK: 页头

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 5) {
                Text(settings.map { "开学 \($0.termStart.formatted(.dateTime.month().day())) · 共 \($0.periodCount) 节" } ?? "还没有学期设置")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textSecondary)
                Text("课表")
                    .font(.system(size: 26, weight: .medium))
                    .foregroundStyle(Theme.text)
                    .tracking(-0.5)
            }
            Spacer()
            Button {
                isImportPresented = true
            } label: {
                Image(systemName: "doc.viewfinder")
                    .font(.system(size: 16))
                    .foregroundStyle(Theme.text)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(Color.white.opacity(0.05)))
                    .overlay(Circle().strokeBorder(Theme.stroke, lineWidth: 1))
            }
            .buttonStyle(PressableStyle())
            .accessibilityLabel("导入课表")
            .sheet(isPresented: $isImportPresented) {
                TimetableImportView()
            }

            Button {
                editingCourse = nil
                editingSlot = nil
                isEditorPresented = true
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Theme.text)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(Color.white.opacity(0.05)))
                    .overlay(Circle().strokeBorder(Theme.stroke, lineWidth: 1))
            }
            .buttonStyle(PressableStyle())
            .accessibilityLabel("添加课程")
        }
        .padding(.horizontal, 2)
    }

    // MARK: 周切换

    private var weekBar: some View {
        HStack(spacing: 10) {
            Button {
                withAnimation(.snappy(duration: 0.2)) {
                    week = max(1, currentWeek - 1)
                }
            } label: {
                Image(systemName: "chevron.left").font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            VStack(spacing: 1) {
                Text("第 \(currentWeek) 周")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.text)
                if let settings {
                    Text(settings.monday(ofWeek: currentWeek).formatted(.dateTime.month().day()))
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.textTertiary)
                }
            }
            .frame(maxWidth: .infinity)

            Button {
                withAnimation(.snappy(duration: 0.2)) {
                    week = min(currentWeek + 1, 30)
                }
            } label: {
                Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if week != nil {
                Button("本周") {
                    withAnimation(.snappy(duration: 0.2)) { week = nil }
                }
                .font(.system(size: 11.5))
                .foregroundStyle(Theme.textSecondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .overlay(Capsule().strokeBorder(Theme.stroke, lineWidth: 1))
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .cardSurface(padding: 0)
    }

    // MARK: 表格

    private var gridCard: some View {
        VStack(spacing: 0) {
            dayHeader
            GeometryReader { geo in
                let columnWidth = max(0, (geo.size.width - timeColumn) / 7)
                ZStack(alignment: .topLeading) {
                    gridLines(columnWidth: columnWidth)

                    ForEach(blocks) { block in
                        courseBlock(block, columnWidth: columnWidth)
                            .offset(
                                x: timeColumn + CGFloat(block.slot.weekday - 1) * columnWidth + 1,
                                y: CGFloat(block.slot.startPeriod - 1) * rowHeight + 1
                            )
                    }
                }
            }
            .frame(height: CGFloat(periodCount) * rowHeight)
        }
        .cardSurface(padding: 8)
    }

    private var dayHeader: some View {
        HStack(spacing: 0) {
            Color.clear.frame(width: timeColumn, height: 34)

            ForEach(1...7, id: \.self) { day in
                let isToday = Calendar.current.component(.weekday, from: Date()) == (day == 7 ? 1 : day + 1)
                VStack(spacing: 1) {
                    Text(weekdayName(day))
                        .font(.system(size: 11, weight: isToday ? .medium : .regular))
                        .foregroundStyle(isToday ? Theme.text : Theme.textSecondary)
                    if let settings {
                        Text(dayNumber(day, settings: settings))
                            .font(.system(size: 9))
                            .foregroundStyle(isToday ? Theme.text : Theme.textTertiary)
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.bottom, 6)
    }

    private func gridLines(columnWidth: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(1...periodCount, id: \.self) { period in
                Rectangle()
                    .fill(Color.white.opacity(0.05))
                    .frame(height: 1)
                    .offset(y: CGFloat(period - 1) * rowHeight)
            }

            ForEach(0...7, id: \.self) { index in
                Rectangle()
                    .fill(Color.white.opacity(0.04))
                    .frame(width: 1, height: CGFloat(periodCount) * rowHeight)
                    .offset(x: timeColumn + CGFloat(index) * columnWidth)
            }

            ForEach(1...periodCount, id: \.self) { period in
                VStack(spacing: 1) {
                    Text("\(period)")
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.textTertiary)
                    Text(settings?.startText(ofPeriod: period) ?? "")
                        .font(.system(size: 8))
                        .foregroundStyle(Theme.textTertiary.opacity(0.75))
                }
                .frame(width: timeColumn)
                .offset(y: CGFloat(period - 1) * rowHeight + 9)
            }
        }
    }

    private func courseBlock(_ block: Block, columnWidth: CGFloat) -> some View {
        let span = CGFloat(block.slot.periodSpan)
        return Button {
            editingCourse = block.course
            editingSlot = block.slot
            isEditorPresented = true
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(block.course.name)
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(Theme.text)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                if span >= 2, !block.course.location.isEmpty {
                    Text(block.course.location)
                        .font(.system(size: 9))
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 5)
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.white.opacity(0.055 + Double(block.course.shade) * 0.045))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.14), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .frame(width: max(0, columnWidth - 2), height: span * rowHeight - 2)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "tablecells")
                .font(.system(size: 24, weight: .light))
                .foregroundStyle(Theme.textTertiary)
            Text("还没有课程")
                .font(.system(size: 14))
                .foregroundStyle(Theme.textSecondary)
            Text("点右上角加一门，或者以后从教务系统导入")
                .font(.system(size: 11.5))
                .foregroundStyle(Theme.textTertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 26)
        .cardSurface()
    }

    // MARK: 数据

    struct Block: Identifiable {
        let id: UUID
        let course: Course
        let slot: CourseSlot
    }

    private var blocks: [Block] {
        courses.flatMap { course in
            course.slots
                .filter { $0.isActive(inWeek: currentWeek) }
                .map { Block(id: $0.id, course: course, slot: $0) }
        }
    }

    private func weekdayName(_ day: Int) -> String {
        ["一", "二", "三", "四", "五", "六", "日"][max(0, min(6, day - 1))]
    }

    private func dayNumber(_ day: Int, settings: TimetableSettings) -> String {
        let monday = settings.monday(ofWeek: currentWeek)
        let date = Calendar.current.date(byAdding: .day, value: day - 1, to: monday) ?? monday
        return "\(Calendar.current.component(.day, from: date))"
    }
}

// MARK: - 课程编辑

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
    @State private var shade: Int

    @FocusState private var nameFocused: Bool

    init(course: Course?, slot: CourseSlot?) {
        self.course = course
        self.slot = slot
        _name = State(initialValue: course?.name ?? "")
        _teacher = State(initialValue: course?.teacher ?? "")
        _location = State(initialValue: course?.location ?? "")
        _weekday = State(initialValue: slot?.weekday ?? 1)
        _startPeriod = State(initialValue: slot?.startPeriod ?? 1)
        _endPeriod = State(initialValue: slot?.endPeriod ?? 2)
        _weekStart = State(initialValue: slot?.weekStart ?? 1)
        _weekEnd = State(initialValue: slot?.weekEnd ?? 16)
        _parity = State(initialValue: slot?.parity ?? .all)
        _shade = State(initialValue: course?.shade ?? 0)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Theme.cardGap) {
                    infoCard
                    timeCard
                    weekCard
                    appearanceCard
                    if slot != nil { deleteButton }
                }
                .padding(.horizontal, Theme.screenPadding)
                .padding(.vertical, 12)
            }
            .background(Theme.bg)
            .navigationTitle(course == nil ? "添加课程" : "编辑课程")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }.foregroundStyle(Theme.textSecondary)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }
                        .fontWeight(.semibold)
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .tint(Theme.ink)
        }
        .presentationBackground(Theme.bg)
        .onAppear { if course == nil { nameFocused = true } }
    }

    private var infoCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField("课程名", text: $name)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(Theme.text)
                .focused($nameFocused)
            row("教师") {
                TextField("可选", text: $teacher)
                    .multilineTextAlignment(.trailing)
            }
            row("地点") {
                TextField("可选", text: $location)
                    .multilineTextAlignment(.trailing)
            }
        }
        .cardSurface()
    }

    private var timeCard: some View {
        VStack(spacing: 0) {
            HStack {
                Text("星期").font(.system(size: 13.5)).foregroundStyle(Theme.text)
                Spacer()
                Picker("星期", selection: $weekday) {
                    ForEach(1...7, id: \.self) { day in
                        Text("周\(["一", "二", "三", "四", "五", "六", "日"][day - 1])").tag(day)
                    }
                }
                .pickerStyle(.menu)
                .tint(Theme.textSecondary)
            }
            .padding(.vertical, 9)

            divider

            stepperRow("开始节次", value: $startPeriod, range: 1...16)
            divider
            stepperRow("结束节次", value: $endPeriod, range: max(startPeriod, 1)...16)
        }
        .cardSurface()
        .onChange(of: startPeriod) { _, newValue in
            if endPeriod < newValue { endPeriod = newValue }
        }
    }

    private var weekCard: some View {
        VStack(spacing: 0) {
            stepperRow("起始周", value: $weekStart, range: 1...30)
            divider
            stepperRow("结束周", value: $weekEnd, range: max(weekStart, 1)...30)

            divider

            HStack {
                Text("单双周").font(.system(size: 13.5)).foregroundStyle(Theme.text)
                Spacer()
                Picker("单双周", selection: $parity) {
                    ForEach(WeekParity.allCases) { item in
                        Text(item.title).tag(item)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 190)
            }
            .padding(.vertical, 9)
        }
        .cardSurface()
        .onChange(of: weekStart) { _, newValue in
            if weekEnd < newValue { weekEnd = newValue }
        }
    }

    private var appearanceCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("色阶").cardLabel()
            HStack(spacing: 8) {
                ForEach(0..<5, id: \.self) { index in
                    Button {
                        shade = index
                    } label: {
                        Circle()
                            .fill(Color.white.opacity(0.055 + Double(index) * 0.045))
                            .frame(width: 30, height: 30)
                            .overlay(
                                Circle().strokeBorder(
                                    shade == index ? Color.white.opacity(0.85) : Theme.stroke,
                                    lineWidth: shade == index ? 1.5 : 1
                                )
                            )
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
            }
            Text("黑白主题下用深浅区分课程，不再引入颜色")
                .font(.system(size: 11))
                .foregroundStyle(Theme.textTertiary)
        }
        .cardSurface()
    }

    private var deleteButton: some View {
        Button {
            if let slot {
                let owner = slot.course
                context.delete(slot)
                if let owner, owner.slots.count <= 1 {
                    context.delete(owner)
                }
                try? context.save()
            }
            dismiss()
        } label: {
            Text("删除这门课")
                .font(.system(size: 13.5))
                .foregroundStyle(Theme.textSecondary)
                .frame(maxWidth: .infinity)
                .frame(height: 46)
                .background(
                    RoundedRectangle(cornerRadius: 15, style: .continuous)
                        .fill(Color.white.opacity(0.04))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 15, style: .continuous)
                        .strokeBorder(Theme.stroke, lineWidth: 1)
                )
        }
        .buttonStyle(PressableStyle())
    }

    // MARK: 小部件

    private func row<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        HStack {
            Text(title).font(.system(size: 13.5)).foregroundStyle(Theme.textSecondary)
            Spacer()
            content()
                .font(.system(size: 13.5))
                .foregroundStyle(Theme.text)
        }
    }

    private func stepperRow(_ title: String, value: Binding<Int>, range: ClosedRange<Int>) -> some View {
        HStack {
            Text(title).font(.system(size: 13.5)).foregroundStyle(Theme.text)
            Spacer()
            Stepper(value: value, in: range) {
                Text("\(value.wrappedValue)")
                    .font(.system(size: 13.5))
                    .monospacedDigit()
                    .foregroundStyle(Theme.textSecondary)
            }
            .fixedSize()
        }
        .padding(.vertical, 6)
    }

    private var divider: some View {
        Rectangle().fill(Color.white.opacity(0.06)).frame(height: 1)
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }

        let target = course ?? Course()
        target.name = trimmed
        target.teacher = teacher
        target.location = location
        target.shade = shade

        if let slot {
            slot.weekday = weekday
            slot.startPeriod = startPeriod
            slot.endPeriod = endPeriod
            slot.weekStart = weekStart
            slot.weekEnd = weekEnd
            slot.parity = parity
        } else {
            let newSlot = CourseSlot(
                weekday: weekday,
                startPeriod: startPeriod,
                endPeriod: endPeriod,
                weekStart: weekStart,
                weekEnd: weekEnd,
                parity: parity
            )
            newSlot.course = target
            target.slots.append(newSlot)
            context.insert(newSlot)
        }

        if course == nil {
            context.insert(target)
        }

        try? context.save()
        dismiss()
    }
}
