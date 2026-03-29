//
//  LumeApp.swift
//  Lume
//
//  Created by CustomIcon on 19-3-26.
//

import SwiftUI
import SwiftData

@main
struct LumeApp: App {
    @State private var sessionManager = SessionManager()
    @Environment(\.openWindow) private var openWindow

    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            ServerConfiguration.self,
            UserSession.self,
            CachedLibrary.self,
            PlaybackPosition.self,
            UserPreference.self,
            DownloadedItem.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            RootView()
                .frame(minWidth: 1100, minHeight: 700)
                .environment(sessionManager)
                .task {
                    await sessionManager.setup(modelContext: sharedModelContainer.mainContext)
                }
        }
        .windowStyle(.hiddenTitleBar)
        .modelContainer(sharedModelContainer)

        Window("Video Player", id: "video-player") {
            if let activeVideo = sessionManager.activeVideoItem {
                PlayerView(item: activeVideo)
                    .id(activeVideo.id)
                    .environment(sessionManager)
                    .themeContainer()
                    .frame(minWidth: 800, minHeight: 450)
            } else {
                Color.black
            }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1280, height: 720)

        Window("Book Reader", id: "book-reader") {
            if let activeBook = sessionManager.activeBookItem {
                BookReaderView(item: activeBook)
                    .id(activeBook.id)
                    .environment(sessionManager)
                    .themeContainer()
                    .frame(minWidth: 400, minHeight: 600)
            } else {
                Color.black
            }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 600, height: 850)

        Window("Help Center", id: "lume-help") {
            HelpView()
                .environment(sessionManager)
                .themeContainer()
                .frame(minWidth: 850, minHeight: 600)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1000, height: 750)
        .commands {
            CommandGroup(replacing: .newItem) {}

            CommandMenu("Playback") {
                Button("Play / Pause") {
                    // Handled by PlayerView
                }
                .keyboardShortcut(.space, modifiers: [])

                Button("Toggle Fullscreen") {
                    // NSApp window fullscreen toggle
                }
                .keyboardShortcut("f", modifiers: [.command, .control])
            }

            CommandMenu("Navigation") {
                Button("Search") {
                    NotificationCenter.default.post(name: .navigateToSearch, object: nil)
                }
                .keyboardShortcut("f", modifiers: .command)

                Button("Home") {
                    NotificationCenter.default.post(name: .navigateToHome, object: nil)
                }
                .keyboardShortcut("1", modifiers: .command)

                Divider()

                Button("Refresh Libraries") {
                    Task { await sessionManager.refreshLibraries() }
                }
                .keyboardShortcut("r", modifiers: .command)
            }

            CommandGroup(replacing: .help) {
                Button("Lume Help") {
                    openWindow(id: "lume-help")
                }
                .keyboardShortcut("/", modifiers: .command)
            }
        }

        Settings {
            SettingsView()
                .environment(sessionManager)
                .modelContainer(sharedModelContainer)
                .task {
                    await sessionManager.setup(modelContext: sharedModelContainer.mainContext)
                }
        }
    }
}

extension Notification.Name {
    static let navigateToSearch = Notification.Name("navigateToSearch")
    static let navigateToHome = Notification.Name("navigateToHome")
}
