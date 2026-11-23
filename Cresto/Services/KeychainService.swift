import Foundation
import Security

/// DeepSeek API Key 存取。系统管加密，App 只拿引用——iOS 的等价物就是 Keychain。
///
/// 方案来自笔记 07：`ThisDeviceOnly` 让换机/iCloud 备份默认不带走钥匙串项，泄露面最小。
/// Key 永不进 UserDefaults、不进日志、不进快照导出；换机后重填一次是特性。
enum KeychainService {
    static let deepseekService = "com.xinyunhang.cresto.deepseek"
    static let deepseekAccount = "apiKey"
    static let wereadService = "com.xinyunhang.cresto.weread"
    static let wereadAccount = "apiKey"

    /// 默认参数保持旧调用（DeepSeek）不变
    static let service = deepseekService
    static let account = deepseekAccount

    struct KeychainError: LocalizedError {
        let status: OSStatus

        var errorDescription: String? {
            "钥匙串写入失败（OSStatus \(status)）"
        }
    }

    // MARK: 增 / 改

    static func save(_ key: String, service: String = KeychainService.deepseekService, account: String = KeychainService.deepseekAccount) throws {
        let data = Data(key.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let attrs: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]

        // 已存在就更新，否则新增；Add/Update 的真实结果才算数
        let lookup = SecItemCopyMatching(query as CFDictionary, nil)
        if lookup == errSecSuccess {
            let update = SecItemUpdate(query as CFDictionary, attrs as CFDictionary)
            if update != errSecSuccess { throw KeychainError(status: update) }
        } else {
            let add = SecItemAdd(query.merging(attrs) { $1 } as CFDictionary, nil)
            if add != errSecSuccess { throw KeychainError(status: add) }
        }
    }

    // MARK: 查

    static func load(service: String = KeychainService.deepseekService, account: String = KeychainService.deepseekAccount) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    // MARK: 删

    static func delete(service: String = KeychainService.deepseekService, account: String = KeychainService.deepseekAccount) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
