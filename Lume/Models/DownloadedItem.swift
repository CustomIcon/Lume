import Foundation
import SwiftData

@Model
final class DownloadedItem {
    @Attribute(.unique) var itemId: String
    var serverId: String
    var name: String
    var type: String
    var collectionType: String?
    var localUrl: String
    var downloadDate: Date
    var size: Int64
    var status: String // "downloading", "completed", "failed"
    var progress: Double
    @Attribute(.externalStorage) var resumeData: Data?
    var localImagePath: String?
    var localSeriesImagePath: String?
    var seriesId: String?
    var seasonId: String?
    
    // Additional metadata to show in libraries
    var seriesName: String?
    var albumName: String?
    var artistName: String?
    
    init(itemId: String, serverId: String, name: String, type: String, collectionType: String? = nil, localUrl: String = "", size: Int64 = 0) {
        self.itemId = itemId
        self.serverId = serverId
        self.name = name
        self.type = type
        self.collectionType = collectionType
        self.localUrl = localUrl
        self.localImagePath = nil
        self.seriesId = nil
        self.seasonId = nil
        self.downloadDate = Date()
        self.size = size
        self.status = "downloading"
        self.progress = 0.0
        self.resumeData = nil
    }
}
