import SwiftUI

struct MiniPlayerView: View {
    @Environment(SessionManager.self) private var session
    @Bindable private var playerManager = MusicPlayerManager.shared
    @State private var currentAlbumURL: URL?
    @State private var showQueue = false

    var body: some View {
        if let current = playerManager.currentSong {
            VStack(spacing: 12) {
                // Top: Album art with overlay title
                ZStack(alignment: .topTrailing) {
                    ZStack(alignment: .bottomLeading) {
                        RemoteImageView(url: currentAlbumURL, section: .music, cornerRadius: 12)
                            .aspectRatio(1, contentMode: .fit)
                            .shadow(color: .black.opacity(0.3), radius: 10, y: 5)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text(current.displayName)
                                .font(.system(size: 13, weight: .bold))
                                .lineLimit(1)
                                .foregroundStyle(.white)
                            if let artist = current.artists?.first {
                                Text(artist)
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(.white.opacity(0.8))
                                    .lineLimit(1)
                            }
                        }
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(LinearGradient(colors: [.black.opacity(0.8), .clear], startPoint: .bottom, endPoint: .top))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    
                    // Close button
                    Button(action: { playerManager.stop() }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title3)
                            .foregroundStyle(.white.opacity(0.6))
                            .padding(8)
                    }
                    .buttonStyle(.plain)
                }

                // Playback Controls
                VStack(spacing: 8) {
                    HStack(spacing: 16) {
                        Button(action: { playerManager.previous() }) {
                            Image(systemName: "backward.fill").font(.system(size: 14))
                        }
                        .buttonStyle(.plain)

                        Button(action: { playerManager.togglePlayPause() }) {
                            Image(systemName: playerManager.isPlaying ? "pause.fill" : "play.fill")
                                .font(.system(size: 20))
                                .frame(width: 40, height: 40)
                                .background(ThemeManager.shared.currentFlavor.accentColor)
                                .clipShape(Circle())
                                .foregroundStyle(.white)
                        }
                        .buttonStyle(.plain)

                        Button(action: { playerManager.next() }) {
                            Image(systemName: "forward.fill").font(.system(size: 14))
                        }
                        .buttonStyle(.plain)
                    }
                    
                    LiquidSlider(
                        value: Binding(
                            get: { playerManager.progress },
                            set: { playerManager.seek(to: $0) }
                        ), 
                        range: 0...(playerManager.duration > 0 ? playerManager.duration : 1)
                    )
                    .frame(height: 12)
                    
                    HStack {
                        Text(formatTime(playerManager.progress))
                        Spacer()
                        Text(formatTime(playerManager.duration))
                    }
                    .font(.system(size: 9).monospacedDigit())
                    .foregroundStyle(.secondary)
                    
                    // Secondary Controls: Shuffle, Repeat, Queue
                    HStack(spacing: 20) {
                        Button { playerManager.isShuffled.toggle() } label: {
                            Image(systemName: "shuffle")
                                .foregroundStyle(playerManager.isShuffled ? ThemeManager.shared.currentFlavor.accentColor : .secondary)
                        }
                        .buttonStyle(.plain)
                        .help("Shuffle")

                        Button {
                            switch playerManager.repeatMode {
                            case .off: playerManager.repeatMode = .all
                            case .all: playerManager.repeatMode = .one
                            case .one: playerManager.repeatMode = .off
                            }
                        } label: {
                            Image(systemName: playerManager.repeatMode == .one ? "repeat.1" : "repeat")
                                .foregroundStyle(playerManager.repeatMode != .off ? ThemeManager.shared.currentFlavor.accentColor : .secondary)
                        }
                        .buttonStyle(.plain)
                        .help(playerManager.repeatMode == .one ? "Repeat One" : (playerManager.repeatMode == .all ? "Repeat All" : "Repeat Off"))

                        Button { showQueue.toggle() } label: {
                            Image(systemName: "list.bullet")
                                .foregroundStyle(showQueue ? ThemeManager.shared.currentFlavor.accentColor : .secondary)
                        }
                        .buttonStyle(.plain)
                        .help("Queue")
                        .popover(isPresented: $showQueue) {
                            QueueView()
                                .frame(width: 250, height: 400)
                        }
                    }
                    .font(.system(size: 14))
                    .padding(.top, 4)
                }
            }
            .padding(12)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(.white.opacity(0.1), lineWidth: 0.5))
            .task(id: current.id) {
                if let id = current.albumId ?? current.id {
                    currentAlbumURL = await session.apiClient.imageURL(itemId: id, imageType: "Primary", maxWidth: 200)
                }
            }
        }
    }

    private func formatTime(_ seconds: Double) -> String {
        guard !seconds.isNaN else { return "0:00" }
        let m = Int(seconds) / 60
        let s = Int(seconds) % 60
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
        .background(.ultraThinMaterial)
    }
}
