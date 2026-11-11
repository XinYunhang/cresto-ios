import Foundation
import UIKit
import Vision

/// 从课表截图里把「星期 / 节次 / 课名」抠出来。
///
/// 做法：Vision 认字 → 用「周一…周日」定位列、用左侧「1 / 1-2」定位行 →
/// 其余文字按坐标落格 → 同一格的文字合并。
/// 识别是启发式的，所以导入前一定会给一个可以逐条改的预览。
struct ImportedCourse: Identifiable, Sendable {
    let id = UUID()
    var weekday: Int
    var startPeriod: Int
    var endPeriod: Int
    var title: String
    var location: String = ""
    var isIncluded: Bool = true
}

enum OCRError: LocalizedError {
    case invalidImage
    case noGrid
    case empty

    var errorDescription: String? {
        switch self {
        case .invalidImage: return "图片读不出来"
        case .noGrid: return "没认出节次列，换一张完整的课表截图试试"
        case .empty: return "没认出任何课程"
        }
    }
}

enum TimetableOCR {
    static func recognize(imageData: Data) async throws -> [ImportedCourse] {
        try await Task.detached(priority: .userInitiated) {
            try perform(imageData: imageData)
        }.value
    }

    // MARK: 主流程

    private static func perform(imageData: Data) throws -> [ImportedCourse] {
        guard let image = UIImage(data: imageData), let cgImage = image.cgImage else {
            throw OCRError.invalidImage
        }

        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["zh-Hans", "en-US"]
        request.usesLanguageCorrection = true

        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        try handler.perform([request])

        let items: [Item] = (request.results ?? []).compactMap { observation in
            guard let text = observation.topCandidates(1).first?.string else { return nil }
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            let box = observation.boundingBox
            return Item(
                text: trimmed,
                cx: box.midX,
                // Vision 的 y 轴朝上，翻成「从上往下」
                cy: 1 - box.midY,
                height: box.height
            )
        }

        return try parse(items)
    }

    // MARK: 坐标 → 表格

    private static func parse(_ items: [Item]) throws -> [ImportedCourse] {
        guard !items.isEmpty else { throw OCRError.empty }

        // 1) 星期表头
        var dayCenters: [Int: CGFloat] = [:]
        for item in items where item.cy < 0.32 {
            if let day = weekday(from: item.text) {
                dayCenters[day] = item.cx
            }
        }

        let columns: [(day: Int, center: CGFloat)]
        if dayCenters.count >= 5 {
            columns = dayCenters
                .map { (day: $0.key, center: $0.value) }
                .sorted { $0.center < $1.center }
        } else {
            // 认不出表头就按七等分硬切，仍给用户改的机会
            let left: CGFloat = 0.12
            let width: CGFloat = (0.96 - 0.12) / 7
            columns = (1...7).map { day in
                (day: day, center: left + width * (CGFloat(day) - 0.5))
            }
        }

        let columnGap = columns.count > 1 ? (columns[1].center - columns[0].center) : 0.11
        let firstColumnEdge = columns[0].center - columnGap * 0.6

        // 2) 左侧节次
        var rows: [(period: Int, center: CGFloat)] = []
        for item in items where item.cx < firstColumnEdge && item.text.count <= 8 {
            if let range = periodRange(from: item.text) {
                rows.append((period: range.lowerBound, center: item.cy))
            }
        }
        rows.sort { $0.center < $1.center }

        guard rows.count >= 4 else { throw OCRError.noGrid }

        let rowGap = (rows.last!.center - rows.first!.center) / CGFloat(max(1, rows.count - 1))

        // 3) 落格
        var cells: [CellKey: (texts: [String], span: Int)] = [:]

        for item in items {
            if item.cx < firstColumnEdge { continue }
            if weekday(from: item.text) != nil && item.cy < 0.32 { continue }
            if isNoise(item.text) { continue }

            let day = nearestColumn(item.cx, columns: columns)
            let rowIndex = nearestRow(item.cy, rows: rows)
            let span = max(1, min(4, Int((item.height / max(rowGap, 0.001)).rounded())))
            let key = CellKey(day: day, period: rows[rowIndex].period)

            var entry = cells[key] ?? (texts: [], span: 1)
            if !entry.texts.contains(item.text) {
                entry.texts.append(item.text)
            }
            entry.span = max(entry.span, span)
            cells[key] = entry
        }

        let courses: [ImportedCourse] = cells.compactMap { key, value in
            let title = cleanTitle(value.texts)
            guard !title.isEmpty else { return nil }
            return ImportedCourse(
                weekday: key.day,
                startPeriod: key.period,
                endPeriod: key.period + value.span - 1,
                title: title,
                location: value.texts.dropFirst().first ?? ""
            )
        }

        guard !courses.isEmpty else { throw OCRError.empty }
        return courses.sorted {
            $0.weekday == $1.weekday ? $0.startPeriod < $1.startPeriod : $0.weekday < $1.weekday
        }
    }

    // MARK: 小工具

    private struct Item {
        let text: String
        let cx: CGFloat
        let cy: CGFloat
        let height: CGFloat
    }

    private struct CellKey: Hashable {
        let day: Int
        let period: Int
    }

    private static let dayMap: [Character: Int] = [
        "一": 1, "二": 2, "三": 3, "四": 4, "五": 5, "六": 6, "日": 7, "天": 7
    ]

    private static func weekday(from text: String) -> Int? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        if trimmed.count == 1, let char = trimmed.first, let day = dayMap[char] {
            return day
        }
        for prefix in ["星期", "周", "礼拜"] where trimmed.hasPrefix(prefix) {
            let rest = trimmed.dropFirst(prefix.count)
            if rest.count == 1, let char = rest.first, let day = dayMap[char] {
                return day
            }
        }
        return nil
    }

    private static func periodRange(from text: String) -> ClosedRange<Int>? {
        let compact = text.replacingOccurrences(of: " ", with: "")
        if let exact = Int(compact), exact >= 1, exact <= 20 {
            return exact...exact
        }
        let numbers = compact
            .split(whereSeparator: { !$0.isNumber })
            .compactMap { Int($0) }
            .filter { $0 >= 1 && $0 <= 20 }
        guard let first = numbers.first else { return nil }
        if numbers.count >= 2, compact.contains("-") || compact.contains("–") || compact.contains("~") {
            return first...max(first, numbers[1])
        }
        return first...first
    }

    private static func nearestColumn(_ x: CGFloat, columns: [(day: Int, center: CGFloat)]) -> Int {
        columns.min { abs($0.center - x) < abs($1.center - x) }?.day ?? 1
    }

    private static func nearestRow(_ y: CGFloat, rows: [(period: Int, center: CGFloat)]) -> Int {
        var best = 0
        var bestDistance = CGFloat.greatestFiniteMagnitude
        for (index, row) in rows.enumerated() {
            let distance = abs(row.center - y)
            if distance < bestDistance {
                bestDistance = distance
                best = index
            }
        }
        return best
    }

    private static func isNoise(_ text: String) -> Bool {
        let noise = ["上午", "下午", "中午", "晚上", "时间", "课表", "节次", "星期", "备注", "课程"]
        if noise.contains(where: { text == $0 }) { return true }
        // 纯数字 / 纯节次写法（1、1-2、第3节）不算课名
        if text.range(of: #"^[0-9\s\-–~·、,，.第节次]+$"#, options: .regularExpression) != nil { return true }
        return false
    }

    private static func cleanTitle(_ texts: [String]) -> String {
        texts
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespaces)
    }
}
