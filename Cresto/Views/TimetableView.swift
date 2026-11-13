import SwiftUI
import SwiftData

enum TimetableMode {
    case list, grid
}

struct SlotItem: Identifiable {
    let course: Course
    let slot: CourseSlot
    var id: UUID { slot.id }
}

/// 课表：默认「周列表」——上面选星期，下面只显示那天的课；右上切到全景网格。
/// 点任意课程进入编辑（不是新增）。
struct TimetableView: View {
    @Environment(\.modelContext) private var context

    @Query private var courses: [Course]
    @Query private var settingsList: [TimetableSettings]

    @State private var mode: TimetableMode = .list
    @State private var week: Int?
    @State private var selectedWeekday: Int = TimetableMath.todayWeekday
    @State private var editingCourse: Course?
    @State private var editingSlot: CourseSlot?
    @State private var isEditorPresented = false
    @State private var isImportPresented = false
    @State private var isManagePresented = false
    @State private var rowHeight: CGFloat = 46
    @State private var pinchBase: CGFloat = 46

    private var settings: TimetableSettings? { settingsList.first }
    private var currentWeek: Int { week ?? settings?.weekNumber() ?? 1 }
    private var periodCount: Int { max(settings?.periodCount ?? 12, 8) }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: Theme.cardGap) {
                header

                switch mode {
                case .list:
                    daySelector
                    dayList
                case .grid:
                    gridCard
                }
            }
            .padding(.horizontal, Theme.screenPadding)
            .padding(.bottom, 128)
        }
        .overlay(alignment: .bottomTrailing) {
            addButton
        }
        .sheet(isPresented: $isEditorPresented, onDismiss: {
            editingCourse = nil
            editingSlot = nil
        }) {
            CourseEditor(course: editingCourse, slot: editingSlot)
        }
        .sheet(isPresented: $isImportPresented) {
            TimetableImportView()
        }
        .sheet(isPresented: $isManagePresented) {
            TimetableSettingsView()
        }
    }

    // MARK: 顶部

    private var header: some View {
        HStack(spacing: 10) {
            Button {
                withAnimation(.snappy(duration: 0.22)) {
                    mode = mode == .list ? .grid : .list
                }
            } label: {
                Image(systemName: mode == .list ? "tablecells" : "list.bullet")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(Theme.text)
                    .frame(width: 38, height: 38)
                    .glassCircle()
            }
            .buttonStyle(PressableStyle())
            .accessibilityLabel(mode == .list ? "切换到网格" : "切换到列表")

            Spacer(minLength: 0)

            Menu {
                ForEach(1...max(20, currentWeek), id: \.self) { index in
                    Button {
                        week = index
                    } label: {
                        if index == currentWeek {
                            Label("第 \(index) 周", systemImage: "checkmark")
                        } else {
                            Text("第 \(index) 周")
                        }
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Text("第 \(currentWeek) 周")
                        .font(.system(size: 17, weight: .semibold))
                    Image(systemName: "chevron.down")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.textTertiary)
                }
                .foregroundStyle(Theme.text)
            }

            Spacer(minLength: 0)

            Menu {
                Button {
                    isManagePresented = true
                } label: {
                    Label("课表管理", systemImage: "tablecells")
                }
                Button {
                    isImportPresented = true
                } label: {
                    Label("导入课表", systemImage: "square.and.arrow.down")
                }
                ShareLink(item: shareText) {
                    Label("分享课表", systemImage: "square.and.arrow.up")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(Theme.text)
                    .frame(width: 38, height: 38)
                    .glassCircle()
            }
            .accessibilityLabel("更多")
        }
        .padding(.top, 2)
    }

    // MARK: 日选择

    private var daySelector: some View {
        HStack(spacing: 5) {
            ForEach(1...7, id: \.self) { day in
                let count = slots(on: day).count
                let isSelected = selectedWeekday == day
                let isToday = day == TimetableMath.todayWeekday && currentWeek == (settings?.weekNumber() ?? 1)

                Button {
                    withAnimation(.snappy(duration: 0.18)) { selectedWeekday = day }
                } label: {
                    VStack(spacing: 5) {
                        Text(TimetableMath.weekdayName(day))
                            .font(.system(size: 11.5, weight: .medium))
                            .foregroundStyle(isSelected ? Theme.text : Theme.textSecondary)
                        Text("\(count)")
                            .font(.system(size: 19, weight: .medium))
                            .monospacedDigit()
                            .foregroundStyle(count == 0 ? Theme.textTertiary : Theme.text)
                        Circle()
                            .fill(isToday ? Theme.text : Color.clear)
                            .frame(width: 4, height: 4)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 9)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(isSelected ? Theme.text.opacity(0.12) : Theme.surface)
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: 当天的课

    private var dayList: some View {
        let items = slots(on: selectedWeekday)
        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 7) {
                Text(TimetableMath.weekdayName(selectedWeekday))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.text)
                if let settings {
                    Text(TimetableMath.dayText(selectedWeekday, week: currentWeek, settings: settings))
                        .font(.system(size: 11.5))
                        .foregroundStyle(Theme.textTertiary)
                }
                Spacer()
                Text("\(items.count) 节课")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Theme.textTertiary)
            }
            .padding(.horizontal, 2)
            .padding(.bottom, 10)

            if items.isEmpty {
                Text("这天没有课")
                    .font(.system(size: 12.5))
                    .foregroundStyle(Theme.textTertiary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 36)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(Theme.surface)
                    )
            } else {
                ForEach(items, id: \.slot.id) { item in
                    courseRow(item.course, item.slot)
                        .padding(.bottom, 8)
                }
            }
        }
    }

    private func courseRow(_ course: Course, _ slot: CourseSlot) -> some View {
        let tone = Theme.courseTone(course.shade)
        return Button {
            edit(course, slot)
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text(course.name)
                    .font(.system(size: 14.5, weight: .semibold))
                    .foregroundStyle(tone.fg)
                Text("\(slot.startPeriod)-\(slot.endPeriod) 节 · \(timeText(slot))")
                    .font(.system(size: 11.5))
                    .foregroundStyle(tone.fg.opacity(0.75))
                Text(metaText(course, slot))
                    .font(.system(size: 11))
                    .foregroundStyle(tone.fg.opacity(0.55))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 15)
            .padding(.vertical, 13)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(tone.bg)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: 网格

    private var gridCard: some View {
        VStack(spacing: 0) {
            dayHeader
            gridBody
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: Theme.cardCorner, style: .continuous)
                .fill(Theme.surface)
        )
    }

    private var dayHeader: some View {
        HStack(spacing: 0) {
            Text(TimetableMath.monthText(week: currentWeek, settings: settings))
                .font(.system(size: 10))
                .foregroundStyle(Theme.textTertiary)
                .frame(width: 34, alignment: .leading)

            ForEach(1...7, id: \.self) { day in
                let isToday = day == TimetableMath.todayWeekday && currentWeek == (settings?.weekNumber() ?? 1)
                VStack(spacing: 3) {
                    Text(TimetableMath.weekdayName(day))
                        .font(.system(size: 12, weight: isToday ? .semibold : .regular))
                        .foregroundStyle(isToday ? Theme.text : Theme.textSecondary)
                    Text(TimetableMath.dayNumber(day, week: currentWeek, settings: settings))
                        .font(.system(size: 11))
                        .foregroundStyle(isToday ? Theme.bg : Theme.textTertiary)
                        .frame(width: 24, height: 24)
                        .background(
                            Circle().fill(isToday ? Theme.text : Color.clear)
                        )
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.bottom, 8)
    }

    private var gridBody: some View {
        GeometryReader { geo in
            let columnWidth = max(0, (geo.size.width - 34) / 7)
            let totalHeight = CGFloat(periodCount) * rowHeight

            ZStack(alignment: .topLeading) {
                rows(columnWidth: columnWidth)
                blocks(columnWidth: columnWidth)
            }
            .frame(height: totalHeight)
        }
        .frame(height: CGFloat(periodCount) * rowHeight)
        .simultaneousGesture(
            MagnificationGesture()
                .onChanged { value in
                    rowHeight = min(72, max(30, pinchBase * value))
                }
                .onEnded { _ in
                    pinchBase = rowHeight
                }
        )
        .animation(.snappy(duration: 0.2), value: rowHeight)
    }

    private func rows(columnWidth: CGFloat) -> some View {
        VStack(spacing: 0) {
            ForEach(1...periodCount, id: \.self) { period in
                HStack(spacing: 0) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("\(period)")
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.textTertiary)
                        if let settings {
                            Text(settings.startText(ofPeriod: period))
                                .font(.system(size: 7.5))
                                .foregroundStyle(Theme.textTertiary.opacity(0.7))
                        }
                    }
                    .frame(width: 34, alignment: .leading)

                    ForEach(1...7, id: \.self) { _ in
                        Rectangle()
                            .fill(Color.clear)
                            .frame(maxWidth: .infinity)
                            .overlay(alignment: .top) {
                                Rectangle()
                                    .fill(Theme.stroke.opacity(0.7))
                                    .frame(height: 1)
                            }
                    }
                }
                .frame(height: rowHeight, alignment: .top)
            }
        }
    }

    private func blocks(columnWidth: CGFloat) -> some View {
        ForEach(activeSlots, id: \.slot.id) { item in
            let tone = Theme.courseTone(item.course.shade)
            let height = CGFloat(item.slot.periodSpan) * rowHeight - 4

            Button {
                edit(item.course, item.slot)
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.course.name)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(tone.fg)
                        .lineLimit(height > 60 ? 4 : 2)
                        .multilineTextAlignment(.leading)
                    if height > 46 {
                        Text(item.slot.location.isEmpty ? item.course.location : item.slot.location)
                            .font(.system(size: 8))
                            .foregroundStyle(tone.fg.opacity(0.6))
                            .lineLimit(1)
                    }
                }
                .padding(.horizontal, 4)
                .padding(.vertical, 4)
                .frame(width: max(0, columnWidth - 3), height: max(0, height), alignment: .topLeading)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(tone.bg)
                )
            }
            .buttonStyle(.plain)
            .offset(
                x: 34 + CGFloat(item.slot.weekday - 1) * columnWidth + 1.5,
                y: CGFloat(item.slot.startPeriod - 1) * rowHeight + 2
            )
        }
    }

    // MARK: 悬浮添加

    private var addButton: some View {
        Button {
            editingCourse = nil
            editingSlot = nil
            isEditorPresented = true
        } label: {
            Image(systemName: "file.badge.plus")
                .font(.system(size: 22, weight: .regular))
                .foregroundStyle(Theme.bg)
                .frame(width: 56, height: 56)
                .background(Circle().fill(Theme.text))
                .shadow(color: .black.opacity(0.18), radius: 16, y: 8)
        }
        .buttonStyle(PressableStyle())
        .padding(.trailing, 20)
        .padding(.bottom, 96)
        .accessibilityLabel("添加课程")
    }

    // MARK: 数据

    private var activeSlots: [SlotItem] {
        var items: [SlotItem] = []
        for course in courses {
            for slot in course.slots where slot.isActive(inWeek: currentWeek) {
                items.append(SlotItem(course: course, slot: slot))
            }
        }
        items.sort { lhs, rhs in
            if lhs.slot.weekday == rhs.slot.weekday {
                return lhs.slot.startPeriod < rhs.slot.startPeriod
            }
            return lhs.slot.weekday < rhs.slot.weekday
        }
        return items
    }

    private func slots(on weekday: Int) -> [SlotItem] {
        activeSlots
            .filter { $0.slot.weekday == weekday }
            .sorted { $0.slot.startPeriod < $1.slot.startPeriod }
    }

    private func timeText(_ slot: CourseSlot) -> String {
        guard let settings else { return "" }
        return "\(settings.startText(ofPeriod: slot.startPeriod))-\(settings.endText(ofPeriod: slot.endPeriod))"
    }

    private func metaText(_ course: Course, _ slot: CourseSlot) -> String {
        let location = slot.location.isEmpty ? course.location : slot.location
        let parts = [course.teacher, location].filter { !$0.isEmpty }
        return parts.joined(separator: " · ")
    }

    private func edit(_ course: Course, _ slot: CourseSlot) {
        editingCourse = course
        editingSlot = slot
        isEditorPresented = true
    }

    private var shareText: String {
        var lines = ["第 \(currentWeek) 周"]
        for day in 1...7 {
            let items = slots(on: day)
            guard !items.isEmpty else { continue }
            lines.append("")
            lines.append(TimetableMath.weekdayName(day))
            for item in items {
                let location = item.slot.location.isEmpty ? item.course.location : item.slot.location
                lines.append("  \(item.slot.startPeriod)-\(item.slot.endPeriod)节  \(item.course.name)  \(location)")
            }
        }
        return lines.joined(separator: "\n")
    }
}

// MARK: - 日期工具

enum TimetableMath {
    /// 周一 = 1 ... 周日 = 7
    static var todayWeekday: Int {
        let component = Calendar.current.component(.weekday, from: Date()) // 1 = 周日
        return ((component + 5) % 7) + 1
    }

    static func weekdayName(_ day: Int) -> String {
        ["一", "二", "三", "四", "五", "六", "日"][max(0, min(6, day - 1))]
    }

    static func date(_ day: Int, week: Int, settings: TimetableSettings?) -> Date? {
        guard let settings else { return nil }
        let monday = settings.monday(ofWeek: week)
        return Calendar.current.date(byAdding: .day, value: day - 1, to: monday)
    }

    static func dayNumber(_ day: Int, week: Int, settings: TimetableSettings?) -> String {
        guard let date = date(day, week: week, settings: settings) else { return "—" }
        return "\(Calendar.current.component(.day, from: date))"
    }

    static func dayText(_ day: Int, week: Int, settings: TimetableSettings?) -> String {
        dayNumber(day, week: week, settings: settings) + "日"
    }

    static func monthText(week: Int, settings: TimetableSettings?) -> String {
        guard let settings, let monday = Optional(settings.monday(ofWeek: week)) else { return "" }
        let month = Calendar.current.component(.month, from: monday)
        return "\(month)月"
    }
}
