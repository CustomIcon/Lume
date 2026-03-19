import Foundation

struct LogEntry: Identifiable, Codable {
    var id = UUID()
    let timestamp: Date
    let message: String
    let level: LogLevel
    
    enum LogLevel: String, Codable {
        case info = "INFO"
        case error = "ERROR"
        case debug = "DEBUG"
    }
}

@Observable
final class LumeLogger {
    static let shared = LumeLogger()
    
    private(set) var entries: [LogEntry] = []
    
    func log(_ message: String, level: LogEntry.LogLevel = .info) {
        let entry = LogEntry(timestamp: Date(), message: message, level: level)
        entries.insert(entry, at: 0)
        
        // Keep last 500 entries only
        if entries.count > 500 {
            entries.removeLast()
        }
        
        // Also print to console
        print("\(level.rawValue) [\(format(entry.timestamp))]: \(message)")
    }
    
    func clear() {
        entries = []
    }
    
    private func format(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter.string(from: date)
    }
}

// Global logger shortcuts
func LumeInfo(_ message: String) { LumeLogger.shared.log(message, level: .info) }
func LumeError(_ message: String) { LumeLogger.shared.log(message, level: .error) }
func LumeDebug(_ message: String) { LumeLogger.shared.log(message, level: .debug) }
