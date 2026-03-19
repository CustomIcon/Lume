import SwiftUI

struct RootView: View {
    @Environment(SessionManager.self) private var session

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
        .animation(.easeInOut, value: session.authState)
    }
}
