import SwiftUI

struct SearchView: View {
    @Environment(SessionManager.self) private var session
    @State private var searchText = ""
    @State private var results: [BaseItemDto] = []
    @State private var suggestions: [BaseItemDto] = []
    @State private var isSearching = false
    @State private var isLoadingSuggestions = false
    @State private var selectedItem: BaseItemDto?
    @State private var searchTask: Task<Void, Never>?

    private let columns = [
        GridItem(.adaptive(minimum: 150, maximum: 200), spacing: 16)
    ]

    var body: some View {
        VStack(spacing: 0) {
            if searchText.isEmpty {
                if isLoadingSuggestions {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if suggestions.isEmpty {
                    ContentUnavailableView(
                        "Search Your Library",
                        systemImage: "magnifyingglass",
                        description: Text("Search across all your libraries for movies, shows, music, and more.")
                    )
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            Text("Discover")
                                .font(.title2)
                                .fontWeight(.bold)
                                .padding(.horizontal)
                            
                            LazyVGrid(columns: columns, spacing: 16) {
                                ForEach(suggestions) { item in
                                    ItemPosterCard(item: item, apiClient: session.apiClient, width: 150)
                                        .onTapGesture { selectedItem = item }
                                        .itemContextMenu(item: item, session: session, onDetail: {
                                            selectedItem = item
                                        })
                                }
                            }
                            .padding(.horizontal)
                        }
                        .padding(.vertical)
                    }
                }
            } else if isSearching {
                ProgressView("Searching...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if results.isEmpty {
                ContentUnavailableView.search(text: searchText)
            } else {
                ScrollView {
                    // Group results by type
                    let grouped = Dictionary(grouping: results, by: { $0.type ?? "Unknown" })
                    let sortedKeys = grouped.keys.sorted()

                    ForEach(sortedKeys, id: \.self) { type in
                        if let items = grouped[type] {
                            VStack(alignment: .leading, spacing: 8) {
                                Text(displayNameForType(type))
                                    .font(.title3)
                                    .fontWeight(.bold)
                                    .padding(.horizontal)

                                LazyVGrid(columns: columns, spacing: 16) {
                                    ForEach(items) { item in
                                        ItemPosterCard(item: item, apiClient: session.apiClient, width: 150)
                                            .onTapGesture { selectedItem = item }
                                            .itemContextMenu(item: item, session: session, onDetail: {
                                                selectedItem = item
                                            })
                                    }
                                }
                                .padding(.horizontal)
                            }
                            .padding(.bottom)
                        }
                    }
                }
                .padding(.top)
            }
        }
        .navigationTitle("Search")
        .navigationDestination(item: $selectedItem) { item in
            if item.type == "Series" {
                SeriesDetailView(series: item)
            } else if item.type == "MusicAlbum" {
                AlbumDetailView(album: item)
            } else {
                ItemDetailView(item: item)
            }
        }
        .searchable(text: $searchText, prompt: "Search all libraries...")
        .task {
            await loadSuggestions()
        }
        .onChange(of: searchText) { _, newValue in
            searchTask?.cancel()
            guard !newValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                results = []
                return
            }
            searchTask = Task {
                try? await Task.sleep(for: .milliseconds(400))
                guard !Task.isCancelled else { return }
                await performSearch(query: newValue)
            }
        }
    }

    private func loadSuggestions() async {
        guard suggestions.isEmpty else { return }
        isLoadingSuggestions = true
        do {
            let result = try await session.apiClient.getItems(
                includeItemTypes: ["Movie", "Series", "MusicArtist"],
                sortBy: ["IsFavoriteOrLiked", "Random"],
                limit: 24,
                recursive: true
            )
            suggestions = result.items ?? []
        } catch {}
        isLoadingSuggestions = false
    }

    private func performSearch(query: String) async {
        isSearching = true
        do {
            let result = try await session.apiClient.searchItems(query: query, limit: 48)
            if !Task.isCancelled {
                results = result.items ?? []
            }
        } catch {
            if !Task.isCancelled {
                results = []
            }
        }
        isSearching = false
    }

    private func displayNameForType(_ type: String) -> String {
        switch type {
        case "Movie": return "Movies"
        case "Series": return "TV Shows"
        case "Episode": return "Episodes"
        case "Audio": return "Songs"
        case "MusicAlbum": return "Albums"
        case "MusicArtist": return "Artists"
        case "Person": return "People"
        case "BoxSet": return "Collections"
        default: return type
        }
    }
}
