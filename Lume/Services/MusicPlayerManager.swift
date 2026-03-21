import SwiftUI
import AVKit
import Combine
import MediaPlayer

@Observable
final class MusicPlayerManager {
    static let shared = MusicPlayerManager()
    
    var currentSong: BaseItemDto?
    var queue: [BaseItemDto] = []
    
    enum RepeatMode { case off, one, all }
    
    var isPlaying = false
    var repeatMode: RepeatMode = .off
    var isShuffled = false
    var progress: Double = 0
    var duration: Double = 0
    var bufferedTime: Double = 0
    var playSessionId: String = UUID().uuidString
    var volume: Float = 1.0 {
        didSet { avPlayer?.volume = volume }
    }
    
    private var avPlayer: AVPlayer?
    private var timeObserver: Any?
    private var sessionManager: SessionManager?
    private var cancellables = Set<AnyCancellable>()
    
    private init() {
        setupRemoteCommandCenter()
    }
    
    func setup(session: SessionManager) {
        self.sessionManager = session
    }
    
    func play(song: BaseItemDto, queue: [BaseItemDto]? = nil) {
        if let newQueue = queue {
            self.queue = newQueue
        }
        
        guard let session = sessionManager else { return }
        
        // Report stop for previous song if it was playing
        if let oldId = self.currentSong?.id {
            let ticks = Int64(max(0, self.progress) * 10_000_000)
            let stopInfo = PlaybackStopInfo(itemId: oldId, positionTicks: ticks, playSessionId: playSessionId)
            Task { try? await session.apiClient.reportPlaybackStopped(stopInfo) }
        }
        
        self.playSessionId = UUID().uuidString
        self.currentSong = song
        let itemId = song.id ?? ""
        
        // Stop current
        avPlayer?.pause()
        if let observer = timeObserver {
            avPlayer?.removeTimeObserver(observer)
        }
        
        Task {
            let url = await session.apiClient.audioStreamURL(itemId: itemId)
            let auth = await session.apiClient.authorizationHeader
            
            guard let url = url else { return }
            
            let headers: [String: String] = [
                "Authorization": auth,
                "X-Emby-Authorization": auth
            ]
            let options = ["AVURLAssetHTTPHeaderFieldsKey": headers]
            let asset = AVURLAsset(url: url, options: options)
            let playerItem = AVPlayerItem(asset: asset)
            
            await MainActor.run {
                let player = AVPlayer(playerItem: playerItem)
                player.volume = volume
                self.avPlayer = player
                
                // Monitor status
                playerItem.publisher(for: \.status)
                    .sink { [weak self] status in
                        if status == .readyToPlay {
                            self?.duration = playerItem.duration.seconds
                            self?.updateNowPlayingInfo()
                            // Report Start
                            let ticks = Int64(max(0, self?.progress ?? 0) * 10_000_000)
                            let startInfo = PlaybackStartInfo(itemId: itemId, positionTicks: ticks, playSessionId: self?.playSessionId)
                            Task { try? await session.apiClient.reportPlaybackStart(startInfo) }
                        } else if status == .failed {
                            print("Audio Playback Error: \(String(describing: playerItem.error))")
                            self?.isPlaying = false
                        }
                    }
                    .store(in: &cancellables)
                
                // Monitor finished
                NotificationCenter.default.publisher(for: .AVPlayerItemDidPlayToEndTime, object: playerItem)
                    .sink { [weak self] _ in self?.next() }
                    .store(in: &cancellables)
                
                // Periodical Progress
                var lastReportedTime: Int = -1
                
                timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.5, preferredTimescale: 600), queue: .main) { [weak self] time in
                    guard let self = self else { return }
                    self.progress = time.seconds
                    let dur = playerItem.duration.seconds
                    if !dur.isNaN {
                        self.duration = dur
                    }
                    self.updateNowPlayingPlaybackInfo()
                    
                    if let currentItem = self.avPlayer?.currentItem {
                        let loadedRanges = currentItem.loadedTimeRanges
                        if let range = loadedRanges.first?.timeRangeValue {
                            self.bufferedTime = range.start.seconds + range.duration.seconds
                        }
                    }
                    
                    let currentInt = Int(self.progress)
                    if currentInt % 10 == 0 && currentInt != lastReportedTime {
                        lastReportedTime = currentInt
                        let ticks = Int64(self.progress * 10_000_000)
                        let isPaused = self.avPlayer?.rate == 0
                        let isMuted = self.avPlayer?.isMuted ?? false
                        let info = PlaybackProgressInfo(itemId: itemId, positionTicks: ticks, isPaused: isPaused, isMuted: isMuted, playSessionId: self.playSessionId)
                        Task { try? await session.apiClient.reportPlaybackProgress(info) }
                    }
                }
                
                player.play()
                self.isPlaying = true
                self.updateNowPlayingInfo()
            }
        }
    }
    
    func togglePlayPause() {
        guard let player = avPlayer else { return }
        if isPlaying {
            player.pause()
            isPlaying = false
        } else {
            player.play()
            isPlaying = true
        }
        updateNowPlayingPlaybackInfo()
    }
    
    func pause() {
        avPlayer?.pause()
        isPlaying = false
        updateNowPlayingPlaybackInfo()
        
        if let id = currentSong?.id {
            let ticks = Int64(max(0, self.progress) * 10_000_000)
            let isMuted = self.avPlayer?.isMuted ?? false
            let info = PlaybackProgressInfo(itemId: id, positionTicks: ticks, isPaused: true, isMuted: isMuted, playSessionId: self.playSessionId)
            Task { try? await sessionManager?.apiClient.reportPlaybackProgress(info) }
        }
    }
    
    func stop() {
        if let id = currentSong?.id {
            let ticks = Int64(max(0, self.progress) * 10_000_000)
            let stopInfo = PlaybackStopInfo(itemId: id, positionTicks: ticks, playSessionId: playSessionId)
            Task { try? await sessionManager?.apiClient.reportPlaybackStopped(stopInfo) }
        }
        
        pause()
        currentSong = nil
        queue = []
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }

    func enqueue(_ items: [BaseItemDto], atEnd: Bool = true) {
        if atEnd {
            queue.append(contentsOf: items)
        } else if let current = currentSong, let idx = queue.firstIndex(where: { $0.id == current.id }) {
            queue.insert(contentsOf: items, at: idx + 1)
        } else {
            queue.insert(contentsOf: items, at: 0)
        }
    }
    
    func next() {
        if repeatMode == .one {
            seek(to: 0)
            avPlayer?.play()
            return
        }
        
        guard let current = currentSong,
              let idx = queue.firstIndex(where: { $0.id == current.id }) else {
            if !queue.isEmpty { play(song: isShuffled ? queue.randomElement()! : queue[0]) }
            return
        }
        
        if isShuffled && queue.count > 1 {
            var nextIdx = Int.random(in: 0..<queue.count)
            while nextIdx == idx && queue.count > 1 { nextIdx = Int.random(in: 0..<queue.count) }
            play(song: queue[nextIdx])
            return
        }
        
        if idx + 1 < queue.count {
            play(song: queue[idx + 1])
        } else if repeatMode == .all && !queue.isEmpty {
            play(song: queue[0])
        } else {
            stop()
        }
    }
    
    func previous() {
        if progress > 3.0 {
            seek(to: 0)
            return
        }
        
        guard let current = currentSong,
              let idx = queue.firstIndex(where: { $0.id == current.id }),
              idx - 1 >= 0 else { return }
        play(song: queue[idx - 1])
    }
    
    func seek(to seconds: Double) {
        avPlayer?.seek(to: CMTime(seconds: seconds, preferredTimescale: 600))
        progress = seconds
    }
    
    private func setupRemoteCommandCenter() {
        let center = MPRemoteCommandCenter.shared()
        
        center.playCommand.isEnabled = true
        center.playCommand.addTarget { [weak self] _ in
            self?.togglePlayPause()
            return .success
        }
        
        center.pauseCommand.isEnabled = true
        center.pauseCommand.addTarget { [weak self] _ in
            self?.togglePlayPause()
            return .success
        }
        
        center.nextTrackCommand.isEnabled = true
        center.nextTrackCommand.addTarget { [weak self] _ in
            self?.next()
            return .success
        }
        
        center.previousTrackCommand.isEnabled = true
        center.previousTrackCommand.addTarget { [weak self] _ in
            self?.previous()
            return .success
        }
    }
    
    private func updateNowPlayingInfo() {
        guard let song = currentSong else { return }
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: song.displayName,
            MPMediaItemPropertyArtist: song.artists?.first ?? "Unknown Artist",
            MPMediaItemPropertyAlbumTitle: song.album ?? ""
        ]
        
        if duration > 0 {
            info[MPMediaItemPropertyPlaybackDuration] = duration
        }
        
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }
    
    private func updateNowPlayingPlaybackInfo() {
        var info = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = progress
        info[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? 1.0 : 0.0
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }
}
