import Foundation

enum APIError: LocalizedError {
    case invalidURL
    case invalidResponse
    case httpError(statusCode: Int, message: String?)
    case decodingError(Error)
    case networkError(Error)
    case unauthorized
    case serverUnreachable

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid server URL"
        case .invalidResponse:
            return "Invalid response from server"
        case .httpError(let code, let message):
            return "HTTP \(code): \(message ?? "Unknown error")"
        case .decodingError(let error):
            return "Failed to parse response: \(error.localizedDescription)"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .unauthorized:
            return "Authentication required. Please log in again."
        case .serverUnreachable:
            return "Server is unreachable. Check your connection and server URL."
        }
    }
}

actor JellyfinAPIClient {
    private let session: URLSession
    private var baseURL: String
    private(set) var accessToken: String?
    private(set) var userId: String?
    private(set) var deviceId: String
    private let deviceName: String
    private let appName = "Lume"
    private let appVersion = "1.0"

    init(baseURL: String = "", accessToken: String? = nil, userId: String? = nil, deviceId: String = UUID().uuidString) {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 300
        self.session = URLSession(configuration: config)
        self.baseURL = baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        self.accessToken = accessToken
        self.userId = userId
        self.deviceId = deviceId
        self.deviceName = Host.current().localizedName ?? "Mac"
    }

    // MARK: - Configuration

    func configure(baseURL: String, accessToken: String? = nil, userId: String? = nil, deviceId: String? = nil) {
        self.baseURL = baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        self.accessToken = accessToken
        self.userId = userId
        if let deviceId { self.deviceId = deviceId }
    }

    func setAuth(accessToken: String, userId: String) {
        self.accessToken = accessToken
        self.userId = userId
    }

    func clearAuth() {
        self.accessToken = nil
        self.userId = nil
    }

    func getCurrentUserId() -> String? {
        userId
    }

    func getBaseURL() -> String {
        baseURL
    }

    func getDeviceId() -> String {
        deviceId
    }

    func getAccessToken() -> String? {
        accessToken
    }

    // MARK: - Authorization Header

    var authorizationHeader: String {
        var safeName = deviceName.replacingOccurrences(of: "\"", with: " ")
        safeName = safeName.unicodeScalars.filter { $0.isASCII }.map { String($0) }.joined()
        if safeName.trimmingCharacters(in: .whitespaces).isEmpty {
            safeName = "Apple_Device"
        }
        var header = "MediaBrowser Client=\"\(appName)\", Device=\"\(safeName)\", DeviceId=\"\(deviceId)\", Version=\"\(appVersion)\""
        if let token = accessToken {
            header += ", Token=\"\(token)\""
        }
        return header
    }

    // MARK: - Request Building

    private func buildURL(path: String, queryItems: [URLQueryItem]? = nil) throws -> URL {
        guard var components = URLComponents(string: "\(baseURL)\(path)") else {
            throw APIError.invalidURL
        }
        if let queryItems, !queryItems.isEmpty {
            components.queryItems = queryItems
        }
        guard let url = components.url else {
            throw APIError.invalidURL
        }
        return url
    }

    private func buildRequest<Body: Encodable>(method: String = "GET", path: String, queryItems: [URLQueryItem]? = nil, body: Body) throws -> URLRequest {
        let url = try buildURL(path: path, queryItems: queryItems)
        var request = URLRequest(url: url)
        request.httpMethod = method
        
        let auth = authorizationHeader
        request.setValue(auth, forHTTPHeaderField: "Authorization")
        request.setValue(auth, forHTTPHeaderField: "X-Emby-Authorization")
        
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        
        let encoder = JSONEncoder()
        request.httpBody = try encoder.encode(body)
        return request
    }

    private func buildRequest(method: String = "GET", path: String, queryItems: [URLQueryItem]? = nil) throws -> URLRequest {
        let url = try buildURL(path: path, queryItems: queryItems)
        var request = URLRequest(url: url)
        request.httpMethod = method
        
        let auth = authorizationHeader
        request.setValue(auth, forHTTPHeaderField: "Authorization")
        request.setValue(auth, forHTTPHeaderField: "X-Emby-Authorization")
        
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        
        // For empty POST requests, specify zero content length to prevent 400 Bad Request
        if method == "POST" || method == "PUT" || method == "DELETE" {
            request.setValue("0", forHTTPHeaderField: "Content-Length")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        
        return request
    }

    // MARK: - Request Execution

    private func execute<T: Decodable>(_ request: URLRequest) async throws -> T {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError {
            if error.code == .notConnectedToInternet || error.code == .timedOut || error.code == .cannotConnectToHost || error.code == .cannotFindHost {
                throw APIError.serverUnreachable
            }
            throw APIError.networkError(error)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        switch httpResponse.statusCode {
        case 200...299:
            break
        case 401:
            throw APIError.unauthorized
        default:
            let message = String(data: data, encoding: .utf8)
            throw APIError.httpError(statusCode: httpResponse.statusCode, message: message)
        }

        do {
            let decoder = JSONDecoder()
            return try decoder.decode(T.self, from: data)
        } catch {
            throw APIError.decodingError(error)
        }
    }

    private func executeVoid(_ request: URLRequest) async throws {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError {
            if error.code == .notConnectedToInternet || error.code == .timedOut || error.code == .cannotConnectToHost || error.code == .cannotFindHost {
                throw APIError.serverUnreachable
            }
            throw APIError.networkError(error)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        switch httpResponse.statusCode {
        case 200...299, 204:
            break
        case 401:
            throw APIError.unauthorized
        default:
            let message = String(data: data, encoding: .utf8)
            throw APIError.httpError(statusCode: httpResponse.statusCode, message: message)
        }
    }

    // MARK: - Server Info

    func getPublicServerInfo() async throws -> PublicServerInfo {
        let request = try buildRequest(path: "/System/Info/Public")
        return try await execute(request)
    }

    // MARK: - Authentication

    func authenticateByName(username: String, password: String) async throws -> AuthenticationResult {
        let body = AuthenticationRequest(username: username, pw: password)
        let request = try buildRequest(method: "POST", path: "/Users/AuthenticateByName", body: body)
        let result: AuthenticationResult = try await execute(request)

        if let token = result.accessToken, let uid = result.user?.id {
            self.accessToken = token
            self.userId = uid
        }

        return result
    }

    // MARK: - Quick Connect

    func initiateQuickConnect() async throws -> QuickConnectResult {
        let request = try buildRequest(method: "POST", path: "/QuickConnect/Initiate")
        return try await execute(request)
    }

    func checkQuickConnect(secret: String) async throws -> QuickConnectState {
        let queryItems = [URLQueryItem(name: "Secret", value: secret)]
        let request = try buildRequest(path: "/QuickConnect/Connect", queryItems: queryItems)
        return try await execute(request)
    }

    func authenticateWithQuickConnect(secret: String) async throws -> AuthenticationResult {
        let body = ["Secret": secret]
        let request = try buildRequest(method: "POST", path: "/Users/AuthenticateWithQuickConnect", body: body)
        let result: AuthenticationResult = try await execute(request)

        if let token = result.accessToken, let uid = result.user?.id {
            self.accessToken = token
            self.userId = uid
        }

        return result
    }

    // MARK: - Libraries / Views

    func getUserViews() async throws -> BaseItemDtoQueryResult {
        guard let userId else { throw APIError.unauthorized }
        let request = try buildRequest(path: "/Users/\(userId)/Views")
        return try await execute(request)
    }

    // MARK: - Items

    func getItems(
        parentId: String? = nil,
        includeItemTypes: [String]? = nil,
        sortBy: [String]? = nil,
        sortOrder: String? = nil,
        fields: [String]? = nil,
        filters: [String]? = nil,
        limit: Int? = nil,
        startIndex: Int? = nil,
        recursive: Bool? = nil,
        searchTerm: String? = nil,
        genres: [String]? = nil,
        years: [Int]? = nil,
        personIds: String? = nil,
        studioIds: String? = nil,
        ids: [String]? = nil,
        isPlayed: Bool? = nil,
        enableImageTypes: [String]? = nil,
        imageTypeLimit: Int? = nil,
        seasonId: String? = nil,
        seriesId: String? = nil,
        isFavorite: Bool? = nil
    ) async throws -> BaseItemDtoQueryResult {
        guard let userId else { throw APIError.unauthorized }

        var queryItems: [URLQueryItem] = []

        if let parentId { queryItems.append(URLQueryItem(name: "ParentId", value: parentId)) }
        if let includeItemTypes { queryItems.append(URLQueryItem(name: "IncludeItemTypes", value: includeItemTypes.joined(separator: ","))) }
        if let sortBy { queryItems.append(URLQueryItem(name: "SortBy", value: sortBy.joined(separator: ","))) }
        if let sortOrder { queryItems.append(URLQueryItem(name: "SortOrder", value: sortOrder)) }
        if let fields { queryItems.append(URLQueryItem(name: "Fields", value: fields.joined(separator: ","))) }
        if let filters { queryItems.append(URLQueryItem(name: "Filters", value: filters.joined(separator: ","))) }
        if let limit { queryItems.append(URLQueryItem(name: "Limit", value: String(limit))) }
        if let startIndex { queryItems.append(URLQueryItem(name: "StartIndex", value: String(startIndex))) }
        if let recursive { queryItems.append(URLQueryItem(name: "Recursive", value: String(recursive))) }
        if let searchTerm { queryItems.append(URLQueryItem(name: "SearchTerm", value: searchTerm)) }
        if let genres { queryItems.append(URLQueryItem(name: "Genres", value: genres.joined(separator: "|"))) }
        if let years { queryItems.append(URLQueryItem(name: "Years", value: years.map(String.init).joined(separator: ","))) }
        if let personIds { queryItems.append(URLQueryItem(name: "PersonIds", value: personIds)) }
        if let studioIds { queryItems.append(URLQueryItem(name: "StudioIds", value: studioIds)) }
        if let ids { queryItems.append(URLQueryItem(name: "Ids", value: ids.joined(separator: ","))) }
        if let isPlayed { queryItems.append(URLQueryItem(name: "IsPlayed", value: String(isPlayed))) }
        if let enableImageTypes { queryItems.append(URLQueryItem(name: "EnableImageTypes", value: enableImageTypes.joined(separator: ","))) }
        if let imageTypeLimit { queryItems.append(URLQueryItem(name: "ImageTypeLimit", value: String(imageTypeLimit))) }
        if let seasonId { queryItems.append(URLQueryItem(name: "SeasonId", value: seasonId)) }
        if let seriesId { queryItems.append(URLQueryItem(name: "SeriesId", value: seriesId)) }
        if let isFavorite { queryItems.append(URLQueryItem(name: "IsFavorite", value: String(isFavorite))) }

        let request = try buildRequest(path: "/Users/\(userId)/Items", queryItems: queryItems)
        return try await execute(request)
    }

    func getItem(itemId: String) async throws -> BaseItemDto {
        guard let userId else { throw APIError.unauthorized }
        let queryItems = [
            URLQueryItem(name: "Fields", value: "PrimaryImageAspectRatio,Overview,People,Genres,Studios,CommunityRating,OfficialRating,MediaSources,MediaStreams,ExternalUrls,ProviderIds")
        ]
        let request = try buildRequest(path: "/Users/\(userId)/Items/\(itemId)", queryItems: queryItems)
        return try await execute(request)
    }

    func getSimilarItems(itemId: String, limit: Int = 12) async throws -> BaseItemDtoQueryResult {
        let queryItems = [
            URLQueryItem(name: "Limit", value: String(limit)),
            URLQueryItem(name: "Fields", value: "PrimaryImageAspectRatio,UserData")
        ]
        let request = try buildRequest(path: "/Items/\(itemId)/Similar", queryItems: queryItems)
        return try await execute(request)
    }

    // MARK: - Seasons & Episodes

    func getSeasons(seriesId: String) async throws -> BaseItemDtoQueryResult {
        guard let userId else { throw APIError.unauthorized }
        let queryItems = [
            URLQueryItem(name: "UserId", value: userId),
            URLQueryItem(name: "Fields", value: "ItemCounts,PrimaryImageAspectRatio")
        ]
        let request = try buildRequest(path: "/Shows/\(seriesId)/Seasons", queryItems: queryItems)
        return try await execute(request)
    }

    func getEpisodes(seriesId: String, seasonId: String) async throws -> BaseItemDtoQueryResult {
        guard let userId else { throw APIError.unauthorized }
        let queryItems = [
            URLQueryItem(name: "UserId", value: userId),
            URLQueryItem(name: "SeasonId", value: seasonId),
            URLQueryItem(name: "Fields", value: "Overview,PrimaryImageAspectRatio,MediaSources,MediaStreams")
        ]
        let request = try buildRequest(path: "/Shows/\(seriesId)/Episodes", queryItems: queryItems)
        return try await execute(request)
    }

    func getNextUp(parentId: String? = nil, limit: Int = 20) async throws -> BaseItemDtoQueryResult {
        guard let userId else { throw APIError.unauthorized }
        var queryItems = [
            URLQueryItem(name: "UserId", value: userId),
            URLQueryItem(name: "Limit", value: String(limit)),
            URLQueryItem(name: "Fields", value: "PrimaryImageAspectRatio,Overview,MediaSources")
        ]
        if let parentId {
            queryItems.append(URLQueryItem(name: "ParentId", value: parentId))
        }
        let request = try buildRequest(path: "/Shows/NextUp", queryItems: queryItems)
        return try await execute(request)
    }

    // MARK: - Resume Items (Continue Watching)

    func getResumeItems(parentId: String? = nil, limit: Int = 12, mediaTypes: [String]? = nil) async throws -> BaseItemDtoQueryResult {
        guard let userId else { throw APIError.unauthorized }
        var queryItems = [
            URLQueryItem(name: "Limit", value: String(limit)),
            URLQueryItem(name: "Fields", value: "PrimaryImageAspectRatio,Overview,MediaSources")
        ]
        if let parentId {
            queryItems.append(URLQueryItem(name: "ParentId", value: parentId))
        }
        if let mediaTypes {
            queryItems.append(URLQueryItem(name: "MediaTypes", value: mediaTypes.joined(separator: ",")))
        }
        let request = try buildRequest(path: "/Users/\(userId)/Items/Resume", queryItems: queryItems)
        return try await execute(request)
    }

    // MARK: - Latest Items

    func getLatestItems(parentId: String? = nil, limit: Int = 16) async throws -> [BaseItemDto] {
        guard let userId else { throw APIError.unauthorized }
        var queryItems = [
            URLQueryItem(name: "Limit", value: String(limit)),
            URLQueryItem(name: "Fields", value: "PrimaryImageAspectRatio,Overview,UserData"),
            URLQueryItem(name: "ImageTypeLimit", value: "1"),
            URLQueryItem(name: "EnableImageTypes", value: "Primary,Backdrop,Thumb")
        ]
        if let parentId {
            queryItems.append(URLQueryItem(name: "ParentId", value: parentId))
        }
        let request = try buildRequest(path: "/Users/\(userId)/Items/Latest", queryItems: queryItems)
        return try await execute(request)
    }

    // MARK: - Music

    func getArtists(parentId: String? = nil, limit: Int? = nil, startIndex: Int? = nil, sortBy: [String]? = nil, sortOrder: String? = nil) async throws -> BaseItemDtoQueryResult {
        guard let userId else { throw APIError.unauthorized }
        var queryItems = [
            URLQueryItem(name: "UserId", value: userId),
            URLQueryItem(name: "Fields", value: "PrimaryImageAspectRatio,SortName")
        ]
        if let parentId { queryItems.append(URLQueryItem(name: "ParentId", value: parentId)) }
        if let limit { queryItems.append(URLQueryItem(name: "Limit", value: String(limit))) }
        if let startIndex { queryItems.append(URLQueryItem(name: "StartIndex", value: String(startIndex))) }
        if let sortBy { queryItems.append(URLQueryItem(name: "SortBy", value: sortBy.joined(separator: ","))) }
        if let sortOrder { queryItems.append(URLQueryItem(name: "SortOrder", value: sortOrder)) }
        let request = try buildRequest(path: "/Artists", queryItems: queryItems)
        return try await execute(request)
    }

    func getAlbums(parentId: String? = nil, artistId: String? = nil, limit: Int? = nil, startIndex: Int? = nil, sortBy: [String]? = nil, sortOrder: String? = nil) async throws -> BaseItemDtoQueryResult {
        guard let userId else { throw APIError.unauthorized }
        var queryItems = [
            URLQueryItem(name: "IncludeItemTypes", value: "MusicAlbum"),
            URLQueryItem(name: "Recursive", value: "true"),
            URLQueryItem(name: "Fields", value: "PrimaryImageAspectRatio,SortName,AlbumArtist")
        ]
        if let parentId { queryItems.append(URLQueryItem(name: "ParentId", value: parentId)) }
        if let artistId { queryItems.append(URLQueryItem(name: "AlbumArtistIds", value: artistId)) }
        if let limit { queryItems.append(URLQueryItem(name: "Limit", value: String(limit))) }
        if let startIndex { queryItems.append(URLQueryItem(name: "StartIndex", value: String(startIndex))) }
        if let sortBy { queryItems.append(URLQueryItem(name: "SortBy", value: sortBy.joined(separator: ","))) }
        if let sortOrder { queryItems.append(URLQueryItem(name: "SortOrder", value: sortOrder)) }
        let request = try buildRequest(path: "/Users/\(userId)/Items", queryItems: queryItems)
        return try await execute(request)
    }

    func getSongs(parentId: String? = nil, albumId: String? = nil, limit: Int? = nil, sortBy: [String]? = nil, sortOrder: String? = nil) async throws -> BaseItemDtoQueryResult {
        guard let userId else { throw APIError.unauthorized }
        var queryItems = [
            URLQueryItem(name: "IncludeItemTypes", value: "Audio"),
            URLQueryItem(name: "Recursive", value: "true"),
            URLQueryItem(name: "Fields", value: "PrimaryImageAspectRatio,MediaSources,Artists,AlbumArtist")
        ]
        if let parentId { queryItems.append(URLQueryItem(name: "ParentId", value: parentId)) }
        if let albumId { queryItems.append(URLQueryItem(name: "ParentId", value: albumId)) }
        if let limit { queryItems.append(URLQueryItem(name: "Limit", value: String(limit))) }
        if let sortBy { queryItems.append(URLQueryItem(name: "SortBy", value: sortBy.joined(separator: ","))) }
        if let sortOrder { queryItems.append(URLQueryItem(name: "SortOrder", value: sortOrder)) }
        let request = try buildRequest(path: "/Users/\(userId)/Items", queryItems: queryItems)
        return try await execute(request)
    }

    // MARK: - Live TV

    func getLiveTvChannels(limit: Int? = nil, startIndex: Int? = nil) async throws -> BaseItemDtoQueryResult {
        guard let userId else { throw APIError.unauthorized }
        var queryItems = [
            URLQueryItem(name: "UserId", value: userId),
            URLQueryItem(name: "Fields", value: "PrimaryImageAspectRatio"),
            URLQueryItem(name: "SortBy", value: "SortName"),
            URLQueryItem(name: "SortOrder", value: "Ascending"),
            URLQueryItem(name: "AddCurrentProgram", value: "true")
        ]
        if let limit { queryItems.append(URLQueryItem(name: "Limit", value: String(limit))) }
        if let startIndex { queryItems.append(URLQueryItem(name: "StartIndex", value: String(startIndex))) }
        let request = try buildRequest(path: "/LiveTv/Channels", queryItems: queryItems)
        return try await execute(request)
    }

    func getLiveTvRecordings(limit: Int? = nil) async throws -> BaseItemDtoQueryResult {
        guard let userId else { throw APIError.unauthorized }
        var queryItems = [
            URLQueryItem(name: "UserId", value: userId),
            URLQueryItem(name: "Fields", value: "PrimaryImageAspectRatio,Overview")
        ]
        if let limit { queryItems.append(URLQueryItem(name: "Limit", value: String(limit))) }
        let request = try buildRequest(path: "/LiveTv/Recordings", queryItems: queryItems)
        return try await execute(request)
    }

    // MARK: - Playback

    func reportPlaybackStart(_ info: PlaybackStartInfo) async throws {
        let request = try buildRequest(method: "POST", path: "/Sessions/Playing", body: info)
        try await executeVoid(request)
    }

    func reportPlaybackProgress(_ info: PlaybackProgressInfo) async throws {
        let request = try buildRequest(method: "POST", path: "/Sessions/Playing/Progress", body: info)
        try await executeVoid(request)
    }

    func reportPlaybackStopped(_ info: PlaybackStopInfo) async throws {
        let request = try buildRequest(method: "POST", path: "/Sessions/Playing/Stopped", body: info)
        try await executeVoid(request)
    }

    // MARK: - Favorites

    func addFavorite(itemId: String) async throws -> UserItemDataDto {
        guard let userId else { throw APIError.unauthorized }
        let request = try buildRequest(method: "POST", path: "/Users/\(userId)/FavoriteItems/\(itemId)")
        return try await execute(request)
    }

    func removeFavorite(itemId: String) async throws -> UserItemDataDto {
        guard let userId else { throw APIError.unauthorized }
        let request = try buildRequest(method: "DELETE", path: "/Users/\(userId)/FavoriteItems/\(itemId)")
        return try await execute(request)
    }

    // MARK: - Played Status

    func markPlayed(itemId: String) async throws -> UserItemDataDto {
        guard let userId else { throw APIError.unauthorized }
        let request = try buildRequest(method: "POST", path: "/Users/\(userId)/PlayedItems/\(itemId)")
        return try await execute(request)
    }

    func markUnplayed(itemId: String) async throws -> UserItemDataDto {
        guard let userId else { throw APIError.unauthorized }
        let request = try buildRequest(method: "DELETE", path: "/Users/\(userId)/PlayedItems/\(itemId)")
        return try await execute(request)
    }

    // MARK: - Image URLs

    func imageURL(itemId: String, imageType: String = "Primary", maxWidth: Int? = nil, maxHeight: Int? = nil, tag: String? = nil) -> URL? {
        var path = "\(baseURL)/Items/\(itemId)/Images/\(imageType)"
        var queryItems: [String] = []
        if let maxWidth { queryItems.append("maxWidth=\(maxWidth)") }
        if let maxHeight { queryItems.append("maxHeight=\(maxHeight)") }
        if let tag { queryItems.append("tag=\(tag)") }
        if !queryItems.isEmpty {
            path += "?" + queryItems.joined(separator: "&")
        }
        return URL(string: path)
    }

    func personImageURL(personId: String, tag: String? = nil, maxWidth: Int? = nil) -> URL? {
        var path = "\(baseURL)/Items/\(personId)/Images/Primary"
        var queryItems: [String] = []
        if let maxWidth { queryItems.append("maxWidth=\(maxWidth)") }
        if let tag { queryItems.append("tag=\(tag)") }
        if !queryItems.isEmpty {
            path += "?" + queryItems.joined(separator: "&")
        }
        return URL(string: path)
    }

    // MARK: - Playback URL

    func streamURL(itemId: String, mediaSourceId: String? = nil, audioStreamIndex: Int? = nil, subtitleStreamIndex: Int? = nil, maxBitrate: Int = 140_000_000) -> URL? {
        guard let userId = self.userId else { return nil }
        // Ensure paths use proper URL encoding if needed, though UUIDs and integers are safe
        var path = "\(baseURL)/Videos/\(itemId)/master.m3u8"
        var queryItems = [
            "UserId=\(userId)",
            "DeviceId=\(deviceId)",
            "PlaySessionId=\(UUID().uuidString)",
            "VideoCodec=h264,hevc",
            "AudioCodec=aac,mp3,ac3,eac3",
            "TranscodingContainer=ts",
            "TranscodingProtocol=hls",
            "MaxStreamingBitrate=\(maxBitrate)",
            "SubtitleMethod=Encode"
        ]
        if let mediaSourceId { queryItems.append("MediaSourceId=\(mediaSourceId)") }
        if let audioStreamIndex { queryItems.append("AudioStreamIndex=\(audioStreamIndex)") }
        if let subtitleStreamIndex { queryItems.append("SubtitleStreamIndex=\(subtitleStreamIndex)") }
        if let token = accessToken { queryItems.append("api_key=\(token)") }
        path += "?" + queryItems.joined(separator: "&")
        return URL(string: path)
    }

    func getPlaybackInfo(itemId: String, mediaSourceId: String? = nil, audioStreamIndex: Int? = nil, subtitleStreamIndex: Int? = nil) async throws -> PlaybackInfoResponse {
        guard let userId else { throw APIError.unauthorized }
        let path = "/Items/\(itemId)/PlaybackInfo"
        var queryItems = [
            URLQueryItem(name: "UserId", value: userId),
            URLQueryItem(name: "StartTimeTicks", value: "0"),
            URLQueryItem(name: "IsPlayback", value: "true"),
            URLQueryItem(name: "AutoOpenLiveStream", value: "true"),
            URLQueryItem(name: "MaxStreamingBitrate", value: "140000000")
        ]
        if let token = accessToken { queryItems.append(URLQueryItem(name: "api_key", value: token)) }
        if let mediaSourceId = mediaSourceId { queryItems.append(URLQueryItem(name: "MediaSourceId", value: mediaSourceId)) }
        
        // Emulate the official Swiftfin / VLCKit Device Profile
        // This profile tells the server that we support EMBEDDED subtitles for nearly every format,
        // which prevents the server from forced transcoding (burning-in) subtitles that were causing de-sync.
        let deviceProfile: [String: Any] = [
            "MaxStreamingBitrate": 140000000,
            "MaxStaticBitrate": 140000000,
            "DirectPlayProfiles": [
                ["Container": "mp4,m4v,mov,mkv,avi,ts,mpegts", "Type": "Video", "VideoCodec": "h264,hevc,vp8,vp9,av1", "AudioCodec": "aac,mp3,ac3,eac3,dts,flac,opus,vorbis"]
            ],
            "TranscodingProfiles": [
                ["Container": "ts", "Type": "Video", "VideoCodec": "h264", "AudioCodec": "aac,mp3", "Protocol": "hls", "Context": "Streaming", "BreakOnNonKeyFrames": true]
            ],
            "SubtitleProfiles": [
                ["Format": "vtt", "Method": "Embed"],
                ["Format": "srt", "Method": "Embed"],
                ["Format": "ass", "Method": "Embed"],
                ["Format": "ssa", "Method": "Embed"],
                ["Format": "pgssub", "Method": "Embed"],
                ["Format": "subrip", "Method": "Embed"],
                ["Format": "vtt", "Method": "External"],
                ["Format": "srt", "Method": "External"]
            ]
        ]
        
        var playbackInfoReq: [String: Any] = [
            "DeviceProfile": deviceProfile
        ]
        
        if let aIdx = audioStreamIndex { playbackInfoReq["AudioStreamIndex"] = aIdx }
        if let sIdx = subtitleStreamIndex { playbackInfoReq["SubtitleStreamIndex"] = sIdx }
        
        let bodyData = try JSONSerialization.data(withJSONObject: playbackInfoReq, options: [])
        
        // POST to PlaybackInfo to retrieve the custom dynamically-negotiated URL
        var request = try buildRequest(path: path, queryItems: queryItems)
        request.httpMethod = "POST"
        request.httpBody = bodyData
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        return try await execute(request)
    }

    func audioStreamURL(itemId: String) -> URL? {
        var path = "\(baseURL)/Audio/\(itemId)/stream"
        var queryItems = [
            "DeviceId=\(deviceId)",
            "Container=mp3,aac,m4a,wav,flac",
            "Static=true"
        ]
        if let token = accessToken { queryItems.append("api_key=\(token)") }
        path += "?" + queryItems.joined(separator: "&")
        return URL(string: path)
    }

    // MARK: - Search

    func searchItems(query: String, limit: Int = 24, includeItemTypes: [String]? = nil) async throws -> BaseItemDtoQueryResult {
        guard let userId else { throw APIError.unauthorized }
        var queryItems = [
            URLQueryItem(name: "SearchTerm", value: query),
            URLQueryItem(name: "Limit", value: String(limit)),
            URLQueryItem(name: "Recursive", value: "true"),
            URLQueryItem(name: "Fields", value: "PrimaryImageAspectRatio,Overview,UserData,MediaSources")
        ]
        if let includeItemTypes {
            queryItems.append(URLQueryItem(name: "IncludeItemTypes", value: includeItemTypes.joined(separator: ",")))
        }
        let request = try buildRequest(path: "/Users/\(userId)/Items", queryItems: queryItems)
        return try await execute(request)
    }
}
