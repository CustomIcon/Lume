import SwiftUI

struct LoginView: View {
    @Environment(SessionManager.self) private var session

    enum AuthMethod {
        case credentials
        case quickConnect
    }

    @State private var authMethod: AuthMethod = .credentials
    @State private var username = ""
    @State private var password = ""
    @State private var isLoading = false
    @State private var errorMessage: String?

    // Quick Connect state
    @State private var quickConnectCode: String?
    @State private var quickConnectSecret: String?
    @State private var isPolling = false
    @State private var pollingTask: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 24) {
                Image("Logo")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 80, height: 80)

                VStack(spacing: 8) {
                    Text("Sign In")
                        .font(.largeTitle)
                        .fontWeight(.bold)

                    if let serverName = session.currentServer?.serverName, !serverName.isEmpty {
                        Text("Connecting to \(serverName)")
                            .font(.body)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Spacer()
                .frame(height: 32)

            VStack(spacing: 20) {
                // Auth method picker
                Picker("Authentication Method", selection: $authMethod) {
                    Text("Username & Password").tag(AuthMethod.credentials)
                    Text("Quick Connect").tag(AuthMethod.quickConnect)
                }
                .pickerStyle(.segmented)
                .onChange(of: authMethod) { _, newValue in
                    errorMessage = nil
                    if newValue != .quickConnect {
                        stopPolling()
                    }
                }

                switch authMethod {
                case .credentials:
                    credentialsForm

                case .quickConnect:
                    quickConnectView
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
            }
            .frame(maxWidth: 400)

            Spacer()
                .frame(height: 24)

            Button("Change Server") {
                Task {
                    await session.disconnectServer()
                }
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .font(.callout)

            Spacer()
        }
        .padding(40)
        .frame(minWidth: 500, minHeight: 450)
        .onDisappear {
            stopPolling()
        }
    }

    private var credentialsForm: some View {
        VStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Username")
                    .font(.headline)
                TextField("Username", text: $username)
                    .textFieldStyle(.roundedBorder)
                    .disabled(isLoading)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Password")
                    .font(.headline)
                SecureField("Password", text: $password)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { loginWithCredentials() }
                    .disabled(isLoading)
            }

            Button(action: loginWithCredentials) {
                if isLoading {
                    ProgressView()
                        .controlSize(.small)
                        .frame(maxWidth: .infinity)
                } else {
                    Text("Sign In")
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(username.isEmpty || isLoading)
        }
    }

    private var quickConnectView: some View {
        VStack(spacing: 16) {
            if let code = quickConnectCode {
                VStack(spacing: 12) {
                    Text("Enter this code on your Jellyfin server:")
                        .font(.body)
                        .foregroundStyle(.secondary)

                    Text(code)
                        .font(.system(size: 48, weight: .bold, design: .monospaced))
                        .foregroundStyle(.primary)
                        .padding()
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(.quaternary)
                        )

                    if isPolling {
                        HStack(spacing: 8) {
                            ProgressView()
                                .controlSize(.small)
                            Text("Waiting for authorization...")
                                .foregroundStyle(.secondary)
                                .font(.callout)
                        }
                    }
                }
            } else {
                Button(action: startQuickConnect) {
                    if isLoading {
                        ProgressView()
                            .controlSize(.small)
                            .frame(maxWidth: .infinity)
                    } else {
                        Text("Get Quick Connect Code")
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(isLoading)
            }
        }
    }

    private func loginWithCredentials() {
        guard !username.isEmpty else { return }
        isLoading = true
        errorMessage = nil

        Task {
            do {
                try await session.login(username: username, password: password)
            } catch {
                errorMessage = error.localizedDescription
            }
            isLoading = false
        }
    }

    private func startQuickConnect() {
        isLoading = true
        errorMessage = nil

        Task {
            do {
                let result = try await session.initiateQuickConnect()
                quickConnectCode = result.code
                quickConnectSecret = result.secret
                startPolling()
            } catch {
                errorMessage = error.localizedDescription
            }
            isLoading = false
        }
    }

    private func startPolling() {
        guard let secret = quickConnectSecret else { return }
        isPolling = true

        pollingTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(3))
                guard !Task.isCancelled else { break }

                do {
                    let authenticated = try await session.pollQuickConnect(secret: secret)
                    if authenticated {
                        try await session.completeQuickConnect(secret: secret)
                        break
                    }
                } catch {
                    errorMessage = error.localizedDescription
                    break
                }
            }
            isPolling = false
        }
    }

    private func stopPolling() {
        pollingTask?.cancel()
        pollingTask = nil
        isPolling = false
        quickConnectCode = nil
        quickConnectSecret = nil
    }
}
