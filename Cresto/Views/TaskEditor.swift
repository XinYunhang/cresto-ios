import SwiftUI
import SwiftData

/// 完整编辑页：标题、备注、日期 + 具体时间、提醒、优先级、重复、标签、子任务。
/// 从 FAB / 待办行 / 主页待办卡进来都是这一个页面。
struct TaskEditor: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    let task: TaskItem?

    @State private var title: String
    @State private var notes: String
    @State private var hasDate: Bool
    @State private var dueDate: Date
    @State private var hasTime: Bool
    @State private var urgency: TaskUrgency
    @State private var reminder: ReminderOffset
    @State private var repeatKind: RepeatKind
    @State private var tags: [String]
    @State private var isAddingTag = false
    @State private var tagDraft = ""
    @State private var drafts: [DraftSubtask]

    @FocusState private var titleFocused: Bool

    init(
        task: TaskItem? = nil,
        defaultDate: Date? = nil,
        defaultTitle: String = "",
        defaultUrgency: TaskUrgency = .low
    ) {
        self.task = task

        let seedDate = task?.dueDate ?? defaultDate ?? Date()
        _title = State(initialValue: task?.title ?? defaultTitle)
        _notes = State(initialValue: task?.notes ?? "")
        _hasDate = State(initialValue: task?.dueDate != nil || defaultDate != nil)
        _dueDate = State(initialValue: seedDate)
        _hasTime = State(initialValue: task?.hasTime ?? false)
        _urgency = State(initialValue: task?.urgency ?? defaultUrgency)
        _reminder = State(initialValue: task?.reminder ?? .none)
        _repeatKind = State(initialValue: task?.repeatKind ?? .none)
        _tags = State(initialValue: task?.tags ?? [])
        _drafts = State(
            initialValue: (task?.subtasks.sorted { $0.order < $1.order } ?? []).map {
                DraftSubtask(title: $0.title, isDone: $0.isDone)
            }
        )
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Theme.cardGap) {
                    titleCard
                    timeCard
                    attributesCard
                    subtaskCard
                    notesCard
                    if task != nil { deleteButton }
                }
                .padding(.horizontal, Theme.screenPadding)
                .padding(.vertical, 12)
            }
            .background(Theme.bg)
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(task == nil ? "新建待办" : "编辑待办")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                        .foregroundStyle(Theme.textSecondary)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }
                        .fontWeight(.semibold)
                        .foregroundStyle(canSave ? Theme.text : Theme.textTertiary)
                        .disabled(!canSave)
                }
            }
            .tint(Theme.ink)
        }
        .presentationBackground(Theme.bg)
        .onAppear {
            if task == nil { titleFocused = true }
        }
    }

    private var canSave: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // MARK: 顶部卡（要做点什么？ + 紧急程度三档滑块，设计图：同一张深灰卡，0.5pt 细分割）

    private var titleCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            TextField("要做点什么？", text: $title, axis: .vertical)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(Theme.text)
                .focused($titleFocused)
                .lineLimit(1...3)
                .padding(.vertical, 14)

            Rectangle()
                .fill(Color.white.opacity(0.08))
                .frame(height: 0.5)

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("紧急程度")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textSecondary)
                    Spacer()
                    Text(urgency.title)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(urgency.tint)
                        .animation(.snappy(duration: 0.2), value: urgency)
                }
                UrgencySlider(selection: $urgency)
            }
            .padding(.vertical, 12)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.card, style: .continuous))
    }

    // MARK: 时间

    private var timeCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("时间").cardLabel()
                Spacer()
                if hasDate {
                    Button("清除") {
                        withAnimation(.snappy(duration: 0.2)) {
                            hasDate = false
                            hasTime = false
                            reminder = .none
                        }
                    }
                    .font(.system(size: 11.5))
                    .foregroundStyle(Theme.textTertiary)
                }
            }

            if hasDate {
                HStack(spacing: 10) {
                    DatePicker("日期", selection: $dueDate, displayedComponents: .date)
                        .datePickerStyle(.compact)
                        .labelsHidden()
                        .environment(\.locale, Locale(identifier: "zh_CN"))

                    Spacer(minLength: 0)

                    Toggle("", isOn: $hasTime.animation(.snappy(duration: 0.2)))
                        .labelsHidden()
                        .tint(Theme.ink)
                        .scaleEffect(0.9)

                    Text("具体时间")
                        .font(.system(size: 12.5))
                        .foregroundStyle(hasTime ? Theme.text : Theme.textTertiary)
                }

                if hasTime {
                    DatePicker("时间", selection: $dueDate, displayedComponents: .hourAndMinute)
                        .datePickerStyle(.compact)
                        .labelsHidden()
                        .environment(\.locale, Locale(identifier: "zh_CN"))
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }

                quickDateChips
            } else {
                Button {
                    withAnimation(.snappy(duration: 0.2)) {
                        hasDate = true
                        dueDate = DefaultDueDate.nextHour()
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "calendar").font(.system(size: 12))
                        Text("添加日期和时间")
                        Spacer()
                        Image(systemName: "plus").font(.system(size: 11, weight: .medium))
                    }
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.textSecondary)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
        .onChange(of: hasTime) { _, newValue in
            if newValue, reminder == .none { reminder = .onTime }
        }
    }

    private var quickDateChips: some View {
        HStack(spacing: 6) {
            chipButton("今天") { setDay(0) }
            chipButton("明天") { setDay(1) }
            chipButton("下周一") {
                let calendar = Calendar.current
                let next = calendar.nextDate(
                    after: Date(),
                    matching: DateComponents(weekday: 2),
                    matchingPolicy: .nextTime
                ) ?? Date()
                dueDate = next
                hasDate = true
            }
            Spacer()
        }
    }

    private func chipButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11.5))
                .foregroundStyle(Theme.textSecondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Capsule().fill(Color.white.opacity(0.05)))
                .overlay(Capsule().strokeBorder(Theme.stroke, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private func setDay(_ offset: Int) {
        let calendar = Calendar.current
        let base = calendar.date(byAdding: .day, value: offset, to: Date()) ?? Date()
        dueDate = base
        hasDate = true
    }

    // MARK: 提醒 / 重复 / 标签

    /// 三行统一排版：左侧标签与右侧内容同字号（13.5），固定最小行高 44 + 等距分隔线，基线对齐
    private var attributesCard: some View {
        VStack(spacing: 0) {
            attributeRow("提醒") {
                valueMenu(title: reminder.title, disabled: !hasDate) {
                    ForEach(ReminderOffset.allCases) { offset in
                        menuButton(offset.title, isSelected: reminder == offset) {
                            reminder = offset
                        }
                    }
                }
            }

            divider

            attributeRow("重复") {
                valueMenu(title: repeatKind.title, disabled: !hasDate) {
                    ForEach(RepeatKind.allCases) { kind in
                        menuButton(kind.title, isSelected: repeatKind == kind) {
                            repeatKind = kind
                        }
                    }
                }
            }

            divider

            tagRow
        }
        .cardSurface()
        .alert("添加标签", isPresented: $isAddingTag) {
            TextField("5 个字以内", text: $tagDraft)
            Button("添加") { commitTag() }
            Button("取消", role: .cancel) {}
        } message: {
            Text("短标签就好，最多 5 个字；拼音组合态以最终确认的文字为准")
        }
    }

    private func attributeRow<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 13.5))
                .foregroundStyle(Theme.text)
            Spacer(minLength: 8)
            content()
        }
        .frame(minHeight: 52)
        .padding(.horizontal, 2)
    }

    /// 右侧值：与左标签同字号，点开菜单选
    private func valueMenu<Content: View>(title: String, disabled: Bool, @ViewBuilder items: () -> Content) -> some View {
        Menu {
            items()
        } label: {
            HStack(spacing: 5) {
                Text(title)
                    .font(.system(size: 13.5))
                    .foregroundStyle(disabled ? Theme.textTertiary : Theme.textSecondary)
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Theme.textTertiary)
            }
        }
        .disabled(disabled)
    }

    private func menuButton(_ title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            if isSelected {
                Label(title, systemImage: "checkmark")
            } else {
                Text(title)
            }
        }
    }

    // MARK: 标签

    private var tagRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("标签")
                    .font(.system(size: 13.5))
                    .foregroundStyle(Theme.text)
                Spacer(minLength: 8)

                Button {
                    isAddingTag = true
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Theme.text)
                        .frame(width: 26, height: 26)
                        .background(Circle().fill(Color.white.opacity(0.06)))
                        .overlay(Circle().strokeBorder(Theme.stroke, lineWidth: 1))
                }
                .buttonStyle(PressableStyle())
                .accessibilityLabel("添加标签")
            }

            if !tags.isEmpty {
                ChipFlowLayout(spacing: 6) {
                    ForEach(tags, id: \.self) { tag in
                        tagChip(tag)
                    }
                }
                .transition(.opacity.combined(with: .scale(scale: 0.95, anchor: .leading)))
            }
        }
        .frame(minHeight: 52, alignment: .leading)
        .padding(.horizontal, 2)
        .padding(.vertical, 8)
        .animation(.snappy(duration: 0.22), value: tags)
    }

    private func tagChip(_ tag: String) -> some View {
        HStack(spacing: 5) {
            Text(tag)
                .font(.system(size: 11.5))
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(1)
            Button {
                withAnimation(.snappy(duration: 0.2)) {
                    tags.removeAll { $0 == tag }
                }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 7.5, weight: .bold))
                    .foregroundStyle(Theme.textTertiary)
                    .frame(width: 13, height: 13)
                    .background(Circle().fill(Color.white.opacity(0.10)))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("移除标签 \(tag)")
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(Capsule().fill(Color.white.opacity(0.06)))
        .overlay(Capsule().strokeBorder(Theme.stroke, lineWidth: 1))
    }

    /// 兼容中文输入法：拼音组合态不做实时截断，只在最终确认时校验，超长按字符截断到 5
    private func commitTag() {
        var text = tagDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        tagDraft = ""
        guard !text.isEmpty else { return }
        if text.count > 5 {
            text = String(text.prefix(5))
        }
        if !tags.contains(text) {
            withAnimation(.snappy(duration: 0.2)) {
                tags.append(text)
            }
        }
    }

    private var divider: some View {
        // 设计图：0.5pt 细分线，三行等距
        Rectangle().fill(Color.white.opacity(0.08)).frame(height: 0.5)
    }

    // MARK: 子任务

    private var subtaskCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("子任务").cardLabel()
                Spacer()
                if !drafts.isEmpty {
                    Text("\(drafts.filter(\.isDone).count)/\(drafts.count)")
                        .font(.system(size: 11.5))
                        .monospacedDigit()
                        .foregroundStyle(Theme.textTertiary)
                }
            }
            .padding(.bottom, 10)

            ForEach($drafts) { $draft in
                HStack(spacing: 10) {
                    Button {
                        draft.isDone.toggle()
                    } label: {
                        Image(systemName: draft.isDone ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 17))
                            .foregroundStyle(draft.isDone ? Theme.ink : Theme.textTertiary)
                    }
                    .buttonStyle(.plain)

                    TextField("子任务", text: $draft.title)
                        .font(.system(size: 13.5))
                        .foregroundStyle(draft.isDone ? Theme.textTertiary : Theme.text)
                        .strikethrough(draft.isDone, color: Theme.textTertiary)

                    Button {
                        drafts.removeAll { $0.id == draft.id }
                    } label: {
                        Image(systemName: "minus.circle")
                            .font(.system(size: 14))
                            .foregroundStyle(Theme.textTertiary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.vertical, 7)
            }

            Button {
                drafts.append(DraftSubtask(title: "", isDone: false))
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "plus").font(.system(size: 11, weight: .medium))
                    Text("添加子任务")
                    Spacer()
                }
                .font(.system(size: 12.5))
                .foregroundStyle(Theme.textTertiary)
                .padding(.top, 8)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .cardSurface()
    }

    // MARK: 备注

    private var notesCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("备注").cardLabel()
            TextField("", text: $notes, axis: .vertical)
                .font(.system(size: 13.5))
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(2...6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }

    private var deleteButton: some View {
        Button {
            if let task {
                TaskActions.delete(task, in: context)
            }
            dismiss()
        } label: {
            Text("删除待办")
                .font(.system(size: 13.5))
                .foregroundStyle(Theme.textSecondary)
                .frame(maxWidth: .infinity)
                .frame(height: 46)
                .background(
                    RoundedRectangle(cornerRadius: AppRadius.item, style: .continuous)
                        .fill(Color.white.opacity(0.04))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: AppRadius.item, style: .continuous)
                        .strokeBorder(Theme.stroke, lineWidth: 1)
                )
        }
        .buttonStyle(PressableStyle())
        .padding(.top, 4)
    }

    // MARK: 保存

    private func save() {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else { return }

        let target = task ?? TaskItem()
        target.title = trimmedTitle
        target.notes = notes
        target.dueDate = hasDate ? dueDate : nil
        target.hasTime = hasDate && hasTime
        target.urgency = urgency
        target.reminder = hasDate ? reminder : .none
        target.repeatKind = hasDate ? repeatKind : .none
        target.tags = tags

        // 子任务整体重建，简单可靠
        for existing in target.subtasks {
            context.delete(existing)
        }
        target.subtasks = drafts
            .filter { !$0.title.trimmingCharacters(in: .whitespaces).isEmpty }
            .enumerated()
            .map { index, draft in
                let subtask = Subtask(title: draft.title, order: index)
                subtask.isDone = draft.isDone
                return subtask
            }

        if task == nil {
            context.insert(target)
        }

        NotificationScheduler.sync(target)
        try? context.save()
        AppLog.info((task == nil ? "新建待办：" : "编辑待办：") + target.title)
        dismiss()
    }
}

struct DraftSubtask: Identifiable {
    let id = UUID()
    var title: String
    var isDone: Bool
}

private enum DefaultDueDate {
    static func nextHour() -> Date {
        let calendar = Calendar.current
        let next = calendar.date(bySetting: .minute, value: 0, of: Date()) ?? Date()
        return calendar.date(byAdding: .hour, value: 1, to: next) ?? Date()
    }
}
