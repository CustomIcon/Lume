import SwiftUI

enum SidebarItem: Hashable {
    case home
    case search
    case downloads
    case settings
    case library(BaseItemDto)
}

struct MainAppView: View {
    @Environment(SessionManager.self) private var session
    @State private var selectedSidebarItem: SidebarItem? = .home
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var isRefreshing = false

    var body: some View {
        ZStack(alignment: .bottom) {
            NavigationSplitView(columnVisibility: $columnVisibility) {
                sidebar
            } detail: {
                if selectedSidebarItem == .settings {
                    SettingsView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                        .background(.ultraThinMaterial)
                } else {
                    NavigationStack {
                        detailContent
                            .navigationDestination(for: BaseItemDto.self) { item in
                                if item.type == "Series" {
                                    SeriesDetailView(series: item)
                                } else if item.type == "MusicAlbum" {
                                    AlbumDetailView(album: item)
                                } else {
                                    ItemDetailView(item: item)
                                }
                            }
                            .navigationDestination(for: String.self) { seriesId in
                                SeriesDownloadsDetailView(seriesId: seriesId)
                            }
                    }
                    .scrollContentBackground(.hidden)
                    .background(.ultraThinMaterial)
                    .toolbarBackground(.hidden, for: .windowToolbar)
                    .toolbarBackground(.hidden, for: .automatic)
                }
            }
            .toolbarBackground(.hidden, for: .windowToolbar)
            .toolbarBackground(.hidden, for: .automatic)
            .background(
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
                .ignoresSafeArea()
            )
            .padding(.bottom, (session.activeVideoItem == nil && session.activeBookItem == nil) ? 0 : 0) // Fixed padding
            
            if let activeVideo = session.activeVideoItem {
                PlayerView(item: activeVideo)
                    .ignoresSafeArea()
                    .zIndex(100)
            } else if let activeBook = session.activeBookItem {
                BookReaderView(item: activeBook)
                    .ignoresSafeArea()
                    .zIndex(100)
            }
        }
        .themeContainer()
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
        .toolbar((session.activeVideoItem != nil || session.activeBookItem != nil) ? .hidden : .visible)
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
        }
    }

    private var sidebar: some View {
        VStack(spacing: 0) {
            List(selection: $selectedSidebarItem) {
                Section {
                    NavigationLink(value: SidebarItem.home) {
                        Label("Home", systemImage: "house")
                    }
                    NavigationLink(value: SidebarItem.search) {
                        Label("Search", systemImage: "magnifyingglass")
                    }
                    NavigationLink(value: SidebarItem.downloads) {
                        Label("Downloads", systemImage: "arrow.down.circle")
                    }
                }

                Section("Libraries") {
                    ForEach(session.libraries) { library in
                        NavigationLink(value: SidebarItem.library(library)) {
                            Label(library.displayName, systemImage: iconForCollectionType(library.collectionType))
                        }
                    }
                }

                Section {
                    NavigationLink(value: SidebarItem.settings) {
                        Label("Settings", systemImage: "gearshape")
                    }
                    
                    Button {
                        Task { await session.logout() }
                    } label: {
                        Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
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
        }
        .background(.ultraThinMaterial)
        .toolbarBackground(.hidden)
        .navigationSplitViewColumnWidth(min: 240, ideal: 260, max: 300)
        .navigationTitle("Lume")
    }

    private func toggleSidebar() {
        NSApp.sendAction(#selector(NSSplitViewController.toggleSidebar(_:)), to: nil, from: nil)
    }

    @ViewBuilder
    private var detailContent: some View {
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
