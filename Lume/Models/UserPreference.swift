import Foundation
import SwiftData

@Model
final class UserPreference {
    var userID: String
    var preferredAudioLanguage: String
    var preferredSubtitleLanguage: String
    var enableSubtitles: Bool
    var defaultPlaybackQuality: String
    var gridViewColumns: Int

    init(userID: String) {
        self.userID = userID
        self.preferredAudioLanguage = "eng"
        self.preferredSubtitleLanguage = "eng"
        self.enableSubtitles = false
        self.defaultPlaybackQuality = "auto"
        self.gridViewColumns = 5
    }
}
