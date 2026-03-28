import SwiftUI

struct ServerSetupView: View {
    @Environment(SessionManager.self) private var session
    @State private var serverURL = ""
    @State private var isValidating = false
    @State private var errorMessage: String?
    @State private var serverInfo: PublicServerInfo?

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 24) {
                // App Icon / Logo
                Image("Logo")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 100, height: 100)

                Text("Welcome to Lume")
                    .font(.largeTitle)
                    .fontWeight(.bold)

                Text("Connect to your Jellyfin server to get started.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Spacer()
                .frame(height: 40)

            VStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Server Address")
                        .font(.headline)

                    TextField("https://your-server.example.com", text: $serverURL)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit { validateServer() }
                        .disabled(isValidating)
                }

                if let errorMessage {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.yellow)
                        Text(errorMessage)
                            .foregroundStyle(.red)
                            .font(.callout)
                    }
                }

                if let serverInfo {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Text("Connected to \(serverInfo.serverName ?? "server") (v\(serverInfo.version ?? "?"))")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }

                Button(action: validateServer) {
                    if isValidating {
                        ProgressView()
                            .controlSize(.small)
                            .frame(maxWidth: .infinity)
                    } else {
                        Text(serverInfo != nil ? "Continue" : "Connect")
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(serverURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isValidating)
            }
            .frame(maxWidth: 400)

            Spacer()
                .frame(height: 24)

            Button("Cancel") {
                session.cancelAddition()
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .font(.callout)

            Spacer()
        }
        .padding(40)
        .frame(minWidth: 500, minHeight: 400)
    }

    private func validateServer() {
        guard !serverURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        // If already validated, proceed to auth
        if serverInfo != nil {
            // Session manager already updated state to needsAuthentication
            return
        }

        isValidating = true
        errorMessage = nil

        Task {
            do {
                var url = serverURL.trimmingCharacters(in: .whitespacesAndNewlines)
                // Add https:// if no scheme
                if !url.contains("://") {
                    url = "https://\(url)"
                    serverURL = url
                }

                let info = try await session.validateAndSaveServer(url: url)
                serverInfo = info
            } catch {
                errorMessage = error.localizedDescription
                serverInfo = nil
            }
            isValidating = false
        }
    }
}
