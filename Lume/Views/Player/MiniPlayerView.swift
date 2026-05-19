import SwiftUI

struct MiniPlayerView: View {
    @Environment(SessionManager.self) private var session
    @Bindable private var playerManager = MusicPlayerManager.shared
    @State private var currentAlbumURL: URL?
    @State private var showQueue = false
    @State private var showLyrics = false

    var body: some View {
        if let current = playerManager.currentSong {
            VStack(spacing: 12) {
                // Top Row: Info and Primary Controls
                HStack(spacing: 12) {
                    // Small Album Art
                    RemoteImageView(url: currentAlbumURL, section: .music, cornerRadius: 8)
                        .frame(width: 48, height: 48)
                        .shadow(color: .black.opacity(0.2), radius: 4, y: 2)
                    
                    // Title and Artist
                    VStack(alignment: .leading, spacing: 1) {
                        MarqueeText(text: current.displayName)
                            .font(.system(size: 13, weight: .bold))
                            .frame(height: 18)
                        
                        if let artist = current.artists?.first {
                            Text(artist)
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    
                    // Controls
                    HStack(spacing: 10) {
                        Button(action: { playerManager.togglePlayPause() }) {
                            Image(systemName: playerManager.isPlaying ? "pause.fill" : "play.fill")
                                .font(.system(size: 15))
                                .frame(width: 36, height: 36)
                                .background(ThemeManager.shared.currentFlavor.accentColor)
                                .clipShape(Circle())
                                .foregroundStyle(.white)
                        }
                        .buttonStyle(.plain)
                        
                        Button(action: { playerManager.stop() }) {
                            Image(systemName: "xmark")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.secondary)
                                .padding(8)
                        }
                        .buttonStyle(.plain)
                    }
                }
                
                // Bottom Row: Slider and Extra Controls
                VStack(spacing: 6) {
                    LiquidSlider(
                        value: $playerManager.progress,
                        range: 0...(playerManager.duration > 0 ? playerManager.duration : 1),
                        onEditingChanged: { scrubbing in
                            if scrubbing {
                                playerManager.isScrubbing = true
                            } else {
                                playerManager.seek(to: playerManager.progress)
                            }
                        }
                    )
                    .frame(height: 8)
                    
                    HStack(spacing: 8) {
                        Text(formatTime(playerManager.progress))
                            .fixedSize(horizontal: true, vertical: false)
                        
                        Spacer()
                        
                        HStack(spacing: 14) {
                            Button { playerManager.previous() } label: { Image(systemName: "backward.fill") }
                            Button { playerManager.next() } label: { Image(systemName: "forward.fill") }
                            Button { showLyrics.toggle() } label: { Image(systemName: "quote.bubble.fill").foregroundStyle(showLyrics ? ThemeManager.shared.currentFlavor.accentColor : .secondary) }
                            Button { showQueue.toggle() } label: { Image(systemName: "list.bullet").foregroundStyle(showQueue ? ThemeManager.shared.currentFlavor.accentColor : .secondary) }
                        }
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .buttonStyle(.plain)
                        
                        Spacer()
                        
                        Text(formatTime(playerManager.duration))
                            .fixedSize(horizontal: true, vertical: false)
                    }
                    .font(.system(size: 10, weight: .medium).monospacedDigit())
                    .foregroundStyle(.tertiary)
                    .padding(.top, 4)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .glassEffect(in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .popover(isPresented: $showLyrics) {
                LyricsView(song: current)
                    .frame(width: 300, height: 450)
            }
            .popover(isPresented: $showQueue) {
                QueueView()
                    .frame(width: 250, height: 400)
            }
            .task(id: current.id) {
                if let id = current.albumId ?? current.id {
                    currentAlbumURL = await session.apiClient.imageURL(itemId: id, imageType: "Primary", maxWidth: 200)
                }
            }
        }
    }

    private func formatTime(_ seconds: Double) -> String {
        guard !seconds.isNaN && !seconds.isInfinite else { return "0:00" }
        let total = Int(seconds)
        let m = total / 60
        let s = total % 60
        return String(format: "%d:%02d", m, s)
    }
}

struct QueueView: View {
    @Bindable private var playerManager = MusicPlayerManager.shared
    
    var body: some View {
        VStack(spacing: 0) {
            Text("Up Next")
                .font(.headline)
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
            
            Divider()
            
            List {
                ForEach(Array(playerManager.queue.enumerated()), id: \.element.id) { index, song in
                    HStack(spacing: 12) {
                        Text("\(index + 1)")
                            .font(.caption2).monospacedDigit()
                            .foregroundStyle(.secondary)
                            .frame(width: 20)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text(song.displayName)
                                .font(.system(size: 12, weight: .medium))
                                .lineLimit(1)
                                .foregroundStyle(playerManager.currentSong?.id == song.id ? Color.accentColor : .primary)
                            if let artist = song.artists?.first {
                                Text(artist).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
                            }
                        }
                        
                        Spacer()
                        
                        if playerManager.currentSong?.id == song.id {
                            Image(systemName: "speaker.wave.2.fill")
                                .font(.caption2)
                                .foregroundStyle(Color.accentColor)
                        }
                    }
                    .padding(.vertical, 4)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        playerManager.play(song: song)
                    }
                }
                .onDelete { indices in
                    playerManager.queue.remove(atOffsets: indices)
                }
                .onMove { from, to in
                    playerManager.queue.move(fromOffsets: from, toOffset: to)
                }
            }
            .listStyle(.plain)
        }
        .glassEffect(in: RoundedRectangle(cornerRadius: 0))
    }
}

struct LyricsView: View {
    let song: BaseItemDto
    @State private var lyricsLines: [String] = []
    @State private var isLoading = true
    @State private var hasLyrics = false
    
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Lyrics")
                    .font(.headline)
                Spacer()
                if hasLyrics {
                    Text(song.artists?.first ?? song.albumArtist ?? "")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 8)
            
            Divider()
            
            if isLoading {
                ProgressView("Searching for lyrics...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if hasLyrics {
                ScrollView {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(Array(lyricsLines.enumerated()), id: \.offset) { index, line in
                            let isEmpty = line.trimmingCharacters(in: .whitespaces).isEmpty
                            
                            if isEmpty {
                                Spacer().frame(height: 12)
                            } else {
                                Text(line)
                                    .font(.system(size: 16, weight: .medium))
                                    .multilineTextAlignment(.leading)
                                    .foregroundStyle(.primary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.horizontal, 24)
                            }
                        }
                    }
                    .padding(.vertical, 24)
                }
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "music.mic")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                    Text("No lyrics found")
                        .font(.headline)
                    Text("We couldn't find lyrics for this track.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task(id: song.id) {
            isLoading = true
            let result = await LyricsManager.shared.getLyrics(songId: song.id ?? UUID().uuidString, title: song.name, artist: song.artists?.first ?? song.albumArtist)
            if let result = result {
                lyricsLines = result.components(separatedBy: "\n")
                hasLyrics = true
            } else {
                lyricsLines = []
                hasLyrics = false
            }
            isLoading = false
        }
    }
}
