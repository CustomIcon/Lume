import SwiftUI
import SwiftData

struct DownloadsView: View {
    @Environment(SessionManager.self) private var session
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \DownloadedItem.downloadDate, order: .reverse) private var downloads: [DownloadedItem]
    
    private let libraries = [
        (name: "Movies", type: "Movie"),
        (name: "TV Shows", type: "Series"),
        (name: "Books", type: "Book"),
        (name: "Music", type: "Audio")
    ]
    
    var body: some View {
        Group {
            if downloads.isEmpty {
                ContentUnavailableView(
                    "No Offline Content",
                    systemImage: "arrow.down.circle",
                    description: Text("Items you download will appear here for you to enjoy even without an internet connection.")
                )
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        // 1. Movies & Books & Music (Normal)
                        ForEach(libraries, id: \.name) { library in
                            if library.type == "Series" {
                                let tvDownloads = downloads.filter { ($0.type == "Episode" || $0.type == "Series") && $0.seriesId != nil }
                                if !tvDownloads.isEmpty {
                                    TVSeriesSection(items: tvDownloads)
                                }
                            } else {
                                let libraryItems = downloads.filter { $0.type == library.type }
                                if !libraryItems.isEmpty {
                                    SectionView(title: library.name, items: libraryItems)
                                }
                            }
                        }
                        
                        let otherItems = downloads.filter { item in
                            !libraries.map { $0.type }.contains(item.type) && item.type != "Episode"
                        }
                        if !otherItems.isEmpty {
                            SectionView(title: "Other", items: otherItems)
                        }
                    }
                    .padding(.vertical)
                }
            }
        }
        .navigationTitle("Downloads")
        .toolbarBackground(.hidden)
    }
}

private struct TVSeriesSection: View {
    let items: [DownloadedItem]
    @Environment(SessionManager.self) private var session
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("TV Shows")
                .font(.title2)
                .fontWeight(.bold)
                .padding(.horizontal)
            
            let seriesGroups = Dictionary(grouping: items.filter { $0.seriesId != nil }, by: { $0.seriesId! })
            
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 20)], spacing: 20) {
                ForEach(seriesGroups.keys.sorted(), id: \.self) { seriesId in
                    if let firstItem = seriesGroups[seriesId]?.first {
                        NavigationLink(value: seriesId) {
                            SeriesDownloadCard(seriesId: seriesId, name: firstItem.seriesName ?? "Unknown Series", episodeCount: seriesGroups[seriesId]?.count ?? 0)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal)
        }
    }
}

private struct SeriesDownloadCard: View {
    let seriesId: String
    let name: String
    let episodeCount: Int
    @Environment(SessionManager.self) private var session
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .bottomTrailing) {
                Group {
                    if let imageURL = session.downloadManager.getLocalSeriesImagePath(for: seriesId),
                       let data = try? Data(contentsOf: imageURL),
                       let nsImage = NSImage(data: data) {
                        Image(nsImage: nsImage)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } else {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.gray.opacity(0.1))
                            .overlay {
                                Image(systemName: "tv")
                                    .font(.largeTitle)
                            }
                    }
                }
                .aspectRatio(0.66, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                
                Text("\(episodeCount) Ep")
                    .font(.caption2.bold())
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .glassEffect(in: Capsule())
                    .padding(8)
            }
            
            Text(name)
                .font(.caption)
                .fontWeight(.bold)
                .lineLimit(1)
        }
    }
}

private struct SectionView: View {
    let title: String
    let items: [DownloadedItem]
    @Environment(SessionManager.self) private var session
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.title2)
                .fontWeight(.bold)
                .padding(.horizontal)
            
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 20)], spacing: 20) {
                ForEach(items) { item in
                    DownloadItemCard(item: item)
                }
            }
            .padding(.horizontal)
        }
    }
}

private struct DownloadItemCard: View {
    let item: DownloadedItem
    @Environment(SessionManager.self) private var session
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .bottomTrailing) {
                Group {
                    if let imageURL = session.downloadManager.getLocalImagePath(for: item.itemId),
                       let data = try? Data(contentsOf: imageURL),
                       let nsImage = NSImage(data: data) {
                        Image(nsImage: nsImage)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } else {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.gray.opacity(0.1))
                            .overlay {
                                Image(systemName: item.type == "Book" ? "book" : (item.type == "Audio" ? "music.note" : "film"))
                                    .font(.largeTitle)
                            }
                    }
                }
                .aspectRatio(item.type == "Audio" || item.type == "MusicAlbum" ? 1.0 : 0.66, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay {
                    if let active = session.downloadManager.activeDownloads[item.itemId] {
                        ZStack {
                            Color.black.opacity(0.4)
                            VStack(spacing: 8) {
                                ProgressView(value: active.progress)
                                    .progressViewStyle(.linear)
                                    .padding(.horizontal)
                                
                                Button {
                                    if active.isPaused {
                                        Task { await session.downloadManager.resumeDownload(itemId: item.itemId, from: session.apiClient) }
                                    } else {
                                        session.downloadManager.pauseDownload(itemId: item.itemId)
                                    }
                                } label: {
                                    Image(systemName: active.isPaused ? "play.fill" : "pause.fill")
                                        .font(.caption)
                                }
                                .buttonStyle(.borderedProminent)
                                .controlSize(.small)
                            }
                        }
                    } else if item.status == "paused" {
                        ZStack {
                            Color.black.opacity(0.4)
                            Button {
                                Task { await session.downloadManager.resumeDownload(itemId: item.itemId, from: session.apiClient) }
                            } label: {
                                Image(systemName: "play.fill")
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    }
                }
                
                if item.status == "completed" {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .padding(8)
                        .glassEffect(in: Circle())
                        .padding(4)
                }
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                    .font(.caption)
                    .fontWeight(.bold)
                    .lineLimit(1)
            }
        }
        .contextMenu {
            Button(role: .destructive) {
                session.downloadManager.deleteDownload(itemId: item.itemId)
            } label: {
                Label("Delete Download", systemImage: "trash")
            }
        }
        .onTapGesture {
            playLocal(item)
        }
    }
    
    private func playLocal(_ item: DownloadedItem) {
        let dto = BaseItemDto(name: item.name, id: item.itemId, collectionType: item.collectionType, type: item.type)
        if item.type == "Book" {
            session.activeBookItem = dto
        } else if item.type == "Audio" {
            MusicPlayerManager.shared.play(song: dto)
        } else {
            session.activeVideoItem = dto
        }
    }
}

// MARK: - Series Downloads Detail View

struct SeriesDownloadsDetailView: View {
    let seriesId: String
    @Environment(SessionManager.self) private var session
    @Query private var allDownloads: [DownloadedItem]
    
    @State private var seasons: [BaseItemDto] = []
    @State private var isLoading = true
    
    var downloads: [DownloadedItem] {
        allDownloads.filter { $0.seriesId == seriesId }
    }
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if let first = downloads.first {
                    HStack(spacing: 20) {
                        if let imageURL = session.downloadManager.getLocalSeriesImagePath(for: seriesId),
                           let data = try? Data(contentsOf: imageURL),
                           let nsImage = NSImage(data: data) {
                            Image(nsImage: nsImage)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 120)
                                .cornerRadius(8)
                        }
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text(first.seriesName ?? "Series")
                                .font(.largeTitle.bold())
                            Text("\(downloads.count) episodes downloaded")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding()
                }
                
                if isLoading {
                    ProgressView("Loading seasons...")
                        .frame(maxWidth: .infinity)
                } else {
                    ForEach(seasons, id: \.id) { season in
                        let seasonEpisodes = downloads.filter { $0.seasonId == season.id }
                        if !seasonEpisodes.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Text(season.name ?? "Season")
                                    .font(.title2.bold())
                                    .padding(.horizontal)
                                
                                LazyVStack(spacing: 12) {
                                    ForEach(seasonEpisodes) { episode in
                                        DownloadEpisodeRow(item: episode)
                                    }
                                }
                                .padding(.horizontal)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Series Downloads")
        .task {
            await loadSeasons()
        }
    }
    
    private func loadSeasons() async {
        do {
            let result = try await session.apiClient.getSeasons(seriesId: seriesId)
            seasons = result.items ?? []
        } catch {}
        isLoading = false
    }
}

struct DownloadEpisodeRow: View {
    let item: DownloadedItem
    @Environment(SessionManager.self) private var session
    
    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                if let imageURL = session.downloadManager.getLocalImagePath(for: item.itemId),
                   let data = try? Data(contentsOf: imageURL),
                   let nsImage = NSImage(data: data) {
                    Image(nsImage: nsImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    Rectangle()
                        .fill(Color.gray.opacity(0.1))
                }
            }
            .frame(width: 120, height: 68)
            .cornerRadius(4)
            .clipped()
            
            VStack(alignment: .leading, spacing: 4) {
                Text(item.name)
                    .fontWeight(.medium)
                Text(item.status.capitalized)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            Button {
                let dto = BaseItemDto(name: item.name, id: item.itemId, collectionType: item.collectionType, type: item.type)
                session.activeVideoItem = dto
            } label: {
                Image(systemName: "play.fill")
            }
            .buttonStyle(.bordered)
        }
        .padding(8)
        .glassEffect(in: RoundedRectangle(cornerRadius: 8))
        .contextMenu {
            Button(role: .destructive) {
                session.downloadManager.deleteDownload(itemId: item.itemId)
            } label: {
                Label("Delete Download", systemImage: "trash")
            }
        }
    }
}
