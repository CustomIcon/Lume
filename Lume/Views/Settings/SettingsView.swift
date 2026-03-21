import SwiftUI
import SwiftData

enum SettingsSection: String, CaseIterable, Identifiable {
    case general = "General"
    case appearance = "Appearance"
    case playback = "Playback"
    case servers = "Servers"
    case about = "About"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .general: return "gear"
        case .appearance: return "paintbrush.fill"
        case .playback: return "play.circle.fill"
        case .servers: return "server.rack"
        case .about: return "info.circle.fill"
        }
    }
}

struct SettingsView: View {
    @State private var selectedSection: SettingsSection = .general

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
        switch selectedSection {
        case .general:
            GeneralSettingsView()
        case .appearance:
            AppearanceSettingsView()
        case .playback:
            PlaybackSettingsView()
        case .servers:
            ServerSettingsView()
        case .about:
            AboutSettingsView()
        }
    }
}

struct GeneralSettingsView: View {
    @AppStorage("gridColumns") private var gridColumns = 5
    @AppStorage("showSidebarLabels") private var showSidebarLabels = true
    @AppStorage("homeSectionLimit") private var homeSectionLimit = 16
    @AppStorage("enableAnimations") private var enableAnimations = true
    @AppStorage("launchToHome") private var launchToHome = true

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                settingsHeader("General", subtitle: "App behavior and display preferences")

                settingsCard {
                    VStack(alignment: .leading, spacing: 16) {
                        settingsRowLabel("Library Grid", icon: "square.grid.3x3")
                        Stepper("Columns: \(gridColumns)", value: $gridColumns, in: 2...10)
                        Text("Number of columns in grid views for movies, shows, etc.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                settingsCard {
                    VStack(alignment: .leading, spacing: 16) {
                        settingsRowLabel("Home Screen", icon: "house")
                        Stepper("Items per section: \(homeSectionLimit)", value: $homeSectionLimit, in: 4...40, step: 4)
                        Text("Maximum items shown in each home screen row.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Toggle("Launch to Home screen", isOn: $launchToHome)
                    }
                }

                settingsCard {
                    VStack(alignment: .leading, spacing: 16) {
                        settingsRowLabel("Interface", icon: "macwindow")
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
                .fill(.ultraThinMaterial)
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
    @AppStorage("maxStreamingBitrate") private var maxStreamingBitrate = 140

    private let bitrateOptions = [
        (label: "Auto (140 Mbps)", value: 140),
        (label: "100 Mbps", value: 100),
        (label: "60 Mbps", value: 60),
        (label: "40 Mbps", value: 40),
        (label: "20 Mbps", value: 20),
        (label: "8 Mbps (1080p)", value: 8),
        (label: "4 Mbps (720p)", value: 4),
        (label: "2 Mbps", value: 2),
    ]

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
                        Picker("Max streaming bitrate", selection: $maxStreamingBitrate) {
                            ForEach(bitrateOptions, id: \.value) { option in
                                Text(option.label).tag(option.value)
                            }
                        }
                        .pickerStyle(.menu)
                    }
                }

                settingsCard {
                    VStack(alignment: .leading, spacing: 16) {
                        settingsRowLabel("Behavior", icon: "play.rectangle")
                        Toggle("Resume from last position", isOn: $resumePlayback)
                        Toggle("Auto-play next episode", isOn: $autoPlayNext)
                        Toggle("Skip intro when available", isOn: $skipIntroEnabled)
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
                    Button {
                        Task { await session.disconnectServer() }
                    } label: {
                        Label("Add Another Server", systemImage: "plus.circle")
                    }
                    .buttonStyle(.bordered)
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
    }

    private func serverCard(_ server: ServerConfiguration) -> some View {
        let isCurrent = session.currentServer?.id == server.id
        return settingsCard {
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
                        Button("Connect") {
                            Task { await session.switchServer(to: server) }
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
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(.primary.opacity(0.06), lineWidth: 1)
                )
        )
}
