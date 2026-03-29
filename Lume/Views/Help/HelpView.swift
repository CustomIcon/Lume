import SwiftUI

enum HelpTopic: String, CaseIterable, Identifiable {
    case introduction = "Introduction"
    case playback = "Playback & Shortcuts"
    case trickplay = "Seek Previews (Trickplay)"
    case libraries = "Libraries & Discovery"
    case settings = "Settings & Management"
    case streaming = "Direct Play vs. Direct Stream"
    
    var id: String { self.rawValue }
    
    var icon: String {
        switch self {
        case .introduction: return "hand.wave"
        case .playback: return "play.circle"
        case .trickplay: return "eye"
        case .libraries: return "film"
        case .settings: return "gearshape"
        case .streaming: return "bolt.horizontal.circle"
        }
    }
}

struct HelpView: View {
    @State private var selectedTopic: HelpTopic? = .introduction
    
    var body: some View {
        NavigationSplitView {
            List(HelpTopic.allCases, selection: $selectedTopic) { topic in
                NavigationLink(value: topic) {
                    Label(topic.rawValue, systemImage: topic.icon)
                }
            }
            .navigationTitle("Lume Help")
        } detail: {
            if let topic = selectedTopic {
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        Text(topic.rawValue)
                            .font(.largeTitle)
                            .fontWeight(.bold)
                        
                        Divider()
                        
                        content(for: topic)
                    }
                    .padding(40)
                    .frame(maxWidth: 800, alignment: .leading)
                }
            } else {
                Text("Select a topic from the sidebar")
                    .foregroundStyle(.secondary)
            }
        }
    }
    
    @ViewBuilder
    private func content(for topic: HelpTopic) -> some View {
        switch topic {
        case .introduction:
            VStack(alignment: .leading, spacing: 16) {
                Text("Welcome to Lume.")
                    .font(.title2)
                Text("Lume is a native Jellyfin client built from the ground up for macOS. It prioritizes fluid performance, native design standards, and a cinematic experience.")
                Text("The goal of Lume is to provide a 'Liquid Glass' aesthetic that feels right at home on your Mac while providing all the power of your Jellyfin server.")
            }
            
        case .playback:
            VStack(alignment: .leading, spacing: 16) {
                Text("Keyboard Shortcuts")
                    .font(.headline)
                
                VStack(alignment: .leading, spacing: 8) {
                    shortcutRow(key: "Space", action: "Play / Pause")
                    shortcutRow(key: "Cmd + F", action: "Toggle Fullscreen")
                    shortcutRow(key: "Left Arrow", action: "Seek Back (10s)")
                    shortcutRow(key: "Right Arrow", action: "Seek Forward (10s)")
                    shortcutRow(key: "S", action: "Open Subtitle Tracks")
                    shortcutRow(key: "A", action: "Open Audio Tracks")
                }
                
                Text("Controls & Intro Skipping")
                    .font(.headline)
                    .padding(.top)
                Text("All playback controls are available in the floating HUD. Hover your mouse near the bottom of the window to reveal the scrubber and volume controls.")
                
                Text("If your server has the 'Intro Skipper' plugin, Lume will automatically detect show intros and provide a 'Skip Intro' button in the bottom right corner when they begin.")
            }
            
        case .trickplay:
            VStack(alignment: .leading, spacing: 16) {
                Text("Understanding Seek Previews")
                    .font(.title2)
                
                Text("Trickplay (Seek Previews) allows you to see visual thumbnails of scenes while scrubbing through the video timeline.")
                
                VStack(alignment: .leading, spacing: 12) {
                    Text("CRITICAL REQUIREMENT:")
                        .fontWeight(.bold)
                        .foregroundStyle(.orange)
                    
                    Text("Trickplay images ONLY appear if they have been generated on your Jellyfin server. In your server settings, ensure 'Trickplay Image Extraction' is enabled under the scheduled tasks and for each respective library.")
                }
                .padding()
                .background(.orange.opacity(0.1))
                .cornerRadius(8)

                Text("If thumbnails are missing on the server, Lume will gracefully fall back to a simple timestamp-only preview.")
                
                Text("You can toggle this feature in Lume Settings > Playback.")
            }
            
        case .libraries:
            VStack(alignment: .leading, spacing: 16) {
                Text("Content Discovery")
                    .font(.headline)
                Text("Lume supports Movies, TV Shows, Music, Live TV, and Books. The Home screen features a 'Next Up' section for easily continuing your series and 'Latest' rows for new discoveries.")
                
                Text("Unified Search")
                    .font(.headline)
                    .padding(.top)
                Text("The Search section in the sidebar allows you to search across all your libraries simultaneously. It includes smart suggestions to help you find what you're looking for faster.")
            }
            
        case .settings:
            VStack(alignment: .leading, spacing: 16) {
                Text("Management")
                    .font(.headline)
                
                Text("• Playback: Set your preferred bitrates, languages, and resume behaviors.")
                Text("• Intro Skipper: Enable/disable the 'Skip Intro' button for supported series.")
                Text("• Appearance: Switch between dozens of 'Liquid Glass' flavors.")
                Text("• Storage: Clear image, subtitle, or lyrics caches to free up local disk space.")
                Text("• Servers: Connect to multiple Jellyfin servers or accounts simultaneously.")
                
                Text("Resume Support")
                    .font(.headline)
                    .padding(.top)
                Text("Lume automatically syncs your progress with the server. If you leave a movie in the middle, you will see it in 'Continue Watching' and can pick up exactly where you left off.")
            }
        case .streaming:
            VStack(alignment: .leading, spacing: 20) {
                Text("Streaming Concepts")
                    .font(.title2)
                
                Text("Lume attempts to play your media in the most efficient way possible based on your server settings and your Mac's hardware capabilities. Here is the breakdown of the two primary modes you will encounter:")
                
                VStack(alignment: .leading, spacing: 12) {
                    Text("1. Direct Play (The Gold Standard)")
                        .font(.headline)
                        .foregroundStyle(.green)
                    Text("The file is sent bit-for-bit from the server to your Mac. Lume's engine handles the decoding locally.")
                    
                    HStack(alignment: .top, spacing: 20) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("ADVANTAGES").font(.caption).bold().foregroundStyle(.secondary)
                            Text("• Zero server CPU/GPU impact")
                            Text("• Original source quality")
                            Text("• Instant seeking")
                        }
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text("DISADVANTAGES").font(.caption).bold().foregroundStyle(.secondary)
                            Text("• High bandwidth required")
                            Text("• Requires hardware codec support")
                        }
                    }
                    .padding()
                    .background(.green.opacity(0.1))
                    .cornerRadius(8)
                }
                
                VStack(alignment: .leading, spacing: 12) {
                    Text("2. Direct Stream (Smart Repacking)")
                        .font(.headline)
                        .foregroundStyle(.blue)
                    Text("The video and audio 'bitstreams' are compatible, but the 'container' (like MKV) is not. The server 're-wraps' them into a compatible format (HLS/MP4) on the fly.")
                    
                    HStack(alignment: .top, spacing: 20) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("ADVANTAGES").font(.caption).bold().foregroundStyle(.secondary)
                            Text("• Very low server CPU impact")
                            Text("• High compatibility")
                            Text("• Maintains source quality")
                        }
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text("DISADVANTAGES").font(.caption).bold().foregroundStyle(.secondary)
                            Text("• Slight startup delay")
                            Text("• Occasional seek overhead")
                        }
                    }
                    .padding()
                    .background(.blue.opacity(0.1))
                    .cornerRadius(8)
                }
                
                Divider().padding(.vertical)
                
                Text("Why does it matter?")
                    .font(.headline)
                Text("If your server is struggling during playback, check if you are 'Transcoding'. Transcoding means your server is actively re-encoding the video, which is very intensive. Lume avoids transcoding whenever possible by using its robust native engine.")
            }
        }
    }
    
    private func shortcutRow(key: String, action: String) -> some View {
        HStack {
            Text(key)
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(.quaternary)
                .cornerRadius(4)
            Text(action)
                .foregroundStyle(.secondary)
        }
    }
}
