import Foundation
import Observation

@Observable
final class SubtitleService: Sendable {
    static let shared = SubtitleService()
    
    private init() {
        try? FileManager.default.createDirectory(at: subtitleFolder, withIntermediateDirectories: true)
    }
    
    var subtitleFolder: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Subtitles", isDirectory: true)
    }
    
    func downloadSubtitle(data: Data, itemId: String, name: String, format: String) throws -> URL {
        // Use a unique name for each subtitle download to allow multiple for one item
        let cleanName = name.replacingOccurrences(of: "[^a-zA-Z0-9]", with: "_", options: .regularExpression)
        let fileName = "\(itemId)_\(cleanName).\(format)"
        let destination = subtitleFolder.appendingPathComponent(fileName)
        
        try data.write(to: destination)
        return destination
    }
    
    func getDownloadedSubtitles(for itemId: String) -> [URL] {
        guard let files = try? FileManager.default.contentsOfDirectory(at: subtitleFolder, includingPropertiesForKeys: nil) else {
            return []
        }
        return files.filter { $0.lastPathComponent.hasPrefix(itemId + "_") }
    }
    
    func clearAllSubtitles() {
        let files = try? FileManager.default.contentsOfDirectory(at: subtitleFolder, includingPropertiesForKeys: nil)
        files?.forEach { try? FileManager.default.removeItem(at: $0) }
    }
    
    func getTotalSizeString() -> String {
        guard let files = try? FileManager.default.contentsOfDirectory(at: subtitleFolder, includingPropertiesForKeys: nil) else {
            return "0 KB"
        }
        
        let totalBytes = files.reduce(0 as Int64) { total, url in
            let attr = try? FileManager.default.attributesOfItem(atPath: url.path)
            return total + (attr?[.size] as? Int64 ?? 0)
        }
        
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useAll]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: totalBytes)
    }
}
