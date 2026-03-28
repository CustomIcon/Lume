import SwiftUI

struct RootView: View {
    @Environment(SessionManager.self) private var session
    @AppStorage("enableAnimations") private var enableAnimations = true

    var body: some View {
        Group {
            switch session.authState {
            case .unknown:
                ProgressView("Loading...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

            case .needsServer:
                ServerSetupView()

            case .needsAuthentication:
                LoginView()

            case .authenticated:
                MainAppView()
                    .onReceive(NotificationCenter.default.publisher(for: .navigateToSearch)) { _ in
                        // Could forward to MainAppView if needed
                    }
                    .onReceive(NotificationCenter.default.publisher(for: .navigateToHome)) { _ in
                        // Could forward to MainAppView if needed
                    }
            }
        }
        .animation(enableAnimations ? .spring(response: 0.4, dampingFraction: 0.8) : nil, value: session.authState)
        .onAppear {
            NSApp.windows.forEach { window in
                window.titlebarAppearsTransparent = true
                window.titleVisibility = .hidden
            }
        }
    }
}
