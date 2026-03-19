import Foundation
import SwiftData

@Model
final class PlaybackPosition {
    var itemID: String
    var userID: String
    var positionTicks: Int64
    var runtimeTicks: Int64
    var isCompleted: Bool
    var lastPlayed: Date

    init(itemID: String, userID: String, positionTicks: Int64, runtimeTicks: Int64 = 0) {
        self.itemID = itemID
        self.userID = userID
        self.positionTicks = positionTicks
        self.runtimeTicks = runtimeTicks
        self.isCompleted = false
        self.lastPlayed = Date()
    }

    var progressPercentage: Double {
        guard runtimeTicks > 0 else { return 0 }
        return Double(positionTicks) / Double(runtimeTicks)
    }

    var positionSeconds: Double {
        Double(positionTicks) / 10_000_000
    }
}
