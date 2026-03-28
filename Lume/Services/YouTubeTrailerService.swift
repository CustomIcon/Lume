import Foundation

final class YouTubeTrailerService: @unchecked Sendable {
    static let shared = YouTubeTrailerService()
    
    // Fallback search instances (Invidious and Piped)
    private let instances: [(url: String, isPiped: Bool)] = [
        ("https://yewtu.be", false),
        ("https://inv.tux.rs", false),
        ("https://pipedapi.rivm.de", true),
        ("https://invidious.flokinet.to", false),
        ("https://iv.ggtyler.dev", false)
    ]
    
    // Dedicated session with browser User-Agent
    private let urlSession: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 8
        config.httpAdditionalHeaders = [
            "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
        ]
        return URLSession(configuration: config)
    }()
    
    /// Resolves a YouTube video ID for a given Jellyfin item.
    func getYouTubeVideoId(for item: BaseItemDto, apiClient: JellyfinAPIClient) async -> String? {
        // 1. Try metadata first (most accurate)
        if let videoId = extractFirstYouTubeId(from: item.remoteTrailers) {
            return videoId
        }
        
        // 2. Fetch full details (episodes -> series)
        guard let itemId = item.id else { return nil }
        let fetchId = (item.type == "Episode" ? item.seriesId : itemId) ?? itemId
        
        var fullItem: BaseItemDto?
        do {
            fullItem = try await apiClient.getItem(itemId: fetchId)
            if let videoId = extractFirstYouTubeId(from: fullItem?.remoteTrailers) {
                return videoId
            }
        } catch {}
        
        // 3. Search Fallback (if metadata failed or missing)
        let searchTitle = (fullItem?.type == "Episode" ? (fullItem?.seriesName ?? fullItem?.displayName) : fullItem?.displayName) ?? item.displayName
        
        var query = searchTitle
        if fullItem?.type == "Movie", let year = fullItem?.productionYear {
            query += " \(year)"
        }
        query += " official trailer"
        
        return await ytSearch(query: query)
    }
    
    private func ytSearch(query: String) async -> String? {
        guard let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else { return nil }
        
        for instance in instances {
            let urlString = instance.isPiped ? "\(instance.url)/search?q=\(encoded)&filter=videos" : "\(instance.url)/api/v1/search?q=\(encoded)&type=video"
            guard let url = URL(string: urlString) else { continue }
            
            do {
                let (data, _) = try await urlSession.data(from: url)
                let json = try? JSONSerialization.jsonObject(with: data)
                
                if instance.isPiped {
                    if let results = json as? [[String: Any]],
                       let first = results.first(where: { ($0["type"] as? String) == "video" }),
                       let path = first["url"] as? String {
                        return extractYouTubeId(from: path)
                    }
                } else {
                    if let results = json as? [[String: Any]],
                       let videoId = results.first?["videoId"] as? String {
                        return videoId
                    }
                }
            } catch {
                continue
            }
        }
        return nil
    }
    
    private func extractFirstYouTubeId(from trailers: [MediaUrl]?) -> String? {
        guard let trailers, !trailers.isEmpty else { return nil }
        for trailer in trailers {
            if let urlString = trailer.url, let videoId = extractYouTubeId(from: urlString) {
                return videoId
            }
        }
        return nil
    }
    
    private func extractYouTubeId(from url: String) -> String? {
        let pattern = #"(?:v=|\/|be\/|embed\/)([0-9A-Za-z_-]{11})"#
        let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive)
        let range = NSRange(url.startIndex..<url.endIndex, in: url)
        if let match = regex?.firstMatch(in: url, options: [], range: range),
           let idRange = Range(match.range(at: 1), in: url) {
            return String(url[idRange])
        }
        return nil
    }
}
