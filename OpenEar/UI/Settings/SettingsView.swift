import SwiftUI
import KeyboardShortcuts

/// Settings/Preferences window
struct SettingsView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        TabView {
            GeneralSettingsView()
                .environmentObject(appState)
                .tabItem {
                    Label("General", systemImage: "gear")
                }

            ModelSettingsView()
                .environmentObject(appState)
                .tabItem {
                    Label("Model", systemImage: "brain")
                }

            PermissionsSettingsView()
                .environmentObject(appState)
                .tabItem {
                    Label("Permissions", systemImage: "lock.shield")
                }

            AboutSettingsView()
                .tabItem {
                    Label("About", systemImage: "info.circle")
                }
        }
        .frame(width: 450, height: 300)
    }
}

// MARK: - General Settings

struct GeneralSettingsView: View {
    @EnvironmentObject private var appState: AppState
    @AppStorage("launchAtLogin") private var launchAtLogin = false

    var body: some View {
        Form {
            Section {
                Toggle("Launch at Login", isOn: $launchAtLogin)

                LabeledContent("Hotkey") {
                    KeyboardShortcuts.Recorder(for: .toggleRecording)
                }
            } header: {
                Text("General")
            }

            Section {
                Text("Hold the hotkey to record, release to transcribe and inject text.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("How to Use")
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

// MARK: - Model Settings

struct ModelSettingsView: View {
    @EnvironmentObject private var appState: AppState
    @StateObject private var modelManager = ModelManager()

    var body: some View {
        Form {
            Section {
                Picker("Model", selection: $appState.selectedModel) {
                    ForEach(ModelManager.availableModels) { model in
                        VStack(alignment: .leading) {
                            Text(model.displayName)
                            Text(model.description)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .tag(model.id)
                    }
                }

                if let modelInfo = modelManager.modelInfo(for: appState.selectedModel) {
                    Text(modelInfo.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Whisper Model")
            }

            Section {
                HStack {
                    if appState.isModelDownloaded {
                        Label("Model Ready", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    } else if modelManager.isDownloading {
                        ProgressView(value: appState.modelDownloadProgress)
                            .progressViewStyle(.linear)
                        Text("\(Int(appState.modelDownloadProgress * 100))%")
                            .monospacedDigit()
                    } else {
                        Button("Download Model") {
                            Task {
                                await appState.downloadModel()
                            }
                        }
                    }
                }
            } header: {
                Text("Status")
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

// MARK: - Permissions Settings

struct PermissionsSettingsView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        Form {
            Section {
                permissionRow(
                    title: "Microphone",
                    description: "Required for audio capture",
                    icon: "mic.fill",
                    status: appState.microphonePermission,
                    action: {
                        // Open System Settings for microphone
                        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                )

                permissionRow(
                    title: "Accessibility",
                    description: "Required for text injection",
                    icon: "accessibility",
                    status: appState.accessibilityPermission,
                    action: {
                        appState.requestAccessibilityPermission()
                    }
                )
            } header: {
                Text("Required Permissions")
            }

            Section {
                Button("Refresh Permission Status") {
                    Task {
                        await appState.checkPermissions()
                    }
                }

                Button("Open Setup Wizard") {
                    AppDelegate.shared?.showOnboarding()
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    @ViewBuilder
    private func permissionRow(
        title: String,
        description: String,
        icon: String,
        status: AppState.PermissionState,
        action: @escaping () -> Void
    ) -> some View {
        HStack {
            Image(systemName: icon)
                .frame(width: 24)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading) {
                Text(title)
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            switch status {
            case .granted:
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            case .denied:
                Button("Grant") {
                    action()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            case .unknown:
                Button("Check") {
                    action()
                }
                .controlSize(.small)
            }
        }
    }
}

// MARK: - About Settings

struct AboutSettingsView: View {
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "waveform.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(.blue)

            Text("OpenEar")
                .font(.title)
                .fontWeight(.semibold)

            Text("Version 1.0")
                .font(.caption)
                .foregroundStyle(.secondary)

            Text("Local speech-to-text for Mac")
                .font(.body)
                .foregroundStyle(.secondary)

            Divider()

            VStack(spacing: 8) {
                Text("Powered by WhisperKit")
                    .font(.caption)

                Link("View on GitHub", destination: URL(string: "https://github.com/argmaxinc/WhisperKit")!)
                    .font(.caption)
            }
            .foregroundStyle(.secondary)

            Spacer()
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Preview

#Preview {
    SettingsView()
        .environmentObject(AppState())
}
