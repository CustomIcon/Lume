import SwiftUI

struct SubtitleSearchView: View {
    @Environment(SessionManager.self) private var session
    let itemId: String
    let onDownload: (URL) -> Void
    @Environment(\.dismiss) private var dismiss
    
    @State private var searchResults: [ExternalSubtitle] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var selectedLanguage = "eng" // ISO 639-2
    @State private var searchText = ""
    
    private let languages = [
        ("eng", "English"),
        ("spa", "Spanish"),
        ("fra", "French"),
        ("ger", "German"),
        ("ita", "Italian"),
        ("por", "Portuguese"),
        ("rus", "Russian"),
        ("chi", "Chinese"),
        ("jpn", "Japanese")
    ]
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Remote Subtitles")
                    .font(.headline)
                Spacer()
                Picker("", selection: $selectedLanguage) {
                    ForEach(languages, id: \.0) { lang in
                        Text(lang.1).tag(lang.0)
                    }
                }
                .frame(width: 120)
                .onChange(of: selectedLanguage) { _, _ in
                    Task { await performSearch() }
                }
                
                Button("Done") { dismiss() }
                    .buttonStyle(.borderedProminent)
            }
            .padding()
            .background(.ultraThinMaterial)
            
            HStack {
                TextField("Manual search (e.g. Movie Name 2024)", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { Task { await performSearch() } }
                
                Button {
                    Task { await performSearch() }
                } label: {
                    Image(systemName: "magnifyingglass")
                }
                .buttonStyle(.bordered)
            }
            .padding(.horizontal)
            .padding(.bottom, 8)
            .background(.ultraThinMaterial)
            
            Divider()
            
            if isLoading {
                Spacer()
                VStack(spacing: 16) {
                    ProgressView()
                    Text("Searching OpenSubtitles...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            } else if let error = errorMessage {
                Spacer()
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.title)
                        .foregroundStyle(.secondary)
                    Text(error)
                        .foregroundStyle(.secondary)
                    Button("Retry") { Task { await performSearch() } }
                }
                Spacer()
            } else if searchResults.isEmpty {
                Spacer()
                VStack(spacing: 8) {
                    Image(systemName: "text.magnifyingglass")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                    Text("No subtitles found externally.")
                        .foregroundStyle(.secondary)
                }
                Spacer()
            } else {
                List(searchResults) { sub in
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(sub.name)
                                .font(.body.bold())
                                .lineLimit(1)
                            
                            HStack(spacing: 12) {
                                Label(sub.language, systemImage: "character.bubble")
                                Label(sub.format.uppercased(), systemImage: "doc.text")
                                Label("OpenSubtitles", systemImage: "network")
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                        
                        Spacer()
                        
                        Button {
                            Task { await download(sub) }
                        } label: {
                            Image(systemName: "arrow.down.circle")
                                .font(.title3)
                                .foregroundStyle(themeColor)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.vertical, 4)
                }
                .listStyle(.inset)
            }
        }
        .frame(width: 500, height: 400)
        .background(Color(.windowBackgroundColor))
        .task { await performSearch() }
    }
    
    private var themeColor: Color {
        ThemeManager.shared.currentFlavor.accentColor
    }
    
    private func performSearch() async {
        isLoading = true
        errorMessage = nil
        
        do {
            // 1. Fetch full item details to get correct title/year/IMDB
            let fullItem = try await session.apiClient.getItem(itemId: itemId)
            
            let titleToSearch: String
            if !searchText.trimmingCharacters(in: .whitespaces).isEmpty {
                titleToSearch = searchText
            } else if fullItem.type == "Episode" {
                let season = fullItem.parentIndexNumber ?? 1
                let episode = fullItem.indexNumber ?? 1
                let seFormat = String(format: "S%02dE%02d", season, episode)
                titleToSearch = "\(fullItem.seriesName ?? "") \(seFormat) \(fullItem.name ?? "")"
            } else {
                titleToSearch = fullItem.name ?? ""
            }
            
            let imdbId = fullItem.providerIds?["Imdb"]
            
            // 2. Search external service
            searchResults = await ExternalSubtitleService.shared.search(
                title: titleToSearch,
                year: fullItem.productionYear,
                type: fullItem.type ?? "Movie",
                imdbId: imdbId,
                language: selectedLanguage
            )
        } catch {
            errorMessage = error.localizedDescription
        }
        
        isLoading = false
    }
    
    private func download(_ sub: ExternalSubtitle) async {
        guard let fileId = sub.fileId else { return }
        do {
            let data = try await ExternalSubtitleService.shared.download(fileId: fileId)
            let url = try SubtitleService.shared.downloadSubtitle(
                data: data,
                itemId: itemId,
                name: sub.name,
                format: sub.format
            )
            onDownload(url)
            dismiss()
        } catch {
            errorMessage = "Download failed: \(error.localizedDescription)"
        }
    }
}
