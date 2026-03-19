import SwiftUI

struct GenericLibraryView: View {
    @Environment(SessionManager.self) private var session
    let library: BaseItemDto

    @State private var items: [BaseItemDto] = []
    @State private var isLoading = true
    @State private var totalCount = 0
    @State private var searchText = ""

    private let pageSize = 100
    private let columns = [GridItem(.adaptive(minimum: 150, maximum: 200), spacing: 16)]

    var body: some View {
        Group {
            if isLoading && items.isEmpty {
                ProgressView("Loading...").frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if items.isEmpty {
                ContentUnavailableView(
                    "No Items",
                    systemImage: "folder",
                    description: Text("This library appears to be empty.")
                )
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 20) {
                        ForEach(filteredItems, id: \.id) { item in
                            NavigationLink(value: item) {
                                ItemPosterCard(item: item, apiClient: session.apiClient, width: 150)
                            }
                            .buttonStyle(.plain)
                            .itemContextMenu(item: item, session: session, onDetail: {})
                            .onAppear {
                                if item.id == items.last?.id { loadMore() }
                            }
                        }
                    }
                    .padding()
                }
            }
        }
        .navigationTitle(library.displayName)
        .searchable(text: $searchText, prompt: "Filter items")
        .task { await loadItems() }
    }

    private var filteredItems: [BaseItemDto] {
        guard !searchText.isEmpty else { return items }
        return items.filter { ($0.name ?? "").localizedCaseInsensitiveContains(searchText) }
    }

    private func loadItems() async {
        isLoading = true
        do {
            let result = try await session.apiClient.getItems(
                parentId: library.id, sortBy: ["SortName"], sortOrder: "Ascending",
                fields: ["PrimaryImageAspectRatio", "Overview", "UserData"],
                limit: pageSize, recursive: true
            )
            items = result.items ?? []
            totalCount = result.totalRecordCount ?? 0
        } catch {}
        isLoading = false
    }

    private func loadMore() {
        guard items.count < totalCount, !isLoading else { return }
        isLoading = true
        Task {
            do {
                let result = try await session.apiClient.getItems(
                    parentId: library.id, sortBy: ["SortName"], sortOrder: "Ascending",
                    fields: ["PrimaryImageAspectRatio", "Overview", "UserData"],
                    limit: pageSize, startIndex: items.count, recursive: true
                )
                items.append(contentsOf: result.items ?? [])
            } catch {}
            isLoading = false
        }
    }
}
