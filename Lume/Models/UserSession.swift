import Foundation
import SwiftData

@Model
final class UserSession {
    var userID: String
    var username: String
    var accessToken: String
    var serverID: String
    var isActive: Bool
    var lastLoginDate: Date

    init(userID: String, username: String, accessToken: String, serverID: String) {
        self.userID = userID
        self.username = username
        self.accessToken = accessToken
        self.serverID = serverID
        self.isActive = true
        self.lastLoginDate = Date()
    }
}
