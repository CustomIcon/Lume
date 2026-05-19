import SwiftUI

struct RemoteImageView: View {
    let url: URL?
    var section: CacheSection = .others
    var cornerRadius: CGFloat = 8
    var aspectRatio: CGFloat? = nil
    var title: String? = nil
    var itemType: String? = nil
    var contentMode: ContentMode = .fill
    var hideTitle: Bool = false

    @State private var image: NSImage? = nil
    @State private var isLoading = false
    @State private var loadTask: Task<Void, Never>? = nil

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
            } else if isLoading {
                placeholderView(isSkeleton: true)
                    .shimmer()
            } else {
                placeholderView(isSkeleton: false)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        .onAppear { loadImage() }
        .onDisappear { 
            loadTask?.cancel() 
            loadTask = nil
        }
        .onChange(of: url) { _, _ in loadImage() }
    }

    private func loadImage() {
        loadTask?.cancel()
        
        guard let url else { 
            self.image = nil
            return 
        }
        
        // 1. Check memory/disk cache via manager (Fast check, still on main but memory is fast)
        if let cached = ImageCacheManager.shared.getCachedImage(for: url, section: section) {
            self.image = cached
            self.isLoading = false
            return
        }
        
        // 2. Fetch from network or disk if memory failed
        isLoading = true
        loadTask = Task {
            do {
                // Check disk again in background to be sure
                let (data, _) = try await URLSession.lume.data(from: url)
                
                // IMPORTANT: Check for cancellation before processing heavy data
                if Task.isCancelled { return }
                
                if let downloadedImage = NSImage(data: data) {
                    // Cache the data
                    ImageCacheManager.shared.cacheData(data, for: url, section: section)
                    
                    if !Task.isCancelled {
                        await MainActor.run {
                            self.image = downloadedImage
                            self.isLoading = false
                        }
                    }
                } else {
                    if !Task.isCancelled {
                        await MainActor.run { self.isLoading = false }
                    }
                }
            } catch {
                if !Task.isCancelled {
                    await MainActor.run {
                        self.isLoading = false
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func placeholderView(isSkeleton: Bool) -> some View {
        Group {
            if section == .books, let title = title {
                if isSkeleton {
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .fill(.quaternary)
                } else {
                    DynamicPlaceholderView(title: title, icon: "book.pages", cornerRadius: cornerRadius, useSerif: true, hideTitle: hideTitle)
                }
            } else if (itemType == "MusicArtist" || itemType == "Artist" || itemType == "AlbumArtist" || itemType == "Person" || itemType == "Actor" || itemType == "Director" || itemType == "Producer" || itemType == "Writer"), let title = title {
                if isSkeleton {
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .fill(.quaternary)
                } else {
                    DynamicPlaceholderView(title: title, icon: (itemType?.contains("Artist") == true || itemType?.contains("Music") == true) ? "music.mic" : "person.fill", cornerRadius: cornerRadius, hideTitle: hideTitle)
                }
            } else if (section == .music || itemType == "MusicGenre" || itemType == "Playlist" || itemType == "MusicAlbum" || itemType == "Audio"), let title = title {
                if isSkeleton {
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .fill(.quaternary)
                } else {
                    DynamicPlaceholderView(title: title, icon: "music.quarternote.3", cornerRadius: cornerRadius, hideTitle: hideTitle)
                }
            } else {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(.quaternary)
                    .overlay {
                        if !isSkeleton {
                            Image(systemName: "photo")
                                .font(.title2)
                                .foregroundStyle(.tertiary)
                        }
                    }
            }
        }
    }
}

struct DynamicPlaceholderView: View {
    let title: String
    let icon: String
    let cornerRadius: CGFloat
    var useSerif: Bool = false
    var hideTitle: Bool = false

    var body: some View {
        ZStack {
            gradientBackground
            
            VStack(alignment: .center, spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 28, weight: .light))
                    .foregroundStyle(.white.opacity(0.4))
                
                if !hideTitle {
                    Text(title)
                        .font(.system(size: 14, weight: .bold, design: useSerif ? .serif : .rounded))
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 12)
                        .lineLimit(useSerif ? 5 : 3)
                        .minimumScaleFactor(0.7)
                        .shadow(color: .black.opacity(0.3), radius: 2, x: 0, y: 1)
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
    }

    private var gradientBackground: some View {
        let colors = getColors(for: title)
        return LinearGradient(
            colors: colors,
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private func getColors(for title: String) -> [Color] {
        var hash: UInt64 = 5381
        for byte in title.utf8 {
            hash = ((hash << 5) &+ hash) &+ UInt64(byte)
        }
        
        let palette: [Color] = [
            Color(red: 0.10, green: 0.12, blue: 0.20),
            Color(red: 0.20, green: 0.08, blue: 0.08),
            Color(red: 0.08, green: 0.15, blue: 0.10),
            Color(red: 0.15, green: 0.10, blue: 0.20),
            Color(red: 0.12, green: 0.18, blue: 0.22),
            Color(red: 0.18, green: 0.12, blue: 0.08),
            Color(red: 0.15, green: 0.15, blue: 0.15),
            Color(red: 0.25, green: 0.10, blue: 0.15)
        ]
        
        let index1 = Int(hash % UInt64(palette.count))
        let index2 = Int((hash / UInt64(palette.count)) % UInt64(palette.count))
        let c1 = palette[index1]
        var c2 = palette[index2]
        if c1 == c2 { c2 = palette[(index1 + 1) % palette.count] }
        return [c1, c2]
    }
}

struct ItemPosterCard: View {
    let item: BaseItemDto
    let apiClient: JellyfinAPIClient
    var width: CGFloat = 150
    var imageRatio: CGFloat {
        let t = item.type ?? ""
        return (t == "MusicAlbum" || t == "Audio" || t == "MusicArtist" || t == "Playlist" || t == "MusicGenre") ? 1.0 : 1.5
    }

    @State private var imageURL: URL?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack(alignment: .bottomLeading) {
                RemoteImageView(url: imageURL, section: CacheSection.from(itemType: item.type), cornerRadius: 8, title: item.displayName, itemType: item.type)
                    .frame(width: width, height: width * imageRatio)
                    .clipped()
                    .liquidCard()

                // Progress bar
                if let progress = item.userData?.playedPercentage, progress > 0 {
                    GeometryReader { geo in
                        VStack {
                            Spacer()
                            ZStack(alignment: .leading) {
                                Rectangle()
                                    .fill(.ultraThinMaterial)
                                    .frame(height: 4)
                                Rectangle()
                                    .fill(.tint)
                                    .frame(width: geo.size.width * (progress / 100), height: 4)
                            }
                        }
                    }
                }

                // Watched badge
                if item.userData?.played == true {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.white)
                        .padding(6)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                }
            }
            .frame(width: width, height: width * imageRatio)
            .clipped()

            MarqueeText(text: item.displayName, font: .caption, fontWeight: .medium)
                .frame(width: width, height: 16, alignment: .leading)

            if let year = item.yearText {
                Text(year)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(width: width, alignment: .leading)
            }
        }
        .task {
            if let id = item.id {
                let tag = item.imageTags?["Primary"]
                imageURL = await apiClient.imageURL(itemId: id, imageType: "Primary", maxWidth: Int(width * 2), tag: tag)
            }
        }
    }
}

struct ItemBackdropCard: View {
    let item: BaseItemDto
    let apiClient: JellyfinAPIClient
    var width: CGFloat = 300

    @State private var imageURL: URL?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack(alignment: .bottomLeading) {
                RemoteImageView(url: imageURL, section: CacheSection.from(itemType: item.type), cornerRadius: 10, title: item.displayName, itemType: item.type)
                    .frame(width: width, height: width * 9 / 16)
                    .clipped()

                if let progress = item.userData?.playedPercentage, progress > 0 {
                    GeometryReader { geo in
                        VStack {
                            Spacer()
                            ZStack(alignment: .leading) {
                                Rectangle()
                                    .fill(.ultraThinMaterial)
                                    .frame(height: 4)
                                Rectangle()
                                    .fill(.tint)
                                    .frame(width: geo.size.width * (progress / 100), height: 4)
                            }
                        }
                    }
                }
            }
            .frame(width: width, height: width * 9 / 16)
            .clipped()
            .liquidCard()

            VStack(alignment: .leading, spacing: 2) {
                if let episodeLabel = item.episodeLabel, let seriesName = item.seriesName {
                    Text(seriesName)
                        .font(.caption)
                        .fontWeight(.medium)
                        .lineLimit(1)
                    Text("\(episodeLabel) - \(item.displayName)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                } else {
                    MarqueeText(text: item.displayName, font: .caption, fontWeight: .medium)
                        .frame(width: width, height: 16, alignment: .leading)
                    if let year = item.yearText {
                        Text(year)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .frame(width: width, alignment: .leading)
        }
        .task {
            if let id = item.id {
                // Try backdrop first, fall back to primary
                let backdropTags = item.backdropImageTags ?? item.parentBackdropImageTags
                if let tag = backdropTags?.first {
                    let backdropId = item.parentBackdropItemId ?? id
                    imageURL = await apiClient.imageURL(itemId: backdropId, imageType: "Backdrop", maxWidth: Int(width * 2), tag: tag)
                } else if let tag = item.imageTags?["Primary"] {
                    imageURL = await apiClient.imageURL(itemId: id, imageType: "Primary", maxWidth: Int(width * 2), tag: tag)
                } else {
                    imageURL = await apiClient.imageURL(itemId: id, imageType: "Primary", maxWidth: Int(width * 2))
                }
            }
        }
    }
}
