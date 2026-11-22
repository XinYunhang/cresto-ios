import SwiftUI

// MARK: - 底栏

enum AppTab: String, CaseIterable, Identifiable {
    case overview, tasks, course, api

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview: return "概览"
        case .tasks: return "待办"
        case .course: return "课表"
        case .api: return "API"
        }
    }

    var symbol: String {
        switch self {
        case .overview: return "square.grid.2x2"
        case .tasks: return "checkmark.circle"
        case .course: return "tablecells"
        case .api: return "cpu"
        }
    }
}
