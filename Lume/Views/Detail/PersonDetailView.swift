import SwiftUI

struct PersonDetailView: View {
    @Environment(SessionManager.self) private var session
    let person: BaseItemPerson
    
    @State private var items: [BaseItemDto] = []
    @State private var isLoading = true
    @State private var personDetail: BaseItemDto?
    @State private var imageURL: URL?
    
    private let columns = [GridItem(.adaptive(minimum: 160, maximum: 200), spacing: 24)]
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                // Header section
                HStack(alignment: .top, spacing: 32) {
                    // Profile Image
                    RemoteImageView(url: imageURL, section: .others, cornerRadius: 12, title: person.name, itemType: "Person")
                        .frame(width: 200, height: 300)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .shadow(color: .black.opacity(0.3), radius: 10, x: 0, y: 5)
                    
                    VStack(alignment: .leading, spacing: 24) {
                        Text(person.name ?? "Unknown")
                            .font(.system(size: 48, weight: .bold, design: .rounded))
                        
                        // Personal Info Grid
                        HStack(spacing: 40) {
                            if let birthDate = formatDate(personDetail?.premiereDate) {
                                infoRow(label: "Born", value: birthDate)
                            }
                            if let deathDate = formatDate(personDetail?.endDate) {
                                infoRow(label: "Died", value: deathDate)
                            }
                            if let productionYear = personDetail?.productionYear, personDetail?.premiereDate == nil {
                                infoRow(label: "Born", value: String(productionYear))
                            }
                        }
                        
                        // External Links
                        HStack(spacing: 12) {
                            if let wikipedia = personDetail?.externalUrls?.first(where: { ($0.name ?? "").contains("Wikipedia") }), let urlStr = wikipedia.url, let url = URL(string: urlStr) {
                                Link(destination: url) {
                                    Label("Wikipedia", systemImage: "arrow.up.right.circle.fill")
                                        .padding(.horizontal, 16)
                                        .padding(.vertical, 8)
                                        .background(.white.opacity(0.1), in: Capsule())
                                }
                                .buttonStyle(.plain)
                            }
                            
                            if let imdbId = personDetail?.providerIds?["Imdb"], let url = URL(string: "https://www.imdb.com/name/\(imdbId)") {
                                Link(destination: url) {
                                    Label("IMDb", systemImage: "star.fill")
                                        .padding(.horizontal, 16)
                                        .padding(.vertical, 8)
                                        .background(.white.opacity(0.1), in: Capsule())
                                }
                                .buttonStyle(.plain)
                                .foregroundStyle(.yellow)
                            }
                            
                            if let tmdbId = personDetail?.providerIds?["Tmdb"], let url = URL(string: "https://www.themoviedb.org/person/\(tmdbId)") {
                                Link(destination: url) {
                                    Label("TMDB", systemImage: "play.circle.fill")
                                        .padding(.horizontal, 16)
                                        .padding(.vertical, 8)
                                        .background(.white.opacity(0.1), in: Capsule())
                                }
                                .buttonStyle(.plain)
                                .foregroundStyle(.cyan)
                            }
                        }
                        
                        if let overview = personDetail?.overview, !overview.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Biography")
                                    .font(.headline)
                                    .foregroundStyle(.secondary)
                                
                                Text(overview)
                                    .font(.body)
                                    .lineSpacing(4)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        
                        Spacer()
                    }
                    .padding(.top, 20)
                }
                .padding(.horizontal, 40)
                
                // Filmography section
                VStack(alignment: .leading, spacing: 20) {
                    Text("Filmography")
                        .font(.title2)
                        .fontWeight(.bold)
                        .padding(.horizontal, 40)
                    
                    if isLoading {
                        HStack {
                            Spacer()
                            ProgressView()
                            Spacer()
                        }
                        .frame(height: 200)
                    } else if items.isEmpty {
                        Text("No items found.")
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 40)
                    } else {
                        LazyVGrid(columns: columns, spacing: 32) {
                            ForEach(items) { item in
                                NavigationLink(value: item) {
                                    ItemPosterCard(item: item, apiClient: session.apiClient, width: 180)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 40)
                    }
                }
            }
            .padding(.vertical, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.clear)
        .task { await loadData() }
        .navigationTitle(person.name ?? "Person")
        .toolbarBackground(.hidden)
    }
    
    private func loadData() async {
        guard let personId = person.id else { return }
        isLoading = true
        
        do {
            let response = try await session.apiClient.getItems(
                includeItemTypes: ["Movie", "Series"],
                sortBy: ["ProductionYear", "PremiereDate", "SortName"],
                sortOrder: "Descending",
                fields: ["PrimaryImageAspectRatio", "UserData", "ProductionYear"],
                recursive: true,
                personIds: personId
            )
            items = response.items ?? []
            
            do {
                personDetail = try await session.apiClient.getItem(itemId: personId)
            } catch {
                LumeDebug("Could not fetch extended person details: \(error)")
            }
            
            imageURL = await session.apiClient.personImageURL(personId: personId, tag: person.primaryImageTag)
        } catch {
            LumeError("Failed to load person detail: \(error)")
        }
        
        isLoading = false
    }
    
    private func infoRow(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label.uppercased())
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 14, weight: .medium))
        }
    }
    
    private func formatDate(_ dateString: String?) -> String? {
        guard let dateString else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        
        if let date = formatter.date(from: dateString) {
            let outputFormatter = DateFormatter()
            outputFormatter.dateStyle = .long
            return outputFormatter.string(from: date)
        }
        
        formatter.formatOptions = [.withFullDate]
        if let date = formatter.date(from: dateString) {
            let outputFormatter = DateFormatter()
            outputFormatter.dateStyle = .long
            return outputFormatter.string(from: date)
        }
        
        return nil
    }
}
