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

    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            ServerConfiguration.self,
            UserSession.self,
            CachedLibrary.self,
            PlaybackPosition.self,
            UserPreference.self,
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
                .environment(sessionManager)
                .task {
                    await sessionManager.setup(modelContext: sharedModelContainer.mainContext)
                }
        }
        .modelContainer(sharedModelContainer)
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
        }

        Settings {
            SettingsView()
                .environment(sessionManager)
        }
    }
}

extension Notification.Name {
    static let navigateToSearch = Notification.Name("navigateToSearch")
    static let navigateToHome = Notification.Name("navigateToHome")
}
