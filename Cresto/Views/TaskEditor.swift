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
    @State private var priority: TaskPriority
    @State private var reminder: ReminderOffset
    @State private var repeatKind: RepeatKind
    @State private var tagsText: String
    @State private var drafts: [DraftSubtask]

    @FocusState private var titleFocused: Bool

    init(task: TaskItem? = nil, defaultDate: Date? = nil, defaultTitle: String = "") {
        self.task = task

        let seedDate = task?.dueDate ?? defaultDate ?? Date()
        _title = State(initialValue: task?.title ?? defaultTitle)
        _notes = State(initialValue: task?.notes ?? "")
        _hasDate = State(initialValue: task?.dueDate != nil || defaultDate != nil)
        _dueDate = State(initialValue: seedDate)
        _hasTime = State(initialValue: task?.hasTime ?? false)
        _priority = State(initialValue: task?.priority ?? .none)
        _reminder = State(initialValue: task?.reminder ?? .none)
        _repeatKind = State(initialValue: task?.repeatKind ?? .none)
        _tagsText = State(initialValue: task?.tags.joined(separator: ", ") ?? "")
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

    // MARK: 标题

    private var titleCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField("要做点什么？", text: $title, axis: .vertical)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(Theme.text)
                .focused($titleFocused)
                .lineLimit(1...3)

            HStack(spacing: 6) {
                ForEach([TaskPriority.none, .low, .high], id: \.id) { item in
                    let selected = priority == item
                    Button {
                        withAnimation(.snappy(duration: 0.2)) { priority = item }
                    } label: {
                        HStack(spacing: 4) {
                            if item == .high {
                                Image(systemName: "exclamationmark").font(.system(size: 9, weight: .bold))
                            }
                            Text(item.title)
                        }
                        .font(.system(size: 11.5))
                        .foregroundStyle(selected ? Theme.bg : Theme.textSecondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(
                            Capsule().fill(selected ? Theme.ink : Color.white.opacity(0.05))
                        )
                        .overlay(
                            Capsule().strokeBorder(selected ? Color.clear : Theme.stroke, lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
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

    private var attributesCard: some View {
        VStack(spacing: 0) {
            HStack {
                Text("提醒").font(.system(size: 13.5)).foregroundStyle(Theme.text)
                Spacer()
                Picker("提醒", selection: $reminder) {
                    ForEach(ReminderOffset.allCases) { offset in
                        Text(offset.title).tag(offset)
                    }
                }
                .pickerStyle(.menu)
                .tint(Theme.textSecondary)
                .disabled(!hasDate)
            }
            .padding(.vertical, 9)

            divider

            HStack {
                Text("重复").font(.system(size: 13.5)).foregroundStyle(Theme.text)
                Spacer()
                Picker("重复", selection: $repeatKind) {
                    ForEach(RepeatKind.allCases) { kind in
                        Text(kind.title).tag(kind)
                    }
                }
                .pickerStyle(.menu)
                .tint(Theme.textSecondary)
                .disabled(!hasDate)
            }
            .padding(.vertical, 9)

            divider

            VStack(alignment: .leading, spacing: 8) {
                Text("标签").font(.system(size: 13.5)).foregroundStyle(Theme.text)
                TextField("用逗号分隔，比如：开发, 习惯", text: $tagsText)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.textSecondary)
                    .autocorrectionDisabled()

                if !parsedTags.isEmpty {
                    HStack(spacing: 6) {
                        ForEach(parsedTags, id: \.self) { tag in
                            AccentChip(text: tag)
                        }
                    }
                }
            }
            .padding(.vertical, 9)
        }
        .cardSurface()
    }

    private var divider: some View {
        Rectangle().fill(Color.white.opacity(0.06)).frame(height: 1)
    }

    private var parsedTags: [String] {
        tagsText
            .split(whereSeparator: { $0 == "," || $0 == "，" })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
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
            TextField("补充一点细节", text: $notes, axis: .vertical)
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
                    RoundedRectangle(cornerRadius: 15, style: .continuous)
                        .fill(Color.white.opacity(0.04))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 15, style: .continuous)
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
        target.priority = priority
        target.reminder = hasDate ? reminder : .none
        target.repeatKind = hasDate ? repeatKind : .none
        target.tags = parsedTags

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
