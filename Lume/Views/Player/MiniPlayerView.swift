import SwiftUI

struct MiniPlayerView: View {
    @Environment(SessionManager.self) private var session
    @Bindable private var playerManager = MusicPlayerManager.shared
    @State private var currentAlbumURL: URL?

    var body: some View {
        if let current = playerManager.currentSong {
            HStack(spacing: 20) {
                // Album Art & Info
                HStack(spacing: 12) {
                    RemoteImageView(url: currentAlbumURL, section: .music, cornerRadius: 6)
                        .frame(width: 52, height: 52)
                        .shadow(radius: 4)
                        
                    VStack(alignment: .leading, spacing: 2) {
                        Text(current.displayName)
                            .font(.system(size: 14, weight: .semibold))
                            .lineLimit(1)
                        if let artist = current.artists?.first {
                            Text(artist)
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    .frame(width: 180, alignment: .leading)
                }

                Spacer()

                // Playback Controls
                VStack(spacing: 4) {
                    HStack(spacing: 24) {
                        Button(action: { playerManager.previous() }) {
                            Image(systemName: "backward.fill")
                                .font(.title3)
                        }
                        .buttonStyle(.plain)

                        Button(action: { playerManager.togglePlayPause() }) {
                            Image(systemName: playerManager.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                                .font(.system(size: 38))
                        }
                        .buttonStyle(.plain)

                        Button(action: { playerManager.next() }) {
                            Image(systemName: "forward.fill")
                                .font(.title3)
                        }
                        .buttonStyle(.plain)
                    }
                    
                    // Scrobbler
                    HStack(spacing: 8) {
                        Text(formatTime(playerManager.progress))
                            .font(.system(size: 10).monospacedDigit())
                            .foregroundStyle(.secondary)
                        
                        Slider(value: Binding(
                            get: { playerManager.progress },
                            set: { playerManager.seek(to: $0) }
                        ), in: 0...(playerManager.duration > 0 ? playerManager.duration : 1))
                        .accentColor(.white)
                        .scaleEffect(x: 1, y: 0.5)

                        Text(formatTime(playerManager.duration))
                            .font(.system(size: 10).monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    .frame(width: 350)
                }

                Spacer()
                
                // Volume & More
                HStack(spacing: 16) {
                    Button(action: { /* Add to favorites */ }) {
                        Image(systemName: "heart")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    
                    Image(systemName: "speaker.wave.2")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(width: 150, alignment: .trailing)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 14)
            .liquidPanel()
            .padding(20)
            .task(id: current.id) {
                if let id = current.albumId ?? current.id {
                    currentAlbumURL = await session.apiClient.imageURL(itemId: id, imageType: "Primary", maxWidth: 100)
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
