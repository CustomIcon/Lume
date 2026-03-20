import Foundation
import SwiftData
import SwiftUI

@Observable
final class SessionManager {

    enum AuthState: Equatable {
        case unknown
        case needsServer
        case needsAuthentication
        case authenticated
    }

    private(set) var authState: AuthState = .unknown
    private(set) var currentServer: ServerConfiguration?
    private(set) var currentSession: UserSession?
    private(set) var libraries: [BaseItemDto] = []
    private(set) var isLiveTvEnabled = false
    private(set) var isLoading = false
    private(set) var error: String?
    var activeVideoItem: BaseItemDto?
    var activeBookItem: BaseItemDto?

    let apiClient: JellyfinAPIClient

    private var modelContext: ModelContext?

    init() {
        self.apiClient = JellyfinAPIClient()
    }

    func setup(modelContext: ModelContext) async {
        self.modelContext = modelContext
        LumeInfo("SessionManager starting up...")
        await loadExistingSession()
    }

    private func loadExistingSession() async {
        guard let modelContext else { return }

        do {
            let serverDescriptor = FetchDescriptor<ServerConfiguration>(
                sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
            )
            let servers = try modelContext.fetch(serverDescriptor)

            let sessionDescriptor = FetchDescriptor<UserSession>(
                predicate: #Predicate<UserSession> { $0.isActive },
                sortBy: [SortDescriptor(\.lastLoginDate, order: .reverse)]
            )
            let sessions = try modelContext.fetch(sessionDescriptor)

            if let server = servers.first, let session = sessions.first {
                self.currentServer = server
                self.currentSession = session
                await apiClient.configure(
                    baseURL: server.serverURL,
                    accessToken: session.accessToken,
                    userId: session.userID,
                    deviceId: server.deviceID
                )
                LumeInfo("Found saved session for \(session.username) on \(server.serverURL)")
                // Validate the session is still active
                do {
                    _ = try await apiClient.getUserViews()
                    authState = .authenticated
                    await loadLibraries()
                } catch {
                    // Token might be expired
                    authState = .needsAuthentication
                }
            } else if let server = servers.first {
                self.currentServer = server
                await apiClient.configure(baseURL: server.serverURL, deviceId: server.deviceID)
                authState = .needsAuthentication
            } else {
                authState = .needsServer
            }
        } catch {
            authState = .needsServer
        }
    }

    func validateAndSaveServer(url: String) async throws -> PublicServerInfo {
        isLoading = true
        error = nil
        defer { isLoading = false }

        let cleanURL = url.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))

        await apiClient.configure(baseURL: cleanURL)

        let info = try await apiClient.getPublicServerInfo()

        guard let modelContext else { throw APIError.invalidResponse }

        // Remove old servers
        let existingServers = try modelContext.fetch(FetchDescriptor<ServerConfiguration>())
        for server in existingServers {
            modelContext.delete(server)
        }

        let server = ServerConfiguration(
            serverURL: cleanURL,
            serverName: info.serverName ?? "",
            serverVersion: info.version ?? ""
        )

        modelContext.insert(server)
        try modelContext.save()

        self.currentServer = server
        await apiClient.configure(baseURL: cleanURL, deviceId: server.deviceID)
        authState = .needsAuthentication

        return info
    }

    func login(username: String, password: String) async throws {
        isLoading = true
        error = nil
        defer { isLoading = false }

        let result = try await apiClient.authenticateByName(username: username, password: password)

        guard let token = result.accessToken,
              let userId = result.user?.id,
              let userName = result.user?.name else {
            throw APIError.invalidResponse
        }

        guard let modelContext, let server = currentServer else {
            throw APIError.invalidResponse
        }

        // Deactivate old sessions
        let existingSessions = try modelContext.fetch(FetchDescriptor<UserSession>())
        for session in existingSessions {
            session.isActive = false
        }

        let session = UserSession(
            userID: userId,
            username: userName,
            accessToken: token,
            serverID: server.deviceID
        )

        modelContext.insert(session)
        try modelContext.save()

        self.currentSession = session
        authState = .authenticated
        LumeInfo("Authenticated successfully as \(userName)")
        await loadLibraries()
    }

    func switchServer(to server: ServerConfiguration) async {
        LumeInfo("Switching to server: \(server.serverName ?? "Unknown") (\(server.serverURL))")
        self.currentServer = server
        
        // Find stored session for this server
        guard let modelContext else { return }
        let deviceID = server.deviceID
        let descriptor = FetchDescriptor<UserSession>(
            predicate: #Predicate<UserSession> { $0.isActive && $0.serverID == deviceID },
            sortBy: [SortDescriptor(\.lastLoginDate, order: .reverse)]
        )
        
        do {
            let sessions = try modelContext.fetch(descriptor)
            if let session = sessions.first {
                LumeInfo("Found active session for user \(session.username)")
                self.currentSession = session
                await apiClient.configure(
                    baseURL: server.serverURL,
                    accessToken: session.accessToken,
                    userId: session.userID,
                    deviceId: server.deviceID
                )
                authState = .authenticated
                await loadLibraries()
            } else {
                LumeInfo("No active session for this server. Redirecting to login.")
                self.currentSession = nil
                await apiClient.configure(baseURL: server.serverURL, deviceId: server.deviceID)
                authState = .needsAuthentication
            }
        } catch {
            LumeError("Failed to fetch session for server switch: \(error.localizedDescription)")
            authState = .needsAuthentication
        }
    }

    func initiateQuickConnect() async throws -> QuickConnectResult {
        isLoading = true
        error = nil
        defer { isLoading = false }

        return try await apiClient.initiateQuickConnect()
    }

    func pollQuickConnect(secret: String) async throws -> Bool {
        let state = try await apiClient.checkQuickConnect(secret: secret)
        return state.authenticated ?? false
    }

    func completeQuickConnect(secret: String) async throws {
        isLoading = true
        error = nil
        defer { isLoading = false }

        let result = try await apiClient.authenticateWithQuickConnect(secret: secret)

        guard let token = result.accessToken,
              let userId = result.user?.id,
              let userName = result.user?.name else {
            throw APIError.invalidResponse
        }

        guard let modelContext, let server = currentServer else {
            throw APIError.invalidResponse
        }

        let existingSessions = try modelContext.fetch(FetchDescriptor<UserSession>())
        for session in existingSessions {
            session.isActive = false
        }

        let session = UserSession(
            userID: userId,
            username: userName,
            accessToken: token,
            serverID: server.deviceID
        )

        modelContext.insert(session)
        try modelContext.save()

        self.currentSession = session
        authState = .authenticated
        LumeInfo("QuickConnect completed as \(userName)")
        await loadLibraries()
    }

    func loadLibraries() async {
        do {
            let result = try await apiClient.getUserViews()
            let allowedTypes = ["movies", "tvshows", "music", "livetv", "books"]
            libraries = (result.items ?? []).filter { allowedTypes.contains($0.collectionType ?? "") }

            // Cache libraries
            if let modelContext, let userId = currentSession?.userID {
                let existingCached = try modelContext.fetch(FetchDescriptor<CachedLibrary>(
                    predicate: #Predicate<CachedLibrary> { $0.userID == userId }
                ))
                for cached in existingCached {
                    modelContext.delete(cached)
                }

                for (index, lib) in libraries.enumerated() {
                    let cached = CachedLibrary(
                        itemID: lib.id ?? "",
                        name: lib.name ?? "",
                        collectionType: lib.collectionType ?? "unknown",
                        sortOrder: index,
                        imageTag: lib.imageTags?["Primary"],
                        userID: userId
                    )
                    modelContext.insert(cached)
                }
                try modelContext.save()
            }
            LumeInfo("Loaded \(libraries.count) libraries (Movies/TV/Music/Books)")
            
            // Check if Live TV is available and has channels
            do {
                let liveResult = try await apiClient.getLiveTvChannels(limit: 1)
                let count = liveResult.totalRecordCount ?? liveResult.items?.count ?? 0
                if count > 0 && !libraries.contains(where: { $0.collectionType == "livetv" }) {
                    let liveTvLib = BaseItemDto(name: "Live TV", id: "livetv-virtual", collectionType: "livetv")
                    libraries.append(liveTvLib)
                    LumeInfo("Live TV is available, added to libraries.")
                }
            } catch {
                LumeInfo("Live TV not available or access denied: \(error.localizedDescription)")
            }
        } catch {
            self.error = error.localizedDescription
            LumeError("Failed to load libraries: \(error.localizedDescription)")
        }
    }

    func refreshLibraries() async {
        await loadLibraries()
    }

    func logout() async {
        LumeInfo("Logging out of current session.")
        if let session = currentSession {
            session.isActive = false
            try? modelContext?.save()
        }
        await apiClient.clearAuth()
        currentSession = nil
        libraries = []
        authState = .needsAuthentication
    }

    func disconnectServer() async {
        LumeInfo("Disconnecting current server.")
        await logout()
        if let server = currentServer, let modelContext {
            // Only delete if it's the currently active one during explicit disconnect request
            // modelContext.delete(server) // Removed: Keep server in SwiftData for multi-server list
            server.isActive = false 
            try? modelContext.save()
        }
        currentServer = nil
        authState = .needsServer
    }

    func toggleFavorite(itemId: String, isFavorite: Bool) async throws -> UserItemDataDto {
        if isFavorite {
            return try await apiClient.removeFavorite(itemId: itemId)
        } else {
            return try await apiClient.addFavorite(itemId: itemId)
        }
    }

    func togglePlayed(itemId: String, isPlayed: Bool) async throws -> UserItemDataDto {
        if isPlayed {
            return try await apiClient.markUnplayed(itemId: itemId)
        } else {
            return try await apiClient.markPlayed(itemId: itemId)
        }
    }
}
