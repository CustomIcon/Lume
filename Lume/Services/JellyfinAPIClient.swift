@preconcurrency import Foundation

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

    init(baseURL: String = "", accessToken: String? = nil, userId: String? = nil, deviceId: String = UUID().uuidString, ignoreSSLErrors: Bool = false) {
        self.session = URLSession.lume
        self.baseURL = baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        self.accessToken = accessToken
        self.userId = userId
        self.deviceId = deviceId
        self.deviceName = Host.current().localizedName ?? "Mac"
        LumeSessionDelegate.shared.ignoreSSLErrors = ignoreSSLErrors
    }

    func configure(baseURL: String, accessToken: String? = nil, userId: String? = nil, deviceId: String? = nil, ignoreSSLErrors: Bool = false) {
        self.baseURL = baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        self.accessToken = accessToken
        self.userId = userId
        if let deviceId { self.deviceId = deviceId }
        LumeSessionDelegate.shared.ignoreSSLErrors = ignoreSSLErrors
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

    private func buildURL(path: String, queryItems: [URLQueryItem]? = nil) throws -> URL {
        guard let base = URL(string: baseURL + "/") else {
            throw APIError.invalidURL
        }
        
        let urlWithPath = base.appending(path: path.trimmingCharacters(in: CharacterSet(charactersIn: "/")))
        guard var components = URLComponents(url: urlWithPath, resolvingAgainstBaseURL: false) else {
            throw APIError.invalidURL
        }
        
        var allQueryItems = (queryItems ?? [])
        if let token = accessToken {
            allQueryItems.append(URLQueryItem(name: "Token", value: token))
            allQueryItems.append(URLQueryItem(name: "api_key", value: token))
        }
        
        if !allQueryItems.isEmpty {
            components.queryItems = allQueryItems
        }
        
        guard let url = components.url else {
            throw APIError.invalidURL
        }
        return url
    }

    private func buildRequest(method: String = "GET", path: String, queryItems: [URLQueryItem]? = nil, bodyData: Data? = nil) throws -> URLRequest {
        let url = try buildURL(path: path, queryItems: queryItems)
        var request = URLRequest(url: url)
        request.httpMethod = method
        
        let auth = authorizationHeader
        request.setValue(auth, forHTTPHeaderField: "Authorization")
        request.setValue(auth, forHTTPHeaderField: "X-Emby-Authorization")
        
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        
        if let bodyData {
            request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
            request.httpBody = bodyData
        } else if method == "POST" || method == "PUT" || method == "DELETE" {
            request.setValue("0", forHTTPHeaderField: "Content-Length")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        
        return request
    }

    private func executeData(_ request: URLRequest, timeout: TimeInterval? = nil) async throws -> Data {
        var finalRequest = request
        if let timeout {
            finalRequest.timeoutInterval = timeout
        } else {
            // Default timeout for all API requests to 15s instead of standard 60s
            finalRequest.timeoutInterval = 15.0
        }
        
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: finalRequest)
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

        return data
    }

    private func executeVoid(_ request: URLRequest, timeout: TimeInterval? = nil) async throws {
        var finalRequest = request
        if let timeout {
            finalRequest.timeoutInterval = timeout
        }
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

    func getPublicServerInfo() async throws -> PublicServerInfo {
        let request = try buildRequest(path: "/System/Info/Public")
        let data = try await executeData(request)
        return try await MainActor.run { try JSONDecoder().decode(PublicServerInfo.self, from: data) }
    }

    func authenticateByName(username: String, password: String) async throws -> AuthenticationResult {
        let body = AuthenticationRequest(username: username, pw: password)
        let bodyData = try await MainActor.run { try JSONEncoder().encode(body) }
        let request = try buildRequest(method: "POST", path: "/Users/AuthenticateByName", bodyData: bodyData)
        let data = try await executeData(request)
        let result = try await MainActor.run { try JSONDecoder().decode(AuthenticationResult.self, from: data) }

        if let token = result.accessToken, let uid = result.user?.id {
            self.accessToken = token
            self.userId = uid
        }

        return result
    }

    func initiateQuickConnect() async throws -> QuickConnectResult {
        let request = try buildRequest(method: "POST", path: "/QuickConnect/Initiate")
        let data = try await executeData(request)
        return try await MainActor.run { try JSONDecoder().decode(QuickConnectResult.self, from: data) }
    }

    func checkQuickConnect(secret: String) async throws -> QuickConnectState {
        let queryItems = [URLQueryItem(name: "Secret", value: secret)]
        let request = try buildRequest(path: "/QuickConnect/Connect", queryItems: queryItems)
        let data = try await executeData(request)
        return try await MainActor.run { try JSONDecoder().decode(QuickConnectState.self, from: data) }
    }

    func authenticateWithQuickConnect(secret: String) async throws -> AuthenticationResult {
        let bodyData = try JSONSerialization.data(withJSONObject: ["Secret": secret])
        let request = try buildRequest(method: "POST", path: "/Users/AuthenticateWithQuickConnect", bodyData: bodyData)
        let data = try await executeData(request)
        let result = try await MainActor.run { try JSONDecoder().decode(AuthenticationResult.self, from: data) }

        if let token = result.accessToken, let uid = result.user?.id {
            self.accessToken = token
            self.userId = uid
        }

        return result
    }

    func ping() async -> Bool {
        guard !baseURL.isEmpty else { return false }
        do {
            // Faster 2.5s timeout for ping
            let request = try buildRequest(path: "/System/Info/Public")
            _ = try await executeData(request, timeout: 2.5)
            return true
        } catch {
            return false
        }
    }

    func getUserViews(timeout: TimeInterval? = nil) async throws -> BaseItemDtoQueryResult {
        guard let userId else { throw APIError.unauthorized }
        let request = try buildRequest(path: "/Users/\(userId)/Views")
        let data = try await executeData(request, timeout: timeout)
        return try await MainActor.run { try JSONDecoder().decode(BaseItemDtoQueryResult.self, from: data) }
    }

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
        artistIds: [String]? = nil,
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
        if let artistIds { queryItems.append(URLQueryItem(name: "ArtistIds", value: artistIds.joined(separator: ","))) }
        if let studioIds { queryItems.append(URLQueryItem(name: "StudioIds", value: studioIds)) }
        if let ids { queryItems.append(URLQueryItem(name: "Ids", value: ids.joined(separator: ","))) }
        if let isPlayed { queryItems.append(URLQueryItem(name: "IsPlayed", value: String(isPlayed))) }
        if let enableImageTypes { queryItems.append(URLQueryItem(name: "EnableImageTypes", value: enableImageTypes.joined(separator: ","))) }
        if let imageTypeLimit { queryItems.append(URLQueryItem(name: "ImageTypeLimit", value: String(imageTypeLimit))) }
        if let seasonId { queryItems.append(URLQueryItem(name: "SeasonId", value: seasonId)) }
        if let seriesId { queryItems.append(URLQueryItem(name: "SeriesId", value: seriesId)) }
        if let isFavorite { queryItems.append(URLQueryItem(name: "IsFavorite", value: String(isFavorite))) }

        let request = try buildRequest(path: "/Users/\(userId)/Items", queryItems: queryItems)
        let data = try await executeData(request)
        return try await MainActor.run { try JSONDecoder().decode(BaseItemDtoQueryResult.self, from: data) }
    }

    func getItem(itemId: String) async throws -> BaseItemDto {
        guard let userId else { throw APIError.unauthorized }
        let queryItems = [
            URLQueryItem(name: "Fields", value: "PrimaryImageAspectRatio,Overview,People,Genres,Studios,CommunityRating,OfficialRating,MediaSources,MediaStreams,ExternalUrls,ProviderIds,RemoteTrailers")
        ]
        let request = try buildRequest(path: "/Users/\(userId)/Items/\(itemId)", queryItems: queryItems)
        let data = try await executeData(request)
        return try await MainActor.run { try JSONDecoder().decode(BaseItemDto.self, from: data) }
    }

    func getRecommendations() async throws -> [BaseItemDto] {
        guard let userId else { throw APIError.unauthorized }
        let queryItems = [
            URLQueryItem(name: "Fields", value: "PrimaryImageAspectRatio,UserData,Overview"),
            URLQueryItem(name: "Limit", value: "12")
        ]
        let request = try buildRequest(path: "/Users/\(userId)/Suggestions", queryItems: queryItems)
        let data = try await executeData(request)
        
        // Suggestions returns a BaseItemDtoQueryResult or similar? 
        // Actually /Suggestions returns items directly or wrapped. 
        // Let's assume BaseItemDtoQueryResult for safety if it's a query result.
        // Actually /Suggestions returns a list of items.
        let result = try await MainActor.run { try JSONDecoder().decode(BaseItemDtoQueryResult.self, from: data) }
        return result.items ?? []
    }

    func getSimilarItems(itemId: String, limit: Int = 12) async throws -> BaseItemDtoQueryResult {
        let queryItems = [
            URLQueryItem(name: "Limit", value: String(limit)),
            URLQueryItem(name: "Fields", value: "PrimaryImageAspectRatio,UserData")
        ]
        let request = try buildRequest(path: "/Items/\(itemId)/Similar", queryItems: queryItems)
        let data = try await executeData(request)
        return try await MainActor.run { try JSONDecoder().decode(BaseItemDtoQueryResult.self, from: data) }
    }

    func getSeasons(seriesId: String) async throws -> BaseItemDtoQueryResult {
        guard let userId else { throw APIError.unauthorized }
        let queryItems = [
            URLQueryItem(name: "UserId", value: userId),
            URLQueryItem(name: "Fields", value: "ItemCounts,PrimaryImageAspectRatio")
        ]
        let request = try buildRequest(path: "/Shows/\(seriesId)/Seasons", queryItems: queryItems)
        let data = try await executeData(request)
        return try await MainActor.run { try JSONDecoder().decode(BaseItemDtoQueryResult.self, from: data) }
    }

    func getEpisodes(seriesId: String, seasonId: String) async throws -> BaseItemDtoQueryResult {
        guard let userId else { throw APIError.unauthorized }
        let queryItems = [
            URLQueryItem(name: "UserId", value: userId),
            URLQueryItem(name: "SeasonId", value: seasonId),
            URLQueryItem(name: "Fields", value: "Overview,PrimaryImageAspectRatio,MediaSources,MediaStreams")
        ]
        let request = try buildRequest(path: "/Shows/\(seriesId)/Episodes", queryItems: queryItems)
        let data = try await executeData(request)
        return try await MainActor.run { try JSONDecoder().decode(BaseItemDtoQueryResult.self, from: data) }
    }

    func getNextUp(parentId: String? = nil, limit: Int = 20) async throws -> BaseItemDtoQueryResult {
        guard let userId else { throw APIError.unauthorized }
        var queryItems = [
            URLQueryItem(name: "UserId", value: userId),
            URLQueryItem(name: "Limit", value: String(limit)),
            URLQueryItem(name: "Fields", value: "PrimaryImageAspectRatio,Overview,MediaSources,SeriesId,SeriesName,ParentId,Type,ImageTags,ParentBackdropImageTags,ParentBackdropItemId,ParentLogoImageTag,ParentLogoItemId,RemoteTrailers")
        ]
        if let parentId {
            queryItems.append(URLQueryItem(name: "ParentId", value: parentId))
        }
        let request = try buildRequest(path: "/Shows/NextUp", queryItems: queryItems)
        let data = try await executeData(request)
        return try await MainActor.run { try JSONDecoder().decode(BaseItemDtoQueryResult.self, from: data) }
    }

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
        let data = try await executeData(request)
        return try await MainActor.run { try JSONDecoder().decode(BaseItemDtoQueryResult.self, from: data) }
    }

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
        let data = try await executeData(request)
        return try await MainActor.run { try JSONDecoder().decode([BaseItemDto].self, from: data) }
    }

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
        let data = try await executeData(request)
        return try await MainActor.run { try JSONDecoder().decode(BaseItemDtoQueryResult.self, from: data) }
    }

    func getAlbumArtists(parentId: String? = nil, limit: Int? = nil, startIndex: Int? = nil, sortBy: [String]? = nil, sortOrder: String? = nil) async throws -> BaseItemDtoQueryResult {
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
        let request = try buildRequest(path: "/Artists/AlbumArtists", queryItems: queryItems)
        let data = try await executeData(request)
        return try await MainActor.run { try JSONDecoder().decode(BaseItemDtoQueryResult.self, from: data) }
    }

    func getMusicGenres(parentId: String? = nil, sortBy: [String]? = nil, sortOrder: String? = nil) async throws -> BaseItemDtoQueryResult {
        guard let userId else { throw APIError.unauthorized }
        var queryItems = [
            URLQueryItem(name: "UserId", value: userId),
            URLQueryItem(name: "Fields", value: "PrimaryImageAspectRatio,SortName,ImageTags"),
            URLQueryItem(name: "Recursive", value: "true")
        ]
        if let parentId { queryItems.append(URLQueryItem(name: "ParentId", value: parentId)) }
        if let sortBy { queryItems.append(URLQueryItem(name: "SortBy", value: sortBy.joined(separator: ","))) }
        if let sortOrder { queryItems.append(URLQueryItem(name: "SortOrder", value: sortOrder)) }
        let request = try buildRequest(path: "/MusicGenres", queryItems: queryItems)
        let data = try await executeData(request)
        return try await MainActor.run { try JSONDecoder().decode(BaseItemDtoQueryResult.self, from: data) }
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
        let data = try await executeData(request)
        return try await MainActor.run { try JSONDecoder().decode(BaseItemDtoQueryResult.self, from: data) }
    }

    func getSongs(parentId: String? = nil, albumId: String? = nil, limit: Int? = nil, sortBy: [String]? = nil, sortOrder: String? = nil) async throws -> BaseItemDtoQueryResult {
        guard let userId else { throw APIError.unauthorized }
        var queryItems = [
            URLQueryItem(name: "IncludeItemTypes", value: "Audio"),
            URLQueryItem(name: "Recursive", value: "true"),
            URLQueryItem(name: "Fields", value: "PrimaryImageAspectRatio,MediaSources,Artists,AlbumArtist")
        ]
        if let parentId { queryItems.append(URLQueryItem(name: "ParentId", value: parentId)) }
        if let albumId { queryItems.append(URLQueryItem(name: "AlbumIds", value: albumId)) }
        if let limit { queryItems.append(URLQueryItem(name: "Limit", value: String(limit))) }
        if let sortBy { queryItems.append(URLQueryItem(name: "SortBy", value: sortBy.joined(separator: ","))) }
        if let sortOrder { queryItems.append(URLQueryItem(name: "SortOrder", value: sortOrder)) }
        let request = try buildRequest(path: "/Users/\(userId)/Items", queryItems: queryItems)
        let data = try await executeData(request)
        return try await MainActor.run { try JSONDecoder().decode(BaseItemDtoQueryResult.self, from: data) }
    }

    func getInstantMix(itemId: String, limit: Int = 50) async throws -> BaseItemDtoQueryResult {
        guard let userId else { throw APIError.unauthorized }
        let queryItems = [
            URLQueryItem(name: "UserId", value: userId),
            URLQueryItem(name: "Limit", value: String(limit)),
            URLQueryItem(name: "Fields", value: "PrimaryImageAspectRatio,Overview,MediaSources,Artists,AlbumArtist")
        ]
        let request = try buildRequest(path: "/Items/\(itemId)/InstantMix", queryItems: queryItems)
        let data = try await executeData(request)
        return try await MainActor.run { try JSONDecoder().decode(BaseItemDtoQueryResult.self, from: data) }
    }

    func getLiveTvChannels(limit: Int? = nil, startIndex: Int? = nil, searchTerm: String? = nil) async throws -> BaseItemDtoQueryResult {
        guard let userId else { throw APIError.unauthorized }
        
        var queryItems = [
            URLQueryItem(name: "UserId", value: userId),
            URLQueryItem(name: "Fields", value: "PrimaryImageAspectRatio,Overview"),
            URLQueryItem(name: "SortBy", value: "SortName"),
            URLQueryItem(name: "SortOrder", value: "Ascending"),
            URLQueryItem(name: "EnableTotalRecordCount", value: "true"),
            URLQueryItem(name: "EnableFavoriteSorting", value: "true")
        ]
        if let limit { queryItems.append(URLQueryItem(name: "Limit", value: String(limit))) }
        if let startIndex { queryItems.append(URLQueryItem(name: "StartIndex", value: String(startIndex))) }
        if let searchTerm, !searchTerm.isEmpty { queryItems.append(URLQueryItem(name: "searchTerm", value: searchTerm)) }
        
        // Use the official endpoint without dual API keys.
        let request = try buildRequest(path: "/LiveTv/Channels", queryItems: queryItems)
        let data = try await executeData(request)
        return try await MainActor.run { try JSONDecoder().decode(BaseItemDtoQueryResult.self, from: data) }
    }

    func getLiveTvPrograms(channelIds: [String]? = nil, limit: Int? = nil) async throws -> BaseItemDtoQueryResult {
        guard let userId else { throw APIError.unauthorized }
        var queryItems = [
            URLQueryItem(name: "UserId", value: userId),
            URLQueryItem(name: "HasAired", value: "false"),
            URLQueryItem(name: "IsAiring", value: "true"),
            URLQueryItem(name: "Fields", value: "PrimaryImageAspectRatio,Overview"),
            URLQueryItem(name: "EnableTotalRecordCount", value: "false")
        ]
        if let channelIds, !channelIds.isEmpty {
            queryItems.append(URLQueryItem(name: "ChannelIds", value: channelIds.joined(separator: ",")))
        }
        if let limit { queryItems.append(URLQueryItem(name: "Limit", value: String(limit))) }
        let request = try buildRequest(path: "/LiveTv/Programs", queryItems: queryItems)
        let data = try await executeData(request)
        return try await MainActor.run { try JSONDecoder().decode(BaseItemDtoQueryResult.self, from: data) }
    }

    func getLiveTvRecordings(limit: Int? = nil, startIndex: Int? = nil, searchTerm: String? = nil) async throws -> BaseItemDtoQueryResult {
        guard let userId else { throw APIError.unauthorized }
        
        var queryItems = [
            URLQueryItem(name: "UserId", value: userId),
            URLQueryItem(name: "Fields", value: "PrimaryImageAspectRatio,Overview"),
            URLQueryItem(name: "EnableTotalRecordCount", value: "true")
        ]
        if let limit { queryItems.append(URLQueryItem(name: "Limit", value: String(limit))) }
        if let startIndex { queryItems.append(URLQueryItem(name: "StartIndex", value: String(startIndex))) }
        if let searchTerm, !searchTerm.isEmpty { queryItems.append(URLQueryItem(name: "searchTerm", value: searchTerm)) }
        
        let request = try buildRequest(path: "/LiveTv/Recordings", queryItems: queryItems)
        let data = try await executeData(request)
        return try await MainActor.run { try JSONDecoder().decode(BaseItemDtoQueryResult.self, from: data) }
    }

    func reportPlaybackStart(_ info: PlaybackStartInfo) async throws {
        let bodyData = try await MainActor.run { try JSONEncoder().encode(info) }
        let request = try buildRequest(method: "POST", path: "/Sessions/Playing", bodyData: bodyData)
        try await executeVoid(request)
    }

    func reportPlaybackProgress(_ info: PlaybackProgressInfo) async throws {
        let bodyData = try await MainActor.run { try JSONEncoder().encode(info) }
        let request = try buildRequest(method: "POST", path: "/Sessions/Playing/Progress", bodyData: bodyData)
        try await executeVoid(request)
    }

    func reportPlaybackStopped(_ info: PlaybackStopInfo) async throws {
        let bodyData = try await MainActor.run { try JSONEncoder().encode(info) }
        let request = try buildRequest(method: "POST", path: "/Sessions/Playing/Stopped", bodyData: bodyData)
        try await executeVoid(request)
    }

    func addFavorite(itemId: String) async throws -> UserItemDataDto {
        guard let userId else { throw APIError.unauthorized }
        let request = try buildRequest(method: "POST", path: "/Users/\(userId)/FavoriteItems/\(itemId)")
        let data = try await executeData(request)
        return try await MainActor.run { try JSONDecoder().decode(UserItemDataDto.self, from: data) }
    }

    func removeFavorite(itemId: String) async throws -> UserItemDataDto {
        guard let userId else { throw APIError.unauthorized }
        let request = try buildRequest(method: "DELETE", path: "/Users/\(userId)/FavoriteItems/\(itemId)")
        let data = try await executeData(request)
        return try await MainActor.run { try JSONDecoder().decode(UserItemDataDto.self, from: data) }
    }

    func markPlayed(itemId: String) async throws -> UserItemDataDto {
        guard let userId else { throw APIError.unauthorized }
        let request = try buildRequest(method: "POST", path: "/Users/\(userId)/PlayedItems/\(itemId)")
        let data = try await executeData(request)
        return try await MainActor.run { try JSONDecoder().decode(UserItemDataDto.self, from: data) }
    }

    func markUnplayed(itemId: String) async throws -> UserItemDataDto {
        guard let userId else { throw APIError.unauthorized }
        let request = try buildRequest(method: "DELETE", path: "/Users/\(userId)/PlayedItems/\(itemId)")
        let data = try await executeData(request)
        return try await MainActor.run { try JSONDecoder().decode(UserItemDataDto.self, from: data) }
    }

    func getLocalTrailers(itemId: String) async throws -> [BaseItemDto] {
        guard let userId else { throw APIError.unauthorized }
        let request = try buildRequest(path: "/Users/\(userId)/Items/\(itemId)/LocalTrailers")
        let data = try await executeData(request)
        return try await MainActor.run { try JSONDecoder().decode([BaseItemDto].self, from: data) }
    }

    func imageURL(itemId: String, imageType: String = "Primary", maxWidth: Int? = nil, maxHeight: Int? = nil, tag: String? = nil) async -> URL? {
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

    func personImageURL(personId: String, tag: String? = nil, maxWidth: Int? = nil) async -> URL? {
        var path = "\(baseURL)/Items/\(personId)/Images/Primary"
        var queryItems: [String] = []
        if let maxWidth { queryItems.append("maxWidth=\(maxWidth)") }
        if let tag { queryItems.append("tag=\(tag)") }
        if !queryItems.isEmpty {
            path += "?" + queryItems.joined(separator: "&")
        }
        return URL(string: path)
    }

    func streamURL(itemId: String, mediaSourceId: String? = nil, audioStreamIndex: Int? = nil, subtitleStreamIndex: Int? = nil, maxBitrate: Int = 140_000_000) async -> URL? {
        guard let userId = self.userId else { return nil }
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

    func getPlaybackInfo(itemId: String, mediaSourceId: String? = nil, audioStreamIndex: Int? = nil, subtitleStreamIndex: Int? = nil, maxBitrate: Int = 140_000_000, allowDirectPlay: Bool = true) async throws -> PlaybackInfoResponse {
        guard let userId else { throw APIError.unauthorized }
        let path = "/Items/\(itemId)/PlaybackInfo"
        var queryItems = [
            URLQueryItem(name: "UserId", value: userId),
            URLQueryItem(name: "StartTimeTicks", value: "0"),
            URLQueryItem(name: "IsPlayback", value: "true"),
            URLQueryItem(name: "AutoOpenLiveStream", value: "true"),
            URLQueryItem(name: "MaxStreamingBitrate", value: String(maxBitrate))
        ]
        if let token = accessToken { queryItems.append(URLQueryItem(name: "api_key", value: token)) }
        if let mediaSourceId = mediaSourceId { queryItems.append(URLQueryItem(name: "MediaSourceId", value: mediaSourceId)) }
        
        let deviceProfile: [String: Any] = [
            "MaxStreamingBitrate": maxBitrate,
            "MaxStaticBitrate": maxBitrate,
            "DirectPlayProfiles": allowDirectPlay ? [
                ["Container": "mp4,m4v,mov,mkv,avi,ts,mpegts", "Type": "Video", "VideoCodec": "h264,hevc,vp8,vp9,av1", "AudioCodec": "aac,mp3,ac3,eac3,dts,flac,opus,vorbis"]
            ] : [],
            "TranscodingProfiles": [
                ["Container": "ts", "Type": "Video", "VideoCodec": "h264", "AudioCodec": "aac,mp3", "Protocol": "hls", "Context": "Streaming", "BreakOnNonKeyFrames": true]
            ],
            "SubtitleProfiles": [
                ["Format": "vtt", "Method": "Embed"], ["Format": "srt", "Method": "Embed"], ["Format": "ass", "Method": "Embed"], ["Format": "ssa", "Method": "Embed"], ["Format": "pgssub", "Method": "Embed"], ["Format": "subrip", "Method": "Embed"], ["Format": "vtt", "Method": "External"], ["Format": "srt", "Method": "External"]
            ]
        ]
        
        var playbackInfoReq: [String: Any] = ["DeviceProfile": deviceProfile]
        if let aIdx = audioStreamIndex { playbackInfoReq["AudioStreamIndex"] = aIdx }
        if let sIdx = subtitleStreamIndex { playbackInfoReq["SubtitleStreamIndex"] = sIdx }
        
        let bodyData = try JSONSerialization.data(withJSONObject: playbackInfoReq, options: [])
        var request = try buildURL(path: path, queryItems: queryItems).asRequest()
        request.httpMethod = "POST"
        request.httpBody = bodyData
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(authorizationHeader, forHTTPHeaderField: "Authorization")
        request.setValue(authorizationHeader, forHTTPHeaderField: "X-Emby-Authorization")
        
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
             throw APIError.invalidResponse
        }
        return try await MainActor.run { try JSONDecoder().decode(PlaybackInfoResponse.self, from: data) }
    }

    func audioStreamURL(itemId: String) async -> URL? {
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

    func downloadURL(itemId: String) async -> URL? {
        var path = "\(baseURL)/Items/\(itemId)/Download"
        if let token = accessToken {
            path += "?api_key=\(token)"
        }
        return URL(string: path)
    }

    func downloadBookData(itemId: String) async throws -> Data {
        let request = try buildRequest(path: "/Items/\(itemId)/Download")
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
            throw APIError.httpError(statusCode: statusCode, message: "Failed to download book")
        }
        return data
    }

    func searchItems(query: String, parentId: String? = nil, limit: Int = 24, includeItemTypes: [String]? = nil) async throws -> BaseItemDtoQueryResult {
        guard let userId else { throw APIError.unauthorized }
        var queryItems = [
            URLQueryItem(name: "SearchTerm", value: query),
            URLQueryItem(name: "Limit", value: String(limit)),
            URLQueryItem(name: "Recursive", value: "true"),
            URLQueryItem(name: "Fields", value: "PrimaryImageAspectRatio,Overview,UserData,MediaSources")
        ]
        if let parentId {
            queryItems.append(URLQueryItem(name: "ParentId", value: parentId))
        }
        if let includeItemTypes {
            queryItems.append(URLQueryItem(name: "IncludeItemTypes", value: includeItemTypes.joined(separator: ",")))
        }
        let request = try buildRequest(path: "/Users/\(userId)/Items", queryItems: queryItems)
        let data = try await executeData(request)
        return try await MainActor.run { try JSONDecoder().decode(BaseItemDtoQueryResult.self, from: data) }
    }

    func getPlaylists(limit: Int? = nil, startIndex: Int = 0) async throws -> BaseItemDtoQueryResult {
        guard let userId else { throw APIError.unauthorized }
        var queryItems = [
            URLQueryItem(name: "SortBy", value: "SortName"),
            URLQueryItem(name: "SortOrder", value: "Ascending"),
            URLQueryItem(name: "IncludeItemTypes", value: "Playlist"),
            URLQueryItem(name: "Recursive", value: "true"),
            URLQueryItem(name: "Fields", value: "PrimaryImageAspectRatio,SortName,CanDelete"),
            URLQueryItem(name: "StartIndex", value: String(startIndex)),
            URLQueryItem(name: "MediaTypes", value: "Audio")
        ]
        if let limit { queryItems.append(URLQueryItem(name: "Limit", value: String(limit))) }
        let request = try buildRequest(path: "/Users/\(userId)/Items", queryItems: queryItems)
        let data = try await executeData(request)
        return try await MainActor.run { try JSONDecoder().decode(BaseItemDtoQueryResult.self, from: data) }
    }

    func searchRemoteSubtitles(itemId: String, language: String? = nil) async throws -> [RemoteSubtitleInfo] {
        var queryItems: [URLQueryItem] = []
        if let language {
            queryItems.append(URLQueryItem(name: "Language", value: language))
        }
        let request = try buildRequest(path: "/Items/\(itemId)/RemoteSubtitles/SearchResults", queryItems: queryItems)
        let data = try await executeData(request)
        return try await MainActor.run { try JSONDecoder().decode([RemoteSubtitleInfo].self, from: data) }
    }

    func downloadRemoteSubtitle(itemId: String, id: String) async throws -> Data {
        let request = try buildRequest(method: "POST", path: "/Items/\(itemId)/RemoteSubtitles/Download/\(id)")
        return try await executeData(request)
    }

    // MARK: - Intro Skipper & Media Segments
    func getIntroTimestamps(itemId: String) async throws -> [IntroTimestamp] {
        // We try /MediaSegments (Official/Newer), /Episode (confusedpolarbear), then /Items (other variants/future specs)
        let paths = [
            "/MediaSegments/\(itemId)?includeSegmentTypes=Intro&includeSegmentTypes=Outro",
            "/Episode/\(itemId)/IntroTimestamps", 
            "/Items/\(itemId)/IntroTimestamps"
        ]
        
        for path in paths {
            do {
                let request = try buildRequest(path: path)
                let data = try await executeData(request)
                
                let segments: [IntroTimestamp]? = await MainActor.run {
                    if path.contains("MediaSegments") {
                        guard let segmentResponse = try? JSONDecoder().decode(MediaSegmentResponse.self, from: data) else { return nil }
                        return segmentResponse.items.filter { $0.type == "Intro" || $0.type == "Outro" }.map { seg in
                            IntroTimestamp(
                                start: Double(seg.startTicks) / 10_000_000.0,
                                end: Double(seg.endTicks) / 10_000_000.0,
                                type: seg.type.lowercased()
                            )
                        }
                    } else if let list = try? JSONDecoder().decode([IntroTimestamp].self, from: data) {
                        return list
                    } else if let single = try? JSONDecoder().decode(IntroTimestamp.self, from: data) {
                        return [single]
                    }
                    return nil
                }
                
                if let result = segments, !result.isEmpty {
                    return result
                }
            } catch {
                await MainActor.run {
                    LumeDebug("Intro Skipper: Tried path \(path) - not found or error: \(error.localizedDescription)")
                }
            }
        }
        
        return []
    }

    // MARK: - Trickplay / Seek Preview
    func getTrickplayManifest(itemId: String, width: Int = 320) async throws -> TrickplayManifest {
        let request = try buildRequest(path: "/Videos/\(itemId)/Trickplay/\(width)/manifest.json")
        let data = try await executeData(request)
        return try await MainActor.run { try JSONDecoder().decode(TrickplayManifest.self, from: data) }
    }

    func trickplayImageURL(itemId: String, index: Int, width: Int = 320) -> URL? {
        var path = "\(baseURL)/Videos/\(itemId)/Trickplay/\(width)/tiles/\(index).jpg"
        if let token = accessToken {
            path += "?api_key=\(token)"
        }
        return URL(string: path)
    }
}

struct TrickplayManifest: Codable {
    let version: String?
    let width: Int
    let height: Int
    let interval: Int // in milliseconds
    let count: Int
    
    enum CodingKeys: String, CodingKey {
        case version = "Version"
        case width = "Width"
        case height = "Height"
        case interval = "Interval"
        case count = "Count"
    }
}

struct IntroTimestamp: Decodable {
    let start: Double
    let end: Double
    let type: String // "intro" or "outro"
    
    enum CodingKeys: String, CodingKey {
        case start, end, type
        case introStart = "IntroStart"
        case introEnd = "IntroEnd"
    }
    
    init(start: Double, end: Double, type: String = "intro") {
        self.start = start
        self.end = end
        self.type = type
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.type = (try? container.decode(String.self, forKey: .type)) ?? "intro"
        
        // Try various key names found in different plugin versions
        if let s = try? container.decode(Double.self, forKey: .introStart) {
            self.start = s
        } else if let s = try? container.decode(Double.self, forKey: .start) {
            self.start = s
        } else {
            throw DecodingError.keyNotFound(CodingKeys.introStart, .init(codingPath: decoder.codingPath, debugDescription: "No start key found"))
        }

        if let e = try? container.decode(Double.self, forKey: .introEnd) {
            self.end = e
        } else if let e = try? container.decode(Double.self, forKey: .end) {
            self.end = e
        } else {
            throw DecodingError.keyNotFound(CodingKeys.introEnd, .init(codingPath: decoder.codingPath, debugDescription: "No end key found"))
        }
    }
}

struct MediaSegmentResponse: Decodable {
    let items: [MediaSegment]
    
    enum CodingKeys: String, CodingKey {
        case items = "Items"
    }
}

struct MediaSegment: Decodable {
    let id: String
    let type: String
    let startTicks: Int64
    let endTicks: Int64
    
    enum CodingKeys: String, CodingKey {
        case id = "Id"
        case type = "Type"
        case startTicks = "StartTicks"
        case endTicks = "EndTicks"
    }
}

extension URL {
    nonisolated func asRequest() -> URLRequest {
        URLRequest(url: self)
    }
}
