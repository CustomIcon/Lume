import SwiftUI
import SwiftData

enum SettingsSection: String, CaseIterable, Identifiable {
    case general = "General"
    case appearance = "Appearance"
    case sidebar = "Sidebar"
    case playback = "Playback"
    case storage = "Storage"
    case servers = "Servers"
    case about = "About"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .general: return "gear"
        case .appearance: return "paintbrush.fill"
        case .sidebar: return "sidebar.left"
        case .playback: return "play.circle.fill"
        case .storage: return "folder.fill"
        case .servers: return "server.rack"
        case .about: return "info.circle.fill"
        }
    }
}

struct SettingsView: View {
    @State private var selectedSection: SettingsSection = .general
    @AppStorage("enableAnimations") private var enableAnimations = true
    @Environment(SessionManager.self) private var session

    var body: some View {
        HStack(spacing: 0) {
            // Settings Sidebar
            List(SettingsSection.allCases, selection: $selectedSection) { section in
                Label(section.rawValue, systemImage: section.icon)
                    .tag(section)
            }
            .listStyle(.sidebar)
            .frame(width: 200)
            .scrollContentBackground(.hidden)
            
            Divider()
            
            // Settings Detail
            detailView
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .frame(minWidth: 750, minHeight: 550)
    }

    @ViewBuilder
    private var detailView: some View {
        ZStack {
            switch selectedSection {
            case .general:
                GeneralSettingsView()
            case .appearance:
                AppearanceSettingsView()
            case .sidebar:
                SidebarSettingsView()
            case .playback:
                PlaybackSettingsView()
            case .storage:
                StorageSettingsView()
            case .servers:
                ServerSettingsView()
            case .about:
                AboutSettingsView()
            }
        }
        .id(selectedSection)
        .transition(enableAnimations ? .asymmetric(insertion: .opacity.combined(with: .scale(scale: 0.98)), removal: .opacity) : .identity)
        .animation(enableAnimations ? .spring(response: 0.35, dampingFraction: 0.85) : nil, value: selectedSection)
    }
}

struct GeneralSettingsView: View {
    @AppStorage("showSidebarLabels") private var showSidebarLabels = true
    @AppStorage("enableAnimations") private var enableAnimations = true
    @AppStorage("launchToHome") private var launchToHome = true
    @AppStorage("playTrailerInHome") private var playTrailerInHome = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                settingsHeader("General", subtitle: "App behavior and display preferences")

                settingsCard {
                    VStack(alignment: .leading, spacing: 16) {
                        settingsRowLabel("Interface", icon: "macwindow")
                        Toggle("Launch to Home screen", isOn: $launchToHome)
                        Toggle("Play trailer in Home (BETA)", isOn: $playTrailerInHome)
                        Toggle("Show sidebar labels", isOn: $showSidebarLabels)
                        Toggle("Enable animations", isOn: $enableAnimations)
                    }
                }

                Spacer(minLength: 20)
            }
            .padding(.horizontal, 40)
            .padding(.vertical, 32)
            .frame(maxWidth: 600)
            .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

struct AppearanceSettingsView: View {
    @State private var themeManager = ThemeManager.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                settingsHeader("Appearance", subtitle: "Choose a theme that suits your style")

                // Current theme preview
                currentThemePreview

                // Theme categories
                ForEach(ThemeCategory.allCases) { category in
                    themeCategorySection(category)
                }

                Spacer(minLength: 20)
            }
            .padding(.horizontal, 40)
            .padding(.vertical, 32)
            .frame(maxWidth: 750)
            .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var currentThemePreview: some View {
        HStack(spacing: 20) {
            themePreviewBlock(themeManager.currentFlavor, size: 80)

            VStack(alignment: .leading, spacing: 4) {
                Text("Active Theme")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .tracking(0.5)
                Text(themeManager.currentFlavor.rawValue)
                    .font(.title3)
                    .fontWeight(.bold)
                Text(themeManager.currentFlavor.isDark ? "Dark theme" : "Light theme")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            HStack(spacing: 6) {
                colorSwatch(themeManager.currentFlavor.accentColor, label: "Accent")
                colorSwatch(themeManager.currentFlavor.secondaryAccent, label: "Secondary")
                colorSwatch(themeManager.currentFlavor.backgroundColor, label: "BG")
                colorSwatch(themeManager.currentFlavor.textColor, label: "Text")
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(themeManager.currentFlavor == .oled ? AnyShapeStyle(Color.black) : AnyShapeStyle(.ultraThinMaterial))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(themeManager.currentFlavor.accentColor.opacity(0.3), lineWidth: 1.5)
                )
        )
    }

    private func themeCategorySection(_ category: ThemeCategory) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: category.icon)
                    .foregroundStyle(category.flavors.first?.accentColor ?? .accentColor)
                Text(category.rawValue)
                    .font(.headline)
                Spacer()
                Text("\(category.flavors.count) variant\(category.flavors.count == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 130, maximum: 160), spacing: 12)], spacing: 12) {
                ForEach(category.flavors) { flavor in
                    themeCard(flavor)
                }
            }
        }
    }

    private func themeCard(_ flavor: ThemeFlavor) -> some View {
        let isSelected = themeManager.currentFlavor == flavor
        return Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                themeManager.currentFlavor = flavor
            }
        } label: {
            VStack(spacing: 0) {
                themePreviewBlock(flavor, size: 56)
                    .frame(maxWidth: .infinity)
                    .frame(height: 60)
                    .background(flavor.backgroundColor)

                VStack(spacing: 2) {
                    Text(flavor.rawValue)
                        .font(.caption2)
                        .fontWeight(.medium)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Text(flavor.isDark ? "Dark" : "Light")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 6)
                .padding(.horizontal, 4)
                .frame(maxWidth: .infinity)
            }
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(isSelected ? flavor.accentColor : Color.primary.opacity(0.1), lineWidth: isSelected ? 2 : 0.5)
            )
            .overlay(alignment: .topTrailing) {
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(flavor.accentColor)
                        .padding(4)
                }
            }
            .shadow(color: isSelected ? flavor.accentColor.opacity(0.15) : .clear, radius: 6)
        }
        .buttonStyle(.plain)
    }

    private func themePreviewBlock(_ flavor: ThemeFlavor, size: CGFloat) -> some View {
        HStack(spacing: size * 0.05) {
            // Sidebar
            RoundedRectangle(cornerRadius: size * 0.05)
                .fill(flavor.secondaryBackground)
                .frame(width: size * 0.22)
                .overlay(alignment: .top) {
                    VStack(spacing: size * 0.03) {
                        ForEach(0..<3, id: \.self) { _ in
                            RoundedRectangle(cornerRadius: 1)
                                .fill(flavor.textColor.opacity(0.25))
                                .frame(height: size * 0.04)
                                .padding(.horizontal, size * 0.02)
                        }
                    }
                    .padding(.top, size * 0.06)
                }

            // Content
            VStack(spacing: size * 0.03) {
                RoundedRectangle(cornerRadius: 1)
                    .fill(flavor.accentColor)
                    .frame(height: size * 0.05)
                HStack(spacing: size * 0.03) {
                    RoundedRectangle(cornerRadius: size * 0.03)
                        .fill(flavor.secondaryAccent.opacity(0.4))
                    RoundedRectangle(cornerRadius: size * 0.03)
                        .fill(flavor.textColor.opacity(0.12))
                }
                .frame(height: size * 0.28)
                Spacer(minLength: 0)
            }
            .padding(size * 0.03)
        }
        .frame(width: size, height: size * 0.65)
        .background(flavor.backgroundColor)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.08))
    }

    private func colorSwatch(_ color: Color, label: String) -> some View {
        VStack(spacing: 3) {
            RoundedRectangle(cornerRadius: 5)
                .fill(color)
                .frame(width: 24, height: 24)
                .overlay(
                    RoundedRectangle(cornerRadius: 5)
                        .stroke(.primary.opacity(0.12), lineWidth: 0.5)
                )
            Text(label)
                .font(.system(size: 8))
                .foregroundStyle(.secondary)
        }
    }
}

struct PlaybackSettingsView: View {
    @AppStorage("preferDirectPlay") private var preferDirectPlay = true
    @AppStorage("preferredSubLanguage") private var preferredSubLanguage = "eng"
    @AppStorage("preferredAudioLanguage") private var preferredAudioLanguage = "eng"
    @AppStorage("autoPlayNext") private var autoPlayNext = true
    @AppStorage("skipIntroEnabled") private var skipIntroEnabled = true
    @AppStorage("defaultSubtitlesOn") private var defaultSubtitlesOn = false
    @AppStorage("resumePlayback") private var resumePlayback = true
    @AppStorage("enableSeekPreviews") private var enableSeekPreviews = true

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                settingsHeader("Playback", subtitle: "Video, audio, and subtitle preferences")

                settingsCard {
                    VStack(alignment: .leading, spacing: 16) {
                        settingsRowLabel("Streaming", icon: "antenna.radiowaves.left.and.right")
                        Toggle("Prefer direct play (no transcoding)", isOn: $preferDirectPlay)
                        Text("When enabled, Lume requests the raw file from the server.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                settingsCard {
                    VStack(alignment: .leading, spacing: 16) {
                        settingsRowLabel("Behavior", icon: "play.rectangle")
                        Toggle("Resume from last position", isOn: $resumePlayback)
                        Toggle("Auto-play next episode (WIP)", isOn: $autoPlayNext)
                        Toggle("Skip intro when available (WIP)", isOn: $skipIntroEnabled)
                        Toggle("Enable seek previews (Thumbnails)", isOn: $enableSeekPreviews)
                    }
                }

                settingsCard {
                    VStack(alignment: .leading, spacing: 16) {
                        settingsRowLabel("Languages", icon: "globe")
                        HStack {
                            Text("Preferred audio")
                            Spacer()
                            TextField("ISO 639-2", text: $preferredAudioLanguage)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 100)
                        }
                        HStack {
                            Text("Preferred subtitles")
                            Spacer()
                            TextField("ISO 639-2", text: $preferredSubLanguage)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 100)
                        }
                        Toggle("Enable subtitles by default", isOn: $defaultSubtitlesOn)
                        Text("Use ISO 639-2 codes: eng, jpn, fre, deu, spa, etc.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer(minLength: 20)
            }
            .padding(.horizontal, 40)
            .padding(.vertical, 32)
            .frame(maxWidth: 600)
            .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

struct ServerSettingsView: View {
    @Environment(SessionManager.self) private var session
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \ServerConfiguration.createdAt, order: .reverse) private var servers: [ServerConfiguration]
    @Query(sort: \UserSession.lastLoginDate, order: .reverse) private var sessions: [UserSession]

    @State private var showDeleteAlert = false
    @State private var serverToDelete: ServerConfiguration?
    
    @State private var showSwitchAlert = false
    @State private var switchTarget: SwitchTarget?
    
    enum SwitchTarget {
        case user(UserSession)
        case server(ServerConfiguration)
        
        var name: String {
            switch self {
            case .user(let session): return session.username
            case .server(let server): return server.serverName
            }
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                settingsHeader("Servers", subtitle: "Manage your Jellyfin server connections")

                if servers.isEmpty {
                    settingsCard {
                        VStack(spacing: 12) {
                            Image(systemName: "server.rack")
                                .font(.largeTitle)
                                .foregroundStyle(.secondary)
                            Text("No servers configured")
                                .foregroundStyle(.secondary)
                            Button("Add Server") {
                                Task { await session.disconnectServer() }
                            }
                            .buttonStyle(.borderedProminent)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 20)
                    }
                } else {
                    ForEach(servers) { server in
                        serverCard(server)
                    }
                }

                if !servers.isEmpty {
                    HStack(spacing: 12) {
                        Button {
                            session.addAnotherUser()
                        } label: {
                            Label("Add Account", systemImage: "person.badge.plus")
                        }
                        .buttonStyle(.bordered)
                        
                        Button {
                            session.addAnotherServer()
                        } label: {
                            Label("Add Server", systemImage: "plus.circle")
                        }
                        .buttonStyle(.bordered)
                    }
                }

                if let currentSession = session.currentSession {
                    settingsCard {
                        VStack(alignment: .leading, spacing: 12) {
                            settingsRowLabel("Active Session", icon: "person.fill.checkmark")
                            HStack {
                                Text("User")
                                Spacer()
                                Text(currentSession.username)
                                    .foregroundStyle(.secondary)
                            }
                            HStack {
                                Text("Last login")
                                Spacer()
                                Text(currentSession.lastLoginDate.formatted(date: .abbreviated, time: .shortened))
                                    .foregroundStyle(.secondary)
                            }
                            Button("Sign Out", role: .destructive) {
                                Task { await session.logout() }
                            }
                            .buttonStyle(.bordered)
                            .tint(.red)
                        }
                    }
                }

                Spacer(minLength: 20)
            }
            .padding(.horizontal, 40)
            .padding(.vertical, 32)
            .frame(maxWidth: 600)
            .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .alert("Remove Server?", isPresented: $showDeleteAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Remove", role: .destructive) {
                if let server = serverToDelete {
                    deleteServer(server)
                }
            }
        } message: {
            Text("This will remove all account data for this server.")
        }
        .alert("Switch to \(switchTarget?.name ?? "Target")?", isPresented: $showSwitchAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Confirm") {
                if let target = switchTarget {
                    executeSwitch(target)
                }
            }
        } message: {
            Text("Switching will refresh the app and load the new libraries.")
        }
    }
    
    private func executeSwitch(_ target: SwitchTarget) {
        Task {
            switch target {
            case .user(let session_):
                await session.switchUser(to: session_)
            case .server(let server_):
                await session.switchServer(to: server_)
            }
        }
    }

    private func serverCard(_ server: ServerConfiguration) -> some View {
        let isCurrent = session.currentServer?.id == server.id
        let deviceID = server.deviceID
        let serverSessions = sessions.filter { $0.serverID == deviceID }
        
        return settingsCard {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 16) {
                    Image(systemName: isCurrent ? "checkmark.circle.fill" : "server.rack")
                        .font(.title2)
                        .foregroundStyle(isCurrent ? .green : .secondary)
                        .frame(width: 32)
    
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 8) {
                            Text(server.serverName.isEmpty ? "Server" : server.serverName)
                                .font(.headline)
                            if isCurrent {
                                Text("ACTIVE")
                                    .font(.system(size: 9, weight: .bold))
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 2)
                                    .background(.green.opacity(0.15), in: Capsule())
                                    .foregroundStyle(.green)
                            }
                        }
                        Text(server.serverURL)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
    
                    Spacer()
    
                    HStack(spacing: 8) {
                        if !isCurrent {
                            Button("Switch") {
                                switchTarget = .server(server)
                                showSwitchAlert = true
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                        
                        Button(role: .destructive) {
                            serverToDelete = server
                            showDeleteAlert = true
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .tint(.red)
                    }
                }
                
                Divider()
                
                VStack(alignment: .leading, spacing: 10) {
                    Text("Accounts (\(serverSessions.count))")
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundStyle(.secondary)
                        .padding(.bottom, 4)
                        
                    ForEach(serverSessions) { userSession in
                        HStack {
                            Label(userSession.username, systemImage: "person.circle")
                                .foregroundStyle(session.currentSession?.userID == userSession.userID && isCurrent ? .primary : .secondary)
                            
                            if session.currentSession?.userID == userSession.userID && isCurrent {
                                Text("ACTIVE")
                                    .font(.system(size: 8, weight: .bold))
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 1)
                                    .background(.blue.opacity(0.15), in: Capsule())
                                    .foregroundStyle(.blue)
                            }
                            
                            Spacer()
                            
                            if !isCurrent || session.currentSession?.userID != userSession.userID {
                                Button("Connect") {
                                    switchTarget = .user(userSession)
                                    showSwitchAlert = true
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            }
                            
                            Button(role: .destructive) {
                                modelContext.delete(userSession)
                                try? modelContext.save()
                                if session.currentSession?.userID == userSession.userID {
                                    Task { await session.logout() }
                                }
                            } label: {
                                Image(systemName: "xmark.circle")
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                    }
                    
                    if isCurrent {
                        Button {
                            session.addAnotherUser()
                        } label: {
                            Label("Add Account", systemImage: "person.badge.plus")
                                .font(.caption)
                        }
                        .buttonStyle(.plain)
                        .padding(.top, 4)
                        .foregroundStyle(.tint)
                    }
                }
                .padding(.leading, 48)
            }
        }
    }

    private func deleteServer(_ server: ServerConfiguration) {
        let deviceId = server.deviceID
        for s in sessions where s.serverID == deviceId {
            modelContext.delete(s)
        }
        modelContext.delete(server)
        if session.currentServer?.id == server.id {
            Task { await session.disconnectServer() }
        }
        try? modelContext.save()
    }
}

struct AboutSettingsView: View {
    @State private var logger = LumeLogger.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                settingsHeader("About Lume", subtitle: "A native Jellyfin client for macOS")

                settingsCard {
                    HStack(spacing: 20) {
                        Image("Logo")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 80, height: 80)
                            .clipShape(RoundedRectangle(cornerRadius: 16))

                        VStack(alignment: .leading, spacing: 4) {
                            Text("Lume")
                                .font(.title2)
                                .fontWeight(.bold)
                            Text("Version 1.0 (Build 1)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text("SwiftUI + SwiftData + VLCKit")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                        Spacer()
                    }
                }

                settingsCard {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            settingsRowLabel("Logs", icon: "doc.text")
                            Spacer()
                            Text("\(logger.entries.count)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Button("Clear") { logger.clear() }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                        }

                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 4) {
                                if logger.entries.isEmpty {
                                    Text("No logs.")
                                        .foregroundStyle(.secondary)
                                        .padding()
                                } else {
                                    ForEach(logger.entries) { entry in
                                        HStack(alignment: .top, spacing: 8) {
                                            Text(entry.level.rawValue)
                                                .font(.system(size: 8, weight: .bold, design: .monospaced))
                                                .padding(.horizontal, 4)
                                                .padding(.vertical, 2)
                                                .background(logColor(entry.level), in: RoundedRectangle(cornerRadius: 2))
                                                .foregroundStyle(.white)

                                            VStack(alignment: .leading, spacing: 1) {
                                                Text(entry.message)
                                                    .font(.system(size: 10, design: .monospaced))
                                                    .textSelection(.enabled)
                                                Text(entry.timestamp, style: .time)
                                                    .font(.system(size: 8))
                                                    .foregroundStyle(.tertiary)
                                            }
                                        }
                                    }
                                }
                            }
                            .padding(8)
                        }
                        .frame(height: 200)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(.quaternary.opacity(0.3))
                        )
                    }
                }

                Spacer(minLength: 20)
            }
            .padding(.horizontal, 40)
            .padding(.vertical, 32)
            .frame(maxWidth: 600)
            .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private func logColor(_ level: LogEntry.LogLevel) -> Color {
        switch level {
        case .info: return .blue
        case .error: return .red
        case .debug: return .gray
        }
    }
}

struct StorageSettingsView: View {
    @State private var subtitleSize = SubtitleService.shared.getTotalSizeString()
    @State private var imageCacheSize = ImageCacheManager.shared.getTotalSizeString()
    @State private var lyricsCacheSize = ByteCountFormatter.string(fromByteCount: Int64(LyricsManager.shared.getCacheSizeInBytes()), countStyle: .file)
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                settingsHeader("Storage", subtitle: "Manage local data and cache")
                
                settingsCard {
                    VStack(alignment: .leading, spacing: 16) {
                        settingsRowLabel("Subtitles", icon: "captions.bubble")
                        HStack {
                            VStack(alignment: .leading) {
                                Text("Downloaded Subtitles")
                                Text("Subtitles downloaded from remote providers during playback.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(subtitleSize)
                                .font(.system(size: 13, design: .monospaced))
                                .foregroundStyle(.secondary)
                            Button("Clear") {
                                SubtitleService.shared.clearAllSubtitles()
                                subtitleSize = SubtitleService.shared.getTotalSizeString()
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                }
                
                settingsCard {
                    VStack(alignment: .leading, spacing: 16) {
                        settingsRowLabel("Images", icon: "photo")
                        HStack {
                            VStack(alignment: .leading) {
                                Text("Image Cache")
                                Text("Cached posters, backdrops, and profile images.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(imageCacheSize)
                                .font(.system(size: 13, design: .monospaced))
                                .foregroundStyle(.secondary)
                            Button("Clear") {
                                ImageCacheManager.shared.clearCache()
                                imageCacheSize = ImageCacheManager.shared.getTotalSizeString()
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                }
                
                settingsCard {
                    VStack(alignment: .leading, spacing: 16) {
                        settingsRowLabel("Lyrics", icon: "music.mic")
                        HStack {
                            VStack(alignment: .leading) {
                                Text("Lyrics Cache")
                                Text("Cached lyrics fetched from remote providers.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(lyricsCacheSize)
                                .font(.system(size: 13, design: .monospaced))
                                .foregroundStyle(.secondary)
                            Button("Clear") {
                                LyricsManager.shared.clearCache()
                                lyricsCacheSize = ByteCountFormatter.string(fromByteCount: Int64(LyricsManager.shared.getCacheSizeInBytes()), countStyle: .file)
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                }
                
                Spacer(minLength: 20)
            }
            .padding(.horizontal, 40)
            .padding(.vertical, 32)
            .frame(maxWidth: 600)
            .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

private func settingsHeader(_ title: String, subtitle: String) -> some View {
    VStack(alignment: .leading, spacing: 4) {
        Text(title)
            .font(.largeTitle)
            .fontWeight(.bold)
        Text(subtitle)
            .font(.body)
            .foregroundStyle(.secondary)
    }
    .padding(.bottom, 8)
}

private func settingsRowLabel(_ text: String, icon: String) -> some View {
    Label(text, systemImage: icon)
        .font(.headline)
}

private func settingsCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
    content()
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            if ThemeManager.shared.currentFlavor == .oled {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(ThemeManager.shared.currentFlavor.secondaryBackground)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(.white.opacity(0.1), lineWidth: 1)
                    )
            } else {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(.primary.opacity(0.06), lineWidth: 1)
                    )
            }
        }
}

struct SidebarSettingsView: View {
    @Environment(SessionManager.self) private var session

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                settingsHeader("Sidebar", subtitle: "Customize your library order and visibility")

                Text("Drag libraries to reorder them in the sidebar. Toggle the visibility of libraries you don't need.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                settingsCard {
                    List {
                        // Visible libraries (reorderable)
                        Section("Shown in Sidebar") {
                             if session.visibleLibraries.isEmpty && session.libraries.filter({ !session.hiddenLibraryIds.contains($0.id ?? "") }).isEmpty {
                                 Text("No libraries shown.")
                                     .foregroundStyle(.secondary)
                                     .font(.caption)
                             } else {
                                 ForEach(session.visibleLibraries) { library in
                                     HStack {
                                         Image(systemName: iconForCollectionType(library.collectionType))
                                             .frame(width: 24)
                                         Text(library.displayName)
                                         Spacer()
                                         Button(action: { session.toggleLibraryVisibility(id: library.id ?? "") }) {
                                             Image(systemName: "eye")
                                                 .foregroundStyle(.secondary)
                                         }
                                         .buttonStyle(.plain)
                                         
                                         Image(systemName: "line.3.horizontal")
                                             .foregroundStyle(.tertiary)
                                             .padding(.leading, 8)
                                     }
                                     .padding(.vertical, 4)
                                     .tag(library.id)
                                 }
                                 .onMove { from, to in
                                     session.moveLibrary(from: from, to: to)
                                 }
                             }
                        }
                        
                        // Hidden libraries
                        let hidden = session.libraries.filter { session.hiddenLibraryIds.contains($0.id ?? "") }
                        if !hidden.isEmpty {
                            Section("Hidden") {
                                ForEach(hidden) { library in
                                    HStack {
                                        Image(systemName: iconForCollectionType(library.collectionType))
                                            .frame(width: 24)
                                            .foregroundStyle(.secondary)
                                        Text(library.displayName)
                                            .foregroundStyle(.secondary)
                                        Spacer()
                                        Button(action: { session.toggleLibraryVisibility(id: library.id ?? "") }) {
                                            Image(systemName: "eye.slash")
                                                .foregroundStyle(.secondary)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                    .padding(.vertical, 4)
                                    .tag(library.id)
                                }
                            }
                        }
                    }
                    .listStyle(.plain)
                    .frame(height: 500) // Fixed height within settings card
                }

                Spacer(minLength: 20)
            }
            .padding(.horizontal, 40)
            .padding(.vertical, 32)
            .frame(maxWidth: 600)
            .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
    
    private func iconForCollectionType(_ type: String?) -> String {
        switch type {
            case "movies": return "film"
            case "tvshows": return "tv"
            case "music": return "music.note"
            case "livetv", "liverecordings", "LiveTv", "channels": return "antenna.radiowaves.left.and.right"
            case "books": return "book"
            default: return "folder"
        }
    }
}
