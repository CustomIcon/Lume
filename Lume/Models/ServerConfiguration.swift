import Foundation
import SwiftData

@Model
final class ServerConfiguration {
    var serverURL: String
    var serverName: String
    var serverVersion: String
    var deviceID: String
    var createdAt: Date
    var isActive: Bool = true
 
    init(serverURL: String, serverName: String = "", serverVersion: String = "", deviceID: String = UUID().uuidString) {
        self.serverURL = serverURL
        self.serverName = serverName
        self.serverVersion = serverVersion
        self.deviceID = deviceID
        self.createdAt = Date()
        self.isActive = true
    }

    var baseURL: URL? {
        URL(string: serverURL)
    }
}
