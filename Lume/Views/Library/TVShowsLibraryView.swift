import SwiftUI

struct TVShowsLibraryView: View {
    @Environment(SessionManager.self) private var session
    let library: BaseItemDto

    @State private var shows: [BaseItemDto] = []
    @State private var isLoading = true
    @State private var totalCount = 0
    @State private var sortBy = "SortName"
    @State private var sortOrder = "Ascending"
    @State private var searchText = ""

    private let pageSize = 100
    private let columns = [GridItem(.adaptive(minimum: 150, maximum: 200), spacing: 16)]

    var body: some View {
        Group {
            if isLoading && shows.isEmpty {
                ProgressView("Loading shows...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if shows.isEmpty {
                ContentUnavailableView(
                    "No TV Shows",
                    systemImage: "tv",
                    description: Text("This library has no TV shows.")
                )
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 20) {
                        ForEach(filteredShows, id: \.id) { show in
                            NavigationLink(value: show) {
                                ItemPosterCard(item: show, apiClient: session.apiClient, width: 150)
                            }
                            .buttonStyle(.plain)
                            .itemContextMenu(item: show, session: session, onDetail: {
                                // Handled by NavigationLink value
                            })
                            .onAppear {
                                if show.id == shows.last?.id { loadMore() }
                            }
                        }
                    }
                    .padding()
                }
            }
        }
        .navigationTitle(library.displayName)
        .toolbar {
            ToolbarItemGroup {
                Picker("Sort", selection: $sortBy) {
                    Text("Name").tag("SortName")
                    Text("Date Added").tag("DateCreated")
                    Text("Year").tag("ProductionYear")
                    Text("Rating").tag("CommunityRating")
                }
                .onChange(of: sortBy) { _, _ in reload() }

                Button {
                    sortOrder = sortOrder == "Ascending" ? "Descending" : "Ascending"
                    reload()
                } label: {
                    Image(systemName: sortOrder == "Ascending" ? "arrow.up" : "arrow.down")
                }
            }
        }
        .searchable(text: $searchText, prompt: "Filter shows")
        .task { await loadShows() }
    }

    private var filteredShows: [BaseItemDto] {
        guard !searchText.isEmpty else { return shows }
        return shows.filter { ($0.name ?? "").localizedCaseInsensitiveContains(searchText) }
    }

    private func loadShows() async {
        isLoading = true
        do {
            let result = try await session.apiClient.getItems(
                parentId: library.id,
                includeItemTypes: ["Series"],
                sortBy: [sortBy],
                sortOrder: sortOrder,
                fields: ["PrimaryImageAspectRatio", "Overview", "UserData"],
                limit: pageSize,
                recursive: true
            )
            shows = result.items ?? []
            totalCount = result.totalRecordCount ?? 0
        } catch {}
        isLoading = false
    }

    private func loadMore() {
        guard shows.count < totalCount, !isLoading else { return }
        isLoading = true
        Task {
            do {
                let result = try await session.apiClient.getItems(
                    parentId: library.id,
                    includeItemTypes: ["Series"],
                    sortBy: [sortBy],
                    sortOrder: sortOrder,
                    fields: ["PrimaryImageAspectRatio", "Overview", "UserData"],
                    limit: pageSize,
                    startIndex: shows.count,
                    recursive: true
                )
                shows.append(contentsOf: result.items ?? [])
            } catch {}
            isLoading = false
        }
    }

    private func reload() {
        shows = []
        Task { await loadShows() }
    }
}

struct SeriesDetailView: View {
    @Environment(SessionManager.self) private var session
    let series: BaseItemDto

    @State private var fullSeries: BaseItemDto?
    @State private var seasons: [BaseItemDto] = []
    @State private var selectedSeason: BaseItemDto?
    @State private var episodes: [BaseItemDto] = []
    @State private var isLoadingSeasons = true
    @State private var isLoadingEpisodes = false
    @State private var backdropURL: URL?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // Backdrop header
                ZStack(alignment: .bottomLeading) {
                    RemoteImageView(url: backdropURL, section: .tvShows, cornerRadius: 0)
                        .frame(height: 300)
                        .frame(maxWidth: .infinity)
                        .clipped()
                        .overlay {
                            LinearGradient(
                                colors: [.clear, .clear, Color(nsColor: .windowBackgroundColor)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        }

                    VStack(alignment: .leading, spacing: 8) {
                        Text(series.displayName)
                            .font(.largeTitle)
                            .fontWeight(.bold)

                        HStack(spacing: 12) {
                            if let year = series.yearText { Text(year) }
                            if let rating = series.communityRating {
                                HStack(spacing: 2) {
                                    Image(systemName: "star.fill").foregroundStyle(.yellow)
                                    Text(String(format: "%.1f", rating))
                                }
                            }
                        }
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    }
                    .padding()
                }

                if let overview = (fullSeries ?? series).overview {
                    Text(overview).font(.body).foregroundStyle(.secondary).padding().lineLimit(4)
                }

                Divider().padding(.horizontal)

                if !seasons.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(seasons, id: \.id) { season in
                                Button {
                                    selectedSeason = season
                                    loadEpisodes(for: season)
                                } label: {
                                    Text(season.displayName)
                                        .padding(.horizontal, 12).padding(.vertical, 6)
                                        .background(RoundedRectangle(cornerRadius: 8).fill(selectedSeason?.id == season.id ? Color.accentColor : Color.clear))
                                        .foregroundStyle(selectedSeason?.id == season.id ? .white : .primary)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding()
                    }
                }

                if isLoadingEpisodes {
                    ProgressView().padding()
                } else {
                    LazyVStack(spacing: 8) {
                        ForEach(episodes, id: \.id) { episode in
                            NavigationLink(value: episode) {
                                EpisodeRow(episode: episode, apiClient: session.apiClient)
                            }
                            .buttonStyle(.plain)
                            .itemContextMenu(item: episode, session: session, onPlay: {
                                session.activeVideoItem = episode
                            })
                        }
                    }
                    .padding(.horizontal)
                }
            }
        }
        .navigationTitle(series.displayName)
        .task { await loadSeriesData() }
    }

    private func loadSeriesData() async {
        if let seriesId = series.id {
            do {
                fullSeries = try await session.apiClient.getItem(itemId: seriesId)
            } catch {}
            if let tag = series.backdropImageTags?.first {
                backdropURL = await session.apiClient.imageURL(itemId: seriesId, imageType: "Backdrop", maxWidth: 1280, tag: tag)
            }
            do {
                let result = try await session.apiClient.getSeasons(seriesId: seriesId)
                seasons = result.items ?? []
                if let first = seasons.first {
                    selectedSeason = first
                    loadEpisodes(for: first)
                }
            } catch {}
        }
        isLoadingSeasons = false
    }

    private func loadEpisodes(for season: BaseItemDto) {
        guard let seriesId = series.id, let seasonId = season.id else { return }
        isLoadingEpisodes = true
        Task {
            do {
                let result = try await session.apiClient.getEpisodes(seriesId: seriesId, seasonId: seasonId)
                episodes = result.items ?? []
            } catch {}
            isLoadingEpisodes = false
        }
    }
}

struct EpisodeRow: View {
    let episode: BaseItemDto
    let apiClient: JellyfinAPIClient
    @State private var thumbURL: URL?

    var body: some View {
        HStack(spacing: 12) {
            ZStack(alignment: .bottomLeading) {
                RemoteImageView(url: thumbURL, section: .tvShows, cornerRadius: 6)
                    .frame(width: 180, height: 100)

                if let progress = episode.userData?.playedPercentage, progress > 0 {
                    GeometryReader { geo in
                        VStack {
                            Spacer()
                            ZStack(alignment: .leading) {
                                Rectangle().fill(.ultraThinMaterial).frame(height: 3)
                                Rectangle().fill(.tint).frame(width: geo.size.width * (progress / 100), height: 3)
                            }
                        }
                    }
                    .frame(width: 180, height: 100)
                }
            }
            .frame(width: 180, height: 100)

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    if let num = episode.indexNumber { Text("Episode \(num)").font(.caption).foregroundStyle(.secondary) }
                    if let runtime = episode.runtimeText { Text("  \(runtime)").font(.caption).foregroundStyle(.tertiary) }
                }

                Text(episode.displayName).font(.headline).lineLimit(1)
                if let overview = episode.overview { Text(overview).font(.caption).foregroundStyle(.secondary).lineLimit(2) }
            }
            Spacer()
            if episode.userData?.played == true { Image(systemName: "checkmark.circle.fill").foregroundStyle(.green) }
        }
        .padding(8).background(RoundedRectangle(cornerRadius: 8).fill(.quaternary.opacity(0.5))).contentShape(Rectangle())
        .task {
            if let id = episode.id {
                let tag = episode.imageTags?["Primary"]
                thumbURL = await apiClient.imageURL(itemId: id, imageType: "Primary", maxWidth: 360, tag: tag)
            }
        }
    }
}
