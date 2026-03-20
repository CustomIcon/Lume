import SwiftUI

struct LiveTVLibraryView: View {
    @Environment(SessionManager.self) private var session
    let library: BaseItemDto

    @State private var selectedTab = 0
    @State private var channels: [BaseItemDto] = []
    @State private var recordings: [BaseItemDto] = []
    @State private var isLoading = true
    @State private var searchText = ""
    @State private var errorMessage: String?
    @State private var totalChannels = 0
    @State private var searchTask: Task<Void, Never>?
    @State private var allChannels: [BaseItemDto] = []
    @State private var allRecordings: [BaseItemDto] = []

    private let columns = [GridItem(.adaptive(minimum: 140, maximum: 200), spacing: 20)]
    private let pageSize = 100

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $selectedTab) {
                Text("Channels").tag(0)
                Text("Recordings").tag(1)
            }
            .pickerStyle(.segmented)
            .padding()
            .frame(maxWidth: 300)

            Group {
                if let errorMessage {
                    ContentUnavailableView {
                        Label("Error Loading Live TV", systemImage: "exclamationmark.triangle")
                    } description: {
                        Text(errorMessage)
                    } actions: {
                        Button("Retry") {
                            self.errorMessage = nil
                            Task { await loadData() }
                        }
                        .buttonStyle(.borderedProminent)
                    }
                } else if isLoading && (selectedTab == 0 ? channels.isEmpty : recordings.isEmpty) {
                    ProgressView("Loading Live TV...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if selectedTab == 0 && channels.isEmpty {
                    ContentUnavailableView(
                        "No Channels",
                        systemImage: "antenna.radiowaves.left.and.right",
                        description: Text("No Live TV channels found on this server.")
                    )
                } else if selectedTab == 1 && recordings.isEmpty {
                    ContentUnavailableView(
                        "No Recordings",
                        systemImage: "record.circle",
                        description: Text("No Live TV recordings found.")
                    )
                } else {
                    ScrollView {
                        if selectedTab == 0 {
                            channelGrid
                        } else {
                            recordingGrid
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .navigationTitle(library.displayName)
        .searchable(text: $searchText, prompt: selectedTab == 0 ? "Search channels" : "Search recordings")
        .task {
            await loadData()
        }
        .onChange(of: selectedTab) { _, _ in
            Task { await loadData() }
        }
        .onChange(of: searchText) { _, _ in
            searchTask?.cancel()
            searchTask = Task {
                try? await Task.sleep(nanoseconds: 500_000_000)
                guard !Task.isCancelled else { return }
                await loadData()
            }
        }
    }

    private var channelGrid: some View {
        LazyVGrid(columns: columns, spacing: 24) {
            ForEach(channels, id: \.id) { channel in
                ChannelCard(channel: channel, apiClient: session.apiClient)
                    .onTapGesture {
                        session.activeVideoItem = channel
                    }
                    .itemContextMenu(item: channel, session: session, onPlay: {
                        session.activeVideoItem = channel
                    })
                    .onAppear {
                        if channel.id == channels.last?.id {
                            loadMoreChannels()
                        }
                    }
            }
        }
        .padding()
    }

    private var recordingGrid: some View {
        LazyVGrid(columns: columns, spacing: 24) {
            ForEach(recordings, id: \.id) { recording in
                NavigationLink(value: recording) {
                    ItemPosterCard(item: recording, apiClient: session.apiClient, width: 180)
                }
                .buttonStyle(.plain)
                .itemContextMenu(item: recording, session: session, onPlay: {
                    session.activeVideoItem = recording
                })
            }
        }
        .padding()
    }



    private func loadData() async {
        isLoading = true
        errorMessage = nil
        do {
            if selectedTab == 0 {
                if searchText.isEmpty {
                    let result = try await session.apiClient.getLiveTvChannels(limit: pageSize)
                    channels = result.items ?? []
                    totalChannels = result.totalRecordCount ?? channels.count
                    LumeInfo("Loaded \(channels.count) Live TV channels (total: \(totalChannels))")
                } else {
                    if allChannels.isEmpty {
                        let result = try await session.apiClient.getLiveTvChannels(limit: 20000)
                        allChannels = result.items ?? []
                    }
                    channels = allChannels.filter { ($0.name ?? "").localizedCaseInsensitiveContains(searchText) }
                    totalChannels = channels.count
                }
            } else {
                if searchText.isEmpty {
                    let result = try await session.apiClient.getLiveTvRecordings(limit: pageSize)
                    recordings = result.items ?? []
                    LumeInfo("Loaded \(recordings.count) recordings")
                } else {
                    if allRecordings.isEmpty {
                        let result = try await session.apiClient.getLiveTvRecordings(limit: 10000)
                        allRecordings = result.items ?? []
                    }
                    recordings = allRecordings.filter { ($0.name ?? "").localizedCaseInsensitiveContains(searchText) }
                }
            }
        } catch let error as APIError {
            if case .httpError(let code, _) = error, (code == 403 || code == 401) {
                errorMessage = "Access to Live TV was denied by the server (HTTP \(code)).\n\nPlease ensure your user account has the 'Allow Live TV access' permission enabled in the Jellyfin Administration dashboard."
            } else {
                errorMessage = error.localizedDescription
            }
            LumeError("Failed to load Live TV data: \(error)")
        } catch {
            errorMessage = error.localizedDescription
            LumeError("Failed to load Live TV data: \(error)")
        }
        isLoading = false
    }

    private func loadMoreChannels() {
        guard searchText.isEmpty else { return }
        guard channels.count < totalChannels, !isLoading else { return }
        isLoading = true
        Task {
            do {
                let result = try await session.apiClient.getLiveTvChannels(limit: pageSize, startIndex: channels.count)
                channels.append(contentsOf: result.items ?? [])
            } catch {
                LumeError("Failed to load more channels: \(error)")
            }
            isLoading = false
        }
    }
}

struct ChannelCard: View {
    let channel: BaseItemDto
    let apiClient: JellyfinAPIClient
    @State private var imageURL: URL?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(.ultraThinMaterial)

                if imageURL != nil {
                    RemoteImageView(url: imageURL, section: CacheSection.from(itemType: channel.type), cornerRadius: 4)
                        .aspectRatio(contentMode: .fit)
                        .padding(12)
                } else {
                    Image(systemName: "tv")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                }
            }
            .aspectRatio(16/9, contentMode: .fit)
            .clipped()
            .overlay(alignment: .topTrailing) {
                if let number = channel.channelNumber {
                    Text(number)
                        .font(.caption2.bold())
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.ultraThinMaterial)
                        .cornerRadius(4)
                        .padding(8)
                }
            }
            .overlay(alignment: .topLeading) {
                Circle()
                    .fill(.red)
                    .frame(width: 8, height: 8)
                    .padding(10)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(channel.displayName)
                    .font(.headline)
                    .lineLimit(1)

                if let program = channel.currentProgram {
                    Text(program.name ?? "No program info")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 4)
        }
        .contentShape(Rectangle())
        .task {
            if let id = channel.id {
                imageURL = await apiClient.imageURL(itemId: id, imageType: "Primary", tag: channel.imageTags?["Primary"])
            }
        }
    }
}
