import Foundation
import Observation

struct ExternalSubtitle: Identifiable, Sendable {
    let id: String
    let name: String
    let language: String
    let format: String
    let downloadUrl: URL
    let provider: String
    let fileId: Int?
}

@Observable
final class ExternalSubtitleService: Sendable {
    static let shared = ExternalSubtitleService()
    
    private let apiKey = "dLbXreFClkKJj0x3YBRfTJpie7u0G526"
    private let userAgent = "VLSub 0.9"
    
    private init() {}
    
    func search(title: String, year: Int?, type: String, imdbId: String?, language: String) async -> [ExternalSubtitle] {
        // OpenSubtitles.com uses 2-letter codes for the modern API search
        // Mapping eng -> en, spa -> es, etc.
        let langCode = String(language.prefix(2)).lowercased()
        
        var queryItems = [
            URLQueryItem(name: "languages", value: langCode),
            URLQueryItem(name: "query", value: title)
        ]
        
        if let year = year {
            queryItems.append(URLQueryItem(name: "year", value: String(year)))
        }
        
        if let imdbId = imdbId {
            let clean = imdbId.replacingOccurrences(of: "tt", with: "")
            queryItems.append(URLQueryItem(name: "imdb_id", value: clean))
        }

        var components = URLComponents(string: "https://api.opensubtitles.com/api/v1/subtitles")!
        components.queryItems = queryItems
        
        guard let url = components.url else { return [] }
        
        var request = URLRequest(url: url)
        request.setValue(apiKey, forHTTPHeaderField: "Api-Key")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                LumeError("[Subtitle] OS Search failed with status: \(http.statusCode)")
                return []
            }
            
            let decoder = JSONDecoder()
            let searchResult = try decoder.decode(OSModernSearchResponse.self, from: data)
            
            return searchResult.data.compactMap { item in
                let attr = item.attributes
                guard let file = attr.files.first else { return nil }
                
                return ExternalSubtitle(
                    id: item.id,
                    name: attr.release ?? "Subtitle",
                    language: attr.language ?? langCode,
                    format: attr.format ?? "srt",
                    downloadUrl: URL(string: "https://api.opensubtitles.com/api/v1/download")!, // We'll use this for the POST
                    provider: "OpenSubtitles",
                    fileId: file.file_id
                )
            }
        } catch {
            LumeError("[Subtitle] OS Modern Search failed: \(error)")
            return []
        }
    }
    
    func download(fileId: Int) async throws -> Data {
        let url = URL(string: "https://api.opensubtitles.com/api/v1/download")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "Api-Key")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        
        let body = ["file_id": fileId]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw NSError(domain: "SubtitleDownload", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to get download link"])
        }
        
        let dlResponse = try JSONDecoder().decode(OSDownloadResponse.self, from: data)
        guard let link = dlResponse.link, let dlUrl = URL(string: link) else {
            throw NSError(domain: "SubtitleDownload", code: 2, userInfo: [NSLocalizedDescriptionKey: "No download link in response"])
        }
        
        // Final download of the file
        let (finalData, _) = try await URLSession.shared.data(from: dlUrl)
        return finalData
    }
}

// MARK: - Modern OS API Models

struct OSModernSearchResponse: Codable {
    let data: [OSModernSubtitleItem]
}

struct OSModernSubtitleItem: Codable {
    let id: String
    let attributes: OSModernSubtitleAttributes
}

struct OSModernSubtitleAttributes: Codable {
    let subtitle_id: String?
    let language: String?
    let format: String?
    let release: String?
    let files: [OSModernFile]
}

struct OSModernFile: Codable {
    let file_id: Int
    let file_name: String?
}

struct OSDownloadResponse: Codable {
    let link: String?
    let file_name: String?
}
