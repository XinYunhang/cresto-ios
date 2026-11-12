import SwiftUI
import SwiftData

struct SearchView: View {
    @Environment(\.dismiss) private var dismiss

    @Query(sort: \TaskItem.createdAt, order: .reverse) private var tasks: [TaskItem]
    @Query private var courses: [Course]

    @State private var text = ""
    @State private var editing: TaskItem?
    @FocusState private var focused: Bool

    private var keyword: String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var matchedTasks: [TaskItem] {
        guard !keyword.isEmpty else { return [] }
        return tasks.filter { $0.title.localizedCaseInsensitiveContains(keyword) }.prefix(8).map { $0 }
    }

    private var matchedCourses: [Course] {
        guard !keyword.isEmpty else { return [] }
        return courses.filter {
            $0.name.localizedCaseInsensitiveContains(keyword)
                || $0.location.localizedCaseInsensitiveContains(keyword)
                || $0.teacher.localizedCaseInsensitiveContains(keyword)
        }
    }

    private var matchedCards: [TarotCard] {
        guard !keyword.isEmpty else { return [] }
        return TarotDeck.major.filter {
            $0.name.contains(keyword)
                || $0.en.localizedCaseInsensitiveContains(keyword)
                || $0.uprightKeywords.joined().contains(keyword)
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack(spacing: 9) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 15))
                        .foregroundStyle(Theme.textTertiary)
                    TextField("待办、课程、塔罗牌", text: $text)
                        .focused($focused)
                        .font(.system(size: 15))
                        .foregroundStyle(Theme.text)
                        .submitLabel(.search)
                    if !text.isEmpty {
                        Button {
                            text = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 15))
                                .foregroundStyle(Theme.textTertiary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 14)
                .frame(height: 44)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Theme.surface)
                )
                .padding(.horizontal, Theme.screenPadding)
                .padding(.top, 8)

                ScrollView {
                    VStack(spacing: Theme.cardGap) {
                        if keyword.isEmpty {
                            Text("输入关键词：待办标题、课程名或牌子")
                                .font(.system(size: 12.5))
                                .foregroundStyle(Theme.textTertiary)
                                .frame(maxWidth: .infinity)
                                .padding(.top, 40)
                        } else if matchedTasks.isEmpty && matchedCourses.isEmpty && matchedCards.isEmpty {
                            Text("没有找到「\(keyword)」")
                                .font(.system(size: 12.5))
                                .foregroundStyle(Theme.textTertiary)
                                .frame(maxWidth: .infinity)
                                .padding(.top, 40)
                        }

                        if !matchedTasks.isEmpty {
                            resultCard("待办", count: matchedTasks.count) {
                                ForEach(matchedTasks) { task in
                                    Button {
                                        editing = task
                                    } label: {
                                        row(title: task.title,
                                            subtitle: task.dueDate?.taskLabel(hasTime: task.hasTime) ?? "未安排")
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }

                        if !matchedCourses.isEmpty {
                            resultCard("课程", count: matchedCourses.count) {
                                ForEach(matchedCourses) { course in
                                    row(title: course.name,
                                        subtitle: [course.teacher, course.location].filter { !$0.isEmpty }.joined(separator: " · "))
                                }
                            }
                        }

                        if !matchedCards.isEmpty {
                            resultCard("塔罗", count: matchedCards.count) {
                                ForEach(matchedCards) { card in
                                    row(title: "\(card.name) \(card.en)", subtitle: card.uprightKeywords.joined(separator: " · "))
                                }
                            }
                        }
                    }
                    .padding(.horizontal, Theme.screenPadding)
                    .padding(.top, 12)
                    .padding(.bottom, 30)
                }
            }
            .background(Theme.bg)
            .navigationTitle("搜索")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }.foregroundStyle(Theme.text)
                }
            }
            .tint(Theme.text)
            .sheet(item: $editing) { task in
                TaskEditor(task: task)
            }
        }
        .presentationBackground(Theme.bg)
        .onAppear { focused = true }
    }

    private func resultCard<Content: View>(_ title: String, count: Int, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(title).cardLabel()
                Spacer()
                Text("\(count)").font(.system(size: 11)).monospacedDigit().foregroundStyle(Theme.textTertiary)
            }
            .padding(.bottom, 6)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }

    private func row(title: String, subtitle: String) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.textTertiary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
    }
}
