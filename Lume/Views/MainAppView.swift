import SwiftUI
import SwiftData

enum SidebarItem: Hashable {
    case home
    case search
    case downloads
    case settings
    case library(BaseItemDto)
}

struct MainAppView: View {
    @Environment(SessionManager.self) private var session
    @State private var selectedSidebarItem: SidebarItem?
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var isRefreshing = false
    @State private var showSignOutAlert = false
    @AppStorage("enableAnimations") private var enableAnimations = true
    @Environment(\.openWindow) private var openWindow
    @Query private var allSessions: [UserSession]

    var body: some View {
        ZStack(alignment: .bottom) {
            NavigationSplitView(columnVisibility: $columnVisibility) {
                sidebar
            } detail: {
                Group {
                    if selectedSidebarItem == .settings {
                        SettingsView()
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                            .background(ThemeManager.shared.currentFlavor == .oled ? ThemeManager.shared.currentFlavor.backgroundColor : Color.clear)
                            .background(ThemeManager.shared.currentFlavor == .oled ? AnyShapeStyle(Color.clear) : AnyShapeStyle(.ultraThinMaterial))
                    } else {
                        NavigationStack {
                            detailContent
                                .navigationDestination(for: BaseItemDto.self) { item in
                                    if item.type == "Series" {
                                        SeriesDetailView(series: item)
                                    } else if item.type == "MusicAlbum" {
                                        AlbumDetailView(album: item)
                                    } else if item.type == "MusicArtist" || item.type == "Playlist" || item.type == "MusicGenre" {
                                        MusicCollectionDetailView(collection: item)
                                    } else if item.type == "Audio" {
                                        ItemDetailView(item: item)
                                    } else {
                                        ItemDetailView(item: item)
                                    }
                                }
                                .navigationDestination(for: BaseItemPerson.self) { person in
                                    PersonDetailView(person: person)
                                }
                                .navigationDestination(for: String.self) { seriesId in
                                    SeriesDownloadsDetailView(seriesId: seriesId)
                                }
                        }
                        .scrollContentBackground(.hidden)
                        .background(ThemeManager.shared.currentFlavor == .oled ? ThemeManager.shared.currentFlavor.backgroundColor : Color.clear)
                        .background(ThemeManager.shared.currentFlavor == .oled ? AnyShapeStyle(Color.clear) : AnyShapeStyle(.ultraThinMaterial))
                        .toolbarBackground(.hidden, for: .windowToolbar)
                        .toolbarBackground(.hidden, for: .automatic)
                    }
                }
                .background(
                    Group {
                        if ThemeManager.shared.currentFlavor == .oled {
                            ThemeManager.shared.currentFlavor.backgroundColor
                        } else {
                            LinearGradient(
                                colors: [
                                    ThemeManager.shared.currentFlavor.accentColor.opacity(0.15),
                                    ThemeManager.shared.currentFlavor.backgroundColor,
                                    ThemeManager.shared.currentFlavor.backgroundColor,
                                    ThemeManager.shared.currentFlavor.accentColor.opacity(0.05)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        }
                    }
                )
                .animation(enableAnimations ? .spring(response: 0.35, dampingFraction: 0.85) : nil, value: selectedSidebarItem)
            }
        }
        .themeContainer()
        .onChange(of: session.activeVideoItem) { old, newValue in
            if newValue != nil {
                openWindow(id: "video-player")
            }
        }
        .onChange(of: session.activeBookItem) { old, newValue in
            if newValue != nil {
                openWindow(id: "book-reader")
            }
        }
        .onAppear {
            // Apply titlebar transparency immediately
            NSApp.windows.forEach { window in
                window.titlebarAppearsTransparent = true
                window.titleVisibility = .hidden
            }
            // Repeat after a short delay for good measure during initialization animations
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                NSApp.windows.forEach { window in
                    window.titlebarAppearsTransparent = true
                    window.titleVisibility = .hidden
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    Task {
                        isRefreshing = true
                        await session.refreshLibraries()
                        try? await Task.sleep(for: .seconds(0.5))
                        isRefreshing = false
                    }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .rotationEffect(.degrees(isRefreshing ? 360 : 0))
                        .animation(isRefreshing ? .linear(duration: 1).repeatForever(autoreverses: false) : .default, value: isRefreshing)
                }
                .help("Refresh Libraries")
            }
        }
        .task {
            MusicPlayerManager.shared.setup(session: session)
            
            // Default to downloads if offline, otherwise home
            if selectedSidebarItem == nil {
                selectedSidebarItem = session.isOffline ? .downloads : .home
            }
        }
    }

    private var sidebar: some View {
        VStack(spacing: 0) {
            List(selection: $selectedSidebarItem) {
                Section {
                    NavigationLink(value: SidebarItem.home) {
                        Label("Home", systemImage: "house")
                    }
                    .disabled(session.isOffline)
                    
                    NavigationLink(value: SidebarItem.search) {
                        Label("Search", systemImage: "magnifyingglass")
                    }
                    .disabled(session.isOffline)
                    
                    NavigationLink(value: SidebarItem.downloads) {
                        Label("Downloads", systemImage: "arrow.down.circle")
                    }
                }

                if !session.isOffline {
                    Section("Libraries") {
                        ForEach(session.visibleLibraries) { library in
                            NavigationLink(value: SidebarItem.library(library)) {
                                Label(library.displayName, systemImage: iconForCollectionType(library.collectionType))
                            }
                        }
                    }
                }
                
                Section {
                    NavigationLink(value: SidebarItem.settings) {
                        Label("Settings", systemImage: "gearshape")
                    }
                }
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
            .background(.clear)
            
            // MiniPlayer at the bottom of the sidebar
            if MusicPlayerManager.shared.currentSong != nil {
                MiniPlayerView()
                    .padding(12)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            // Profile Section at the very bottom
            if let currentSession = session.currentSession {
                Divider().padding(.horizontal, 16).opacity(0.3)
                
                Menu {
                    Section("Saved Accounts") {
                        // Sessions on THIS server
                        let otherSessions = allSessions.filter { 
                            $0.serverID == session.currentServer?.deviceID && $0.userID != currentSession.userID 
                        }
                        
                        ForEach(otherSessions) { s in
                            Button {
                                Task { await session.switchUser(to: s) }
                            } label: {
                                Label(s.username, systemImage: "person.circle")
                            }
                        }
                        
                        Button {
                            session.addAnotherUser()
                        } label: {
                            Label("Add Another Account", systemImage: "plus")
                        }
                    }
                    
                    Divider()
                    
                    Button(role: .destructive) {
                        showSignOutAlert = true
                    } label: {
                        Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                    }
                } label: {
                    HStack(spacing: 12) {
                        Circle()
                            .fill(ThemeManager.shared.currentFlavor.accentColor.opacity(0.15))
                            .frame(width: 32, height: 32)
                            .overlay {
                                Text(currentSession.username.prefix(1).uppercased())
                                    .font(.system(size: 14, weight: .bold, design: .rounded))
                                    .foregroundStyle(ThemeManager.shared.currentFlavor.accentColor)
                            }
                        
                        VStack(alignment: .leading, spacing: 1) {
                            Text(currentSession.username)
                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                            Text(session.currentServer?.serverName ?? "Offline")
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                        }
                        
                        Spacer()
                        
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .contentShape(Rectangle())
                }
                .menuStyle(.button)
                .buttonStyle(.plain)
                .padding(8)
            }
        }
        .background {
            if ThemeManager.shared.currentFlavor == .oled {
                ThemeManager.shared.currentFlavor.secondaryBackground
                    .ignoresSafeArea()
            } else {
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .ignoresSafeArea(.container, edges: .top)
            }
        }
        .toolbarBackground(.hidden, for: .windowToolbar)
        .toolbarBackground(.hidden, for: .automatic)
        .navigationSplitViewColumnWidth(min: 240, ideal: 260, max: 300)
        .navigationTitle("Lume")
        .alert("Sign Out?", isPresented: $showSignOutAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Sign Out", role: .destructive) {
                Task { await session.logout() }
            }
        } message: {
            Text("You will need to sign in again to access your libraries.")
        }
    }

    private func toggleSidebar() {
        NSApp.sendAction(#selector(NSSplitViewController.toggleSidebar(_:)), to: nil, from: nil)
    }

    @ViewBuilder
    private var detailContent: some View {
        ZStack {
            switch selectedSidebarItem {
            case .home, .none:
                HomeView()
            case .search:
                SearchView()
            case .downloads:
                DownloadsView()
            case .settings:
                SettingsView()
            case .library(let library):
                libraryView(for: library)
            }
        }
        .id("\(selectedSidebarItem?.hashValue ?? 0)-\(session.refreshCounter)")
        .transition(enableAnimations ? .asymmetric(insertion: .opacity.combined(with: .scale(scale: 0.98)), removal: .opacity) : .identity)
    }

    @ViewBuilder
    private func libraryView(for library: BaseItemDto) -> some View {
        let collectionType = library.collectionType ?? ""
        switch collectionType {
        case "movies":
            MoviesLibraryView(library: library)
        case "tvshows":
            TVShowsLibraryView(library: library)
        case "music":
            MusicLibraryView(library: library)
        case "livetv":
            LiveTVLibraryView(library: library)
        case "books":
            BooksLibraryView(library: library)
        default:
            GenericLibraryView(library: library)
        }
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

struct ThemeContainerModifier: ViewModifier {
    @State private var theme = ThemeManager.shared
    
    func body(content: Content) -> some View {
        content
            .tint(theme.currentFlavor.accentColor)
            .foregroundStyle(theme.currentFlavor.textColor)
            .preferredColorScheme(theme.currentFlavor.isDark ? .dark : .light)
    }
}

extension View {
    func themeContainer() -> some View {
        self.modifier(ThemeContainerModifier())
    }
}
