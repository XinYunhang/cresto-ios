import Foundation
import OSLog

/// 轻量日志：OSLog + 一个可导出的文本文件。
/// 文件在 Documents/Logs/cresto.log，超过 512KB 自动清空重来。
enum AppLog {
    static let fileName = "cresto.log"
    private static let maxBytes = 512 * 1024

    private static let logger = Logger(subsystem: "com.nevoit.cresto", category: "App")
    private static let queue = DispatchQueue(label: "com.nevoit.cresto.log")

    static var directory: URL {
        let base = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let dir = base.appendingPathComponent("Logs", isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    static var fileURL: URL { directory.appendingPathComponent(fileName) }

    static var fileSizeText: String {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: fileURL.path),
              let size = attrs[.size] as? NSNumber else { return "0 KB" }
        let kb = size.doubleValue / 1024
        return kb < 1024 ? String(format: "%.1f KB", kb) : String(format: "%.1f MB", kb / 1024)
    }

    static func info(_ message: String) { write("INFO", message) }
    static func warn(_ message: String) { write("WARN", message) }
    static func error(_ message: String) { write("ERROR", message) }

    static func clear() {
        queue.async {
            try? FileManager.default.removeItem(at: fileURL)
            append("------ 日志已清空 ------\n")
        }
    }

    private static func write(_ level: String, _ message: String) {
        logger.log(level: level == "ERROR" ? .error : .info, "\(message, privacy: .public)")
        let stamp = Self.stamp()
        queue.async {
            append("\(stamp) [\(level)] \(message)\n")
        }
    }

    // MARK: 私有

    private static func append(_ text: String) {
        let url = fileURL
        if let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
           let size = attrs[.size] as? NSNumber,
           size.intValue > maxBytes {
            try? FileManager.default.removeItem(at: url)
        }

        guard let data = text.data(using: .utf8) else { return }
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            handle.write(data)
            try? handle.close()
        } else {
            try? data.write(to: url, options: .atomic)
        }
    }

    private static func stamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM-dd HH:mm:ss.SSS"
        return formatter.string(from: Date())
    }
}
