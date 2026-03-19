import SwiftUI

struct RemoteImageView: View {
    let url: URL?
    var section: CacheSection = .others
    var cornerRadius: CGFloat = 8
    var aspectRatio: CGFloat? = nil

    @State private var image: NSImage? = nil
    @State private var isLoading = false

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else if isLoading {
                placeholderView
                    .overlay {
                        ProgressView()
                            .controlSize(.small)
                            .tint(.secondary)
                    }
            } else {
                placeholderView
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        .onAppear { loadImage() }
        .onChange(of: url) { _, _ in loadImage() }
    }

    private func loadImage() {
        guard let url else { 
            self.image = nil
            return 
        }
        
        // 1. Check memory/disk cache via manager
        if let cached = ImageCacheManager.shared.getCachedImage(for: url, section: section) {
            self.image = cached
            return
        }
        
        // 2. Fetch from network
        isLoading = true
        Task {
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                if let downloadedImage = NSImage(data: data) {
                    ImageCacheManager.shared.cacheData(data, for: url, section: section)
                    await MainActor.run {
                        self.image = downloadedImage
                        self.isLoading = false
                    }
                } else {
                    await MainActor.run { self.isLoading = false }
                }
            } catch {
                await MainActor.run {
                    self.isLoading = false
                }
            }
        }
    }

    private var placeholderView: some View {
        RoundedRectangle(cornerRadius: cornerRadius)
            .fill(.quaternary)
            .overlay {
                Image(systemName: "photo")
                    .font(.title2)
                    .foregroundStyle(.tertiary)
            }
    }
}

// MARK: - Item Poster Card

struct ItemPosterCard: View {
    let item: BaseItemDto
    let apiClient: JellyfinAPIClient
    var width: CGFloat = 150
    // If the item is music-related, album art is perfectly square. Otherwise use standard movie poster ratio.
    var imageRatio: CGFloat {
        let t = item.type ?? ""
        return (t == "MusicAlbum" || t == "Audio" || t == "MusicArtist") ? 1.0 : 1.5
    }

    @State private var imageURL: URL?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack(alignment: .bottomLeading) {
                RemoteImageView(url: imageURL, section: CacheSection.from(itemType: item.type), cornerRadius: 8)
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

            Text(item.displayName)
                .font(.caption)
                .fontWeight(.medium)
                .lineLimit(2)
                .frame(width: width, alignment: .leading)

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

// MARK: - Item Backdrop Card

struct ItemBackdropCard: View {
    let item: BaseItemDto
    let apiClient: JellyfinAPIClient
    var width: CGFloat = 300

    @State private var imageURL: URL?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack(alignment: .bottomLeading) {
                RemoteImageView(url: imageURL, section: CacheSection.from(itemType: item.type), cornerRadius: 10)
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
                    Text(item.displayName)
                        .font(.caption)
                        .fontWeight(.medium)
                        .lineLimit(1)
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
