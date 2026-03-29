import SwiftUI
import AVKit
import Combine
import VLCKitSPM

/// Tracks whether we have hidden the cursor so we never double-hide or double-unhide.
private final class CursorHideState {
    static let shared = CursorHideState()
    private var isHidden = false

    func hide() {
        guard !isHidden else { return }
        NSCursor.hide()
        isHidden = true
    }

    func unhide() {
        guard isHidden else { return }
        NSCursor.unhide()
        isHidden = false
    }
}

enum LumePointerVisibility: Equatable {
    case visible, hidden
}

extension View {
    @ViewBuilder
    func pointerVisibility(_ visibility: LumePointerVisibility) -> some View {
        self.onChange(of: visibility) { _, newValue in
            if newValue == .hidden {
                CursorHideState.shared.hide()
            } else {
                CursorHideState.shared.unhide()
            }
        }
        .onDisappear {
            CursorHideState.shared.unhide()
        }
    }
}

struct VLCTrackInfo: Identifiable, Hashable {
    let index: Int32
    let name: String
    var id: Int32 { index }
}

struct VLCVideoPlayer: NSViewRepresentable {
    let url: URL
    let mediaOptions: [String] // subtitle options, etc.
    let externalSubtitles: [URL]
    @Binding var proxy: Proxy
    let onSecondsUpdated: (Double, Double) -> Void
    let onStateUpdated: (VLCMediaPlayerState) -> Void

    class Coordinator: NSObject, VLCMediaPlayerDelegate {
        var parent: VLCVideoPlayer
        var mediaPlayer: VLCMediaPlayer

        init(_ parent: VLCVideoPlayer) {
            self.parent = parent
            self.mediaPlayer = VLCMediaPlayer()
            super.init()
            self.mediaPlayer.delegate = self
            DispatchQueue.main.async {
                parent.proxy.mediaPlayer = self.mediaPlayer
            }
        }

        func mediaPlayerTimeChanged(_ aNotification: Notification) {
            let current = Double(mediaPlayer.time.intValue) / 1000.0
            let total = Double(mediaPlayer.media?.length.intValue ?? 0) / 1000.0
            parent.onSecondsUpdated(current, total)
        }

        func mediaPlayerStateChanged(_ aNotification: Notification) {
            if mediaPlayer.state == .playing || mediaPlayer.state == .opening || mediaPlayer.state == .buffering {
                mediaPlayer.currentVideoSubTitleIndex = -1
            }
            parent.onStateUpdated(mediaPlayer.state)
        }
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.black.cgColor
        context.coordinator.mediaPlayer.drawable = view

        let media = VLCMedia(url: url)
        media.addOptions(mediaOptions.reduce([String: String]()) { dict, opt in
            var d = dict
            let parts = opt.split(separator: "=")
            if parts.count == 2 {
                d[String(parts[0])] = String(parts[1])
            } else {
                d[opt] = nil
            }
            return d
        })
        context.coordinator.mediaPlayer.currentVideoSubTitleIndex = -1
        context.coordinator.mediaPlayer.play()

        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        let currentMediaURL = context.coordinator.mediaPlayer.media?.url
        if currentMediaURL != url {
            let media = VLCMedia(url: url)
            media.addOptions(mediaOptions.reduce([String: String]()) { dict, opt in
                var d = dict
                let parts = opt.split(separator: "=")
                if parts.count == 2 {
                    d[String(parts[0])] = String(parts[1])
                } else {
                    d[opt] = nil
                }
                return d
            })
            
            context.coordinator.mediaPlayer.media = media
            context.coordinator.mediaPlayer.currentVideoSubTitleIndex = -1
            context.coordinator.mediaPlayer.play()
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    struct Proxy {
        weak var mediaPlayer: VLCMediaPlayer?
        var rate: Float { mediaPlayer?.rate ?? 0 }

        func play() { mediaPlayer?.play() }
        func pause() { mediaPlayer?.pause() }
        func stop() { mediaPlayer?.stop() }

        func togglePlay() {
            if mediaPlayer?.isPlaying ?? false { mediaPlayer?.pause() } else { mediaPlayer?.play() }
        }

        func jumpForward(_ dur: Duration) -> Double {
            let next = (mediaPlayer?.time.intValue ?? 0) + Int32(dur.components.seconds * 1000)
            mediaPlayer?.time = VLCTime(int: next)
            return Double(next) / 1000.0
        }

        func jumpBackward(_ dur: Duration) -> Double {
            let next = (mediaPlayer?.time.intValue ?? 0) - Int32(dur.components.seconds * 1000)
            mediaPlayer?.time = VLCTime(int: next)
            return Double(next) / 1000.0
        }

        func setSeconds(_ seconds: Duration) {
            mediaPlayer?.time = VLCTime(int: Int32(seconds.components.seconds * 1000))
        }

        /// Returns the available SPU (subtitle) tracks from VLC.
        /// Index -1 means "Disable subtitles".
        var subtitleTracks: [VLCTrackInfo] {
            guard let player = mediaPlayer else { return [] }
            var tracks: [VLCTrackInfo] = []
            if let names = player.videoSubTitlesNames as? [String],
               let indexes = player.videoSubTitlesIndexes as? [NSNumber] {
                for (name, idx) in zip(names, indexes) {
                    tracks.append(VLCTrackInfo(index: idx.int32Value, name: name))
                }
            }
            return tracks
        }

        var currentSubtitleIndex: Int32 {
            get { mediaPlayer?.currentVideoSubTitleIndex ?? -1 }
            set { mediaPlayer?.currentVideoSubTitleIndex = newValue }
        }

        var videoSize: CGSize { mediaPlayer?.videoSize ?? .zero }

        var stats: VLCMedia.Stats? {
            guard let player = mediaPlayer, let media = player.media else { return nil }
            return media.statistics
        }

        func setSubtitleTrack(_ index: Int32) {
            mediaPlayer?.currentVideoSubTitleIndex = index
        }

        var audioTracks: [VLCTrackInfo] {
            guard let player = mediaPlayer else { return [] }
            var tracks: [VLCTrackInfo] = []
            if let names = player.audioTrackNames as? [String],
               let indexes = player.audioTrackIndexes as? [NSNumber] {
                for (name, idx) in zip(names, indexes) {
                    tracks.append(VLCTrackInfo(index: idx.int32Value, name: name))
                }
            }
            return tracks
        }

        var currentAudioIndex: Int32 {
            get { mediaPlayer?.currentAudioTrackIndex ?? -1 }
        }

        func setAudioTrack(_ index: Int32) {
            mediaPlayer?.currentAudioTrackIndex = index
        }

        func setSubtitleScale(_ scale: Int) {
            // Try KVC first (dynamic update)
            mediaPlayer?.setValue(NSNumber(value: Int32(scale)), forKey: "textRendererFontSize")
            // Some VLC versions use a different key or require Float
            mediaPlayer?.setValue(NSNumber(value: Float(scale)), forKey: "textRendererFontSize")
            forceSubtitleReload()
        }
        
        func setSubtitleStyle(font: String, color: String, opacity: Double) {
            // VLCKit doesn't reliably expose dynamic color/opacity updates via KVC.
            // These styles are handled at media initialization in the VLCVideoPlayer view.
            forceSubtitleReload()
        }
        
        private func forceSubtitleReload() {
            // Toggling the track off and on forces VLC to reload the text renderer with new settings
            let current = mediaPlayer?.currentVideoSubTitleIndex ?? -1
            if current != -1 {
                mediaPlayer?.currentVideoSubTitleIndex = -1
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    self.mediaPlayer?.currentVideoSubTitleIndex = current
                }
            }
        }

        var isMuted: Bool {
            get { mediaPlayer?.audio?.isMuted ?? false }
            set { mediaPlayer?.audio?.isMuted = newValue }
        }

        func toggleMute() {
            mediaPlayer?.audio?.isMuted.toggle()
        }

        var volume: Int32 {
            get { mediaPlayer?.audio?.volume ?? 0 }
            set { mediaPlayer?.audio?.volume = newValue }
        }

        func addSubtitle(url: URL) {
            mediaPlayer?.addPlaybackSlave(url, type: .subtitle, enforce: true)
        }
    }
}

@Observable
final class PlayerViewModel {
    var player: AVPlayer?
    var vlcProxy = VLCVideoPlayer.Proxy()
    var isPlaying = false {
        didSet {
            if isPlaying {
                SleepPreventer.shared.startPreventingSleep(reason: "Watching media in Lume")
            } else {
                SleepPreventer.shared.stopPreventingSleep()
            }
        }
    }

    var isLoading = true
    var statusMessage: String = "Finding best stream..."
    var showControls = true
    var lastMouseMovement = Date()
    var currentPlaybackTime: Double = 0
    var duration: Double = 0
    var bufferedTime: Double = 0
    var isDraggingSlider = false

    // VLC native track selection (by VLC index)
    var selectedSubtitleIndex: Int32 = -1
    var selectedAudioIndex: Int32 = -1

    // Track lists populated once VLC starts playing
    var vlcSubtitleTracks: [VLCTrackInfo] = []
    var vlcAudioTracks: [VLCTrackInfo] = []

    var progressTimer: Timer?
    private var cancellables = Set<AnyCancellable>()
    var playSessionId: String?
    var mediaSourceId: String?
    var lastReportedTime: Double = -999.0
    var currentPosition: Int64 = 0
    var hasStartedPlaying = false
    var tracksLoaded = false
    var externalSubtitles: [URL] = []
    var subtitleCues: [SubtitleCue] = []
    var activeCues: [SubtitleCue] = []
    var userSelectedSubtitleIndex: Int = -999
    var subtitleScale: Int = UserDefaults.standard.integer(forKey: "subtitleScale") == 0 ? 44 : UserDefaults.standard.integer(forKey: "subtitleScale")
    var subtitleColor: String = "#FFFFFF" 
    var subtitleBgOpacity: Double = 0.0 
    var subtitleFont: String {
        get { UserDefaults.standard.string(forKey: "subtitleFont") ?? "Inter" }
        set { UserDefaults.standard.set(newValue, forKey: "subtitleFont") }
    }
    var subtitleOffset: Double = 0.0 // Temporary offset in seconds
    
    var isFullscreen = false
    var trickplayManifest: TrickplayManifest?
    var cachedBaseURL: String = ""
    var cachedToken: String?
    var hasResumed = false
    var showInfo = false
    var liveBitrate: Float = 0
    var lostFrames: Int32 = 0
    var seekToOnPlay: Double? = nil

    var volume: Int32 = 100 {
        didSet {
            vlcProxy.volume = volume
        }
    }
    var lastVolume: Int32 = 100
    
    var playURL: URL?
    
    var intros: [IntroTimestamp] = []
    var showSkipButton = false
    var currentSegment: IntroTimestamp? = nil
    
    var nextItem: BaseItemDto? = nil
    var previousItem: BaseItemDto? = nil

    func cleanup() {
        progressTimer?.invalidate()
        progressTimer = nil
        vlcProxy.stop()
        player?.pause()
        player = nil
        hasStartedPlaying = false
        lastReportedTime = -999.0
        tracksLoaded = false
        isLoading = false
        CursorHideState.shared.unhide()
        SleepPreventer.shared.stopPreventingSleep()
        nextItem = nil
        previousItem = nil
    }
    
    func setupFullscreenObserver() {
        NotificationCenter.default.publisher(for: NSWindow.didEnterFullScreenNotification)
            .sink { [weak self] _ in self?.isFullscreen = true }
            .store(in: &cancellables)
        
        NotificationCenter.default.publisher(for: NSWindow.didExitFullScreenNotification)
            .sink { [weak self] _ in self?.isFullscreen = false }
            .store(in: &cancellables)
            
        // Initial state
        if let window = NSApp.keyWindow ?? NSApp.mainWindow ?? NSApp.windows.first(where: { $0.isVisible }) {
            isFullscreen = window.styleMask.contains(.fullScreen)
        }
    }

    /// Load track lists from VLC player once playback has started.
    func loadTracksFromVLC(apiClient: JellyfinAPIClient, item: BaseItemDto) async {
        guard !tracksLoaded else { return }
        
        // VLC needs time to register all tracks, especially on HLS
        try? await Task.sleep(nanoseconds: 1_200_000_000) // 1.2s
        
        vlcSubtitleTracks = vlcProxy.subtitleTracks
        vlcAudioTracks = vlcProxy.audioTracks
        
        let prefSub = UserDefaults.standard.string(forKey: "preferredSubLanguage") ?? "eng"
        let prefAudio = UserDefaults.standard.string(forKey: "preferredAudioLanguage") ?? "eng"
        let subsOn = UserDefaults.standard.bool(forKey: "defaultSubtitlesOn")
        
        // Handle Audio Preservation
        if selectedAudioIndex != -1 {
            vlcProxy.setAudioTrack(selectedAudioIndex)
        } else if let bestAudio = findBestTrack(in: vlcAudioTracks, lang: prefAudio) {
            vlcProxy.setAudioTrack(bestAudio.index)
            selectedAudioIndex = bestAudio.index
        } else {
            selectedAudioIndex = vlcProxy.currentAudioIndex
        }
        
        // Handle Subtitle Preservation
        if userSelectedSubtitleIndex != -999 {
            // Respect existing selection (from menu or previous quality level)
            if userSelectedSubtitleIndex != -1 && (subtitleCues.isEmpty) {
                 Task { await loadJellyfinSubtitles(apiClient: apiClient, item: item, index: userSelectedSubtitleIndex) }
            }
        } else {
            // First time loading - apply defaults
            if subsOn {
                if let streams = item.mediaSources?.first?.mediaStreams?.filter({ $0.type == "Subtitle" }),
                   let bestSub = streams.first(where: { ($0.language?.lowercased().contains(prefSub) ?? false) || ($0.displayTitle?.lowercased().contains(prefSub) ?? false) }) ?? streams.first(where: { $0.isDefault == true }) {
                    LumeInfo("Automatched custom subtitle: \(bestSub.displayTitle ?? "Unknown")")
                    let idx = bestSub.index ?? -1
                    userSelectedSubtitleIndex = idx
                    Task { await loadJellyfinSubtitles(apiClient: apiClient, item: item, index: idx) }
                }
            } else {
                userSelectedSubtitleIndex = -1
            }
        }
        
        if !vlcAudioTracks.isEmpty {
            tracksLoaded = true
        }
    }
    
    func getTrickplayURL(itemId: String, index: Int, width: Int = 320) -> URL? {
        guard !cachedBaseURL.isEmpty else { return nil }
        var path = "\(cachedBaseURL)/Videos/\(itemId)/Trickplay/\(width)/tiles/\(index).jpg"
        if let token = cachedToken {
            path += "?api_key=\(token)"
        }
        return URL(string: path)
    }

    func loadTrickplay(apiClient: JellyfinAPIClient, itemId: String) async {
        do {
            trickplayManifest = try await apiClient.getTrickplayManifest(itemId: itemId)
            LumeDebug("Loaded trickplay manifest: \(trickplayManifest?.count ?? 0) tiles")
        } catch {
            LumeError("Trickplay manifest not found for item \(itemId)")
            trickplayManifest = nil
        }
    }

    func getExternalSubtitles(apiClient: JellyfinAPIClient, item: BaseItemDto) async -> [URL] {
        let base = await apiClient.getBaseURL()
        let token = await apiClient.getAccessToken()
        
        var urls: [URL] = []
        let mediaSource = item.mediaSources?.first { $0.id == mediaSourceId } ?? item.mediaSources?.first
        
        guard let sourceId = mediaSource?.id, let streams = mediaSource?.mediaStreams else { return [] }
        
        for stream in streams where stream.type == "Subtitle" {
            if let delivery = stream.deliveryUrl {
                let full = base + delivery + (delivery.contains("?") ? "&api_key=\(token ?? "")" : "?api_key=\(token ?? "")")
                if let url = URL(string: full) {
                    LumeDebug("Discovered external subtitle: \(stream.displayTitle ?? "Unknown")")
                    urls.append(url)
                }
            } else if stream.isExternal == true || stream.isTextSubtitleStream == true {
                let codec = stream.codec ?? "srt"
                let idx = stream.index ?? 0
                let urlString = "\(base)/Videos/\(item.id ?? "")/\(sourceId)/Subtitles/\(idx)/0/Stream.\(codec)?api_key=\(token ?? "")"
                if let url = URL(string: urlString) {
                    LumeDebug("Discovered fallback subtitle: \(stream.displayTitle ?? "Unknown")")
                    urls.append(url)
                }
            }
        }
        return urls
    }
    
    func loadJellyfinSubtitles(apiClient: JellyfinAPIClient, item: BaseItemDto, index: Int) async {
        guard index != -1 else {
            subtitleCues = []
            activeCues = []
            return
        }
        
        let base = await apiClient.getBaseURL()
        let token = await apiClient.getAccessToken()
        let sourceId = item.mediaSources?.first?.id ?? item.id ?? ""
        
        // We will try several common Jellyfin paths for subtitle streams
        let possiblePaths = [
            "\(base)/Videos/\(item.id ?? "")/\(sourceId)/Subtitles/\(index)/Stream.vtt?api_key=\(token ?? "")",
            "\(base)/Videos/\(item.id ?? "")/\(sourceId)/Subtitles/\(index)/0/Stream.vtt?api_key=\(token ?? "")",
            "\(base)/Videos/\(item.id ?? "")/Subtitles/\(index)/Stream.vtt?api_key=\(token ?? "")"
        ]
        
        for urlString in possiblePaths {
            guard let url = URL(string: urlString) else { continue }
            LumeDebug("Trying custom subtitle fetch: \(urlString)")
            
            do {
                let (data, response) = try await URLSession.shared.data(from: url)
                guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                    continue
                }
                
                if let content = String(data: data, encoding: .utf8) {
                    let parsed = SubtitleParser.parse(content)
                    if !parsed.isEmpty {
                        LumeInfo("Found and parsed \(parsed.count) cues from \(urlString)")
                        await MainActor.run {
                            subtitleCues = parsed
                        }
                        return // SUCCESS
                    }
                }
            } catch {
                LumeError("Failed to fetch path \(urlString): \(error)")
            }
        }
        
        LumeError("Could not fetch subtitles for item \(item.id ?? "") at index \(index) using any known path.")
    }
    
    func updateActiveCues(at time: Double) {
        let adjTime = time - subtitleOffset
        let matching = subtitleCues.filter { adjTime >= $0.startTime && adjTime <= $0.endTime }
        if matching != activeCues {
            activeCues = matching
        }
    }

    func loadIntros(apiClient: JellyfinAPIClient, itemId: String) async {
        do {
            intros = try await apiClient.getIntroTimestamps(itemId: itemId)
            LumeDebug("Loaded \(intros.count) intros for item \(itemId)")
        } catch {
            LumeDebug("No intros found for \(itemId)")
            intros = []
        }
    }

    func loadSiblings(apiClient: JellyfinAPIClient, item: BaseItemDto) async {
        nextItem = nil
        previousItem = nil
        guard item.type == "Episode", let seriesId = item.seriesId, let seasonId = item.seasonId else { return }
        do {
            let result = try await apiClient.getEpisodes(seriesId: seriesId, seasonId: seasonId)
            let episodes = result.items ?? []
            if let currentIndex = episodes.firstIndex(where: { $0.id == item.id }) {
                if currentIndex < episodes.count - 1 {
                    nextItem = episodes[currentIndex + 1]
                }
                if currentIndex > 0 {
                    previousItem = episodes[currentIndex - 1]
                }
            }
        } catch {
            LumeError("Failed to load siblings: \(error.localizedDescription)")
        }
    }

    func checkIntroVisibility(currentTime: Double) {
        guard !intros.isEmpty else {
            showSkipButton = false
            currentSegment = nil
            return
        }

        if let segment = intros.first(where: { currentTime >= $0.start && currentTime <= $0.end }) {
            currentSegment = segment
            showSkipButton = true
        } else {
            showSkipButton = false
            currentSegment = nil
        }
    }

    func skipSegment() {
        guard let segment = currentSegment else { return }
        vlcProxy.setSeconds(Duration.seconds(segment.end + 0.5))
        currentPlaybackTime = segment.end + 0.5
        showSkipButton = false
    }

    private func findBestTrack(in tracks: [VLCTrackInfo], lang: String) -> VLCTrackInfo? {
        let l = lang.lowercased()
        // Try exact match in name (which often contains language code or name)
        return tracks.first { $0.name.lowercased().contains(l) } 
            ?? tracks.first { $0.name.lowercased().contains("english") && l == "eng" }
    }

    deinit {
        cleanup()
    }
}

struct PlayerView: View {
    @Environment(SessionManager.self) private var session
    @Environment(\.dismissWindow) private var dismissWindow
    let item: BaseItemDto

    @AppStorage("resumePlayback") private var resumePlayback = true
    @FocusState private var isFocused: Bool
    @State private var vm = PlayerViewModel()
    @State private var fullItem: BaseItemDto?
    @State private var errorMessage: String?
    @AppStorage("skipIntroEnabled") private var skipIntroEnabled = true
    @State private var showSubtitleSearch = false
    @State private var showSubtitleSettings = false
    @State private var infoPosition = CGSize.zero
    @State private var captionPosition = CGSize.zero
    @GestureState private var infoDragOffset = CGSize.zero
    @GestureState private var captionDragOffset = CGSize.zero
    
    private var resolvedItem: BaseItemDto { fullItem ?? item }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let errorMessage {
                VStack(spacing: 16) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 48))
                        .foregroundStyle(.yellow)
                    Text("Playback Error")
                        .font(.title2.bold())
                        .foregroundStyle(.white)
                    Text(errorMessage)
                        .font(.body)
                        .foregroundStyle(.white.opacity(0.7))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                    Button("Close") { stopPlayback() }
                        .buttonStyle(.borderedProminent)
                        .padding(.top, 8)
                }
            } else if let playURL = vm.playURL {
                VLCVideoPlayer(
                    url: playURL, 
                    mediaOptions: [
                        "sub-track=-1",
                        "no-sub-autodetect-file",
                        "no-sub-autodetect-fuzzy",
                        "no-sub-margin",
                        "video-title-show=0"
                    ],
                    externalSubtitles: vm.externalSubtitles,
                    proxy: $vm.vlcProxy
                ) { seconds, duration in
                    guard !vm.isDraggingSlider else { return }
                    vm.currentPlaybackTime = seconds
                    vm.duration = duration
                    vm.updateActiveCues(at: seconds)
                    vm.checkIntroVisibility(currentTime: seconds)
                    
                    if let stats = vm.vlcProxy.stats {
                        let rawBitrate = max(stats.inputBitrate, stats.demuxBitrate)
                        vm.liveBitrate = rawBitrate
                        vm.lostFrames = stats.lostPictures
                    }
                } onStateUpdated: { state in
                    switch state {
                    case .opening:
                        if !vm.hasStartedPlaying {
                            vm.isLoading = true
                            vm.statusMessage = "Opening..."
                        }
                    case .buffering:
                        if !vm.hasStartedPlaying {
                            vm.isLoading = true
                            vm.statusMessage = "Buffering..."
                        }
                    case .playing:
                        vm.isPlaying = true
                        vm.hasStartedPlaying = true
                        vm.isLoading = false
                        vm.vlcProxy.setSubtitleScale(vm.subtitleScale)
                        
                        // Resume from requested position or last position
                        if let manualSeek = vm.seekToOnPlay {
                            LumeInfo("Resuming from manual position: \(manualSeek)s")
                            vm.vlcProxy.setSeconds(Duration.seconds(manualSeek))
                            vm.currentPlaybackTime = manualSeek
                            vm.seekToOnPlay = nil
                            vm.hasResumed = true
                        } else if resumePlayback && !vm.hasResumed {
                            if let ticks = resolvedItem.userData?.playbackPositionTicks, ticks > 0 {
                                let seconds = Double(ticks) / 10_000_000.0
                                LumeInfo("Resuming from saved position: \(seconds)s")
                                vm.vlcProxy.setSeconds(Duration.seconds(seconds))
                                vm.currentPlaybackTime = seconds
                            }
                            vm.hasResumed = true
                        }
                        
                        Task { await vm.loadTracksFromVLC(apiClient: session.apiClient, item: resolvedItem) }
                        if vm.lastReportedTime == -999.0 {
                            let ticks = Int64(vm.currentPlaybackTime * 10_000_000)
                            let startInfo = PlaybackStartInfo(
                                itemId: item.id ?? "",
                                mediaSourceId: vm.mediaSourceId,
                                positionTicks: ticks,
                                playSessionId: vm.playSessionId
                            )
                            Task { try? await session.apiClient.reportPlaybackStart(startInfo) }
                            vm.lastReportedTime = vm.currentPlaybackTime
                        }
                    case .paused:
                        vm.isPlaying = false
                        let ticks = Int64(vm.currentPlaybackTime * 10_000_000)
                        let progressInfo = PlaybackProgressInfo(
                            itemId: item.id ?? "",
                            mediaSourceId: vm.mediaSourceId,
                            positionTicks: ticks,
                            isPaused: true,
                            playSessionId: vm.playSessionId
                        )
                        Task { try? await session.apiClient.reportPlaybackProgress(progressInfo) }
                    case .ended:
                        stopPlayback()
                    case .error:
                        vm.isLoading = false
                        errorMessage = "VLC could not play this media. The server may not support direct play for this format."
                    default:
                        break
                    }
                }
                .ignoresSafeArea()
                .onAppear {
                    vm.vlcProxy.setSubtitleScale(vm.subtitleScale)
                    vm.vlcProxy.setSubtitleStyle(font: vm.subtitleFont, color: vm.subtitleColor, opacity: vm.subtitleBgOpacity)
                }
                .onChange(of: vm.subtitleScale) { _, newValue in
                    vm.vlcProxy.setSubtitleScale(newValue)
                    UserDefaults.standard.set(newValue, forKey: "subtitleScale")
                }
                .onChange(of: vm.subtitleColor) { _, n in
                    vm.vlcProxy.setSubtitleStyle(font: vm.subtitleFont, color: n, opacity: vm.subtitleBgOpacity)
                    UserDefaults.standard.set(n, forKey: "subtitleColor")
                }
                .onChange(of: vm.subtitleFont) { _, n in
                    vm.vlcProxy.setSubtitleStyle(font: n, color: vm.subtitleColor, opacity: vm.subtitleBgOpacity)
                    UserDefaults.standard.set(n, forKey: "subtitleFont")
                }
                .onChange(of: vm.subtitleBgOpacity) { _, n in
                    vm.vlcProxy.setSubtitleStyle(font: vm.subtitleFont, color: vm.subtitleColor, opacity: n)
                    UserDefaults.standard.set(n, forKey: "subtitleBgOpacity")
                }
                .zIndex(0)
                
                // Custom Subtitle Overlay
                SubtitleOverlay(cues: vm.activeCues, vm: vm)
                    .allowsHitTesting(false)
                    .padding(.bottom, vm.showControls ? 140 : 40)
                    .animation(nil, value: vm.showControls)
                    .animation(nil, value: vm.activeCues)
            }

            Color.black.opacity(0.001)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onContinuousHover { _ in
                    isFocused = true
                    triggerControls()
                }

                .onTapGesture {
                    withAnimation {
                        vm.showControls.toggle()
                        vm.lastMouseMovement = Date()
                    }
                }

            if errorMessage == nil {
                VStack {
                    topLiquidBar
                    Spacer()
                    bottomLiquidHUD
                }
                .contentShape(Rectangle())
                .opacity(vm.showControls || vm.isLoading ? 1 : 0)
                .animation(.spring(response: 0.5, dampingFraction: 0.8), value: vm.showControls)
                .pointerVisibility(
                    isPointerNeeded
                        ? LumePointerVisibility.visible
                        : LumePointerVisibility.hidden
                )
                
                VStack(alignment: .trailing, spacing: 12) {
                    Spacer()
                    
                    // Skip Intro / Credits Button
                    if vm.showSkipButton && skipIntroEnabled {
                        Button {
                            vm.skipSegment()
                        } label: {
                            Label(vm.currentSegment?.type.lowercased() == "outro" ? "Skip Credits" : "Skip Intro", systemImage: "forward.end.fill")
                                .font(.headline)
                                .padding(.horizontal, 24)
                                .padding(.vertical, 14)
                                .glassEffect(in: Capsule())
                                .shadow(color: .black.opacity(0.3), radius: 10)
                        }
                        .buttonStyle(.plain)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                .padding(.trailing, 40)
                .padding(.bottom, vm.showControls ? 210 : 60)
                .animation(.spring(response: 0.45, dampingFraction: 0.8), value: vm.showControls)
                .zIndex(10)
            }

            if vm.isLoading && errorMessage == nil {
                ZStack {
                    Color.black.opacity(0.8).ignoresSafeArea()
                    VStack(spacing: 24) {
                        ProgressView().controlSize(.large)
                        VStack(spacing: 8) {
                            Text(vm.statusMessage)
                                .font(.system(size: 16, weight: .bold, design: .rounded))
                                .foregroundStyle(.white)
                            Text("Preparing playback...")
                                .font(.system(size: 12, design: .rounded))
                                .foregroundStyle(.white.opacity(0.6))
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $showSubtitleSearch) {
            if let itemId = item.id {
                SubtitleSearchView(itemId: itemId) { url in
                    vm.vlcProxy.addSubtitle(url: url)
                    // Re-load tracks so the new one shows up in menu
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                        vm.tracksLoaded = false
                        Task { await vm.loadTracksFromVLC(apiClient: session.apiClient, item: resolvedItem) }
                    }
                }
            }
        }
        .task { await prepareAndPlay() }
        .onAppear {
            setupTimer()
            vm.setupFullscreenObserver()
            isFocused = true
        }
        .onDisappear { stopPlayback() }
        .focusable()
        .focusEffectDisabled()
        .focused($isFocused)
        .onKeyPress(.space) {
            togglePlay()
            return .handled
        }
        .onKeyPress { press in
            handleKeyPress(press)
        }
        .overlay {
            if vm.showInfo {
                mediaInfoOverlay
                    .offset(x: infoPosition.width + infoDragOffset.width, y: infoPosition.height + infoDragOffset.height)
                    .gesture(
                        DragGesture()
                            .updating($infoDragOffset) { value, state, _ in
                                state = value.translation
                            }
                            .onEnded { value in
                                infoPosition.width += value.translation.width
                                infoPosition.height += value.translation.height
                            }
                    )
                    .onContinuousHover { _ in triggerControls() }
            }
            if showSubtitleSettings {
                SubtitleSettingsModal(vm: vm, isPresented: $showSubtitleSettings)
                    .offset(x: captionPosition.width + captionDragOffset.width, y: captionPosition.height + captionDragOffset.height)
                    .gesture(
                        DragGesture()
                            .updating($captionDragOffset) { value, state, _ in
                                state = value.translation
                            }
                            .onEnded { value in
                                captionPosition.width += value.translation.width
                                captionPosition.height += value.translation.height
                            }
                    )
                    .onContinuousHover { _ in triggerControls() }
            }
        }
    }

    private var mediaInfoOverlay: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                overlayHeader(title: "Stream Intelligence", icon: "bolt.shield.fill") {
                    withAnimation { vm.showInfo = false }
                }

                playbackInfoSection
                Divider().opacity(0.1)
                videoPerformanceSection
                Divider().opacity(0.1)
                originalMediaSection
            }
            .padding(32)
        }
        .frame(width: 580)
        .frame(maxHeight: 650)
        .glassEffect(in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: .black.opacity(0.3), radius: 20)
        .transition(.asymmetric(
            insertion: .scale(scale: 0.95).combined(with: .opacity),
            removal: .scale(scale: 0.95).combined(with: .opacity)
        ))
    }

    @ViewBuilder
    private func overlayHeader(title: String, icon: String, onClose: @escaping () -> Void) -> some View {
        HStack {
            Label(title, systemImage: icon)
                .font(.system(size: 20, weight: .bold, design: .rounded))
            Spacer()
            Button(action: { withAnimation(.modalSpring) { onClose() } }) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
                    .font(.title3)
            }
            .buttonStyle(.plain)
        }
        .padding(.bottom, 4)
    }

    private var playbackInfoSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("PLAYBACK INFORMATION", color: .blue)
            Grid(alignment: .leading, horizontalSpacing: 40, verticalSpacing: 10) {
                GridRow {
                    infoItem(label: "Player", value: "Lume / LibVLC")
                    infoItem(label: "Play method", value: playMethod)
                }
                GridRow {
                    infoItem(label: "Protocol", value: vm.playURL?.scheme?.uppercased() ?? "HTTPS")
                    infoItem(label: "Stream type", value: "Video")
                }
            }
            
            HStack(spacing: 12) {
                Text(vm.playURL?.absoluteString ?? "N/A")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.5))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(.white.opacity(0.06))
                    .cornerRadius(8)
                
                Button {
                    let pb = NSPasteboard.general
                    pb.clearContents()
                    pb.setString(vm.playURL?.absoluteString ?? "N/A", forType: .string)
                } label: {
                    Label("Copy", systemImage: "doc.on.doc.fill")
                        .font(.system(size: 12, weight: .bold))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(.blue.opacity(0.15))
                        .foregroundStyle(.blue)
                        .cornerRadius(8)
                }
                .buttonStyle(.plain)
            }
            .padding(.top, 4)
        }
    }

    private var videoPerformanceSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("VIDEO PERFORMANCE", color: .orange)
            Grid(alignment: .leading, horizontalSpacing: 40, verticalSpacing: 10) {
                GridRow {
                    infoItem(label: "Window size", value: "\(Int(vm.vlcProxy.videoSize.width))x\(Int(vm.vlcProxy.videoSize.height))")
                    infoItem(label: "Resolution", value: streamResolution)
                }
                GridRow {
                    infoItem(label: "Dropped frames", value: "\(vm.lostFrames)")
                    infoItem(label: "Live bitrate", value: formatLiveBitrate(vm.liveBitrate))
                }
            }
        }
    }

    private var originalMediaSection: some View {
        Group {
            if let source = resolvedItem.mediaSources?.first(where: { $0.id == vm.mediaSourceId }) ?? resolvedItem.mediaSources?.first {
                let streams = source.mediaStreams ?? []
                let audioStream = streams.first(where: { $0.type == "Audio" && ($0.index ?? -1) == vm.selectedAudioIndex }) ?? streams.first(where: { $0.type == "Audio" })
                VStack(alignment: .leading, spacing: 12) {
                    sectionHeader("ORIGINAL MEDIA SPECIFICATIONS", color: .green)
                    Grid(alignment: .leading, horizontalSpacing: 40, verticalSpacing: 10) {
                        GridRow {
                            infoItem(label: "Container", value: source.container?.uppercased() ?? "MKV")
                            infoItem(label: "Total size", value: formatSize(source.size))
                        }
                        GridRow {
                            infoItem(label: "Nominal bitrate", value: formatBitrate(source.bitrate))
                            if let video = streams.first(where: { $0.type == "Video" }) {
                                infoItem(label: "Video codec", value: video.codec?.uppercased() ?? "H264")
                            }
                        }
                        if let audio = audioStream {
                            GridRow {
                                infoItem(label: "Audio codec", value: audio.codec?.uppercased() ?? "AAC")
                                infoItem(label: "Audio channels", value: "\(audio.channels ?? 2)")
                            }
                            GridRow {
                                infoItem(label: "Audio bitrate", value: formatBitrate(audio.bitRate))
                                infoItem(label: "Container", value: source.container?.uppercased() ?? "MKV")
                            }
                        }
                    }
                }
            }
        }
    }

    private func sectionHeader(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(color)
    }

    private func infoItem(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.white.opacity(0.4))
            Text(value)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.9))
        }
    }
    
    private var playMethod: String {
        if vm.playURL?.isFileURL == true { return "Direct Play (Local)" }
        let url = vm.playURL?.absoluteString ?? ""
        if url.contains("static=true") { return "Direct Play" }
        if url.contains("transcoding") || url.contains("Transcode") { return "Transcoding" }
        return "Direct Stream"
    }
    
    private var streamResolution: String {
        guard let source = resolvedItem.mediaSources?.first(where: { $0.id == vm.mediaSourceId }) ?? resolvedItem.mediaSources?.first,
              let video = source.mediaStreams?.first(where: { $0.type == "Video" }) else { return "Unknown" }
        return "\(video.width ?? 0)x\(video.height ?? 0)"
    }
    
    private func formatSize(_ bytes: Int64?) -> String {
        guard let bytes else { return "Unknown" }
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useAll]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
    
    private func formatBitrate(_ bps: Int?) -> String {
        guard let unwrapped = bps else { return "Unknown" }
        return String(format: "%.1f Mbps", Double(unwrapped) / 1_000_000.0)
    }

    private var nominalBitrateText: String {
        guard let source = resolvedItem.mediaSources?.first(where: { $0.id == vm.mediaSourceId }) ?? resolvedItem.mediaSources?.first,
              let bitrate = source.bitrate else { return "Unknown" }
        return String(format: "%.2f Mbps", Double(bitrate) / 1_000_000.0)
    }

    private func infoRow(label: String, value: String, mono: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label.uppercased())
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 12, design: mono ? .monospaced : .default))
                .foregroundStyle(.primary)
                .lineLimit(mono ? nil : 2) // URL stays expanded
                .textSelection(.enabled)
        }
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            let pb = NSPasteboard.general
            pb.clearContents()
            pb.setString(value, forType: .string)
        }
    }

    private func prepareAndPlay(resumeAt: Double? = nil) async {
        guard let itemId = item.id else {
            errorMessage = "Invalid item — no ID"
            return
        }

        vm.isLoading = true
        vm.statusMessage = "Checking local storage..."
        errorMessage = nil
        
        if let resumeAt {
            vm.seekToOnPlay = resumeAt
        }

        // 1. Check for local download
        if let localURL = session.downloadManager.getLocalURL(for: itemId) {
            LumeDebug("Playing local file: \(localURL.path)")
            vm.playURL = localURL
            vm.isLoading = false
            vm.hasStartedPlaying = true
            return
        }

        vm.statusMessage = "Fetching media info..."
        
        vm.cachedBaseURL = await session.apiClient.getBaseURL()
        vm.cachedToken = await session.apiClient.getAccessToken()
        
        // Load trickplay manifest if available
        Task { await vm.loadTrickplay(apiClient: session.apiClient, itemId: itemId) }
        
        // Load Intro Skipper data
        Task {
            await vm.loadIntros(apiClient: session.apiClient, itemId: itemId)
            await vm.loadSiblings(apiClient: session.apiClient, item: resolvedItem)
        }

        if fullItem == nil || fullItem?.mediaSources == nil {
            do {
                fullItem = try await session.apiClient.getItem(itemId: itemId)
            } catch {
                LumeError("Failed to fetch item details: \(error)")
            }
        }
        
        // NOW PRE-COLLECT SUBTITLES WITH RICH DATA
        vm.externalSubtitles = await vm.getExternalSubtitles(apiClient: session.apiClient, item: resolvedItem)

        let base = await session.apiClient.getBaseURL()
        let token = await session.apiClient.getAccessToken()
        let mediaSourceId = resolvedItem.mediaSources?.first?.id

        let preferDirectPlay = UserDefaults.standard.bool(forKey: "preferDirectPlay")
        let maxBitrateMbps = UserDefaults.standard.integer(forKey: "maxStreamingBitrate")
        // If 0 or 140, treat as "Auto/Highest"
        let maxBitrate = (maxBitrateMbps == 0 || maxBitrateMbps == 140) ? 140_000_000 : (maxBitrateMbps * 1_000_000)
        let effectiveBitrate = preferDirectPlay ? 140_000_000 : maxBitrate
        
        let preferredSubLang = UserDefaults.standard.string(forKey: "preferredSubLanguage") ?? "eng"
        let defaultSubIndex = resolvedItem.mediaSources?.first?.mediaStreams?.first(where: { 
            $0.type == "Subtitle" && ($0.language == preferredSubLang || $0.language == "und")
        })?.index
        
        var subIndex: Int? = nil
        if vm.userSelectedSubtitleIndex != -1 && vm.userSelectedSubtitleIndex != -999 {
            subIndex = vm.userSelectedSubtitleIndex
        } else if UserDefaults.standard.bool(forKey: "defaultSubtitlesOn") {
            subIndex = defaultSubIndex
        }
        
        // Load custom subtitle parser data
        if let effectiveIdx = subIndex {
            Task { await vm.loadJellyfinSubtitles(apiClient: session.apiClient, item: resolvedItem, index: effectiveIdx) }
        }

        vm.statusMessage = "Negotiating stream..."
        do {
            let info = try await session.apiClient.getPlaybackInfo(
                itemId: itemId,
                mediaSourceId: mediaSourceId,
                audioStreamIndex: nil,
                subtitleStreamIndex: nil, // Never burn subtitles on server
                maxBitrate: effectiveBitrate,
                allowDirectPlay: preferDirectPlay
            )

            if let source = info.mediaSources?.first {
                // If user prefers direct play, we try direct methods first
                if preferDirectPlay {
                    if source.supportsDirectPlay == true {
                        let sourceId = source.id ?? mediaSourceId ?? itemId
                        if item.type == "Channel" || item.type == "TvChannel" {
                            vm.playURL = await session.apiClient.streamURL(itemId: itemId, mediaSourceId: sourceId, maxBitrate: effectiveBitrate)
                            LumeInfo("Using HLS Live channel stream: \(vm.playURL?.absoluteString ?? "")")
                        } else {
                            var directPlayURL = "\(base)/Videos/\(itemId)/stream?static=true&MediaSourceId=\(sourceId)"
                            if let token { directPlayURL += "&api_key=\(token)" }
                            LumeInfo("Using direct play: \(directPlayURL)")
                            vm.playURL = URL(string: directPlayURL)
                        }
                        vm.playSessionId = info.playSessionId
                        vm.mediaSourceId = source.id
                        return
                    }
                    
                    if source.supportsDirectStream == true,
                       let directURL = source.directStreamUrl {
                        let fullURL = base + directURL
                        LumeInfo("Using direct stream: \(fullURL)")
                        vm.playURL = URL(string: fullURL)
                        vm.playSessionId = info.playSessionId
                        vm.mediaSourceId = source.id
                        return
                    }
                }

                // If Transcoding is available or Direct Play is OFF/unsupported, use it
                if let transURL = source.transcodingUrl {
                    let fullURL = base + transURL
                    LumeInfo("Using transcode stream: \(fullURL)")
                    vm.playURL = URL(string: fullURL)
                    vm.playSessionId = info.playSessionId
                    vm.mediaSourceId = source.id
                    return
                }
                
                if !preferDirectPlay {
                   let transURL = await session.apiClient.streamURL(
                       itemId: itemId, 
                       mediaSourceId: source.id, 
                       subtitleStreamIndex: nil, // Never burn subtitles on server
                       maxBitrate: effectiveBitrate
                   )
                   LumeInfo("Forcing transcoding HLS fallback: \(transURL?.absoluteString ?? "N/A")")
                   vm.playURL = transURL
                   vm.playSessionId = info.playSessionId
                   vm.mediaSourceId = source.id
                   return
                }
            }
        } catch {
            LumeDebug("PlaybackInfo failed: \(error). Falling back to direct stream URL.")
        }

        vm.statusMessage = "Using fallback stream..."
        let sourceId = mediaSourceId ?? itemId
        vm.mediaSourceId = sourceId
        
        if !preferDirectPlay || item.type == "Channel" || item.type == "TvChannel" {
            vm.playURL = await session.apiClient.streamURL(
                itemId: itemId, 
                mediaSourceId: sourceId, 
                subtitleStreamIndex: nil, // Never burn subtitles on server
                maxBitrate: effectiveBitrate
            )
            LumeInfo("Using HLS fallback: \(vm.playURL?.absoluteString ?? "")")
        } else {
            var fallbackURL = "\(base)/Videos/\(itemId)/stream?static=true&MediaSourceId=\(sourceId)"
            if let token { fallbackURL += "&api_key=\(token)" }
            LumeInfo("Using direct play fallback: \(fallbackURL)")
            vm.playURL = URL(string: fallbackURL)
        }
    }
    
    private func togglePlay() {
        vm.vlcProxy.togglePlay()
        triggerControls()
        // Optimistic update for UI feel
        vm.isPlaying.toggle()
    }

    private func triggerControls() {
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            vm.showControls = true
            vm.lastMouseMovement = Date()
        }
    }

    private func setupTimer() {
        Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            if Date().timeIntervalSince(vm.lastMouseMovement) > 4.0 && !vm.isDraggingSlider {
                withAnimation(.easeInOut(duration: 0.8)) { vm.showControls = false }
            }
            // Retry loading tracks if not loaded yet (VLC sometimes needs a moment)
            if vm.hasStartedPlaying && !vm.tracksLoaded {
                Task { await vm.loadTracksFromVLC(apiClient: session.apiClient, item: resolvedItem) }
            }
            
            // Periodically report progress (every 10 seconds)
            if vm.hasStartedPlaying && 
               abs(vm.currentPlaybackTime - vm.lastReportedTime) >= 10.0 {
                let ticks = Int64(vm.currentPlaybackTime * 10_000_000)
                let progressInfo = PlaybackProgressInfo(
                    itemId: item.id ?? "",
                    mediaSourceId: vm.mediaSourceId,
                    positionTicks: ticks,
                    isPaused: false,
                    playSessionId: vm.playSessionId
                )
                Task { try? await session.apiClient.reportPlaybackProgress(progressInfo) }
                vm.lastReportedTime = vm.currentPlaybackTime
            }
        }
    }

    private var topLiquidBar: some View {
        HStack(spacing: 20) {

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    if item.type == "Episode", let seriesName = item.seriesName {
                        Text(seriesName)
                            .foregroundStyle(.white.opacity(0.8))
                        Text(":")
                            .foregroundStyle(.white.opacity(0.4))
                    }
                    Text(item.displayName)
                        .foregroundStyle(.white)
                }
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .shadow(radius: 4)

                if let year = item.productionYear {
                    Text(String(year))
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.7))
                } else if item.type == "Channel" || item.type == "TvChannel" {
                    Text("Live")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(.red)
                }
            }
            Spacer()
                if vm.vlcAudioTracks.count > 1 {
                    liquidMenu(label: "Audio", icon: "speaker.wave.2") { audioMenu }
                }
                
                // Consolidated Captions Pill
                HStack(spacing: 0) {
                    liquidMenuButton(label: "Captions", icon: "captions.bubble") { subtitleMenu }
                    
                    if vm.userSelectedSubtitleIndex != -1 {
                        Divider().frame(height: 20).background(.white.opacity(0.12)).padding(.horizontal, 4)
                        
                        Button { withAnimation(.modalSpring) { showSubtitleSettings = true } } label: {
                            Image(systemName: "textformat.size")
                                .font(.system(size: 15, weight: .bold))
                                .padding(.horizontal, 14)
                                .padding(.vertical, 10)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .help("Subtitle Styling")
                    }
                }
                .glassEffect(in: Capsule())
                
                Button { toggleFullscreen() } label: {
                    Image(systemName: vm.isFullscreen ? "arrow.down.right.and.arrow.up.left" : "viewfinder")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(14)
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .glassEffect(in: Capsule())
                .help(vm.isFullscreen ? "Exit Fullscreen" : "Full Screen")

                Button { withAnimation(.modalSpring) { vm.showInfo.toggle() } } label: {
                    Image(systemName: "info.circle")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(14)
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .glassEffect(in: Capsule())
                .help("Media Information")
            }
            .padding(.horizontal, 30)
            .padding(.top, 40)
            .background(
                LinearGradient(colors: [.black.opacity(0.8), .clear], startPoint: .top, endPoint: .bottom)
                    .ignoresSafeArea()
            )
        }

    private var bottomLiquidHUD: some View {
        VStack(spacing: 30) {
            VStack(spacing: 12) {
                if item.type != "Channel" && item.type != "TvChannel" {
                    HStack {
                        Text(formatTime(vm.currentPlaybackTime))
                            .font(.system(size: 13, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.9))
                        Spacer()
                        Text(formatTime(vm.duration))
                            .font(.system(size: 13, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.9))
                    }
                    .padding(.horizontal, 4)

                    ModernScrubber(vm: vm, item: resolvedItem)
                } else {
                    HStack {
                        Circle()
                            .fill(.red)
                            .frame(width: 8, height: 8)
                        Text("LIVE")
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                        Spacer()
                    }
                    .padding(.horizontal, 4)
                }
            }
            .padding(.horizontal, 30)

            ZStack {
                HStack(spacing: 30) {
                    if resolvedItem.type == "Episode", let prev = vm.previousItem {
                        Button {
                            stopPlayback()
                            session.activeVideoItem = prev
                        } label: {
                            Image(systemName: "backward.end.fill")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(.white)
                                .padding(14)
                                .contentShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .glassEffect(in: Circle())
                    }

                    HStack(spacing: 20) {
                        Button { vm.currentPlaybackTime = vm.vlcProxy.jumpBackward(Duration.seconds(10)) } label: {
                            Image(systemName: "gobackward.10")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(.white)
                                .frame(width: 32, height: 32)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)

                        Button { togglePlay() } label: {
                            Image(systemName: vm.isPlaying ? "pause.fill" : "play.fill")
                                .font(.system(size: 22))
                                .foregroundStyle(.white)
                                .shadow(color: .white.opacity(0.3), radius: 6)
                                .frame(width: 48, height: 48)
                                .contentShape(Circle())
                        }
                        .buttonStyle(.plain)

                        Button { vm.currentPlaybackTime = vm.vlcProxy.jumpForward(Duration.seconds(10)) } label: {
                            Image(systemName: "goforward.10")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(.white)
                                .frame(width: 32, height: 32)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 22)
                    .padding(.vertical, 8)
                    .glassEffect(in: Capsule())

                    if resolvedItem.type == "Episode", let next = vm.nextItem {
                        Button {
                            stopPlayback()
                            session.activeVideoItem = next
                        } label: {
                            Image(systemName: "forward.end.fill")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(.white)
                                .padding(14)
                                .contentShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .glassEffect(in: Circle())
                    }
                }
                
                HStack {
                    Spacer()
                    
                    if vm.playURL?.isFileURL == false && 
                       item.type != "Channel" && 
                       item.type != "TvChannel" && 
                       !UserDefaults.standard.bool(forKey: "preferDirectPlay") {
                        qualityMenu
                            .padding(.trailing, 8)
                    }
                    
                    HStack(spacing: 0) {
                        Button {
                            if vm.volume > 0 {
                                vm.lastVolume = vm.volume
                                vm.volume = 0
                            } else {
                                vm.volume = vm.lastVolume > 0 ? vm.lastVolume : 100
                            }
                        } label: {
                            Image(systemName: vm.volume == 0 ? "speaker.slash.fill" : (vm.volume < 40 ? "speaker.1.fill" : "speaker.3.fill"))
                                .font(.system(size: 14))
                                .foregroundStyle(.white)
                                .frame(width: 32)
                        }
                        .buttonStyle(.plain)

                        LiquidSlider(value: Binding(
                            get: { Double(vm.volume) },
                            set: { vm.volume = Int32($0) }
                        ), range: 0...100)
                        .frame(width: 100)
                    }
                    .padding(10)
                    .glassEffect(in: Capsule())
                }
                .padding(.trailing, 30)
            }
        }
        .padding(.bottom, 60)
        .background(
            LinearGradient(colors: [.clear, .black.opacity(0.9)], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
        )
    }

    private func liquidMenuButton<Content: View>(label: String, icon: String, @ViewBuilder menu: () -> Content) -> some View {
        Menu { menu() } label: {
            HStack(spacing: 8) {
                Image(systemName: icon)
                Text(label).font(.system(size: 14, weight: .semibold, design: .rounded))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func liquidMenu<Content: View>(label: String, icon: String, @ViewBuilder menu: () -> Content) -> some View {
        Menu { menu() } label: {
            HStack(spacing: 8) {
                Image(systemName: icon)
                Text(label).font(.system(size: 14, weight: .semibold, design: .rounded))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .contentShape(Capsule())
            .glassEffect(in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private var isPointerNeeded: Bool {
        if vm.isLoading || !vm.hasStartedPlaying || !vm.isFullscreen { return true }
        if vm.showControls || showSubtitleSearch || showSubtitleSettings || vm.showInfo { return true }
        return false
    }

    @ViewBuilder
    private var audioMenu: some View {
        ForEach(vm.vlcAudioTracks) { track in
            Button {
                vm.selectedAudioIndex = track.index
                vm.vlcProxy.setAudioTrack(track.index)
            } label: {
                HStack {
                    Text(track.name)
                    if track.index == vm.selectedAudioIndex {
                        Spacer()
                        Image(systemName: "checkmark")
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var subtitleMenu: some View {
        Button {
            vm.userSelectedSubtitleIndex = -1
            Task { await vm.loadJellyfinSubtitles(apiClient: session.apiClient, item: resolvedItem, index: -1) }
        } label: {
            HStack {
                Text("Off")
                if vm.userSelectedSubtitleIndex == -1 {
                    Spacer()
                    Image(systemName: "checkmark")
                }
            }
        }

        Divider()

        if let streams = resolvedItem.mediaSources?.first?.mediaStreams?.filter({ $0.type == "Subtitle" }), !streams.isEmpty {
            Section("Subtitles") {
                ForEach(streams, id: \.index) { stream in
                    let idx = stream.index ?? -1
                    Button {
                        vm.userSelectedSubtitleIndex = idx
                        Task { await vm.loadJellyfinSubtitles(apiClient: session.apiClient, item: resolvedItem, index: idx) }
                    } label: {
                        HStack {
                            Text(stream.displayTitle ?? "Subtitle \(idx)")
                            if vm.userSelectedSubtitleIndex == idx {
                                Spacer()
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            }
            Divider()
        }

        Button {
            showSubtitleSearch = true
        } label: {
            Label("Download Subtitles...", systemImage: "arrow.down.circle")
        }
    }

    private func updateSize(_ size: Int) {
        vm.subtitleScale = size
        UserDefaults.standard.set(size, forKey: "subtitleScale")
    }

    private func formatTime(_ seconds: Double) -> String {
        guard !seconds.isNaN else { return "0:00" }
        let h = Int(seconds) / 3600
        let m = (Int(seconds) % 3600) / 60
        let s = Int(seconds) % 60
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, s) }
        return String(format: "%d:%02d", m, s)
    }

    private var qualityLabel: String {
        let mbps = UserDefaults.standard.integer(forKey: "maxStreamingBitrate")
        if mbps == 0 || mbps >= 140 { return "Auto" }
        return "\(mbps) Mbps"
    }
    
    private func formatLiveBitrate(_ bitrate: Float) -> String {
        guard bitrate > 0 else { return "0.00 Mbps" }
        
        // VLC stats usually return bits/s. If it's already Mbps (e.g. < 100), handle that.
        if bitrate < 100 {
            return String(format: "%.2f Mbps", bitrate)
        }
        
        // Convert bits/s to Mbps
        return String(format: "%.2f Mbps", Double(bitrate) / 1_000_000.0)
    }

    @ViewBuilder
    private var qualityMenu: some View {
        Menu {
            Button("Auto / Max") { setQuality(0) }
            Divider()
            Group {
                Button("1080p 20 Mbps") { setQuality(20) }
                Button("1080p 15 Mbps") { setQuality(15) }
                Button("1080p 10 Mbps") { setQuality(10) }
                Button("720p 6 Mbps") { setQuality(6) }
                Button("720p 4 Mbps") { setQuality(4) }
                Button("480p 2 Mbps") { setQuality(2) }
                Button("360p 1 Mbps") { setQuality(1) }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 14))
                Text(qualityLabel)
                    .font(.system(size: 12, weight: .bold, design: .rounded))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .contentShape(Capsule())
            .glassEffect(in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private func setQuality(_ mbps: Int) {
        UserDefaults.standard.set(mbps, forKey: "maxStreamingBitrate")
        let currentPos = vm.currentPlaybackTime
        vm.vlcProxy.stop()
        vm.tracksLoaded = false
        vm.hasResumed = false
        Task {
            await prepareAndPlay(resumeAt: currentPos)
        }
    }

    private func stopPlayback() {
        guard let itemId = item.id else { return }
        let ticks = Int64(vm.currentPlaybackTime * 10_000_000)
        let stopInfo = PlaybackStopInfo(
            itemId: itemId, 
            mediaSourceId: vm.mediaSourceId, 
            positionTicks: ticks, 
            playSessionId: vm.playSessionId
        )
        Task { try? await session.apiClient.reportPlaybackStopped(stopInfo) }
        vm.cleanup()
        if session.activeVideoItem?.id == item.id {
            withAnimation { session.activeVideoItem = nil }
            dismissWindow(id: "video-player")
        }
    }

    private func toggleFullscreen() {
        // High-precision window lookup:
        // 1. The key window (where the user interaction actually happened)
        // 2. The window with our dedicated 'video-player' ID or title
        // 3. The main window as a final fallback
        let candidates = [
            NSApp.keyWindow,
            NSApp.windows.first { $0.isVisible && ($0.identifier?.rawValue.contains("video-player") == true || $0.title == "Video Player") },
            NSApp.mainWindow
        ].compactMap { $0 }
        
        // We MUST ensure we don't accidentally toggle the main navigation window (titled "Lume")
        // unless it's literally the only window available.
        guard let window = candidates.first(where: { $0.title != "Lume" }) ?? candidates.first else {
            LumeError("Could not find any window to toggle fullscreen")
            return
        }
        
        // Ensure the window has the proper flags to enter native macOS fullscreen spaces
        if !window.collectionBehavior.contains(.fullScreenPrimary) {
            window.collectionBehavior.insert(.fullScreenPrimary)
        }
        
        // Re-enable the zoom button if it was hidden (requirement for some System Fullscreen behaviors)
        window.standardWindowButton(.zoomButton)?.isHidden = false
        
        // Native macOS Fullscreen transition - this moves the app to its own separate Space/Desktop
        window.toggleFullScreen(nil)
        
        // Manual sync for isFullscreen state
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            vm.isFullscreen = window.styleMask.contains(.fullScreen)
        }
    }

    private func handleKeyPress(_ press: KeyPress) -> KeyPress.Result {
        switch press.key {
        case .leftArrow, .init("j"), .init("J"):
            vm.currentPlaybackTime = vm.vlcProxy.jumpBackward(Duration.seconds(10))
            triggerControls()
            return .handled
        case .rightArrow, .init("l"), .init("L"):
            vm.currentPlaybackTime = vm.vlcProxy.jumpForward(Duration.seconds(10))
            triggerControls()
            return .handled
        case .init("f"), .init("F"):
            toggleFullscreen()
            return .handled
        case .init("m"), .init("M"):
            vm.vlcProxy.toggleMute()
            triggerControls()
            return .handled
        case .init("k"), .init("K"):
            vm.vlcProxy.togglePlay()
            triggerControls()
            return .handled
        case .escape:
            if let window = NSApplication.shared.keyWindow,
               window.styleMask.contains(.fullScreen) {
                window.toggleFullScreen(nil)
                return .handled
            }
            return .ignored
        case .upArrow:
            vm.volume = min(200, vm.volume + 5)
            triggerControls()
            return .handled
        case .downArrow:
            vm.volume = max(0, vm.volume - 5)
            triggerControls()
            return .handled
        default:
            return .ignored
        }
    }
}

struct ModernScrubber: View {
    @Environment(SessionManager.self) private var session
    @AppStorage("enableSeekPreviews") private var enableSeekPreviews = true
    @Bindable var vm: PlayerViewModel
    let item: BaseItemDto
    @State private var isHovering = false
    @State private var hoverLocation: CGFloat = 0

    var body: some View {
        GeometryReader { geo in
            let progress = max(0, min(1, CGFloat(vm.currentPlaybackTime / max(vm.duration, 1))))
            let bufferProgress = max(0, min(1, CGFloat(vm.bufferedTime / max(vm.duration, 1))))
            
            // Fixed coordinate mapping: Ensure drag position is perfectly relative to bar width
            let currentDragPos = progress * geo.size.width
            let dragLocX = min(max(0, vm.isDraggingSlider ? currentDragPos : hoverLocation), geo.size.width)
            let hoverTime = Double(dragLocX / max(geo.size.width, 1)) * vm.duration
            let showPreviewImage = enableSeekPreviews && vm.trickplayManifest != nil
            let previewYOffset: CGFloat = showPreviewImage ? -125 : -40

            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.15))
                    .frame(height: isHovering || vm.isDraggingSlider ? 8 : 4)

                Capsule().fill(.white.opacity(0.35))
                    .frame(width: geo.size.width * bufferProgress, height: isHovering || vm.isDraggingSlider ? 8 : 4)

                Capsule().fill(.white)
                    .frame(width: geo.size.width * progress, height: isHovering || vm.isDraggingSlider ? 8 : 4)
                    .shadow(color: .white.opacity(0.4), radius: 6)
                    .overlay(alignment: .trailing) {
                        Circle().fill(.white)
                            .frame(width: 16, height: 16)
                            .shadow(radius: 4)
                            .scaleEffect(isHovering || vm.isDraggingSlider ? 1.2 : 0.001)
                            .opacity(isHovering || vm.isDraggingSlider ? 1 : 0)
                            .offset(x: 8)
                    }

                if isHovering || vm.isDraggingSlider {
                    let previewTime = vm.isDraggingSlider ? vm.currentPlaybackTime : hoverTime
                    
                    VStack(spacing: 8) {
                        // Trickplay Image Preview
                        if enableSeekPreviews,
                           let manifest = vm.trickplayManifest,
                           let itemId = vm.mediaSourceId ?? item.id {
                            let interval = Double(manifest.interval) / 1000.0
                            let index = Int(previewTime / max(interval, 1.0))
                            
                            AsyncImage(url: vm.getTrickplayURL(itemId: itemId, index: index)) { image in
                                image.resizable()
                                    .aspectRatio(contentMode: .fill)
                            } placeholder: {
                                Color.black.overlay(ProgressView().scaleEffect(0.5))
                            }
                            .frame(width: 160, height: 90)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                            .overlay(RoundedRectangle(cornerRadius: 10).stroke(.white.opacity(0.15), lineWidth: 1))
                            .shadow(color: .black.opacity(0.3), radius: 10)
                        }
                        
                        Text(formatTime(previewTime))
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .glassEffect(in: RoundedRectangle(cornerRadius: 8))
                            .shadow(color: .black.opacity(0.2), radius: 6)
                    }
                    .offset(x: min(max(0, dragLocX - 80), geo.size.width - 160), y: previewYOffset)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .animation(.interactiveSpring(response: 0.3, dampingFraction: 0.8), value: isHovering)
            .animation(.interactiveSpring(response: 0.3, dampingFraction: 0.8), value: vm.isDraggingSlider)
            .contentShape(Rectangle())
            .onHover { hovering in isHovering = hovering }
            .onContinuousHover { phase in
                switch phase {
                case .active(let location): hoverLocation = location.x
                case .ended: break
                }
            }
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        vm.isDraggingSlider = true
                        hoverLocation = value.location.x
                        let percent = max(0, min(1, value.location.x / geo.size.width))
                        vm.currentPlaybackTime = Double(percent) * vm.duration
                    }
                    .onEnded { value in
                        let percent = max(0, min(1, value.location.x / geo.size.width))
                        let targetTime = Double(percent) * vm.duration
                        vm.vlcProxy.setSeconds(Duration.seconds(targetTime))
                        vm.isDraggingSlider = false
                    }
            )
        }
        .frame(height: 30)
    }

    private func formatTime(_ seconds: Double) -> String {
        guard !seconds.isNaN else { return "0:00" }
        let h = Int(seconds) / 3600
        let m = (Int(seconds) % 3600) / 60
        let s = Int(seconds) % 60
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, s) }
        return String(format: "%d:%02d", m, s)
    }
}

struct SubtitleOverlay: View {
    let cues: [SubtitleCue]
    let vm: PlayerViewModel
    
    var body: some View {
        VStack {
            Spacer()
            ForEach(cues) { cue in
                Text(cue.text)
                    .font(subtitleFont(size: CGFloat(vm.subtitleScale)))
                    .foregroundStyle(Color(hex: vm.subtitleColor))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(
                        Color.black.opacity(vm.subtitleBgOpacity)
                    )
                    .cornerRadius(8)
                    .shadow(color: .black, radius: 1)
                    .shadow(color: .black, radius: 1)
                    .shadow(color: .black, radius: 1)
                    .shadow(color: .black, radius: 2)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.bottom, 20)
    }

    private func subtitleFont(size: CGFloat) -> Font {
        switch vm.subtitleFont {
        case "Rounded": return .system(size: size, weight: .bold, design: .rounded)
        case "Mono": return .system(size: size, weight: .bold, design: .monospaced)
        case "Serif": return .system(size: size, weight: .bold, design: .serif)
        case "Roboto", "Outfit", "Inter":
            return .custom(vm.subtitleFont, size: size).bold()
        default:
            return .system(size: size, weight: .bold)
        }
    }
}

// MARK: - Custom Subtitle Engine

public struct SubtitleCue: Identifiable, Equatable, Sendable {
    public let id = UUID()
    public let startTime: Double
    public let endTime: Double
    public let text: String
    
    public init(startTime: Double, endTime: Double, text: String) {
        self.startTime = startTime
        self.endTime = endTime
        self.text = text
    }
}

public enum SubtitleParser {
    
    /// Entry point for parsing subtitle files. Infers format from content.
    public static func parse(_ content: String) -> [SubtitleCue] {
        if content.contains("WEBVTT") {
            return parseVTT(content)
        } else {
            return parseSRT(content)
        }
    }
    
    public static func parseSRT(_ srtContent: String) -> [SubtitleCue] {
        var cues: [SubtitleCue] = []
        let normalized = srtContent.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        let blocks = normalized.components(separatedBy: "\n\n")
        
        for block in blocks {
            let lines = block.components(separatedBy: .newlines).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            guard lines.count >= 2 else { continue }
            
            // Check if first line is index or timing
            var timingLine = ""
            var textStartIndex = 0
            
            if lines[0].contains(" --> ") {
                timingLine = lines[0]
                textStartIndex = 1
            } else if lines.count >= 3 && lines[1].contains(" --> ") {
                timingLine = lines[1]
                textStartIndex = 2
            } else {
                continue
            }
            
            let timings = timingLine.components(separatedBy: " --> ")
            guard timings.count == 2 else { continue }
            
            let start = parseTime(timings[0])
            let end = parseTime(timings[1])
            
            let text = lines[textStartIndex...].joined(separator: "\n")
                .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression) // Strip HTML tags like <i>, <b>, etc.
                .trimmingCharacters(in: .whitespacesAndNewlines)
            
            if !text.isEmpty {
                cues.append(SubtitleCue(startTime: start, endTime: end, text: text))
            }
        }
        
        return cues.sorted { $0.startTime < $1.startTime }
    }
    
    public static func parseVTT(_ vttContent: String) -> [SubtitleCue] {
        var cues: [SubtitleCue] = []
        let normalized = vttContent.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        let lines = normalized.components(separatedBy: .newlines)
        
        var currentStart: Double?
        var currentEnd: Double?
        var currentText = ""
        
        for line in lines {
            let cleanLine = line.trimmingCharacters(in: .whitespaces)
            if cleanLine.contains(" --> ") {
                if let s = currentStart, let e = currentEnd, !currentText.isEmpty {
                    cues.append(SubtitleCue(startTime: s, endTime: e, text: currentText.trimmingCharacters(in: .whitespacesAndNewlines)))
                }
                
                let timings = cleanLine.components(separatedBy: " --> ")
                
                let endPart = timings[1].components(separatedBy: .whitespaces).first ?? timings[1]
                
                currentStart = parseTime(timings[0])
                currentEnd = parseTime(endPart)
                currentText = ""
            } else if !cleanLine.isEmpty && 
                        !cleanLine.hasPrefix("WEBVTT") && 
                        !cleanLine.hasPrefix("NOTE") && 
                        !cleanLine.hasPrefix("STYLE") && 
                        !cleanLine.hasPrefix("REGION") {
                if currentStart != nil {
                    currentText += (currentText.isEmpty ? "" : "\n") + cleanLine
                }
            }
        }
        
        // Add final cue
        if let s = currentStart, let e = currentEnd, !currentText.isEmpty {
            cues.append(SubtitleCue(startTime: s, endTime: e, text: currentText.trimmingCharacters(in: .whitespacesAndNewlines)))
        }
        
        return cues.sorted { $0.startTime < $1.startTime }
    }
    
    private static func parseTime(_ timeString: String) -> Double {
        let clean = timeString.replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespaces)
        let parts = clean.split(separator: ":")
        
        if parts.count == 3 {
            let h = Double(parts[0]) ?? 0
            let m = Double(parts[1]) ?? 0
            let s = Double(parts[2]) ?? 0
            return (h * 3600) + (m * 60) + s
        } else if parts.count == 2 {
            let m = Double(parts[0]) ?? 0
            let s = Double(parts[1]) ?? 0
            return (m * 60) + s
        } else {
            return Double(clean) ?? 0
        }
    }
}



struct SubtitleSettingsModal: View {
    @Bindable var vm: PlayerViewModel
    @Binding var isPresented: Bool

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Subtitle Configuration")
                            .font(.system(size: 20, weight: .bold, design: .rounded))
                        Text("Fine-tune your visual experience")
                            .font(.system(size: 12, design: .rounded))
                            .foregroundStyle(.white.opacity(0.5))
                    }
                    Spacer()
                    Button { withAnimation(.modalSpring) { isPresented = false } } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title2)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.bottom, 10)

                VStack(alignment: .leading, spacing: 20) {
                    // Offset Setting
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Label("Synchronization Offset", systemImage: "clock.arrow.2.circlepath")
                                .font(.headline)
                                .fontDesign(.rounded)
                            Spacer()
                            Text("\(String(format: "%.1f", vm.subtitleOffset))s")
                                .font(.system(.body, design: .monospaced))
                                .foregroundStyle(.blue)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(.blue.opacity(0.1))
                                .cornerRadius(6)
                        }
                        
                        HStack(spacing: 15) {
                            Button { vm.subtitleOffset -= 0.1 } label: { Image(systemName: "minus.circle.fill").font(.title3) }
                            Slider(value: $vm.subtitleOffset, in: -10...10, step: 0.1)
                                .accentColor(.blue)
                            Button { vm.subtitleOffset += 0.1 } label: { Image(systemName: "plus.circle.fill").font(.title3) }
                            
                            Button { vm.subtitleOffset = 0 } label: {
                                Text("Reset").font(.caption.bold())
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .background(.white.opacity(0.1))
                                    .cornerRadius(6)
                            }
                        }
                        .buttonStyle(.plain)
                        
                        Text("Positive moves subtitles later, negative moves them earlier.")
                            .font(.system(size: 11))
                            .foregroundStyle(.white.opacity(0.4))
                    }
                    
                    Divider().opacity(0.1)

                    // Size Setting
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Label("Display Size", systemImage: "textformat.size")
                                .font(.headline)
                                .fontDesign(.rounded)
                            Spacer()
                            Text("\(vm.subtitleScale)px")
                                .font(.caption.monospaced())
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(.white.opacity(0.1))
                                .cornerRadius(6)
                        }
                        Slider(value: Binding(get: { Double(vm.subtitleScale) }, set: { vm.subtitleScale = Int($0) }), in: 16...120, step: 1)
                            .accentColor(.white)
                    }

                    Divider().opacity(0.1)

                    // Font Selection
                    VStack(alignment: .leading, spacing: 12) {
                        Label("Typeface", systemImage: "text.cursor")
                            .font(.headline)
                            .fontDesign(.rounded)
                        Picker("", selection: $vm.subtitleFont) {
                            Text("Inter").tag("Inter")
                            Text("Roboto").tag("Roboto")
                            Text("Outfit").tag("Outfit")
                            Text("Rounded").tag("Rounded")
                            Text("Mono").tag("Mono")
                        }
                        .pickerStyle(.segmented)
                    }

                    Divider().opacity(0.1)

                    HStack(alignment: .top, spacing: 30) {
                        // Color Selection
                        VStack(alignment: .leading, spacing: 12) {
                            Label("Color", systemImage: "paintbrush.fill")
                                .font(.headline)
                                .fontDesign(.rounded)
                            HStack(spacing: 12) {
                                ColorCircle(color: .white, hex: "#FFFFFF", current: vm.subtitleColor) { vm.subtitleColor = "#FFFFFF" }
                                ColorCircle(color: .yellow, hex: "#FFFF00", current: vm.subtitleColor) { vm.subtitleColor = "#FFFF00" }
                                ColorCircle(color: .cyan, hex: "#00FFFF", current: vm.subtitleColor) { vm.subtitleColor = "#00FFFF" }
                                ColorCircle(color: .green, hex: "#00FF00", current: vm.subtitleColor) { vm.subtitleColor = "#00FF00" }
                            }
                        }
                        
                        Spacer()

                        VStack(alignment: .leading, spacing: 12) {
                            Label("Opacity", systemImage: "square.stack.3d.up.fill")
                                .font(.headline)
                                .fontDesign(.rounded)
                            Picker("", selection: $vm.subtitleBgOpacity) {
                                Text("None").tag(0.0)
                                Text("Black").tag(0.85)
                            }
                            .pickerStyle(.segmented)
                            .frame(width: 140)
                        }
                    }
                }
            }
            .padding(32)
        }
        .frame(width: 500)
        .frame(maxHeight: 600)
        .glassEffect(in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .frame(width: 500)
        .liquidPanel()
        .shadow(color: .black.opacity(0.3), radius: 20)
        .transition(.asymmetric(
            insertion: .scale(scale: 0.95).combined(with: .opacity),
            removal: .scale(scale: 0.95).combined(with: .opacity)
        ))
    }
}

struct ColorCircle: View {
    let color: Color
    let hex: String
    let current: String
    let action: () -> Void
    
    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 28, height: 28)
            .overlay(
                Circle()
                    .stroke(.blue, lineWidth: hex == current ? 3 : 0)
                    .padding(-4)
            )
            .shadow(color: color.opacity(0.3), radius: 4)
            .onTapGesture {
                withAnimation { action() }
            }
    }
}

extension Animation {
    static let modalSpring = Animation.spring(response: 0.32, dampingFraction: 0.82)
}
