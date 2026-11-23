import Foundation

/// 微信读书同步服务（官方 Agent API Gateway）。
///
/// 契约来源：Tencent/WeChatReading 官方技能 `weread-skills` v1.0.6（SKILL.md / readdata.md / shelf.md / book.md）：
///   POST https://i.weread.qq.com/api/agent/gateway
///   Authorization: Bearer <wrk-...>
///   Body（业务参数平铺，不包 params）：{"api_name": "...", <业务参数...>, "skill_version": "1.0.6"}
///   errcode 非 0 即错误。
///
/// 本 App 用到的三个接口：
///   /readdata/detail  {mode:"monthly", baseTime: 0 或 上月首日时间戳}
///                     → readTimes: { 分桶起始时间戳(秒) : 秒数 }，按天分桶；totalReadTime 以「秒」为单位
///   /shelf/sync       → books[] {bookId, title, author, cover, readUpdateTime, finishReading}
///   /book/getprogress {bookId} → book.progress 为 0-100 整数（1 = 1%，不是 100%）
///
/// 凭证：Key 存钥匙串（com.xinyunhang.cresto.weread），回退 profile.plist 本地默认（不进仓库）；
/// 接口地址可在设置页覆盖，默认官方 Gateway。超时 2s：弱网自动回退本地缓存。
actor WeReadService {
    static let shared = WeReadService()

    static let defaultEndpoint = "https://i.weread.qq.com/api/agent/gateway"
    static let skillVersion = "1.0.6"

    struct Config {
        let endpoint: URL
        let key: String
    }

    enum WeReadError: LocalizedError {
        case notConfigured
        case unauthorized
        case network(String)
        case server(String)
        case malformed

        var errorDescription: String? {
            switch self {
            case .notConfigured: return "还没配置微信读书 Key，去设置页填一下"
            case .unauthorized: return "Key 无效或已失效，去设置页检查"
            case .network(let detail): return "网络不通：\(detail)"
            case .server(let detail): return "微信读书接口返回错误（\(detail)）"
            case .malformed: return "返回结构对不上，稍后再试"
            }
        }
    }

    /// 端点优先级：设置页保存的 UserDefaults → profile.plist 本地默认 → 官方 Gateway
    /// Key：钥匙串 → profile.plist 本地默认
    static func resolvedConfig() -> Config? {
        let savedEndpoint = UserDefaults.standard.string(forKey: "wereadEndpoint")?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let endpointText = (savedEndpoint?.isEmpty == false ? savedEndpoint : nil)
            ?? LocalProfile.wereadEndpoint
            ?? defaultEndpoint
        let key = KeychainService.load(service: KeychainService.wereadService, account: KeychainService.wereadAccount)
            ?? LocalProfile.wereadAPIKey

        guard let key, !key.isEmpty, let endpoint = URL(string: endpointText) else {
            return nil
        }
        return Config(endpoint: endpoint, key: key)
    }

    /// 拉取近 30 天阅读记录与当前在读：
    /// 本月 + 本月之前的自然月（覆盖 30 天窗口）两次 readdata，一次 shelf，一次 getprogress。
    func fetch() async throws -> WeReadSnapshot {
        guard let config = Self.resolvedConfig() else { throw WeReadError.notConfigured }

        async let currentMonth = call(config, api: "/readdata/detail", params: ["mode": "monthly", "baseTime": 0])
        async let previousMonth = call(config, api: "/readdata/detail", params: ["mode": "monthly", "baseTime": Self.previousMonthTimestamp()])
        async let shelf = call(config, api: "/shelf/sync", params: [:])

        let currentPayload = try await currentMonth
        let previousPayload = try await previousMonth
        let shelfPayload = try await shelf

        // 近 30 天：两个月度分桶合并（key 为分桶起始时间戳，value 为秒）
        var minutesByKey: [String: Int] = [:]
        for payload in [currentPayload, previousPayload] {
            guard let readTimes = payload["readTimes"] as? [String: Any] else { continue }
            for (timestampText, value) in readTimes {
                guard let timestamp = Double(timestampText),
                      let seconds = doubleValue(value), seconds > 0 else { continue }
                let day = Date(timeIntervalSince1970: timestamp)
                let key = UsageStore.key(for: day)
                let minutes = max(1, Int((seconds / 60).rounded(.up)))
                minutesByKey[key] = max(minutesByKey[key] ?? 0, minutes)
            }
        }

        let book = await resolveCurrentBook(shelfPayload, config: config)

        return WeReadSnapshot(
            days: minutesByKey.map { WeReadSnapshot.Day(dateKey: $0.key, minutes: $0.value) },
            book: book
        )
    }

    /// 正在读：书架里最近阅读且未读完的书；都读完则取最近阅读的一本；进度另查 getprogress
    private func resolveCurrentBook(_ shelfPayload: [String: Any], config: Config) async -> WeReadSnapshot.Book? {
        let books = shelfPayload["books"] as? [[String: Any]] ?? []
        guard !books.isEmpty else { return nil }

        let sorted = books.sorted {
            (intValue($0["readUpdateTime"]) ?? 0) > (intValue($1["readUpdateTime"]) ?? 0)
        }
        let candidate = sorted.first(where: { (intValue($0["finishReading"]) ?? 0) != 1 }) ?? sorted.first
        guard let candidate,
              let bookId = candidate["bookId"] as? String,
              let title = candidate["title"] as? String, !title.isEmpty else {
            return nil
        }

        // 进度：0-100 整数（1 = 1%）；查询失败不影响热力图
        var progress = 0.0
        if let progressPayload = try? await call(config, api: "/book/getprogress", params: ["bookId": bookId]),
           let bookInfo = progressPayload["book"] as? [String: Any],
           let percent = intValue(bookInfo["progress"]) {
            progress = Double(min(100, max(0, percent))) / 100
        }

        return WeReadSnapshot.Book(
            title: title,
            author: (candidate["author"] as? String) ?? "",
            coverURL: (candidate["cover"] as? String) ?? "",
            progress: progress
        )
    }

    // MARK: - Gateway 调用

    private func call(_ config: Config, api: String, params: [String: Any]) async throws -> [String: Any] {
        var request = URLRequest(url: config.endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(config.key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 2.0

        var body = params
        body["api_name"] = api
        body["skill_version"] = Self.skillVersion
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw WeReadError.network(error.localizedDescription)
        }

        switch (response as? HTTPURLResponse)?.statusCode ?? 0 {
        case 200:
            break
        case 401, 403:
            throw WeReadError.unauthorized
        default:
            throw WeReadError.network("HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0)")
        }

        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw WeReadError.malformed
        }
        if let errcode = intValue(root["errcode"]), errcode != 0 {
            // 鉴权类错误码按未授权处理
            if let message = root["errmsg"] as? String, message.contains("auth") || message.contains("token") {
                throw WeReadError.unauthorized
            }
            throw WeReadError.server("errcode \(errcode)")
        }
        return root
    }

    // MARK: - 工具

    private static func previousMonthTimestamp() -> Int {
        let calendar = Calendar.current
        let firstOfThisMonth = calendar.dateInterval(of: .month, for: Date())?.start ?? Date()
        let previous = calendar.date(byAdding: .month, value: -1, to: firstOfThisMonth) ?? firstOfThisMonth
        return Int(previous.timeIntervalSince1970)
    }

    private static func intValue(_ value: Any?) -> Int? {
        switch value {
        case let int as Int: return int
        case let double as Double: return Int(double.rounded())
        case let number as NSNumber: return number.intValue
        case let text as String:
            if let int = Int(text) { return int }
            return Double(text).map { Int($0.rounded()) }
        default: return nil
        }
    }

    private static func doubleValue(_ value: Any?) -> Double? {
        switch value {
        case let double as Double: return double
        case let int as Int: return Double(int)
        case let number as NSNumber: return number.doubleValue
        case let text as String: return Double(text)
        default: return nil
        }
    }
}