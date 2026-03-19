import Foundation
import SwiftData

@Model
final class CachedLibrary {
    var itemID: String
    var name: String
    var collectionType: String
    var sortOrder: Int
    var imageTag: String?
    var userID: String
    var lastRefreshed: Date

    init(itemID: String, name: String, collectionType: String, sortOrder: Int, imageTag: String? = nil, userID: String) {
        self.itemID = itemID
        self.name = name
        self.collectionType = collectionType
        self.sortOrder = sortOrder
        self.imageTag = imageTag
        self.userID = userID
        self.lastRefreshed = Date()
    }
}
