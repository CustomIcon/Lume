import SwiftUI
import Combine

struct HomeView: View {
    @Environment(SessionManager.self) private var session
    @State private var continueWatching: [BaseItemDto] = []
    @State private var nextUp: [BaseItemDto] = []

    @State private var latestByLibrary: [(library: BaseItemDto, items: [BaseItemDto])] = []
    @State private var isLoading = true
    @State private var slideIndex = 0

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 24) {
                if isLoading {
                    ProgressView("Loading...")
                        .frame(maxWidth: .infinity, minHeight: 200)
                } else {
                    // Next Up (Featured Slideshow)
                    if !nextUp.isEmpty {
                        ZStack(alignment: .bottom) {
                            ForEach(Array(nextUp.prefix(6).enumerated()), id: \.offset) { index, item in
                                if slideIndex == index {
                                    FeaturedSlideView(item: item)
                                        .transition(.opacity.combined(with: .scale(scale: 1.05)))
                                }
                            }
                            
                            // Navigation Arrows
                            HStack {
                                Button {
                                    withAnimation(.spring()) {
                                        let count = min(nextUp.count, 6)
                                        slideIndex = (slideIndex - 1 + count) % count
                                    }
                                } label: {
                                    Image(systemName: "chevron.left")
                                        .font(.system(size: 16, weight: .bold))
                                        .scaleEffect(x: 0.8, y: 1.8) // Stretched vertically
                                        .frame(width: 32, height: 80)
                                        .background(.ultraThinMaterial, in: Capsule())
                                        .contentShape(Capsule())
                                }
                                .buttonStyle(.plain)
                                .opacity(0.8)
                                .padding(.leading, 12)
                                
                                Spacer()
                                
                                Button {
                                    withAnimation(.spring()) {
                                        let count = min(nextUp.count, 6)
                                        slideIndex = (slideIndex + 1) % count
                                    }
                                } label: {
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 16, weight: .bold))
                                        .scaleEffect(x: 0.8, y: 1.8) // Stretched vertically
                                        .frame(width: 32, height: 80)
                                        .background(.ultraThinMaterial, in: Capsule())
                                        .contentShape(Capsule())
                                }
                                .buttonStyle(.plain)
                                .opacity(0.8)
                                .padding(.trailing, 12)
                             }
                            .frame(maxHeight: .infinity)
                            
                            HStack(spacing: 8) {
                                ForEach(0..<min(nextUp.count, 6), id: \.self) { i in
                                    Circle()
                                        .fill(slideIndex == i ? Color.white : Color.white.opacity(0.3))
                                        .frame(width: 8, height: 8)
                                        .contentShape(Circle())
                                        .onTapGesture {
                                            withAnimation(.spring()) {
                                                slideIndex = i
                                            }
                                        }
                                }
                            }
                            .padding(.bottom, 28)
                        }
                        .frame(height: 480)
                        .clipped()
                        .padding(.bottom, 50)
                        .onReceive(Timer.publish(every: 8, on: .main, in: .common).autoconnect()) { _ in
                            withAnimation(.easeInOut(duration: 1.0)) {
                                let count = min(nextUp.count, 6)
                                slideIndex = (slideIndex + 1) % count
                            }
                        }
                        .background {
                            Button("") {
                                withAnimation(.spring()) {
                                    let count = min(nextUp.count, 6)
                                    slideIndex = (slideIndex - 1 + count) % count
                                }
                            }
                            .keyboardShortcut(.leftArrow, modifiers: [])
                            .opacity(0)
                            
                            Button("") {
                                withAnimation(.spring()) {
                                    let count = min(nextUp.count, 6)
                                    slideIndex = (slideIndex + 1) % count
                                }
                            }
                            .keyboardShortcut(.rightArrow, modifiers: [])
                            .opacity(0)
                        }
                    }

                    // Continue Watching
                    if !continueWatching.isEmpty {
                        sectionHeader("Continue Watching", systemImage: "play.circle")
                        ScrollView(.horizontal, showsIndicators: false) {
                            LazyHStack(spacing: 16) {
                                ForEach(continueWatching, id: \.id) { item in
                                    NavigationLink(value: item) {
                                        ItemBackdropCard(item: item, apiClient: session.apiClient, width: 280)
                                    }
                                    .buttonStyle(.plain)
                                    .itemContextMenu(item: item, session: session, onPlay: {
                                        session.activeVideoItem = item
                                    })
                                }
                            }
                            .padding(.horizontal)
                        }
                    }

                    // Recently Added per library
                    ForEach(latestByLibrary, id: \.library.id) { entry in
                        sectionHeader("Latest in \(entry.library.displayName)", systemImage: "sparkles")
                        ScrollView(.horizontal, showsIndicators: false) {
                            LazyHStack(spacing: 12) {
                                ForEach(entry.items, id: \.id) { item in
                                    NavigationLink(value: item) {
                                        ItemPosterCard(item: item, apiClient: session.apiClient, width: 140)
                                    }
                                    .buttonStyle(.plain)
                                    .itemContextMenu(item: item, session: session, onPlay: {
                                        session.activeVideoItem = item
                                    })
                                }
                            }
                            .padding(.horizontal)
                        }
                    }

                    if continueWatching.isEmpty && nextUp.isEmpty && latestByLibrary.isEmpty {
                        ContentUnavailableView(
                            "No Content",
                            systemImage: "film.stack",
                            description: Text("Your libraries are empty or the server returned no items.")
                        )
                        .frame(maxWidth: .infinity, minHeight: 300)
                    }
                }
            }
            .padding(.bottom, 40)
        }
        .ignoresSafeArea(edges: .top)
        .navigationTitle("Home")
        .toolbarBackground(.hidden)
        .task { await loadHomeData() }
        .refreshable { await loadHomeData() }
    }


    private func sectionHeader(_ title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .font(.title2)
            .fontWeight(.bold)
            .padding(.horizontal)
    }

    private func loadHomeData() async {
        isLoading = true
        let apiClient = session.apiClient

        async let resumeTask = apiClient.getResumeItems(mediaTypes: ["Video"])
        async let nextUpTask = apiClient.getNextUp()

        do {
            let resumeResult = try await resumeTask
            continueWatching = resumeResult.items ?? []
        } catch {
            continueWatching = []
        }

        do {
            let nextUpResult = try await nextUpTask
            nextUp = nextUpResult.items ?? []
        } catch {
            nextUp = []
        }



        var latestResults: [(library: BaseItemDto, items: [BaseItemDto])] = []
        for library in session.libraries {
            guard let libId = library.id else { continue }
            let collectionType = library.collectionType ?? ""
            guard collectionType != "livetv" else { continue }
            do {
                let items = try await apiClient.getLatestItems(parentId: libId, limit: 16)
                if !items.isEmpty {
                    latestResults.append((library: library, items: items))
                }
            } catch {}
        }
        latestByLibrary = latestResults
        isLoading = false
    }
}

private struct FeaturedSlideView: View {
    @Environment(SessionManager.self) private var session
    let item: BaseItemDto
    @State private var backdropURL: URL?
    @State private var logoURL: URL?
    @AppStorage("playTrailerInHome") private var playTrailerInHome = false
    @State private var youtubeVideoId: String?
    @State private var isPlayingTrailer = false

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            // Backdrop Layer + Auto-Playing Trailer
            ZStack {
                RemoteImageView(url: backdropURL, section: .others, cornerRadius: 0)
                    .frame(maxWidth: .infinity)
                    .frame(height: 480)
                    .clipped()
                
                if playTrailerInHome, isPlayingTrailer, let videoId = youtubeVideoId {
                    YouTubeTrailerWebView(videoId: videoId)
                        .frame(maxWidth: .infinity)
                        .frame(height: 480)
                        .clipped()
                        .transition(.opacity.animation(.easeInOut(duration: 1.5)))
                        .allowsHitTesting(false)
                }
            }
            .overlay {
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0.0),
                        .init(color: .black.opacity(0.4), location: 0.7),
                        .init(color: .black.opacity(0.8), location: 1.0)
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

            // Clickable Area for the Slide
            NavigationLink(value: item) {
                Color.clear
            }
            .buttonStyle(.plain)

            // Content Layer
            HStack {
                VStack(alignment: .leading, spacing: 12) {
                    Spacer()
                    
                    let title = (item.type == "Episode" ? item.seriesName : item.displayName) ?? item.displayName
                    
                    if let logoURL {
                        RemoteImageView(url: logoURL, section: .others, cornerRadius: 0, contentMode: .fit)
                            .frame(maxWidth: 400, maxHeight: 120, alignment: .bottomLeading)
                    } else {
                        Text(title)
                            .font(.system(size: 40, weight: .black, design: .rounded))
                            .foregroundStyle(.white)
                            .shadow(color: .black.opacity(0.5), radius: 10, x: 0, y: 5)
                            .lineLimit(2)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        if item.type == "Episode" {
                            let epLabel = (item.episodeLabel ?? "") + " • " + (item.displayName)
                            Text(epLabel)
                                .font(.title3)
                                .fontWeight(.semibold)
                                .foregroundStyle(.secondary)
                        } else if let label = item.episodeLabel {
                            Text(label)
                                .font(.headline)
                                .foregroundStyle(.secondary)
                        }

                        Text(item.overview ?? "")
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .frame(maxWidth: 600, alignment: .leading)
                    }

                    HStack(spacing: 20) {
                        Button {
                            session.activeVideoItem = item
                        } label: {
                            Label("Play Now", systemImage: "play.fill")
                                 .font(.headline)
                                 .padding(.horizontal, 28)
                                 .padding(.vertical, 14)
                                 .background(.white, in: RoundedRectangle(cornerRadius: 14)) // Always white
                                 .foregroundStyle(.black) // Always black
                        }
                        .buttonStyle(.plain)

                        Label(item.runtimeText ?? "", systemImage: "clock")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 10)
                }
                
                Spacer()
            }
            .padding(.horizontal, 40)
            .padding(.bottom, 60)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(height: 480)
        .clipped()
        .task {
            if let id = item.id {
                let backdropId = item.parentBackdropItemId ?? id
                let backdropTag = item.backdropImageTags?.first ?? item.parentBackdropImageTags?.first
                backdropURL = await session.apiClient.imageURL(itemId: backdropId, imageType: "Backdrop", maxWidth: 1920, tag: backdropTag)
                
                let logoId = item.parentLogoItemId ?? (item.type == "Episode" ? item.seriesId : id) ?? id
                let logoTag = item.parentLogoImageTag ?? item.imageTags?["Logo"]
                if let logoTag {
                    logoURL = await session.apiClient.imageURL(itemId: logoId, imageType: "Logo", maxWidth: 600, tag: logoTag)
                }
                
                if playTrailerInHome {
                    if let videoId = await YouTubeTrailerService.shared.getYouTubeVideoId(for: item, apiClient: session.apiClient) {
                        youtubeVideoId = videoId
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                            withAnimation {
                                isPlayingTrailer = true
                            }
                        }
                    }
                }
            }
        }
        .onDisappear {
            youtubeVideoId = nil
            isPlayingTrailer = false
        }
    }
    
}
