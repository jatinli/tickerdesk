import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var app
    @AppStorage(SettingsKeys.requireBiometrics) private var requireBiometrics = false
    @State private var apiKey = ""
    @State private var keyStatus: String?

    var body: some View {
        @Bindable var app = app

        NavigationStack {
            Form {
                Section {
                    Picker("Source", selection: $app.dataSource) {
                        ForEach(DataSource.allCases) { Text($0.title).tag($0) }
                    }
                    if app.dataSource == .finnhub {
                        SecureField("Finnhub API key", text: $apiKey)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        Button("Save Key", action: saveKey)
                        Link("Get a free API key", destination: URL(string: "https://finnhub.io/register")!)
                    }
                    if let keyStatus {
                        Text(keyStatus).font(.footnote).foregroundStyle(.secondary)
                    }
                    if app.isUsingFallbackData {
                        Label("No API key saved. Showing simulated prices.", systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                    }
                } header: {
                    Text("Market Data")
                } footer: {
                    Text("Simulated data works offline. Finnhub streams live US trades; the key is stored in the Keychain.")
                }

                Section("Security") {
                    Toggle("Require \(BiometricAuth.biometryName)", isOn: $requireBiometrics)
                }

                Section("About") {
                    LabeledContent("Version", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—")
                    Text("Paper trading only. No real orders are placed and no real money is involved.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Settings")
            .onAppear { apiKey = KeychainStore.string(for: KeychainKey.finnhubAPIKey) ?? "" }
        }
    }

    private func saveKey() {
        do {
            try KeychainStore.set(apiKey.trimmingCharacters(in: .whitespacesAndNewlines), for: KeychainKey.finnhubAPIKey)
            app.rebuildProvider()
            keyStatus = "Saved."
        } catch {
            keyStatus = error.localizedDescription
        }
    }
}

struct LockView: View {
    let onUnlock: () -> Void
    @State private var didFail = false

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "lock.fill")
                .font(.system(size: 48))
                .foregroundStyle(.tint)
            Text("TickerDesk is locked").font(.title2.bold())
            if didFail {
                Text("Authentication failed.").foregroundStyle(.secondary)
            }
            Button("Unlock with \(BiometricAuth.biometryName)") {
                Task { await unlock() }
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
        .task { await unlock() }
    }

    private func unlock() async {
        if await BiometricAuth.authenticate(reason: "Unlock your paper-trading account") {
            onUnlock()
        } else {
            didFail = true
        }
    }
}
