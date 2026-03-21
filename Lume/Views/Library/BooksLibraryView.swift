import SwiftUI

struct BooksLibraryView: View {
    @Environment(SessionManager.self) private var session
    let library: BaseItemDto

    @State private var books: [BaseItemDto] = []
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
            if isLoading && books.isEmpty {
                ProgressView("Loading books...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if books.isEmpty {
                ContentUnavailableView(
                    "No Books",
                    systemImage: "book",
                    description: Text("This library has no books.")
                )
            } else {
                ScrollView {
                    if isGridView {
                        LazyVGrid(columns: columns, spacing: 20) {
                            ForEach(filteredBooks, id: \.id) { book in
                                NavigationLink(value: book) {
                                    ItemPosterCard(item: book, apiClient: session.apiClient, width: 150)
                                }
                                .buttonStyle(.plain)
                                .itemContextMenu(item: book, session: session, onPlay: {
                                    session.activeBookItem = book
                                })
                                .onAppear {
                                    if book.id == books.last?.id { loadMore() }
                                }
                            }
                        }
                        .padding()
                    } else {
                        LazyVStack(spacing: 2) {
                            ForEach(filteredBooks, id: \.id) { book in
                                NavigationLink(value: book) {
                                    BookListRow(item: book, apiClient: session.apiClient)
                                }
                                .buttonStyle(.plain)
                                .itemContextMenu(item: book, session: session, onPlay: {
                                    session.activeBookItem = book
                                })
                                .onAppear {
                                    if book.id == books.last?.id { loadMore() }
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
        .searchable(text: $searchText, prompt: "Filter books")
        .toolbarBackground(.hidden)
        .task { await loadBooks() }
    }

    private var filteredBooks: [BaseItemDto] {
        guard !searchText.isEmpty else { return books }
        return books.filter { ($0.name ?? "").localizedCaseInsensitiveContains(searchText) }
    }

    private func loadBooks() async {
        isLoading = true
        do {
            let result = try await session.apiClient.getItems(
                parentId: library.id,
                includeItemTypes: ["Book"],
                sortBy: [sortBy],
                sortOrder: sortOrder,
                fields: ["PrimaryImageAspectRatio", "Overview", "UserData", "MediaSources"],
                limit: pageSize,
                recursive: true
            )
            books = result.items ?? []
            totalCount = result.totalRecordCount ?? 0
        } catch {}
        isLoading = false
    }

    private func loadMore() {
        guard books.count < totalCount, !isLoading else { return }
        isLoading = true
        Task {
            do {
                let result = try await session.apiClient.getItems(
                    parentId: library.id,
                    includeItemTypes: ["Book"],
                    sortBy: [sortBy],
                    sortOrder: sortOrder,
                    fields: ["PrimaryImageAspectRatio", "Overview", "UserData", "MediaSources"],
                    limit: pageSize,
                    startIndex: books.count,
                    recursive: true
                )
                books.append(contentsOf: result.items ?? [])
            } catch {}
            isLoading = false
        }
    }

    private func reload() {
        books = []
        Task { await loadBooks() }
    }
}

struct BookListRow: View {
    let item: BaseItemDto
    let apiClient: JellyfinAPIClient
    @State private var imageURL: URL?

    var body: some View {
        HStack(spacing: 12) {
            RemoteImageView(url: imageURL, section: .books, cornerRadius: 4, title: item.displayName)
                .frame(width: 40, height: 60)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.displayName)
                    .fontWeight(.medium).lineLimit(1)
                HStack(spacing: 8) {
                    if let year = item.yearText { Text(year) }
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
