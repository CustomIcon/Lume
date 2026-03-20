import SwiftUI

struct HomeView: View {
    @Environment(SessionManager.self) private var session
    @State private var continueWatching: [BaseItemDto] = []
    @State private var nextUp: [BaseItemDto] = []

    @State private var latestByLibrary: [(library: BaseItemDto, items: [BaseItemDto])] = []
    @State private var isLoading = true

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if isLoading {
                    ProgressView("Loading...")
                        .frame(maxWidth: .infinity, minHeight: 200)
                } else {
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

                    // Next Up
                    if !nextUp.isEmpty {
                        sectionHeader("Next Up", systemImage: "arrow.right.circle")
                        ScrollView(.horizontal, showsIndicators: false) {
                            LazyHStack(spacing: 16) {
                                ForEach(nextUp, id: \.id) { item in
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
            .padding(.vertical)
        }
        .navigationTitle("Home")
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
