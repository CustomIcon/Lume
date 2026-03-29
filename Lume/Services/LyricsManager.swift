import Foundation
import SwiftData

struct LyricsResponse: Codable {
    let data: LyricsData?
}

struct LyricsData: Codable {
    let artistName: String?
    let trackName: String?
    let trackId: String?
    let searchEngine: String?
    let artworkUrl: String?
    let lyrics: String?
}

struct CachedLyrics: Codable {
    let songId: String
    let lyrics: String
    let timestamp: Date
}

@Observable
class LyricsManager {
    static let shared = LyricsManager()
    
    private let cacheKey = "lume_lyrics_cache"
    private var cache: [String: CachedLyrics] = [:]
    
    private init() {
        loadCache()
    }
    
    private func loadCache() {
        if let data = UserDefaults.standard.data(forKey: cacheKey),
           let decoded = try? JSONDecoder().decode([String: CachedLyrics].self, from: data) {
            cache = decoded
        }
    }
    
    private func saveCache() {
        if let encoded = try? JSONEncoder().encode(cache) {
            UserDefaults.standard.set(encoded, forKey: cacheKey)
        }
    }
    
    func getLyrics(songId: String, title: String?, artist: String?) async -> String? {
        if let cached = cache[songId] {
            return cached.lyrics
        }
        
        guard let originalTitle = title, !originalTitle.isEmpty else { return nil }
        
        // Sanitize title (remove junk like "(Official Video)", "Live", etc. for better search)
        var sanitizedTitle = originalTitle.replacingOccurrences(of: #"\s*\(.*?\)"#, with: "", options: .regularExpression)
        sanitizedTitle = sanitizedTitle.replacingOccurrences(of: #"\s*\[.*?\]"#, with: "", options: .regularExpression)
        sanitizedTitle = sanitizedTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Try Musixmatch first, fallback to YouTube
        let platforms = ["musixmatch", "youtube"]
        
        for platform in platforms {
            do {
                var urlComponents = URLComponents(string: "https://lyrics.lewdhutao.my.eu.org/v2/\(platform)/lyrics")!
                urlComponents.queryItems = [
                    URLQueryItem(name: "title", value: sanitizedTitle),
                    URLQueryItem(name: "artist", value: artist ?? "")
                ]
                
                guard let url = urlComponents.url else { continue }
                
                let (data, _) = try await URLSession.shared.data(from: url)
                let response = try? JSONDecoder().decode(LyricsResponse.self, from: data)
                
                if let rawLyrics = response?.data?.lyrics, !rawLyrics.isEmpty {
                    // Clean lyrics line endings
                    let lyrics = rawLyrics.components(separatedBy: .newlines).joined(separator: "\n")
                    
                    let cachedLyrics = CachedLyrics(songId: songId, lyrics: lyrics, timestamp: Date())
                    Task { @MainActor in
                        self.cache[songId] = cachedLyrics
                        self.saveCache()
                    }
                    return lyrics
                }
            } catch {
                LumeError("Failed to fetch from \(platform): \(error)")
            }
        }
        
        return nil
    }
    
    func clearCache() {
        Task { @MainActor in
            self.cache.removeAll()
            self.saveCache()
        }
    }
    
    func getCacheSizeInBytes() -> Int {
        if let data = UserDefaults.standard.data(forKey: cacheKey) {
            return data.count
        }
        return 0
    }
}
