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

// MARK: - VLC Track Info (from VLCMediaPlayer at runtime)

struct VLCTrackInfo: Identifiable, Hashable {
    let index: Int32
    let name: String
    var id: Int32 { index }
}

// MARK: - VLC SwiftUI Wrapper

struct VLCVideoPlayer: NSViewRepresentable {
    let url: URL
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
            parent.onStateUpdated(mediaPlayer.state)
        }
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.black.cgColor
        context.coordinator.mediaPlayer.drawable = view

        let media = VLCMedia(url: url)
        context.coordinator.mediaPlayer.media = media
        context.coordinator.mediaPlayer.play()

        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        let currentMediaURL = context.coordinator.mediaPlayer.media?.url
        if currentMediaURL != url {
            let media = VLCMedia(url: url)
            context.coordinator.mediaPlayer.media = media
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

        func jumpForward(_ dur: Duration) {
            let next = (mediaPlayer?.time.intValue ?? 0) + Int32(dur.components.seconds * 1000)
            mediaPlayer?.time = VLCTime(int: next)
        }

        func jumpBackward(_ dur: Duration) {
            let next = (mediaPlayer?.time.intValue ?? 0) - Int32(dur.components.seconds * 1000)
            mediaPlayer?.time = VLCTime(int: next)
        }

        func setSeconds(_ seconds: Duration) {
            mediaPlayer?.time = VLCTime(int: Int32(seconds.components.seconds * 1000))
        }

        // MARK: - Native VLC subtitle track control

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
        }

        func setSubtitleTrack(_ index: Int32) {
            mediaPlayer?.currentVideoSubTitleIndex = index
        }

        /// Returns the available audio tracks from VLC.
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
            // VLCKit often uses a relative size index (0-30 or similar)
            // or we can try to use textRendererFontSize if available.
            // Using perform as a safe way to set these values across different VLCKit versions.
            mediaPlayer?.perform(Selector(("setTextRendererFontSize:")), with: NSNumber(value: scale))
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
    }
}

// MARK: - Player ViewModel

@Observable
final class PlayerViewModel {
    var player: AVPlayer?
    var vlcProxy = VLCVideoPlayer.Proxy()

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
    var playSessionId = UUID().uuidString
    var currentPosition: Int64 = 0
    var hasStartedPlaying = false
    var tracksLoaded = false
    var subtitleScale: Int = UserDefaults.standard.integer(forKey: "subtitleScale") == 0 ? 18 : UserDefaults.standard.integer(forKey: "subtitleScale")

    var playURL: URL?

    func cleanup() {
        progressTimer?.invalidate()
        progressTimer = nil
        vlcProxy.stop()
        player?.pause()
        player = nil
        hasStartedPlaying = false
        tracksLoaded = false
        isLoading = false
        CursorHideState.shared.unhide()
    }

    /// Load track lists from VLC player once playback has started.
    func loadTracksFromVLC() {
        guard !tracksLoaded else { return }
        vlcSubtitleTracks = vlcProxy.subtitleTracks
        vlcAudioTracks = vlcProxy.audioTracks
        selectedSubtitleIndex = vlcProxy.currentSubtitleIndex
        selectedAudioIndex = vlcProxy.currentAudioIndex
        if !vlcSubtitleTracks.isEmpty || !vlcAudioTracks.isEmpty {
            tracksLoaded = true
        }
    }

    deinit {
        cleanup()
    }
}

// MARK: - Player View

struct PlayerView: View {
    @Environment(SessionManager.self) private var session
    let item: BaseItemDto

    @FocusState private var isFocused: Bool
    @State private var vm = PlayerViewModel()
    @State private var fullItem: BaseItemDto?
    @State private var errorMessage: String?

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
                VLCVideoPlayer(url: playURL, proxy: $vm.vlcProxy) { seconds, duration in
                    guard !vm.isDraggingSlider else { return }
                    vm.currentPlaybackTime = seconds
                    vm.duration = duration
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
                        vm.hasStartedPlaying = true
                        vm.isLoading = false
                        // Load VLC's native track lists once playback starts
                        vm.loadTracksFromVLC()
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
                }
                .onChange(of: vm.subtitleScale) { _, newValue in
                    vm.vlcProxy.setSubtitleScale(newValue)
                }
                .zIndex(0)
            }

            Color.black.opacity(0.001)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onContinuousHover { _ in
                    isFocused = true
                    triggerControls()
                }
                .onTapGesture(count: 2) {
                    toggleFullscreen()
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
                    (vm.showControls || vm.isLoading || !vm.hasStartedPlaying)
                        ? LumePointerVisibility.visible
                        : LumePointerVisibility.hidden
                )
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
        .task { await prepareAndPlay() }
        .onAppear {
            setupTimer()
            isFocused = true
        }
        .onDisappear { stopPlayback() }
        .focusable()
        .focusEffectDisabled()
        .focused($isFocused)
        .onKeyPress(.space) {
            vm.vlcProxy.togglePlay()
            triggerControls()
            return .handled
        }
        .onKeyPress { press in
            handleKeyPress(press)
        }
    }

    // MARK: - Playback Preparation

    private func prepareAndPlay() async {
        guard let itemId = item.id else {
            errorMessage = "Invalid item — no ID"
            return
        }

        vm.isLoading = true
        vm.statusMessage = "Fetching media info..."
        errorMessage = nil

        if fullItem == nil || fullItem?.mediaSources == nil {
            do {
                fullItem = try await session.apiClient.getItem(itemId: itemId)
            } catch {
                print("[Lume] Failed to fetch item details: \(error)")
            }
        }

        let base = await session.apiClient.getBaseURL()
        let token = await session.apiClient.getAccessToken()
        let mediaSourceId = resolvedItem.mediaSources?.first?.id

        vm.statusMessage = "Negotiating stream..."
        do {
            let info = try await session.apiClient.getPlaybackInfo(
                itemId: itemId,
                mediaSourceId: mediaSourceId,
                audioStreamIndex: nil,
                subtitleStreamIndex: nil
            )

            if let source = info.mediaSources?.first {
                if source.supportsDirectStream == true,
                   let directURL = source.directStreamUrl {
                    let fullURL = base + directURL
                    print("[Lume] Using direct stream: \(fullURL)")
                    vm.playURL = URL(string: fullURL)
                    vm.playSessionId = info.playSessionId ?? UUID().uuidString
                    return
                }
                if let transURL = source.transcodingUrl {
                    let fullURL = base + transURL
                    print("[Lume] Using transcode stream: \(fullURL)")
                    vm.playURL = URL(string: fullURL)
                    vm.playSessionId = info.playSessionId ?? UUID().uuidString
                    return
                }
                if source.supportsDirectPlay == true {
                    let sourceId = source.id ?? mediaSourceId ?? itemId
                    var directPlayURL = "\(base)/Videos/\(itemId)/stream?static=true&MediaSourceId=\(sourceId)"
                    if let token { directPlayURL += "&api_key=\(token)" }
                    print("[Lume] Using direct play: \(directPlayURL)")
                    vm.playURL = URL(string: directPlayURL)
                    vm.playSessionId = info.playSessionId ?? UUID().uuidString
                    return
                }
            }
        } catch {
            print("[Lume] PlaybackInfo failed: \(error). Falling back to direct stream URL.")
        }

        vm.statusMessage = "Using fallback stream..."
        let sourceId = mediaSourceId ?? itemId
        var fallbackURL = "\(base)/Videos/\(itemId)/stream?static=true&MediaSourceId=\(sourceId)"
        if let token { fallbackURL += "&api_key=\(token)" }
        print("[Lume] Using fallback: \(fallbackURL)")
        vm.playURL = URL(string: fallbackURL)
    }

    // MARK: - Controls

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
                vm.loadTracksFromVLC()
            }
        }
    }

    // MARK: - Top Bar

    private var topLiquidBar: some View {
        HStack(spacing: 20) {
            Button { stopPlayback() } label: {
                Image(systemName: "chevron.left")
                    .font(.title3.bold())
                    .foregroundStyle(.white)
                    .padding(14)
                    .background(.ultraThinMaterial, in: Circle())
                    .overlay(Circle().stroke(.white.opacity(0.1), lineWidth: 1))
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.displayName)
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .shadow(radius: 4)
                if let year = item.productionYear {
                    Text(String(year))
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.7))
                }
            }
            Spacer()
            HStack(spacing: 12) {
                if vm.vlcAudioTracks.count > 1 {
                    liquidMenu(label: "Audio", icon: "speaker.wave.2") { audioMenu }
                }
                liquidMenu(label: "Captions", icon: "captions.bubble") { subtitleMenu }
            }
        }
        .padding(.horizontal, 30)
        .padding(.top, 40)
        .background(
            LinearGradient(colors: [.black.opacity(0.8), .clear], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
        )
    }

    // MARK: - Bottom HUD

    private var bottomLiquidHUD: some View {
        VStack(spacing: 30) {
            VStack(spacing: 12) {
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

                ModernScrubber(vm: vm)
            }
            .padding(.horizontal, 30)

            ZStack {
                HStack(spacing: 40) {
                    Button { vm.vlcProxy.jumpBackward(Duration.seconds(10)) } label: {
                        Image(systemName: "gobackward.10").font(.title2)
                    }
                    .buttonStyle(.plain)

                    Button { vm.vlcProxy.togglePlay() } label: {
                        Image(systemName: vm.vlcProxy.rate == 0 ? "play.fill" : "pause.fill")
                            .font(.system(size: 44))
                            .foregroundStyle(.white)
                            .shadow(color: .white.opacity(0.4), radius: 10)
                    }
                    .buttonStyle(.plain)

                    Button { vm.vlcProxy.jumpForward(Duration.seconds(10)) } label: {
                        Image(systemName: "goforward.10").font(.title2)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 30)
                .padding(.vertical, 15)
                .background(.ultraThinMaterial, in: Capsule())
                .overlay(Capsule().stroke(.white.opacity(0.1), lineWidth: 1))
            }
        }
        .padding(.bottom, 60)
        .background(
            LinearGradient(colors: [.clear, .black.opacity(0.9)], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
        )
    }

    // MARK: - Menus

    private func liquidMenu<Content: View>(label: String, icon: String, @ViewBuilder menu: () -> Content) -> some View {
        Menu { menu() } label: {
            HStack(spacing: 8) {
                Image(systemName: icon)
                Text(label).font(.system(size: 14, weight: .semibold, design: .rounded))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(Capsule().stroke(.white.opacity(0.1), lineWidth: 1))
        }
        .buttonStyle(.plain)
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
            vm.selectedSubtitleIndex = -1
            vm.vlcProxy.setSubtitleTrack(-1)
        } label: {
            HStack {
                Text("Off")
                if vm.selectedSubtitleIndex == -1 {
                    Spacer()
                    Image(systemName: "checkmark")
                }
            }
        }

        if vm.vlcSubtitleTracks.isEmpty {
            Text("No subtitles available")
                .foregroundStyle(.secondary)
        } else {
            ForEach(vm.vlcSubtitleTracks.filter { $0.index != -1 }) { track in
                Button {
                    vm.selectedSubtitleIndex = track.index
                    vm.vlcProxy.setSubtitleTrack(track.index)
                } label: {
                    HStack {
                        Text(track.name)
                        if track.index == vm.selectedSubtitleIndex {
                            Spacer()
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        }

        Divider()

        Menu("Size") {
            Button("Small") { updateSize(12) }
            Button("Normal") { updateSize(18) }
            Button("Large") { updateSize(26) }
            Button("Extra Large") { updateSize(36) }
        }
    }

    private func updateSize(_ size: Int) {
        vm.subtitleScale = size
        UserDefaults.standard.set(size, forKey: "subtitleScale")
    }

    // MARK: - Helpers

    private func formatTime(_ seconds: Double) -> String {
        guard !seconds.isNaN else { return "0:00" }
        let h = Int(seconds) / 3600
        let m = (Int(seconds) % 3600) / 60
        let s = Int(seconds) % 60
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, s) }
        return String(format: "%d:%02d", m, s)
    }

    private func stopPlayback() {
        guard let itemId = item.id else { return }
        let ticks = Int64(vm.currentPlaybackTime * 10_000_000)
        let stopInfo = PlaybackStopInfo(itemId: itemId, positionTicks: ticks, playSessionId: vm.playSessionId)
        Task { try? await session.apiClient.reportPlaybackStopped(stopInfo) }
        vm.cleanup()
        withAnimation { session.activeVideoItem = nil }
    }

    private func toggleFullscreen() {
        if let window = NSApp.keyWindow ?? NSApp.mainWindow ?? NSApp.windows.first(where: { $0.isVisible }) {
            window.toggleFullScreen(nil)
        }
    }

    private func handleKeyPress(_ press: KeyPress) -> KeyPress.Result {
        switch press.key {
        case .leftArrow, .init("j"), .init("J"):
            vm.vlcProxy.jumpBackward(Duration.seconds(10))
            triggerControls()
            return .handled
        case .rightArrow, .init("l"), .init("L"):
            vm.vlcProxy.jumpForward(Duration.seconds(10))
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
        default:
            return .ignored
        }
    }
}

// MARK: - Modern Scrubber

struct ModernScrubber: View {
    @Bindable var vm: PlayerViewModel
    @State private var isHovering = false
    @State private var hoverLocation: CGFloat = 0

    var body: some View {
        GeometryReader { geo in
            let progress = CGFloat(vm.currentPlaybackTime / max(vm.duration, 1))
            let bufferProgress = CGFloat(vm.bufferedTime / max(vm.duration, 1))
            let dragLocX = min(max(0, hoverLocation), geo.size.width)
            let hoverTime = Double(dragLocX / geo.size.width) * vm.duration

            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.15))
                    .frame(height: isHovering || vm.isDraggingSlider ? 8 : 4)

                Capsule().fill(.white.opacity(0.35))
                    .frame(width: geo.size.width * bufferProgress, height: isHovering || vm.isDraggingSlider ? 8 : 4)

                Capsule().fill(ThemeManager.shared.currentFlavor.accentColor)
                    .frame(width: geo.size.width * progress, height: isHovering || vm.isDraggingSlider ? 8 : 4)
                    .shadow(color: ThemeManager.shared.currentFlavor.accentColor.opacity(0.4), radius: 6)
                    .overlay(alignment: .trailing) {
                        Circle().fill(.white)
                            .frame(width: 16, height: 16)
                            .shadow(radius: 4)
                            .scaleEffect(isHovering || vm.isDraggingSlider ? 1.2 : 0.001)
                            .opacity(isHovering || vm.isDraggingSlider ? 1 : 0)
                            .offset(x: 8)
                    }

                if isHovering || vm.isDraggingSlider {
                    Text(formatTime(vm.isDraggingSlider ? vm.currentPlaybackTime : hoverTime))
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
                        .shadow(color: .black.opacity(0.2), radius: 6)
                        .offset(x: dragLocX - 35, y: -35)
                }
            }
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
