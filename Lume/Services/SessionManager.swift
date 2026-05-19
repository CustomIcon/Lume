import Foundation
import SwiftData
import SwiftUI
import Network

@Observable
final class SessionManager {

    enum AuthState: Equatable {
        case unknown
        case needsServer
        case needsAuthentication
        case authenticated
    }

    private(set) var authState: AuthState = .unknown
    private(set) var isOffline: Bool = false
    private(set) var currentServer: ServerConfiguration?
    private(set) var currentSession: UserSession?
    private(set) var libraries: [BaseItemDto] = []
    private(set) var hiddenLibraryIds: Set<String> = []
    private(set) var libraryOrder: [String] = [] // Item IDs
    
    var visibleLibraries: [BaseItemDto] {
        let filtered = libraries.filter { !hiddenLibraryIds.contains($0.id ?? "") }
        
        // If we have a custom order, sort by it
        if !libraryOrder.isEmpty {
            return filtered.sorted { a, b in
                let indexA = libraryOrder.firstIndex(of: a.id ?? "") ?? Int.max
                let indexB = libraryOrder.firstIndex(of: b.id ?? "") ?? Int.max
                return indexA < indexB
            }
        }
        
        return filtered
    }

    private(set) var isLiveTvEnabled = false
    private(set) var isLoading = false
    private(set) var error: String?
    private(set) var refreshCounter = 0
    var activeVideoItem: BaseItemDto?
    var activeBookItem: BaseItemDto?
    
    private let pathMonitor = NWPathMonitor()
    private let monitorQueue = DispatchQueue(label: "NetworkMonitor")
    
    private var sidebarSettingsKey: String {
        guard let userId = currentSession?.userID, let serverId = currentServer?.deviceID else { return "sidebar_default" }
        return "sidebar_v2_\(userId)_\(serverId)"
    }
    
    func toggleLibraryVisibility(id: String) {
        if hiddenLibraryIds.contains(id) {
            hiddenLibraryIds.remove(id)
        } else {
            hiddenLibraryIds.insert(id)
        }
        saveSidebarSettings()
    }
    
    func moveLibrary(from source: IndexSet, to destination: Int) {
        var ordered = visibleLibraries
        ordered.move(fromOffsets: source, toOffset: destination)
        
        // Update the full libraryOrder based on the new visible order + keeping hidden ones at the end or wherever
        // Actually, simplest is to just store the IDs of libraries in their current order
        libraryOrder = ordered.map { $0.id ?? "" }
        
        // Also add hidden ones to the end if they aren't in the list?
        // Let's just store the order of ALL libraries.
        var fullOrder = ordered.map { $0.id ?? "" }
        for lib in libraries {
            if !fullOrder.contains(lib.id ?? "") {
                fullOrder.append(lib.id ?? "")
            }
        }
        libraryOrder = fullOrder
        saveSidebarSettings()
    }
    
    private func loadSidebarSettings() {
        let key = sidebarSettingsKey
        if let hidden = UserDefaults.standard.stringArray(forKey: "\(key)_hidden") {
            hiddenLibraryIds = Set(hidden)
        } else {
            hiddenLibraryIds = []
        }
        
        if let order = UserDefaults.standard.stringArray(forKey: "\(key)_order") {
            libraryOrder = order
        } else {
            libraryOrder = []
        }
    }
    
    private func saveSidebarSettings() {
        let key = sidebarSettingsKey
        UserDefaults.standard.set(Array(hiddenLibraryIds), forKey: "\(key)_hidden")
        UserDefaults.standard.set(libraryOrder, forKey: "\(key)_order")
    }
    
    let downloadManager = DownloadManager()
    let apiClient: JellyfinAPIClient

    private var modelContext: ModelContext?

    init() {
        self.apiClient = JellyfinAPIClient()
        startNetworkMonitoring()
    }

    private func startNetworkMonitoring() {
        pathMonitor.pathUpdateHandler = { [weak self] path in
            guard let self = self else { return }
            let isConnected = (path.status == .satisfied)
            if !isConnected {
                DispatchQueue.main.async {
                    if !self.isOffline {
                        LumeInfo("Network disconnected. Entering offline mode.")
                        self.isOffline = true
                        Task { await self.loadLibraries() }
                    }
                }
            } else {
                // Network restored. Let's try to regain online status
                DispatchQueue.main.async {
                    if self.isOffline {
                        Task {
                             if await self.apiClient.ping() {
                                 LumeInfo("Connection to server restored. Going online.")
                                 self.isOffline = false
                                 await self.loadLibraries()
                             }
                        }
                    }
                }
            }
        }
        pathMonitor.start(queue: monitorQueue)
    }

    func setup(modelContext: ModelContext) async {
        self.modelContext = modelContext
        downloadManager.setup(modelContext: modelContext)
        LumeInfo("SessionManager starting up...")
        await loadExistingSession()
    }

    private func loadExistingSession() async {
        guard let modelContext else { return }

        do {
            let serverDescriptor = FetchDescriptor<ServerConfiguration>(
                predicate: #Predicate<ServerConfiguration> { $0.isActive },
                sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
            )
            let servers = try modelContext.fetch(serverDescriptor)
            
            // If no active server found, try to get the most recently created one
            var serverToUse = servers.first
            if serverToUse == nil {
                let allServersDescriptor = FetchDescriptor<ServerConfiguration>(
                    sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
                )
                serverToUse = try modelContext.fetch(allServersDescriptor).first
            }

            let sessionDescriptor = FetchDescriptor<UserSession>(
                predicate: #Predicate<UserSession> { $0.isActive },
                sortBy: [SortDescriptor(\.lastLoginDate, order: .reverse)]
            )
            let sessions = try modelContext.fetch(sessionDescriptor)

            if let server = serverToUse, let session = sessions.first {
                self.currentServer = server
                self.currentSession = session
                loadSidebarSettings()
                LumeSessionDelegate.shared.ignoreSSLErrors = server.ignoreSSLErrors
                await apiClient.configure(
                    baseURL: server.serverURL,
                    accessToken: session.accessToken,
                    userId: session.userID,
                    deviceId: server.deviceID,
                    ignoreSSLErrors: server.ignoreSSLErrors
                )
                LumeInfo("Found saved session for \(session.username) on \(server.serverURL)")
                // Validate the session is still active with a short ping first
                if await !apiClient.ping() {
                    LumeInfo("Server ping failed on startup, entering offline mode.")
                    isOffline = true
                    authState = .authenticated
                    await loadLibraries()
                    return
                }
                
                do {
                    _ = try await apiClient.getUserViews(timeout: 5.0)
                    isOffline = false
                    authState = .authenticated
                    await loadLibraries()
                } catch {
                    // Token might be expired or other actual API error
                    LumeError("Session validation failed: \(error.localizedDescription)")
                    authState = .needsAuthentication
                }
            } else if let server = servers.first {
                self.currentServer = server
                LumeSessionDelegate.shared.ignoreSSLErrors = server.ignoreSSLErrors
                await apiClient.configure(baseURL: server.serverURL, deviceId: server.deviceID, ignoreSSLErrors: server.ignoreSSLErrors)
                authState = .needsAuthentication
            } else {
                authState = .needsServer
            }
        } catch {
            authState = .needsServer
        }
    }

    func validateAndSaveServer(url: String, ignoreSSLErrors: Bool = false) async throws -> PublicServerInfo {
        isLoading = true
        error = nil
        defer { isLoading = false }

        let cleanURL = url.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))

        LumeSessionDelegate.shared.ignoreSSLErrors = ignoreSSLErrors
        await apiClient.configure(baseURL: cleanURL, ignoreSSLErrors: ignoreSSLErrors)

        let info = try await apiClient.getPublicServerInfo()

        guard let modelContext else { throw APIError.invalidResponse }

        // Ensure only this server is active
        let allServers = try modelContext.fetch(FetchDescriptor<ServerConfiguration>())
        for s in allServers { s.isActive = false }
        
        let server = ServerConfiguration(
            serverURL: cleanURL,
            serverName: info.serverName ?? "",
            serverVersion: info.version ?? "",
            ignoreSSLErrors: ignoreSSLErrors
        )
        server.isActive = true

        modelContext.insert(server)
        try modelContext.save()

        self.currentServer = server
        await apiClient.configure(baseURL: cleanURL, deviceId: server.deviceID, ignoreSSLErrors: ignoreSSLErrors)
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

        // Deactivate other sessions
        let allSessions = try? modelContext.fetch(FetchDescriptor<UserSession>())
        for s in allSessions ?? [] { s.isActive = false }

        let session = UserSession(
            userID: userId,
            username: userName,
            accessToken: token,
            serverID: server.deviceID
        )
        session.isActive = true
        session.lastLoginDate = Date()

        modelContext.insert(session)
        try modelContext.save()

        self.currentSession = session
        authState = .authenticated
        LumeInfo("Authenticated successfully as \(userName)")
        await loadLibraries()
    }

    func switchServer(to server: ServerConfiguration) async {
        triggerFullRefresh()
        // Mark this server as active and others as inactive
        self.currentServer = server
        server.isActive = true
        
        // Find stored session for this server
        guard let modelContext else { return }
        
        // Update other servers to be inactive
        if let allServers = try? modelContext.fetch(FetchDescriptor<ServerConfiguration>()) {
            for s in allServers {
                if s.deviceID != server.deviceID { s.isActive = false }
            }
        }
        
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
                session.lastLoginDate = Date() // Renew activity
                LumeSessionDelegate.shared.ignoreSSLErrors = server.ignoreSSLErrors
                await apiClient.configure(
                    baseURL: server.serverURL,
                    accessToken: session.accessToken,
                    userId: session.userID,
                    deviceId: server.deviceID,
                    ignoreSSLErrors: server.ignoreSSLErrors
                )
                
                // Re-verify connectivity for the new server
                isOffline = await !apiClient.ping()
                LumeInfo("Connectivity for new server: \(isOffline ? "OFFLINE" : "ONLINE")")
                
                authState = .authenticated
                await loadLibraries()
            } else {
                LumeInfo("No active session for this server. Redirecting to login.")
                self.currentSession = nil
                LumeSessionDelegate.shared.ignoreSSLErrors = server.ignoreSSLErrors
                await apiClient.configure(baseURL: server.serverURL, deviceId: server.deviceID, ignoreSSLErrors: server.ignoreSSLErrors)
                authState = .needsAuthentication
            }
            try? modelContext.save()
        } catch {
            LumeError("Failed to fetch session for server switch: \(error.localizedDescription)")
            authState = .needsAuthentication
        }
    }

    func switchUser(to session: UserSession) async {
        triggerFullRefresh()
        guard let modelContext else { return }
        LumeInfo("Switching to user: \(session.username)")
        
        // Deactivate other sessions for this specific server? 
        // Not strictly necessary if we rely on lastLoginDate for startup, but cleaner.
        let deviceID = session.serverID
        let descriptor = FetchDescriptor<UserSession>(
            predicate: #Predicate<UserSession> { $0.serverID == deviceID }
        )
        if let sessions = try? modelContext.fetch(descriptor) {
            for s in sessions { s.isActive = (s.id == session.id) }
        }
        
        self.currentSession = session
        session.isActive = true
        session.lastLoginDate = Date() // Renew activity
        
        // Find server configuration and mark as active
        let serverDescriptor = FetchDescriptor<ServerConfiguration>(
            predicate: #Predicate<ServerConfiguration> { $0.deviceID == deviceID }
        )
        if let servers = try? modelContext.fetch(serverDescriptor), let server = servers.first {
            self.currentServer = server
            server.isActive = true
            
            // Mark other servers as inactive
            if let allServers = try? modelContext.fetch(FetchDescriptor<ServerConfiguration>()) {
                for s in allServers {
                    if s.deviceID != server.deviceID { s.isActive = false }
                }
            }
            
            LumeSessionDelegate.shared.ignoreSSLErrors = server.ignoreSSLErrors
            await apiClient.configure(
                baseURL: server.serverURL,
                accessToken: session.accessToken,
                userId: session.userID,
                deviceId: server.deviceID,
                ignoreSSLErrors: server.ignoreSSLErrors
            )
            
            // Re-verify connectivity for the switched user/server
            isOffline = await !apiClient.ping()
            LumeInfo("Connectivity for new selection: \(isOffline ? "OFFLINE" : "ONLINE")")
        }
        
        try? modelContext.save()
        authState = .authenticated
        await loadLibraries()
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
        loadSidebarSettings()
        if isOffline {
            await loadCachedLibraries()
            return
        }

        do {
            let result = try await apiClient.getUserViews()
            isOffline = false
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
        // Recheck connectivity when refreshing
        if await apiClient.ping() {
            isOffline = false
        } else {
            isOffline = true
        }
        await loadLibraries()
    }

    private func loadCachedLibraries() async {
        guard let modelContext, let userId = currentSession?.userID else { return }
        
        do {
            let descriptor = FetchDescriptor<CachedLibrary>(
                predicate: #Predicate<CachedLibrary> { $0.userID == userId },
                sortBy: [SortDescriptor(\.sortOrder)]
            )
            let cached = try modelContext.fetch(descriptor)
            
            self.libraries = cached.map { c in
                var item = BaseItemDto(name: c.name, id: c.itemID, collectionType: c.collectionType)
                if let tag = c.imageTag {
                    item.imageTags = ["Primary": tag]
                }
                return item
            }
            LumeInfo("Loaded \(libraries.count) libraries from local cache.")
        } catch {
            LumeError("Failed to load cached libraries: \(error.localizedDescription)")
        }
    }

    func logout() async {
        triggerFullRefresh()
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

    func addAnotherServer() {
        LumeInfo("Switching to Add Server mode.")
        authState = .needsServer
    }

    func addAnotherUser() {
        LumeInfo("Switching to Add Account mode.")
        // Keep currentServer but clear currentSession for the login screen to allow adding another user
        currentSession = nil
        authState = .needsAuthentication
    }

    func cancelAddition() {
        Task {
            await loadExistingSession()
        }
    }
    
    func triggerFullRefresh() {
        LumeInfo("Triggering full UI refresh.")
        refreshCounter += 1
        libraries = []
    }
}
