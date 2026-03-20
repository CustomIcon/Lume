import SwiftUI

enum SidebarItem: Hashable {
    case home
    case search
    case settings
    case library(BaseItemDto)
}

struct MainAppView: View {
    @Environment(SessionManager.self) private var session
    @State private var selectedSidebarItem: SidebarItem? = .home

    var body: some View {
        ZStack(alignment: .bottom) {
            NavigationSplitView {
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
                    }
                    .scrollContentBackground(.hidden)
                    .background(.ultraThinMaterial)
                }
            }
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
            .padding(.bottom, (MusicPlayerManager.shared.currentSong != nil && session.activeVideoItem == nil && session.activeBookItem == nil) ? 64 : 0)
            
            if let activeVideo = session.activeVideoItem {
                PlayerView(item: activeVideo)
                    .ignoresSafeArea()
                    .zIndex(100)
            } else if let activeBook = session.activeBookItem {
                BookReaderView(item: activeBook)
                    .ignoresSafeArea()
                    .zIndex(100)
            } else {
                MiniPlayerView()
            }
        }
        .themeContainer()
        .toolbar((session.activeVideoItem != nil || session.activeBookItem != nil) ? .hidden : .visible)
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button {
                    Task { await session.refreshLibraries() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .help("Refresh Libraries")
            }
        }
        .task {
            MusicPlayerManager.shared.setup(session: session)
        }
    }

    private var sidebar: some View {
        List(selection: $selectedSidebarItem) {
            Section {
                NavigationLink(value: SidebarItem.home) {
                    Label("Home", systemImage: "house")
                }
                NavigationLink(value: SidebarItem.search) {
                    Label("Search", systemImage: "magnifyingglass")
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
        .background(.ultraThinMaterial)
        .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 220)
        .navigationTitle("Lume")
    }

    @ViewBuilder
    private var detailContent: some View {
        switch selectedSidebarItem {
        case .home, .none:
            HomeView()
        case .search:
            SearchView()
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
