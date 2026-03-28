import SwiftUI

enum MusicTab: String, CaseIterable {
    case suggestions = "Suggestions"
    case albums = "Albums"
    case albumArtists = "Album Artists"
    case artists = "Artists"
    case genres = "Genres"
    case songs = "Songs"
    case playlists = "Playlists"
}

struct MusicLibraryView: View {
    @Environment(SessionManager.self) private var session
    let library: BaseItemDto

    @State private var selectedTab: MusicTab = .suggestions
    @State private var suggestions: [BaseItemDto] = []
    @State private var recentlyPlayed: [BaseItemDto] = []
    @State private var frequentlyPlayed: [BaseItemDto] = []
    @State private var artists: [BaseItemDto] = []
    @State private var albumArtists: [BaseItemDto] = []
    @State private var albums: [BaseItemDto] = []
    @State private var genres: [BaseItemDto] = []
    @State private var songs: [BaseItemDto] = []
    @State private var playlists: [BaseItemDto] = []
    @State private var isLoading = true
    @State private var searchText = ""
    @State private var searchResults: [BaseItemDto] = []
    @State private var isSearching = false
    @State private var searchTask: Task<Void, Swift.Error>?

    private let gridColumns = [
        GridItem(.adaptive(minimum: 160, maximum: 200), spacing: 16)
    ]

    var body: some View {
        VStack(spacing: 0) {
            if searchText.isEmpty {
                Picker("", selection: $selectedTab) {
                    ForEach(MusicTab.allCases, id: \.self) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .padding()

                Divider()

                if isLoading {
                    ProgressView("Loading music...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        switch selectedTab {
                        case .suggestions:
                            suggestionsGrid
                        case .artists:
                            artistsGrid
                        case .albumArtists:
                            albumArtistsGrid
                        case .albums:
                            albumsGrid
                        case .genres:
                            genresGrid
                        case .songs:
                            songsList
                        case .playlists:
                            playlistsGrid
                        }
                    }
                }
            } else {
                // Search Results View for Music
                if isSearching && searchResults.isEmpty {
                    ProgressView("Searching...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if searchResults.isEmpty {
                    ContentUnavailableView.search(text: searchText)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 24) {
                            let grouped = Dictionary(grouping: searchResults, by: { $0.type ?? "Unknown" })
                            let sortedKeys = grouped.keys.sorted()

                            ForEach(sortedKeys, id: \.self) { type in
                                if let items = grouped[type] {
                                    musicSearchSection(title: displayNameForType(type), items: items)
                                }
                            }
                        }
                        .padding()
                    }
                }
            }
        }
        .navigationTitle(library.displayName)
        .searchable(text: $searchText, prompt: "Search music library")
        .task { await loadMusicData() }
        .onChange(of: selectedTab) { _, _ in
            Task { await loadMusicData() }
        }
        .onChange(of: searchText) { _, newValue in
            performSearch(query: newValue)
        }
    }

    private func performSearch(query: String) {
        searchTask?.cancel()
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else {
            searchResults = []
            isSearching = false
            return
        }

        isSearching = true
        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            
            do {
                let result = try await session.apiClient.searchItems(
                    query: query,
                    parentId: library.id,
                    limit: 48,
                    includeItemTypes: ["Audio", "MusicAlbum", "MusicArtist", "Playlist"]
                )
                if !Task.isCancelled {
                    searchResults = result.items ?? []
                }
            } catch {}
            isSearching = false
        }
    }

    private func displayNameForType(_ type: String) -> String {
        switch type {
        case "Audio": return "Songs"
        case "MusicAlbum": return "Albums"
        case "MusicArtist": return "Artists"
        case "Playlist": return "Playlists"
        default: return type
        }
    }

    private func musicSearchSection(title: String, items: [BaseItemDto]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.title3).fontWeight(.bold)
            if title == "Songs" {
                LazyVStack(spacing: 1) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, song in
                        NavigationLink(value: song) {
                            SongRow(song: song, index: index + 1, apiClient: session.apiClient)
                        }
                        .buttonStyle(.plain)
                    }
                }
            } else {
                LazyVGrid(columns: gridColumns, spacing: 20) {
                    ForEach(items, id: \.id) { item in
                        NavigationLink(value: item) {
                            if title == "Artists" {
                                VStack(spacing: 8) {
                                    ArtistImageView(artist: item, apiClient: session.apiClient)
                                        .frame(width: 160, height: 160)
                                        .clipShape(Circle())
                                    Text(item.displayName).font(.caption).fontWeight(.medium).lineLimit(1)
                                }
                            } else {
                                ItemPosterCard(item: item, apiClient: session.apiClient, width: 160)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var suggestionsGrid: some View {
        VStack(alignment: .leading, spacing: 32) {
            if !suggestions.isEmpty {
                suggestionSection(title: "Recently Added Music", items: suggestions)
            }
            if !recentlyPlayed.isEmpty {
                suggestionSection(title: "Recently Played", items: recentlyPlayed)
            }
            if !frequentlyPlayed.isEmpty {
                suggestionSection(title: "Frequently Played", items: frequentlyPlayed)
            }
        }
        .padding(.vertical)
    }

    private func suggestionSection(title: String, items: [BaseItemDto]) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title).font(.title2).fontWeight(.bold).padding(.horizontal)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 20) {
                    ForEach(items, id: \.id) { item in
                        NavigationLink(value: item) {
                            VStack(alignment: .leading, spacing: 6) {
                                ItemPosterCard(item: item, apiClient: session.apiClient, width: 160)
                                if let artist = item.albumArtist ?? item.artists?.first {
                                    Text(artist).font(.caption2).foregroundStyle(.secondary).lineLimit(1).frame(width: 160, alignment: .leading)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal)
            }
        }
    }

    private var albumArtistsGrid: some View {
        LazyVGrid(columns: gridColumns, spacing: 20) {
            ForEach(filteredAlbumArtists, id: \.id) { artist in
                NavigationLink(value: artist) {
                    VStack(spacing: 8) {
                        ArtistImageView(artist: artist, apiClient: session.apiClient)
                            .frame(width: 160, height: 160)
                            .clipShape(Circle())
                        Text(artist.displayName).font(.caption).fontWeight(.medium).lineLimit(1)
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .padding()
    }

    private var genresGrid: some View {
        LazyVGrid(columns: gridColumns, spacing: 20) {
            ForEach(filteredGenres, id: \.id) { genre in
                NavigationLink(value: genre) {
                    ItemPosterCard(item: genre, apiClient: session.apiClient, width: 160)
                }
                .buttonStyle(.plain)
            }
        }
        .padding()
    }

    private var artistsGrid: some View {
        LazyVGrid(columns: gridColumns, spacing: 20) {
            ForEach(filteredArtists, id: \.id) { artist in
                NavigationLink(value: artist) {
                    VStack(spacing: 8) {
                        ArtistImageView(artist: artist, apiClient: session.apiClient)
                            .frame(width: 160, height: 160)
                            .clipShape(Circle())
                        Text(artist.displayName).font(.caption).fontWeight(.medium).lineLimit(1)
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .padding()
    }

    private var albumsGrid: some View {
        LazyVGrid(columns: gridColumns, spacing: 20) {
            ForEach(filteredAlbums, id: \.id) { album in
                NavigationLink(value: album) {
                    VStack(alignment: .leading, spacing: 6) {
                        ItemPosterCard(item: album, apiClient: session.apiClient, width: 160)
                        if let artist = album.albumArtist {
                            Text(artist).font(.caption2).foregroundStyle(.secondary).lineLimit(1).frame(width: 160, alignment: .leading)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .padding()
    }

    private var songsList: some View {
        LazyVStack(spacing: 1) {
            ForEach(Array(filteredSongs.enumerated()), id: \.element.id) { index, song in
                NavigationLink(value: song) {
                    SongRow(song: song, index: index + 1, apiClient: session.apiClient)
                }
                .buttonStyle(.plain)
            }
        }
        .padding()
    }

    private var playlistsGrid: some View {
        Group {
            if playlists.isEmpty {
                ContentUnavailableView("No Playlists", systemImage: "music.note.list", description: Text("You haven't created any playlists yet."))
                    .padding(.top, 40)
            } else {
                LazyVGrid(columns: gridColumns, spacing: 20) {
                    ForEach(filteredPlaylists, id: \.id) { playlist in
                        NavigationLink(value: playlist) {
                            ItemPosterCard(item: playlist, apiClient: session.apiClient, width: 160)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding()
            }
        }
    }

    private var filteredAlbumArtists: [BaseItemDto] {
        guard !searchText.isEmpty else { return albumArtists }
        return albumArtists.filter { ($0.name ?? "").localizedCaseInsensitiveContains(searchText) }
    }

    private var filteredGenres: [BaseItemDto] {
        guard !searchText.isEmpty else { return genres }
        return genres.filter { ($0.name ?? "").localizedCaseInsensitiveContains(searchText) }
    }

    private var filteredArtists: [BaseItemDto] {
        guard !searchText.isEmpty else { return artists }
        return artists.filter { ($0.name ?? "").localizedCaseInsensitiveContains(searchText) }
    }

    private var filteredAlbums: [BaseItemDto] {
        guard !searchText.isEmpty else { return albums }
        return albums.filter { ($0.name ?? "").localizedCaseInsensitiveContains(searchText) || ($0.albumArtist ?? "").localizedCaseInsensitiveContains(searchText) }
    }

    private var filteredSongs: [BaseItemDto] {
        guard !searchText.isEmpty else { return songs }
        return songs.filter { ($0.name ?? "").localizedCaseInsensitiveContains(searchText) }
    }

    private var filteredPlaylists: [BaseItemDto] {
        guard !searchText.isEmpty else { return playlists }
        return playlists.filter { ($0.name ?? "").localizedCaseInsensitiveContains(searchText) }
    }

    private func loadMusicData() async {
        isLoading = true
        let api = session.apiClient
        switch selectedTab {
        case .suggestions:
            do {
                async let latestReq = api.getLatestItems(parentId: library.id, limit: 20)
                async let recentReq = api.getItems(parentId: library.id, includeItemTypes: ["Audio", "MusicAlbum"], sortBy: ["DatePlayed"], sortOrder: "Descending", filters: ["IsPlayed"], limit: 20, recursive: true)
                async let frequentReq = api.getItems(parentId: library.id, includeItemTypes: ["Audio", "MusicAlbum"], sortBy: ["PlayCount"], sortOrder: "Descending", filters: ["IsPlayed"], limit: 20, recursive: true)
                
                suggestions = try await latestReq
                recentlyPlayed = try await recentReq.items ?? []
                frequentlyPlayed = try await frequentReq.items ?? []
            } catch {}
        case .artists:
            do {
                let result = try await api.getArtists(parentId: library.id, sortBy: ["SortName"], sortOrder: "Ascending")
                artists = result.items ?? []
            } catch {}
        case .albumArtists:
            do {
                let result = try await api.getAlbumArtists(parentId: library.id, sortBy: ["SortName"], sortOrder: "Ascending")
                albumArtists = result.items ?? []
            } catch {}
        case .albums:
            do {
                let result = try await api.getAlbums(parentId: library.id, sortBy: ["SortName"], sortOrder: "Ascending")
                albums = result.items ?? []
            } catch {}
        case .genres:
            do {
                let result = try await api.getMusicGenres(parentId: library.id, sortBy: ["SortName"], sortOrder: "Ascending")
                genres = result.items ?? []
            } catch {}
        case .songs:
            do {
                let result = try await api.getSongs(parentId: library.id, limit: 500, sortBy: ["SortName"], sortOrder: "Ascending")
                songs = result.items ?? []
            } catch {}
        case .playlists:
            do {
                // Try fetching audio playlists specifically
                let result = try await api.getPlaylists()
                playlists = result.items ?? []
            } catch {}
        }
        isLoading = false
    }
}

struct ArtistImageView: View {
    let artist: BaseItemDto
    let apiClient: JellyfinAPIClient
    @State private var imageURL: URL?
    var body: some View {
        RemoteImageView(url: imageURL, section: .music, cornerRadius: 80)
            .task {
                if let id = artist.id {
                    imageURL = await apiClient.imageURL(itemId: id, imageType: "Primary", maxWidth: 320, tag: artist.imageTags?["Primary"])
                }
            }
    }
}

struct SongRow: View {
    let song: BaseItemDto
    let index: Int
    let apiClient: JellyfinAPIClient
    var body: some View {
        HStack(spacing: 12) {
            Text("\(index)").font(.caption).foregroundStyle(.secondary).frame(width: 30, alignment: .trailing).monospacedDigit()
            VStack(alignment: .leading, spacing: 2) {
                Text(song.displayName).font(.body).lineLimit(1)
                HStack(spacing: 4) {
                    if let artists = song.artists, !artists.isEmpty { Text(artists.joined(separator: ", ")).foregroundStyle(.secondary) }
                    if let album = song.album { Text("  \(album)").foregroundStyle(.tertiary) }
                }
                .font(.caption).lineLimit(1)
            }
            Spacer()
            if let runtime = song.runtimeText { Text(runtime).font(.caption).foregroundStyle(.secondary).monospacedDigit() }
        }
        .padding(.vertical, 6).padding(.horizontal, 8).contentShape(Rectangle())
    }
}

struct AlbumDetailView: View {
    @Environment(SessionManager.self) private var session
    let album: BaseItemDto
    @State private var tracks: [BaseItemDto] = []
    @State private var imageURL: URL?
    @State private var isLoading = true
    @State private var isFavorite = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack(alignment: .top, spacing: 24) {
                    RemoteImageView(url: imageURL, section: .music, cornerRadius: 8).frame(width: 200, height: 200)
                    VStack(alignment: .leading, spacing: 8) {
                        Text(album.displayName).font(.largeTitle).fontWeight(.bold)
                        if let artist = album.albumArtist { Text(artist).font(.title3).foregroundStyle(.secondary) }
                        if let year = album.yearText { Text(year).font(.body).foregroundStyle(.tertiary) }
                        if let count = album.childCount { Text("\(count) tracks").font(.callout).foregroundStyle(.tertiary) }
                        
                        HStack(spacing: 8) {
                            Button {
                                if !tracks.isEmpty {
                                    MusicPlayerManager.shared.play(song: tracks.first!, queue: tracks)
                                }
                            } label: {
                                Label("Play All", systemImage: "play.fill")
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(tracks.isEmpty)
                            
                            Button {
                                toggleFavorite()
                            } label: {
                                Image(systemName: isFavorite ? "heart.fill" : "heart")
                                    .foregroundStyle(isFavorite ? .red : .secondary)
                            }
                            .buttonStyle(.bordered)
                            
                            Button {
                                if !tracks.isEmpty {
                                    MusicPlayerManager.shared.play(song: tracks.randomElement()!, queue: tracks.shuffled())
                                }
                            } label: {
                                Image(systemName: "shuffle")
                            }
                            .buttonStyle(.bordered)
                            .disabled(tracks.isEmpty)
                            
                            Button {
                                Task {
                                    if let id = album.id {
                                        let mix = try? await session.apiClient.getInstantMix(itemId: id)
                                        if let mixed = mix?.items, !mixed.isEmpty {
                                            MusicPlayerManager.shared.play(song: mixed.first!, queue: mixed)
                                        }
                                    }
                                }
                            } label: {
                                Image(systemName: "wand.and.stars")
                            }
                            .buttonStyle(.bordered)
                        }
                        .padding(.top, 8)
                    }
                    Spacer()
                }.padding()
                Divider()
                if isLoading {
                    ProgressView().frame(maxWidth: .infinity)
                } else {
                    LazyVStack(spacing: 1) {
                        ForEach(Array(tracks.enumerated()), id: \.element.id) { index, track in
                            NavigationLink(value: track) {
                                SongRow(song: track, index: track.indexNumber ?? (index + 1), apiClient: session.apiClient)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal)
                }
            }
        }
        .navigationTitle(album.displayName)
        .toolbarBackground(.hidden)
        .task {
            isFavorite = album.userData?.isFavorite ?? false
            if let id = album.id {
                imageURL = await session.apiClient.imageURL(itemId: id, imageType: "Primary", maxWidth: 400, tag: album.imageTags?["Primary"])
                do {
                    let result = try await session.apiClient.getSongs(albumId: id, sortBy: ["IndexNumber"], sortOrder: "Ascending")
                    tracks = result.items ?? []
                } catch {}
            }
            isLoading = false
        }
    }
    
    private func toggleFavorite() {
        guard let id = album.id else { return }
        Task {
            isFavorite.toggle()
            if isFavorite {
                _ = try? await session.apiClient.addFavorite(itemId: id)
            } else {
                _ = try? await session.apiClient.removeFavorite(itemId: id)
            }
        }
    }
}

struct MusicCollectionDetailView: View {
    @Environment(SessionManager.self) private var session
    let collection: BaseItemDto
    @State private var albums: [BaseItemDto] = []
    @State private var tracks: [BaseItemDto] = []
    @State private var imageURL: URL?
    @State private var isLoading = true
    @State private var isFavorite = false
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack(alignment: .top, spacing: 24) {
                    if collection.type == "MusicArtist" {
                        RemoteImageView(url: imageURL, section: .music, cornerRadius: 80).frame(width: 160, height: 160).clipShape(Circle())
                    } else {
                        RemoteImageView(url: imageURL, section: .music, cornerRadius: 8).frame(width: 200, height: 200)
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        Text(collection.displayName).font(.largeTitle).fontWeight(.bold)
                        Text(collection.type == "MusicArtist" ? "Artist" : (collection.type == "Playlist" ? "Playlist" : "Genre"))
                            .font(.title3).foregroundStyle(.secondary)
                        
                        HStack(spacing: 8) {
                            Button {
                                if !tracks.isEmpty {
                                    MusicPlayerManager.shared.play(song: tracks.first!, queue: tracks)
                                }
                            } label: {
                                Label("Play All", systemImage: "play.fill")
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(tracks.isEmpty)
                            
                            Button {
                                toggleFavorite()
                            } label: {
                                Image(systemName: isFavorite ? "heart.fill" : "heart")
                                    .foregroundStyle(isFavorite ? .red : .secondary)
                            }
                            .buttonStyle(.bordered)
                            
                            Button {
                                if !tracks.isEmpty {
                                    MusicPlayerManager.shared.play(song: tracks.randomElement()!, queue: tracks.shuffled())
                                }
                            } label: {
                                Image(systemName: "shuffle")
                            }
                            .buttonStyle(.bordered)
                            .disabled(tracks.isEmpty)
                            
                            Button {
                                Task {
                                    if let id = collection.id {
                                        let mix = try? await session.apiClient.getInstantMix(itemId: id)
                                        if let mixed = mix?.items, !mixed.isEmpty {
                                            MusicPlayerManager.shared.play(song: mixed.first!, queue: mixed)
                                        }
                                    }
                                }
                            } label: {
                                Image(systemName: "wand.and.stars")
                            }
                            .buttonStyle(.bordered)
                        }
                        .padding(.top, 8)
                    }
                    Spacer()
                }.padding()
                Divider()
                if isLoading {
                    ProgressView().frame(maxWidth: .infinity)
                } else {
                    if !albums.isEmpty {
                        VStack(alignment: .leading, spacing: 16) {
                            Text("Albums").font(.title2).fontWeight(.bold).padding(.horizontal)
                            ScrollView(.horizontal, showsIndicators: false) {
                                LazyHStack(spacing: 20) {
                                    ForEach(albums, id: \.id) { album in
                                        NavigationLink(value: album) {
                                            VStack(alignment: .leading, spacing: 6) {
                                                ItemPosterCard(item: album, apiClient: session.apiClient, width: 160)
                                                if let artist = album.albumArtist ?? album.artists?.first {
                                                    Text(artist).font(.caption2).foregroundStyle(.secondary).lineLimit(1).frame(width: 160, alignment: .leading)
                                                }
                                            }
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                                .padding(.horizontal)
                            }
                        }
                        .padding(.vertical)
                        Divider()
                    }
                    
                    if !tracks.isEmpty {
                        VStack(alignment: .leading, spacing: 16) {
                            Text("Top Tracks").font(.title2).fontWeight(.bold).padding(.horizontal)
                            LazyVStack(spacing: 1) {
                                ForEach(Array(tracks.enumerated()), id: \.element.id) { index, track in
                                    NavigationLink(value: track) {
                                        SongRow(song: track, index: track.indexNumber ?? (index + 1), apiClient: session.apiClient)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.horizontal)
                        }
                    }
                }
            }
        }
        .navigationTitle(collection.displayName)
        .toolbarBackground(.hidden)
        .task {
            isFavorite = collection.userData?.isFavorite ?? false
            if let id = collection.id {
                imageURL = await session.apiClient.imageURL(itemId: id, imageType: "Primary", maxWidth: 400, tag: collection.imageTags?["Primary"])
                do {
                    if collection.type == "MusicGenre" {
                        let result = try await session.apiClient.getItems(includeItemTypes: ["Audio"], sortBy: ["SortName"], sortOrder: "Ascending", recursive: true, genres: [collection.displayName])
                        tracks = result.items ?? []
                    } else if collection.type == "Playlist" {
                        let result = try await session.apiClient.getItems(parentId: id, includeItemTypes: ["Audio"], sortBy: ["SortName"], sortOrder: "Ascending", recursive: true)
                        tracks = result.items ?? []
                    } else {
                        // For MusicArtist, fetch both albums and songs
                        async let fetchAlbums = session.apiClient.getItems(includeItemTypes: ["MusicAlbum"], sortBy: ["SortName"], sortOrder: "Ascending", recursive: true, artistIds: [id])
                        async let fetchTracks = session.apiClient.getItems(includeItemTypes: ["Audio"], sortBy: ["SortName"], sortOrder: "Ascending", recursive: true, artistIds: [id])
                        
                        let albumsResult = try? await fetchAlbums
                        let tracksResult = try? await fetchTracks
                        
                        albums = albumsResult?.items ?? []
                        tracks = tracksResult?.items ?? []
                    }
                } catch {}
            }
            isLoading = false
        }
    }
    
    private func toggleFavorite() {
        guard let id = collection.id else { return }
        Task {
            isFavorite.toggle()
            if isFavorite {
                _ = try? await session.apiClient.addFavorite(itemId: id)
            } else {
                _ = try? await session.apiClient.removeFavorite(itemId: id)
            }
        }
    }
}
