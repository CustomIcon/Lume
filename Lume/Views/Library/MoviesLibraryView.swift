import SwiftUI

struct MoviesLibraryView: View {
    @Environment(SessionManager.self) private var session
    let library: BaseItemDto

    @State private var movies: [BaseItemDto] = []
    @State private var isLoading = true
    @State private var totalCount = 0
    @State private var isGridView = true
    @State private var sortBy = "SortName"
    @State private var sortOrder = "Ascending"
    @State private var searchText = ""

    private let pageSize = 100
    private let columns = [GridItem(.adaptive(minimum: 150, maximum: 200), spacing: 16)]

    var body: some View {
        Group {
            if isLoading && movies.isEmpty {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 20) {
                        ForEach(0..<12, id: \.self) { _ in
                            VStack(alignment: .leading, spacing: 6) {
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(.quaternary)
                                    .frame(height: 225)
                                    .shimmer()
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(.quaternary)
                                    .frame(width: 100, height: 12)
                                    .shimmer()
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(.quaternary)
                                    .frame(width: 60, height: 10)
                                    .shimmer()
                            }
                        }
                    }
                    .padding()
                }
            } else if movies.isEmpty {
                ContentUnavailableView(
                    "No Movies",
                    systemImage: "film",
                    description: Text("This library has no movies.")
                )
            } else {
                ScrollView {
                    if isGridView {
                        LazyVGrid(columns: columns, spacing: 20) {
                            ForEach(filteredMovies, id: \.id) { movie in
                                NavigationLink(value: movie) {
                                    ItemPosterCard(item: movie, apiClient: session.apiClient, width: 150)
                                }
                                .buttonStyle(.plain)
                                .itemContextMenu(item: movie, session: session, onPlay: {
                                    session.activeVideoItem = movie
                                })
                                .onAppear {
                                    if movie.id == movies.last?.id { loadMore() }
                                }
                            }
                        }
                        .padding()
                    } else {
                        LazyVStack(spacing: 2) {
                            ForEach(filteredMovies, id: \.id) { movie in
                                NavigationLink(value: movie) {
                                    MovieListRow(item: movie, apiClient: session.apiClient)
                                }
                                .buttonStyle(.plain)
                                .itemContextMenu(item: movie, session: session, onPlay: {
                                    session.activeVideoItem = movie
                                })
                                .onAppear {
                                    if movie.id == movies.last?.id { loadMore() }
                                }
                            }
                        }
                        .padding()
                    }
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
                    Text("Runtime").tag("Runtime")
                }
                .onChange(of: sortBy) { _, _ in reload() }

                Button {
                    sortOrder = sortOrder == "Ascending" ? "Descending" : "Ascending"
                    reload()
                } label: {
                    Image(systemName: sortOrder == "Ascending" ? "arrow.up" : "arrow.down")
                }

                Divider()

                Button { isGridView.toggle() } label: {
                    Image(systemName: isGridView ? "list.bullet" : "square.grid.2x2")
                }
            }
        }
        .searchable(text: $searchText, prompt: "Filter movies")
        .toolbarBackground(.hidden)
        .task { await loadMovies() }
    }

    private var filteredMovies: [BaseItemDto] {
        guard !searchText.isEmpty else { return movies }
        return movies.filter { ($0.name ?? "").localizedCaseInsensitiveContains(searchText) }
    }

    private func loadMovies() async {
        isLoading = true
        do {
            let result = try await session.apiClient.getItems(
                parentId: library.id,
                includeItemTypes: ["Movie"],
                sortBy: [sortBy],
                sortOrder: sortOrder,
                fields: ["PrimaryImageAspectRatio", "Overview", "UserData", "MediaSources"],
                limit: pageSize,
                recursive: true
            )
            movies = result.items ?? []
            totalCount = result.totalRecordCount ?? 0
        } catch {}
        isLoading = false
    }

    private func loadMore() {
        guard movies.count < totalCount, !isLoading else { return }
        isLoading = true
        Task {
            do {
                let result = try await session.apiClient.getItems(
                    parentId: library.id,
                    includeItemTypes: ["Movie"],
                    sortBy: [sortBy],
                    sortOrder: sortOrder,
                    fields: ["PrimaryImageAspectRatio", "Overview", "UserData", "MediaSources"],
                    limit: pageSize,
                    startIndex: movies.count,
                    recursive: true
                )
                movies.append(contentsOf: result.items ?? [])
            } catch {}
            isLoading = false
        }
    }

    private func reload() {
        movies = []
        Task { await loadMovies() }
    }
}

struct MovieListRow: View {
    let item: BaseItemDto
    let apiClient: JellyfinAPIClient
    @State private var imageURL: URL?

    var body: some View {
        HStack(spacing: 12) {
            RemoteImageView(url: imageURL, section: .movies, cornerRadius: 4, title: item.displayName, itemType: item.type)
                .frame(width: 40, height: 60)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.displayName)
                    .fontWeight(.medium).lineLimit(1)
                HStack(spacing: 8) {
                    if let year = item.yearText { Text(year) }
                    if let runtime = item.runtimeText { Text(runtime) }
                    if let rating = item.communityRating {
                        HStack(spacing: 2) {
                            Image(systemName: "star.fill").foregroundStyle(.yellow)
                            Text(String(format: "%.1f", rating))
                        }
                    }
                }
                .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if item.userData?.played == true { Image(systemName: "checkmark.circle.fill").foregroundStyle(.green).font(.caption) }
            if item.userData?.isFavorite == true { Image(systemName: "heart.fill").foregroundStyle(.red).font(.caption) }
        }
        .padding(.vertical, 4).padding(.horizontal, 8).contentShape(Rectangle())
        .task {
            if let id = item.id {
                imageURL = await apiClient.imageURL(itemId: id, imageType: "Primary", maxWidth: 80, tag: item.imageTags?["Primary"])
            }
        }
    }
}
