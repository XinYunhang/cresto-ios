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

/// sheet 一次带走「课程 + 时段」，避免 isPresented 和两个可选状态分步更新时
/// 内容闭包读到旧值（点课程却显示成「添加课程」）。
private struct CourseEditorContext: Identifiable {
    let id = UUID()
    let course: Course?
    let slot: CourseSlot?
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
    @State private var editorContext: CourseEditorContext?
    @State private var isImportPresented = false
    @State private var isJSONImportPresented = false
    @State private var isManagePresented = false
    @State private var rowHeight: CGFloat = 46
    /// 捏合开始时锁定的行高；手势进行中不随 rowHeight 漂移
    @State private var pinchBase: CGFloat?
    @State private var now = Date()
    @Environment(\.scenePhase) private var scenePhase
    private let liveTicker = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    private var settings: TimetableSettings? { settingsList.first }
    private var currentWeek: Int { week ?? settings?.weekNumber(for: now) ?? 1 }
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
            .padding(.bottom, Theme.bottomScrollInset)
        }
        .onReceive(liveTicker) { _ in
            guard scenePhase == .active else { return }
            now = Date()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { now = Date() }
        }
        .simultaneousGesture(zoomGesture)
        .floatingAddButton("添加课程") {
            editorContext = CourseEditorContext(course: nil, slot: nil)
        }
        .sheet(item: $editorContext) { context in
            if let course = context.course, let slot = context.slot {
                CourseDetailSheet(course: course, slot: slot, displayWeek: currentWeek)
            } else {
                CourseEditor(course: nil, slot: nil)
            }
        }
        .sheet(isPresented: $isImportPresented) {
            TimetableImportView()
        }
        .sheet(isPresented: $isJSONImportPresented) {
            TimetableJSONImportView()
        }
        .sheet(isPresented: $isManagePresented) {
            TimetableSettingsView()
        }
    }

    /// 双指捏合：只改网格行高。手势挂在稳定的 ScrollView 上，
    /// 不跟着会重排的网格内容一起重建；开始捏合时锁定基准行高。
    private var zoomGesture: some Gesture {
        MagnifyGesture(minimumScaleDelta: 0.01)
            .onChanged { value in
                guard mode == .grid else { return }
                let base = pinchBase ?? rowHeight
                if pinchBase == nil { pinchBase = base }
                rowHeight = min(84, max(28, base * value.magnification))
            }
            .onEnded { _ in
                pinchBase = nil
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
                ReiconIcon(icon: mode == .list ? .gridCells : .list, size: 20.5)
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
                            Label { Text("第 \(index) 周") } icon: { ReiconIcon(icon: .check, size: 14) }
                        } else {
                            Text("第 \(index) 周")
                        }
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Text("第 \(currentWeek) 周")
                        .font(.system(size: 17, weight: .semibold))
                    ReiconIcon(icon: .chevronDown, size: 14.5)
                        .foregroundStyle(Theme.textTertiary)
                }
                .foregroundStyle(Theme.text)
            }

            Spacer(minLength: 0)

            Menu {
                Button {
                    isManagePresented = true
                } label: {
                    Label { Text("课表管理") } icon: { ReiconIcon(icon: .gridCells, size: 15) }
                }
                Button {
                    isImportPresented = true
                } label: {
                    Label { Text("截图识别导入") } icon: { ReiconIcon(icon: .image, size: 15) }
                }
                Button {
                    isJSONImportPresented = true
                } label: {
                    Label { Text("喜鹊课表 JSON 导入") } icon: { ReiconIcon(icon: .download, size: 15) }
                }
                ShareLink(item: shareText) {
                    Label { Text("分享课表") } icon: { ReiconIcon(icon: .share, size: 15) }
                }
            } label: {
                ReiconIcon(icon: .moreHorizontal, size: 20.5)
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
                let isToday = day == TimetableMath.todayWeekday && currentWeek == (settings?.weekNumber(for: now) ?? 1)

                Button {
                    withAnimation(.snappy(duration: 0.18)) { selectedWeekday = day }
                } label: {
                    VStack(spacing: 5) {
                        Text(TimetableMath.weekdayName(day))
                            .font(.system(size: 11.5, weight: isSelected ? .semibold : .medium))
                            .foregroundStyle(isSelected ? Theme.brand : Theme.textSecondary)
                        Text("\(count)")
                            .font(.system(size: 19, weight: isSelected ? .semibold : .medium))
                            .monospacedDigit()
                            .foregroundStyle(isSelected ? Theme.brand : (count == 0 ? Theme.textTertiary : Theme.text))
                        Circle()
                            .fill(isToday ? Theme.brand : Color.clear)
                            .frame(width: 4, height: 4)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 9)
                    .cardElevation(
                        radius: AppRadius.item,
                        fill: isSelected ? Theme.brandSoft : Theme.surface
                    )
                    .overlay {
                        if isSelected {
                            RoundedRectangle(cornerRadius: AppRadius.item, style: .continuous)
                                .strokeBorder(Theme.brand.opacity(0.32), lineWidth: 0.8)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: 当天的课

    private var dayList: some View {
        let items = slots(on: selectedWeekday)
        let isViewingToday = selectedWeekday == TimetableMath.todayWeekday
            && currentWeek == (settings?.weekNumber(for: now) ?? 1)
        let nextUpcomingID: UUID? = isViewingToday ? items.first(where: {
            if case .upcoming = TimetableLiveMath.status(for: $0.slot, isToday: true, settings: settings, now: now) {
                return true
            }
            return false
        })?.slot.id : nil

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
                    .cardElevation(radius: AppRadius.item)
            } else {
                ForEach(items, id: \.slot.id) { item in
                    let live = TimetableLiveMath.status(
                        for: item.slot,
                        isToday: isViewingToday,
                        settings: settings,
                        now: now
                    )
                    courseRow(
                        item.course,
                        item.slot,
                        liveStatus: live,
                        isNextUpcoming: item.slot.id == nextUpcomingID
                    )
                    .padding(.bottom, 8)
                }
            }
        }
    }

    private func courseRow(
        _ course: Course,
        _ slot: CourseSlot,
        liveStatus: CourseLiveStatus?,
        isNextUpcoming: Bool
    ) -> some View {
        let tone = Theme.courseTone(course.shade)
        let isOngoing: Bool = {
            if case .ongoing = liveStatus { return true }
            return false
        }()
        let isEnded = liveStatus == .ended
        let isHighlighted = isOngoing || isNextUpcoming

        return Button {
            edit(course, slot)
        } label: {
            HStack(spacing: 0) {
                if isHighlighted {
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(tone.fg)
                        .frame(width: 3.5)
                        .padding(.vertical, 10)
                        .padding(.leading, 8)
                }

                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .center, spacing: 8) {
                        Text(course.name)
                            .font(.system(size: 14.5, weight: .semibold))
                            .foregroundStyle(tone.fg)
                            .lineLimit(1)

                        Spacer(minLength: 4)

                        if let badge = statusBadgeText(liveStatus, isNextUpcoming: isNextUpcoming) {
                            Text(badge)
                                .font(.system(size: 10.5, weight: .medium))
                                .monospacedDigit()
                                .foregroundStyle(isOngoing ? Color.white : tone.fg)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(
                                    Capsule().fill(isOngoing ? tone.fg : tone.fg.opacity(0.14))
                                )
                        }
                    }

                    Text("第 \(slot.startPeriod)-\(slot.endPeriod) 节")
                        .font(.system(size: 11.5, weight: .medium, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(tone.fg.opacity(0.78))

                    Text(metaText(course, slot))
                        .font(.system(size: 11))
                        .foregroundStyle(tone.fg.opacity(0.60))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, isHighlighted ? 10 : 15)
                .padding(.trailing, 15)
                .padding(.vertical, 13)
            }
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: AppRadius.item, style: .continuous)
                        .fill(
                            isHighlighted
                                ? LinearGradient(
                                    colors: [tone.bg, tone.bg.opacity(0.78)],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                                : LinearGradient(
                                    colors: [tone.bg, tone.bg],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                        )
                    RoundedRectangle(cornerRadius: AppRadius.item, style: .continuous)
                        .strokeBorder(
                            isOngoing ? tone.fg.opacity(0.32) : Color.white.opacity(0.35),
                            lineWidth: isOngoing ? 1 : 0.5
                        )
                }
            )
            .shadow(
                color: Color.black.opacity(isHighlighted ? 0.06 : 0.03),
                radius: isHighlighted ? 10 : 6,
                y: 3
            )
            .opacity(isEnded ? 0.50 : 1)
        }
        .buttonStyle(.plain)
    }

    private func statusBadgeText(_ status: CourseLiveStatus?, isNextUpcoming: Bool) -> String? {
        guard let status else { return nil }
        switch status {
        case .ongoing(_, let remaining):
            return "正在上 · 剩 \(remaining)m"
        case .upcoming(let minutes):
            guard isNextUpcoming else { return nil }
            if minutes < 60 { return "\(minutes) 分钟后" }
            let h = minutes / 60
            let m = minutes % 60
            return m == 0 ? "\(h) 小时后" : "\(h)h\(m)m 后"
        case .ended:
            return "已结束"
        }
    }

    // MARK: 网格

    private var gridCard: some View {
        VStack(spacing: 0) {
            dayHeader
            gridBody

            Text("双指捏合调整行高")
                .font(.system(size: 9.5))
                .foregroundStyle(Theme.textTertiary)
                .padding(.top, 9)
                .padding(.bottom, 2)
        }
        .padding(8)
        .cardElevation(radius: AppRadius.card)
    }

    private var dayHeader: some View {
        HStack(spacing: 0) {
            Text(TimetableMath.monthText(week: currentWeek, settings: settings))
                .font(.system(size: 10))
                .foregroundStyle(Theme.textTertiary)
                .frame(width: 28, alignment: .leading)

            ForEach(1...7, id: \.self) { day in
                let isToday = day == TimetableMath.todayWeekday && currentWeek == (settings?.weekNumber(for: now) ?? 1)
                VStack(spacing: 3) {
                    Text(TimetableMath.weekdayName(day))
                        .font(.system(size: 12, weight: isToday ? .semibold : .regular))
                        .foregroundStyle(isToday ? Theme.brand : Theme.textSecondary)
                    Text(TimetableMath.dayNumber(day, week: currentWeek, settings: settings))
                        .font(.system(size: 11, weight: isToday ? .semibold : .regular))
                        .foregroundStyle(isToday ? Color.white : Theme.textTertiary)
                        .frame(width: 24, height: 24)
                        .background(
                            Circle().fill(isToday ? Theme.brand : Color.clear)
                        )
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.bottom, 8)
    }

    private var gridBody: some View {
        GeometryReader { geo in
            let columnWidth = max(0, (geo.size.width - 28) / 7)
            let totalHeight = CGFloat(periodCount) * rowHeight

            ZStack(alignment: .topLeading) {
                rows(columnWidth: columnWidth)
                blocks(columnWidth: columnWidth)
            }
            .frame(height: totalHeight)
        }
        .frame(height: CGFloat(periodCount) * rowHeight)
    }

    private func rows(columnWidth: CGFloat) -> some View {
        VStack(spacing: 0) {
            ForEach(1...periodCount, id: \.self) { period in
                HStack(spacing: 0) {
                    Text("\(period)")
                        .font(.system(size: 11, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(Theme.textTertiary)
                        .frame(width: 28, alignment: .leading)

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
        let isCurrentWeek = currentWeek == (settings?.weekNumber(for: now) ?? 1)
        let today = TimetableMath.todayWeekday

        return ForEach(activeSlots, id: \.slot.id) { item in
            let tone = Theme.courseTone(item.course.shade)
            let height = CGFloat(item.slot.periodSpan) * rowHeight - 4
            let live = TimetableLiveMath.status(
                for: item.slot,
                isToday: isCurrentWeek && item.slot.weekday == today,
                settings: settings,
                now: now
            )
            let isOngoing: Bool = {
                if case .ongoing = live { return true }
                return false
            }()
            let isEnded = live == .ended

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
                    RoundedRectangle(cornerRadius: AppRadius.grid, style: .continuous)
                        .fill(tone.bg)
                )
                .overlay {
                    if isOngoing {
                        RoundedRectangle(cornerRadius: AppRadius.grid, style: .continuous)
                            .strokeBorder(tone.fg, lineWidth: 1.5)
                    }
                }
                .opacity(isEnded ? 0.52 : 1)
            }
            .buttonStyle(.plain)
            .offset(
                x: 28 + CGFloat(item.slot.weekday - 1) * columnWidth + 1.5,
                y: CGFloat(item.slot.startPeriod - 1) * rowHeight + 2
            )
        }
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
        editorContext = CourseEditorContext(course: course, slot: slot)
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
