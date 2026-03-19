import SwiftUI

enum MusicTab: String, CaseIterable {
    case artists = "Artists"
    case albums = "Albums"
    case songs = "Songs"
    case playlists = "Playlists"
}

struct MusicLibraryView: View {
    @Environment(SessionManager.self) private var session
    let library: BaseItemDto

    @State private var selectedTab: MusicTab = .albums
    @State private var artists: [BaseItemDto] = []
    @State private var albums: [BaseItemDto] = []
    @State private var songs: [BaseItemDto] = []
    @State private var playlists: [BaseItemDto] = []
    @State private var isLoading = true
    @State private var searchText = ""

    private let gridColumns = [
        GridItem(.adaptive(minimum: 160, maximum: 200), spacing: 16)
    ]

    var body: some View {
        VStack(spacing: 0) {
            Picker("Section", selection: $selectedTab) {
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
                    case .artists:
                        artistsGrid
                    case .albums:
                        albumsGrid
                    case .songs:
                        songsList
                    case .playlists:
                        playlistsGrid
                    }
                }
            }
        }
        .navigationTitle(library.displayName)
        .searchable(text: $searchText, prompt: "Filter music")
        .task { await loadMusicData() }
        .onChange(of: selectedTab) { _, _ in
            Task { await loadMusicData() }
        }
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
                SongRow(song: song, index: index + 1, apiClient: session.apiClient)
                    .onTapGesture { MusicPlayerManager.shared.play(song: song, queue: filteredSongs) }
            }
        }
        .padding()
    }

    private var playlistsGrid: some View {
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
        case .artists:
            do {
                let result = try await api.getArtists(parentId: library.id, sortBy: ["SortName"], sortOrder: "Ascending")
                artists = result.items ?? []
            } catch {}
        case .albums:
            do {
                let result = try await api.getAlbums(parentId: library.id, sortBy: ["SortName"], sortOrder: "Ascending")
                albums = result.items ?? []
            } catch {}
        case .songs:
            do {
                let result = try await api.getSongs(parentId: library.id, limit: 500, sortBy: ["SortName"], sortOrder: "Ascending")
                songs = result.items ?? []
            } catch {}
        case .playlists:
            do {
                let result = try await api.getItems(parentId: library.id, includeItemTypes: ["Playlist"], sortBy: ["SortName"], sortOrder: "Ascending", recursive: true)
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
        .onTapGesture { MusicPlayerManager.shared.play(song: song) }
    }
}

struct AlbumDetailView: View {
    @Environment(SessionManager.self) private var session
    let album: BaseItemDto
    @State private var tracks: [BaseItemDto] = []
    @State private var imageURL: URL?
    @State private var isLoading = true
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
                    }
                    Spacer()
                }.padding()
                Divider()
                if isLoading {
                    ProgressView().frame(maxWidth: .infinity)
                } else {
                    LazyVStack(spacing: 1) {
                        ForEach(Array(tracks.enumerated()), id: \.element.id) { index, track in
                            SongRow(song: track, index: track.indexNumber ?? (index + 1), apiClient: session.apiClient)
                                .onTapGesture { MusicPlayerManager.shared.play(song: track, queue: tracks) }
                        }
                    }
                    .padding(.horizontal)
                }
            }
        }
        .navigationTitle(album.displayName)
        .task {
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
}
