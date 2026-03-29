import SwiftUI

struct ItemDetailView: View {
    @Environment(SessionManager.self) private var session
    let item: BaseItemDto

    @State private var fullItem: BaseItemDto?
    @State private var similarItems: [BaseItemDto] = []
    @State private var backdropURL: URL?
    @State private var posterURL: URL?
    @State private var isLoading = true
    @State private var isFavorite: Bool = false
    @State private var isPlayed: Bool = false
    @State private var logoURL: URL?

    private var displayItem: BaseItemDto {
        fullItem ?? item
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if displayItem.type != "Book" && displayItem.type != "Episode" && displayItem.type != "Audio" && displayItem.type != "MusicAlbum" {
                    // Backdrop
                    ZStack(alignment: .bottomLeading) {
                        RemoteImageView(url: backdropURL, section: CacheSection.from(itemType: displayItem.type), cornerRadius: 0)
                            .frame(height: 350)
                            .frame(maxWidth: .infinity)
                            .clipped()
                            .overlay {
                                // Top Dark Fade for Readability
                                LinearGradient(
                                    stops: [
                                        .init(color: .black, location: 0.0),
                                        .init(color: .black.opacity(0.4), location: 0.2),
                                        .init(color: .clear, location: 0.5)
                                    ],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                                
                                // Bottom Dark Fade for Atmosphere
                                LinearGradient(
                                    stops: [
                                        .init(color: .clear, location: 0.5),
                                        .init(color: .black.opacity(0.5), location: 0.85),
                                        .init(color: .black, location: 1.0)
                                    ],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            }
                            .mask {
                                LinearGradient(
                                    stops: [
                                        .init(color: .black, location: 0.0),
                                        .init(color: .black, location: 0.8),
                                        .init(color: .clear, location: 1.0)
                                    ],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            }

                        headerContent
                    }
                } else {
                    // No backdrop for books, episodes, or music items, just the content
                    headerContent
                        .padding(.top, 80) // Space for the top bar
                }

                // Overview
                if let overview = displayItem.overview {
                    Text(overview)
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .padding()
                        .textSelection(.enabled)
                }

                // Genres
                if let genres = displayItem.genres, !genres.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(genres, id: \.self) { genre in
                                Text(genre)
                                    .font(.caption)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 4)
                                    .padding(.vertical, 4)
                                    .glassEffect(in: Capsule())
                            }
                        }
                        .padding(.horizontal)
                    }
                }

                // Cast & Crew
                if let people = displayItem.people, !people.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(displayItem.type == "Audio" || displayItem.type == "MusicAlbum" || displayItem.type == "MusicVideo" ? "Artists" : "Cast & Crew")
                            .font(.title3)
                            .fontWeight(.bold)
                            .padding(.horizontal)

                        ScrollView(.horizontal, showsIndicators: false) {
                            LazyHStack(spacing: 16) {
                                ForEach(Array(people.prefix(20).enumerated()), id: \.offset) { _, person in
                                    PersonCard(person: person, apiClient: session.apiClient)
                                }
                            }
                            .padding(.horizontal)
                        }
                    }
                    .padding(.top)
                }

                // Similar Items
                if !similarItems.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("More Like This")
                            .font(.title3)
                            .fontWeight(.bold)
                            .padding(.horizontal)

                        ScrollView(.horizontal, showsIndicators: false) {
                            LazyHStack(spacing: 12) {
                                ForEach(similarItems, id: \.id) { similar in
                                    NavigationLink(value: similar) {
                                        ItemPosterCard(item: similar, apiClient: session.apiClient, width: 130)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.horizontal)
                        }
                    }
                    .padding(.top)
                }

                // Media Info
                if let sources = displayItem.mediaSources, !sources.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Media Info")
                            .font(.title3)
                            .fontWeight(.bold)
                            .padding(.horizontal)

                        ForEach(sources) { source in
                            MediaSourceInfoRow(source: source)
                                .padding(.horizontal)
                        }
                    }
                    .padding(.top)
                }

                Spacer(minLength: 40)
            }
        }
        .ignoresSafeArea(edges: .top)
        .navigationTitle(displayItem.displayName)
        .toolbarBackground(.hidden, for: .windowToolbar)
        .toolbarBackground(.hidden, for: .automatic)
        .task { await loadDetails() }
    }

    private var headerContent: some View {
        HStack(alignment: .bottom, spacing: 24) {
            // Poster
            let isWide = (displayItem.primaryImageAspectRatio ?? (displayItem.type == "Episode" ? 1.77 : 0.66)) > 1.2
            let isSquare = displayItem.type == "MusicAlbum" || displayItem.type == "Audio"
            let pWidth: CGFloat = isWide ? 250 : isSquare ? 200 : 150
            let pHeight: CGFloat = isSquare ? pWidth : (isWide ? pWidth / 1.77 : pWidth * 1.5)
            
            RemoteImageView(url: posterURL, section: CacheSection.from(itemType: displayItem.type), cornerRadius: 8, title: displayItem.displayName)
                .frame(width: pWidth, height: pHeight)
                .liquidCard()

            // Title & metadata
            VStack(alignment: .leading, spacing: 8) {
                if let episodeLabel = displayItem.episodeLabel {
                    Text(episodeLabel)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                if let logoURL {
                    RemoteImageView(url: logoURL, section: CacheSection.from(itemType: displayItem.type), cornerRadius: 0, contentMode: .fit)
                        .frame(maxWidth: 280, maxHeight: 70, alignment: .leading)
                } else {
                    Text(displayItem.displayName)
                        .font(.largeTitle)
                        .fontWeight(.bold)
                }

                if let seriesName = displayItem.seriesName {
                    Text(seriesName)
                        .font(.title3)
                        .foregroundStyle(.secondary)
                } else if displayItem.type == "Audio" || displayItem.type == "MusicAlbum" || displayItem.type == "MusicVideo", let artist = displayItem.albumArtist ?? displayItem.artists?.first {
                    Text(artist)
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }

                metadataRow

                actionButtons
            }
        }
        .padding()
    }

    private var metadataRow: some View {
        HStack(spacing: 12) {
            if let year = displayItem.yearText {
                Text(year)
            }
            if let runtime = displayItem.runtimeText {
                Text(runtime)
            }
            if let rating = displayItem.communityRating {
                HStack(spacing: 2) {
                    Image(systemName: "star.fill")
                        .foregroundStyle(.yellow)
                    Text(String(format: "%.1f", rating))
                }
            }
            if let officialRating = displayItem.officialRating {
                Text(officialRating)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(.secondary, lineWidth: 1)
                    )
            }
            if let critic = displayItem.criticRating {
                HStack(spacing: 2) {
                    Image(systemName: "theatermasks.fill")
                    Text("\(Int(critic))%")
                }
                .foregroundStyle(.secondary)
            }
        }
        .font(.callout)
        .foregroundStyle(.secondary)
    }

    private var actionButtons: some View {
        HStack(spacing: 12) {
            Button {
                if displayItem.type == "Book" {
                    session.activeBookItem = displayItem
                } else if displayItem.type == "Audio" {
                    MusicPlayerManager.shared.play(song: displayItem)
                } else {
                    session.activeVideoItem = displayItem
                }
            } label: {
                Label(displayItem.type == "Book" ? "Read" : "Play", systemImage: displayItem.type == "Book" ? "book.fill" : "play.fill")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            Button {
                toggleFavorite()
            } label: {
                Image(systemName: isFavorite ? "heart.fill" : "heart")
                    .foregroundStyle(isFavorite ? .red : .secondary)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)

            if displayItem.type == "Audio" || displayItem.type == "MusicAlbum" || displayItem.type == "MusicVideo" {
                Button {
                    Task {
                        if let albumId = displayItem.albumId ?? displayItem.id {
                            let result = try? await session.apiClient.getSongs(albumId: albumId)
                            if let tracks = result?.items?.shuffled(), !tracks.isEmpty {
                                MusicPlayerManager.shared.play(song: tracks.first!, queue: tracks)
                            }
                        }
                    }
                } label: {
                    Image(systemName: "shuffle")
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                
                Button {
                    Task {
                        if let id = displayItem.id {
                            let mix = try? await session.apiClient.getInstantMix(itemId: id)
                            if let items = mix?.items, !items.isEmpty {
                                MusicPlayerManager.shared.play(song: items.first!, queue: items)
                            }
                        }
                    }
                } label: {
                    Image(systemName: "wand.and.stars")
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            } else {
                Button {
                    togglePlayed()
                } label: {
                    Image(systemName: isPlayed ? "eye.fill" : "eye")
                        .foregroundStyle(isPlayed ? .green : .secondary)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }
            
            downloadButton
        }
    }
    
    private var downloadButton: some View {
        Group {
            if let active = session.downloadManager.activeDownloads[displayItem.id ?? ""] {
                HStack(spacing: 8) {
                    ProgressView(value: active.progress)
                        .progressViewStyle(.circular)
                        .controlSize(.small)
                    
                    Button {
                        if active.isPaused {
                            Task { await session.downloadManager.resumeDownload(itemId: displayItem.id ?? "", from: session.apiClient) }
                        } else {
                            session.downloadManager.pauseDownload(itemId: displayItem.id ?? "")
                        }
                    } label: {
                        Image(systemName: active.isPaused ? "play.fill" : "pause.fill")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            } else if session.downloadManager.isDownloaded(displayItem.id ?? "") {
                Button {
                    // Logic to delete or show menu
                } label: {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
                .contextMenu {
                    Button(role: .destructive) {
                        session.downloadManager.deleteDownload(itemId: displayItem.id ?? "")
                    } label: {
                        Label("Delete Download", systemImage: "trash")
                    }
                }
            } else {
                Button {
                    Task {
                        await session.downloadManager.download(displayItem, from: session.apiClient)
                    }
                } label: {
                    Image(systemName: "arrow.down.circle")
                }
            }
        }
        .padding(.horizontal, 4)
    }


    private func loadDetails() async {
        guard let itemId = item.id else { return }

        // Load full item details
        do {
            fullItem = try await session.apiClient.getItem(itemId: itemId)
            isFavorite = fullItem?.userData?.isFavorite ?? false
            isPlayed = fullItem?.userData?.played ?? false
        } catch {}

        // Load images
        let backdropTags = item.backdropImageTags ?? item.parentBackdropImageTags
        let backdropId = item.parentBackdropItemId ?? itemId
        if let tag = backdropTags?.first {
            backdropURL = await session.apiClient.imageURL(itemId: backdropId, imageType: "Backdrop", maxWidth: 1920, tag: tag)
        }
        posterURL = await session.apiClient.imageURL(itemId: itemId, imageType: "Primary", maxWidth: 300, tag: item.imageTags?["Primary"])
        
        if let logoTag = fullItem?.imageTags?["Logo"] {
            logoURL = await session.apiClient.imageURL(itemId: itemId, imageType: "Logo", maxWidth: 640, tag: logoTag)
        }

        // Load similar
        do {
            let result = try await session.apiClient.getSimilarItems(itemId: itemId)
            similarItems = result.items ?? []
        } catch {}

        isLoading = false
    }

    private func toggleFavorite() {
        guard let itemId = item.id else { return }
        Task {
            do {
                let result = try await session.toggleFavorite(itemId: itemId, isFavorite: isFavorite)
                isFavorite = result.isFavorite ?? isFavorite
            } catch {}
        }
    }

    private func togglePlayed() {
        guard let itemId = item.id else { return }
        Task {
            do {
                let result = try await session.togglePlayed(itemId: itemId, isPlayed: isPlayed)
                isPlayed = result.played ?? isPlayed
            } catch {}
        }
    }
}

struct PersonCard: View {
    let person: BaseItemPerson
    let apiClient: JellyfinAPIClient
    @State private var imageURL: URL?

    var body: some View {
        NavigationLink(value: person) {
            VStack(spacing: 4) {
                RemoteImageView(url: imageURL, section: .others, cornerRadius: 40, title: person.name, itemType: person.type ?? "Person", hideTitle: true)
                    .frame(width: 80, height: 80)
                    .clipShape(Circle())

                Text(person.name ?? "")
                    .font(.caption2)
                    .fontWeight(.medium)
                    .lineLimit(1)
                    .frame(width: 80)

                if let role = person.role, !role.isEmpty {
                    Text(role)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .frame(width: 80)
                }
            }
        }
        .buttonStyle(.plain)
        .task {
            if let id = person.id {
                imageURL = await apiClient.personImageURL(personId: id, tag: person.primaryImageTag, maxWidth: 160)
            }
        }
    }
}

struct MediaSourceInfoRow: View {
    let source: MediaSourceInfo

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let name = source.name {
                Text(name)
                    .font(.headline)
            }

            HStack(spacing: 16) {
                if let container = source.container {
                    Label(container.uppercased(), systemImage: "doc")
                }
                if let bitrate = source.bitrate {
                    Label("\(bitrate / 1_000_000) Mbps", systemImage: "speedometer")
                }
                if let size = source.size {
                    Label(ByteCountFormatter.string(fromByteCount: size, countStyle: .file), systemImage: "externaldrive")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            // Video/Audio streams
            if let streams = source.mediaStreams {
                ForEach(streams.filter { $0.type == "Video" }) { stream in
                    HStack(spacing: 8) {
                        Image(systemName: "film")
                        Text([stream.codec?.uppercased(), stream.width.flatMap { w in stream.height.map { h in "\(w)x\(h)" } }].compactMap { $0 }.joined(separator: " "))
                    }
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                }
                ForEach(streams.filter { $0.type == "Audio" }) { stream in
                    HStack(spacing: 8) {
                        Image(systemName: "speaker.wave.2")
                        Text([stream.displayTitle, stream.codec?.uppercased()].compactMap { $0 }.joined(separator: " - "))
                    }
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(.quaternary.opacity(0.5))
        )
    }
}
