import Foundation

// MARK: - Indirect Wrapper (to break recursive value types)

final class IndirectItem: Codable, Hashable {
    let value: BaseItemDto

    init(_ value: BaseItemDto) {
        self.value = value
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        self.value = try container.decode(BaseItemDto.self)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(value)
    }

    static func == (lhs: IndirectItem, rhs: IndirectItem) -> Bool {
        lhs.value == rhs.value
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(value)
    }
}

// MARK: - Server Info

struct PublicServerInfo: Codable {
    let localAddress: String?
    let serverName: String?
    let version: String?
    let id: String?
    let startupWizardCompleted: Bool?

    enum CodingKeys: String, CodingKey {
        case localAddress = "LocalAddress"
        case serverName = "ServerName"
        case version = "Version"
        case id = "Id"
        case startupWizardCompleted = "StartupWizardCompleted"
    }
}

// MARK: - Authentication

struct AuthenticationRequest: Codable {
    let username: String
    let pw: String

    enum CodingKeys: String, CodingKey {
        case username = "Username"
        case pw = "Pw"
    }
}

struct AuthenticationResult: Codable {
    let user: UserDto?
    let accessToken: String?
    let serverId: String?

    enum CodingKeys: String, CodingKey {
        case user = "User"
        case accessToken = "AccessToken"
        case serverId = "ServerId"
    }
}

struct UserDto: Codable, Identifiable {
    let name: String?
    let serverId: String?
    let id: String?
    let hasPassword: Bool?
    let primaryImageTag: String?

    enum CodingKeys: String, CodingKey {
        case name = "Name"
        case serverId = "ServerId"
        case id = "Id"
        case hasPassword = "HasPassword"
        case primaryImageTag = "PrimaryImageTag"
    }
}

// MARK: - Quick Connect

struct QuickConnectResult: Codable {
    let secret: String?
    let code: String?
    let authenticated: Bool?
    let dateAdded: String?

    enum CodingKeys: String, CodingKey {
        case secret = "Secret"
        case code = "Code"
        case authenticated = "Authenticated"
        case dateAdded = "DateAdded"
    }
}

struct QuickConnectState: Codable {
    let authenticated: Bool?
    let secret: String?

    enum CodingKeys: String, CodingKey {
        case authenticated = "Authenticated"
        case secret = "Secret"
    }
}

// MARK: - Library / Views

struct BaseItemDtoQueryResult: Codable {
    let items: [BaseItemDto]?
    let totalRecordCount: Int?
    let startIndex: Int?

    enum CodingKeys: String, CodingKey {
        case items = "Items"
        case totalRecordCount = "TotalRecordCount"
        case startIndex = "StartIndex"
    }
}

struct BaseItemDto: Codable, Identifiable, Hashable {
    let name: String?
    let serverId: String?
    let id: String?
    let etag: String?
    let dateCreated: String?
    let collectionType: String?
    let type: String?
    let overview: String?
    let productionYear: Int?
    let indexNumber: Int?
    let parentIndexNumber: Int?
    let communityRating: Double?
    let officialRating: String?
    let runTimeTicks: Int64?
    let genres: [String]?
    let tags: [String]?
    let studios: [NameIdPair]?
    let people: [BaseItemPerson]?
    let parentId: String?
    let seriesName: String?
    let seriesId: String?
    let seasonId: String?
    let seasonName: String?
    let imageTags: [String: String]?
    let backdropImageTags: [String]?
    let parentBackdropImageTags: [String]?
    let parentBackdropItemId: String?
    let userData: UserItemDataDto?
    let mediaSources: [MediaSourceInfo]?
    let mediaStreams: [MediaStream]?
    let premiereDate: String?
    let criticRating: Double?
    let albumArtist: String?
    let album: String?
    let artists: [String]?
    let artistItems: [NameIdPair]?
    let albumId: String?
    let childCount: Int?
    let recursiveItemCount: Int?
    let status: String?
    let airDays: [String]?
    let endDate: String?
    let locationType: String?
    let channelNumber: String?
    private let _currentProgram: IndirectItem?

    var currentProgram: BaseItemDto? {
        _currentProgram?.value
    }
    let videoType: String?
    let hasSubtitles: Bool?
    let container: String?
    let sortName: String?
    let primaryImageAspectRatio: Double?

    enum CodingKeys: String, CodingKey {
        case name = "Name"
        case serverId = "ServerId"
        case id = "Id"
        case etag = "Etag"
        case dateCreated = "DateCreated"
        case collectionType = "CollectionType"
        case type = "Type"
        case overview = "Overview"
        case productionYear = "ProductionYear"
        case indexNumber = "IndexNumber"
        case parentIndexNumber = "ParentIndexNumber"
        case communityRating = "CommunityRating"
        case officialRating = "OfficialRating"
        case runTimeTicks = "RunTimeTicks"
        case genres = "Genres"
        case tags = "Tags"
        case studios = "Studios"
        case people = "People"
        case parentId = "ParentId"
        case seriesName = "SeriesName"
        case seriesId = "SeriesId"
        case seasonId = "SeasonId"
        case seasonName = "SeasonName"
        case imageTags = "ImageTags"
        case backdropImageTags = "BackdropImageTags"
        case parentBackdropImageTags = "ParentBackdropImageTags"
        case parentBackdropItemId = "ParentBackdropItemId"
        case userData = "UserData"
        case mediaSources = "MediaSources"
        case mediaStreams = "MediaStreams"
        case premiereDate = "PremiereDate"
        case criticRating = "CriticRating"
        case albumArtist = "AlbumArtist"
        case album = "Album"
        case artists = "Artists"
        case artistItems = "ArtistItems"
        case albumId = "AlbumId"
        case childCount = "ChildCount"
        case recursiveItemCount = "RecursiveItemCount"
        case status = "Status"
        case airDays = "AirDays"
        case endDate = "EndDate"
        case locationType = "LocationType"
        case channelNumber = "ChannelNumber"
        case _currentProgram = "CurrentProgram"
        case videoType = "VideoType"
        case hasSubtitles = "HasSubtitles"
        case container = "Container"
        case sortName = "SortName"
        case primaryImageAspectRatio = "PrimaryImageAspectRatio"
    }

    static func == (lhs: BaseItemDto, rhs: BaseItemDto) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    var displayName: String {
        name ?? "Unknown"
    }

    var yearText: String? {
        productionYear.map { String($0) }
    }

    var runtimeMinutes: Int? {
        guard let ticks = runTimeTicks else { return nil }
        return Int(ticks / 600_000_000)
    }

    var runtimeText: String? {
        guard let minutes = runtimeMinutes else { return nil }
        let hours = minutes / 60
        let remainingMinutes = minutes % 60
        if hours > 0 {
            return "\(hours)h \(remainingMinutes)m"
        }
        return "\(remainingMinutes)m"
    }

    var episodeLabel: String? {
        guard let season = parentIndexNumber, let episode = indexNumber else { return nil }
        return "S\(season):E\(episode)"
    }
}

struct NameIdPair: Codable, Identifiable, Hashable {
    let name: String?
    let id: String?

    enum CodingKeys: String, CodingKey {
        case name = "Name"
        case id = "Id"
    }
}

struct BaseItemPerson: Codable, Identifiable, Hashable {
    let name: String?
    let id: String?
    let role: String?
    let type: String?
    let primaryImageTag: String?

    enum CodingKeys: String, CodingKey {
        case name = "Name"
        case id = "Id"
        case role = "Role"
        case type = "Type"
        case primaryImageTag = "PrimaryImageTag"
    }
}

// MARK: - User Data

struct UserItemDataDto: Codable, Hashable {
    let rating: Double?
    let playedPercentage: Double?
    let unplayedItemCount: Int?
    let playbackPositionTicks: Int64?
    let playCount: Int?
    let isFavorite: Bool?
    let played: Bool?
    let key: String?
    let lastPlayedDate: String?

    enum CodingKeys: String, CodingKey {
        case rating = "Rating"
        case playedPercentage = "PlayedPercentage"
        case unplayedItemCount = "UnplayedItemCount"
        case playbackPositionTicks = "PlaybackPositionTicks"
        case playCount = "PlayCount"
        case isFavorite = "IsFavorite"
        case played = "Played"
        case key = "Key"
        case lastPlayedDate = "LastPlayedDate"
    }
}

// MARK: - Media Info

struct MediaSourceInfo: Codable, Identifiable, Hashable {
    let id: String?
    let name: String?
    let path: String?
    let container: String?
    let size: Int64?
    let bitrate: Int?
    let supportsDirectPlay: Bool?
    let supportsDirectStream: Bool?
    let supportsTranscoding: Bool?
    let mediaStreams: [MediaStream]?
    let directStreamUrl: String?
    let transcodingUrl: String?

    enum CodingKeys: String, CodingKey {
        case id = "Id"
        case name = "Name"
        case path = "Path"
        case container = "Container"
        case size = "Size"
        case bitrate = "Bitrate"
        case supportsDirectPlay = "SupportsDirectPlay"
        case supportsDirectStream = "SupportsDirectStream"
        case supportsTranscoding = "SupportsTranscoding"
        case mediaStreams = "MediaStreams"
        case directStreamUrl = "DirectStreamUrl"
        case transcodingUrl = "TranscodingUrl"
    }
}

struct MediaStream: Codable, Identifiable, Hashable {
    let index: Int?
    let type: String?
    let codec: String?
    let language: String?
    let displayTitle: String?
    let displayLanguage: String?
    let title: String?
    let isDefault: Bool?
    let isExternal: Bool?
    let isForced: Bool?
    let channels: Int?
    let bitRate: Int?
    let width: Int?
    let height: Int?
    let deliveryUrl: String?
    let isTextSubtitleStream: Bool?
    let supportsExternalStream: Bool?

    var id: Int? { index }

    enum CodingKeys: String, CodingKey {
        case index = "Index"
        case type = "Type"
        case codec = "Codec"
        case language = "Language"
        case displayTitle = "DisplayTitle"
        case displayLanguage = "DisplayLanguage"
        case title = "Title"
        case isDefault = "IsDefault"
        case isExternal = "IsExternal"
        case isForced = "IsForced"
        case channels = "Channels"
        case bitRate = "BitRate"
        case width = "Width"
        case height = "Height"
        case deliveryUrl = "DeliveryUrl"
        case isTextSubtitleStream = "IsTextSubtitleStream"
        case supportsExternalStream = "SupportsExternalStream"
    }
}

// MARK: - Playback Reporting

struct PlaybackStartInfo: Codable {
    let itemId: String
    var mediaSourceId: String? = nil
    var audioStreamIndex: Int? = nil
    var subtitleStreamIndex: Int? = nil
    var positionTicks: Int64? = nil
    var playSessionId: String? = nil

    enum CodingKeys: String, CodingKey {
        case itemId = "ItemId"
        case mediaSourceId = "MediaSourceId"
        case audioStreamIndex = "AudioStreamIndex"
        case subtitleStreamIndex = "SubtitleStreamIndex"
        case positionTicks = "PositionTicks"
        case playSessionId = "PlaySessionId"
    }
}

struct PlaybackProgressInfo: Codable {
    let itemId: String
    var mediaSourceId: String? = nil
    var positionTicks: Int64? = nil
    var isPaused: Bool? = nil
    var isMuted: Bool? = nil
    var audioStreamIndex: Int? = nil
    var subtitleStreamIndex: Int? = nil
    var volumeLevel: Int? = nil
    var playSessionId: String? = nil

    enum CodingKeys: String, CodingKey {
        case itemId = "ItemId"
        case mediaSourceId = "MediaSourceId"
        case positionTicks = "PositionTicks"
        case isPaused = "IsPaused"
        case isMuted = "IsMuted"
        case audioStreamIndex = "AudioStreamIndex"
        case subtitleStreamIndex = "SubtitleStreamIndex"
        case volumeLevel = "VolumeLevel"
        case playSessionId = "PlaySessionId"
    }
}

struct PlaybackStopInfo: Codable {
    let itemId: String
    var mediaSourceId: String? = nil
    var positionTicks: Int64? = nil
    var playSessionId: String? = nil

    enum CodingKeys: String, CodingKey {
        case itemId = "ItemId"
        case mediaSourceId = "MediaSourceId"
        case positionTicks = "PositionTicks"
        case playSessionId = "PlaySessionId"
    }
}

// MARK: - Live TV

struct LiveTvChannelResult: Codable {
    let items: [BaseItemDto]?
    let totalRecordCount: Int?

    enum CodingKeys: String, CodingKey {
        case items = "Items"
        case totalRecordCount = "TotalRecordCount"
    }
}

struct TimerInfoDto: Codable, Identifiable {
    let id: String?
    let name: String?
    let channelId: String?
    let startDate: String?
    let endDate: String?
    let status: String?
    let programId: String?

    enum CodingKeys: String, CodingKey {
        case id = "Id"
        case name = "Name"
        case channelId = "ChannelId"
        case startDate = "StartDate"
        case endDate = "EndDate"
        case status = "Status"
        case programId = "ProgramId"
    }
}

struct TimerInfoDtoQueryResult: Codable {
    let items: [TimerInfoDto]?
    let totalRecordCount: Int?

    enum CodingKeys: String, CodingKey {
        case items = "Items"
        case totalRecordCount = "TotalRecordCount"
    }
}

struct PlaybackInfoResponse: Codable {
    let mediaSources: [MediaSourceInfo]?
    let playSessionId: String?

    enum CodingKeys: String, CodingKey {
        case mediaSources = "MediaSources"
        case playSessionId = "PlaySessionId"
    }
}

