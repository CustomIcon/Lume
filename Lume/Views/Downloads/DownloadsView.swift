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
            let activeItems = downloads.filter { $0.status != "completed" }
            let completedItems = downloads.filter { $0.status == "completed" }
            
            if activeItems.isEmpty && completedItems.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "face.dashed")
                        .font(.system(size: 64))
                        .foregroundStyle(.secondary.opacity(0.5))
                    Text("Nothing to see here")
                        .font(.title2.bold())
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 32) {
                        // 1. Active Downloads (Anything not completed)
                        if !activeItems.isEmpty {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Downloading")
                                    .font(.title2.bold())
                                    .padding(.horizontal)
                                
                                LazyVStack(spacing: 12) {
                                    ForEach(activeItems) { item in
                                        ActiveDownloadRow(item: item)
                                    }
                                }
                                .padding(.horizontal)
                            }
                        }
                        
                        // 2. Completed Downloads
                        if !completedItems.isEmpty {
                            VStack(alignment: .leading, spacing: 24) {
                                Text("Downloaded")
                                    .font(.title2.bold())
                                    .padding(.horizontal)
                                
                                ForEach(libraries, id: \.name) { library in
                                    if library.type == "Series" {
                                        let tvDownloads = completedItems.filter { ($0.type == "Episode" || $0.type == "Series") && $0.seriesId != nil }
                                        if !tvDownloads.isEmpty {
                                            TVSeriesSection(items: tvDownloads)
                                        }
                                    } else {
                                        let libraryItems = completedItems.filter { $0.type == library.type }
                                        if !libraryItems.isEmpty {
                                            SectionView(title: library.name, items: libraryItems)
                                        }
                                    }
                                }
                                
                                let otherItems = completedItems.filter { item in
                                    !libraries.map { $0.type }.contains(item.type) && item.type != "Episode"
                                }
                                if !otherItems.isEmpty {
                                    SectionView(title: "Other", items: otherItems)
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
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
                            .fill(ThemeManager.shared.currentFlavor.secondaryBackground.opacity(0.4))
                            .overlay {
                                Image(systemName: "tv")
                                    .font(.largeTitle)
                                    .foregroundStyle(ThemeManager.shared.currentFlavor.accentColor.opacity(0.5))
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
                            .fill(ThemeManager.shared.currentFlavor.secondaryBackground.opacity(0.4))
                            .overlay {
                                Image(systemName: item.type == "Book" ? "book" : (item.type == "Audio" ? "music.note" : "film"))
                                    .font(.largeTitle)
                                    .foregroundStyle(ThemeManager.shared.currentFlavor.accentColor.opacity(0.5))
                            }
                    }
                }
                .aspectRatio(item.type == "Audio" || item.type == "MusicAlbum" ? 1.0 : 0.66, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                
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
    @State private var theme = ThemeManager.shared
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
        .scrollContentBackground(.hidden)
        .background(theme.currentFlavor.backgroundColor.ignoresSafeArea())
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
                        .fill(ThemeManager.shared.currentFlavor.secondaryBackground.opacity(0.4))
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

// MARK: - Active Download Row

struct ActiveDownloadRow: View {
    let item: DownloadedItem
    @Environment(SessionManager.self) private var session
    
    var body: some View {
        HStack(spacing: 16) {
            // Smaller Poster
            ZStack {
                if let imageURL = session.downloadManager.getLocalImagePath(for: item.itemId),
                   let data = try? Data(contentsOf: imageURL),
                   let nsImage = NSImage(data: data) {
                    Image(nsImage: nsImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(ThemeManager.shared.currentFlavor.secondaryBackground.opacity(0.4))
                }
            }
            .frame(width: 44, height: 66)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            
            VStack(alignment: .leading, spacing: 6) {
                Text(item.name)
                    .font(.headline)
                    .lineLimit(1)
                
                let progress = session.downloadManager.activeDownloads[item.itemId]?.progress ?? (item.status == "paused" ? 0.0 : 0.0)
                
                HStack(spacing: 12) {
                    ProgressView(value: progress)
                        .progressViewStyle(.linear)
                    
                    Text("\(Int(progress * 100))%")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 35)
                }
            }
            
            HStack(spacing: 12) {
                // Pause / Resume Button
                let active = session.downloadManager.activeDownloads[item.itemId]
                let isPaused = active?.isPaused ?? (item.status == "paused")
                
                Button {
                    if isPaused {
                        Task { await session.downloadManager.resumeDownload(itemId: item.itemId, from: session.apiClient) }
                    } else {
                        session.downloadManager.pauseDownload(itemId: item.itemId)
                    }
                } label: {
                    Image(systemName: isPaused ? "play.fill" : "pause.fill")
                        .font(.body.bold())
                        .frame(width: 36, height: 36)
                        .background(ThemeManager.shared.currentFlavor.secondaryBackground, in: Circle())
                }
                .buttonStyle(.plain)
                
                // Delete Button
                Button {
                    session.downloadManager.deleteDownload(itemId: item.itemId)
                } label: {
                    Image(systemName: "trash.fill")
                        .font(.body.bold())
                        .frame(width: 36, height: 36)
                        .background(ThemeManager.shared.currentFlavor.secondaryBackground, in: Circle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.red)
            }
        }
        .padding(12)
        .background(ThemeManager.shared.currentFlavor.secondaryBackground.opacity(0.3), in: RoundedRectangle(cornerRadius: 14))
    }
}
