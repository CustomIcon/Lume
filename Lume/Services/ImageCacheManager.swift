import Foundation
import SwiftUI

enum CacheSection: String, CaseIterable, Identifiable {
    case movies = "Movies"
    case tvShows = "TV Shows"
    case music = "Music"
    case liveTv = "Live TV"
    case books = "Books"
    case others = "Others"
    
    var id: String { rawValue }
    
    static func from(itemType: String?) -> CacheSection {
        guard let type = itemType else { return .others }
        switch type {
        case "Movie":
            return .movies
        case "Series", "Season", "Episode":
            return .tvShows
        case "MusicAlbum", "Audio", "MusicArtist":
            return .music
        case "Channel", "LiveTvProgram", "LiveTvRecording":
            return .liveTv
        case "Book":
            return .books
        default:
            return .others
        }
    }
}

class ImageCacheManager {
    static let shared = ImageCacheManager()
    
    private let fileManager = FileManager.default
    private let cacheDirectory: URL
    private let memoryCache = NSCache<NSURL, NSImage>()
    
    private init() {
        let urls = fileManager.urls(for: .cachesDirectory, in: .userDomainMask)
        self.cacheDirectory = urls[0].appendingPathComponent("ImageCache")
        
        // Configure memory cache
        memoryCache.countLimit = 100 // Cache up to 100 images in memory
        memoryCache.totalCostLimit = 100 * 1024 * 1024 // 100MB limit
        
        createDirectoryIfNeeded()
    }
    
    private func createDirectoryIfNeeded() {
        for section in CacheSection.allCases {
            let sectionDir = cacheDirectory.appendingPathComponent(section.rawValue)
            if !fileManager.fileExists(atPath: sectionDir.path) {
                try? fileManager.createDirectory(at: sectionDir, withIntermediateDirectories: true)
            }
        }
    }
    
    func getCachedImage(for url: URL, section: CacheSection) -> NSImage? {
        if let memoryImage = memoryCache.object(forKey: url as NSURL) {
            return memoryImage
        }
        
        let fileURL = cacheURL(for: url, section: section)
        if fileManager.fileExists(atPath: fileURL.path),
           let data = try? Data(contentsOf: fileURL),
           let image = NSImage(data: data) {
            memoryCache.setObject(image, forKey: url as NSURL, cost: data.count)
            return image
        }
        return nil
    }
    
    func cacheImage(_ image: NSImage, for url: URL, section: CacheSection) {
        // Set in memory
        memoryCache.setObject(image, forKey: url as NSURL)
        
        // Save to disk
        let fileURL = cacheURL(for: url, section: section)
        if let data = image.tiffRepresentation {
            try? data.write(to: fileURL)
        }
    }
    
    func cacheData(_ data: Data, for url: URL, section: CacheSection) {
        if let image = NSImage(data: data) {
            memoryCache.setObject(image, forKey: url as NSURL, cost: data.count)
        }
        
        let fileURL = cacheURL(for: url, section: section)
        try? data.write(to: fileURL)
    }
    
    private func cacheURL(for url: URL, section: CacheSection) -> URL {
        let input = url.absoluteString
        var hash: UInt64 = 5381
        for byte in input.utf8 {
            hash = ((hash << 5) &+ hash) &+ UInt64(byte)
        }
        let fileName = String(hash)
        return cacheDirectory.appendingPathComponent(section.rawValue).appendingPathComponent(fileName)
    }
    
    func getCacheSize(for section: CacheSection) -> Int64 {
        let sectionDir = cacheDirectory.appendingPathComponent(section.rawValue)
        let files = try? fileManager.contentsOfDirectory(at: sectionDir, includingPropertiesForKeys: [.fileSizeKey])
        let size = files?.reduce(0 as Int64) { total, url in
            let resourceValues = try? url.resourceValues(forKeys: [.fileSizeKey])
            return total + Int64(resourceValues?.fileSize ?? 0)
        } ?? 0
        return size
    }
    
    func clearCache(for section: CacheSection) {
        let sectionDir = cacheDirectory.appendingPathComponent(section.rawValue)
        let files = try? fileManager.contentsOfDirectory(at: sectionDir, includingPropertiesForKeys: nil)
        files?.forEach { try? fileManager.removeItem(at: $0) }
        memoryCache.removeAllObjects()
    }
    
    func formatSize(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useAll]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
    
    func getTotalSizeString() -> String {
        let total = CacheSection.allCases.reduce(0 as Int64) { total, section in
            total + getCacheSize(for: section)
        }
        return formatSize(total)
    }
    
    func clearCache() {
        for section in CacheSection.allCases {
            clearCache(for: section)
        }
        memoryCache.removeAllObjects()
    }
}
