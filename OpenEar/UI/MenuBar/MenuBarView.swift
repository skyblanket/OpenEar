import SwiftUI

/// Main menu bar popover view
struct MenuBarView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        VStack(spacing: 12) {
            // Header with status
            headerSection

            Divider()

            // Main content based on state
            if case .error(let message) = appState.recordingState {
                errorRecoveryView(message: message)
            } else if appState.microphonePermission != .granted || appState.accessibilityPermission != .granted {
                setupNeededView
            } else if !appState.isModelDownloaded {
                modelLoadingView
            } else {
                mainContentView
            }

            Divider()

            // Footer
            footerSection
        }
        .padding(16)
        .frame(width: 280)
    }

    // MARK: - Header

    private var headerSection: some View {
        HStack(spacing: 10) {
            // Status indicator
            Circle()
                .fill(statusColor)
                .frame(width: 10, height: 10)

            Text(statusText)
                .font(.system(size: 13, weight: .medium))

            Spacer()

            // Recording state icon
            if appState.recordingState == .recording {
                Image(systemName: "waveform")
                    .foregroundStyle(.red)
                    .symbolEffect(.pulse)
            }
        }
    }

    private var statusColor: Color {
        switch appState.recordingState {
        case .idle:
            if appState.microphonePermission != .granted || appState.accessibilityPermission != .granted {
                return .orange
            }
            return appState.isModelDownloaded ? .green : .blue
        case .recording:
            return .red
        case .transcribing:
            return .orange
        case .injecting:
            return .blue
        case .error:
            return .red
        }
    }

    private var statusText: String {
        switch appState.recordingState {
        case .idle:
            if appState.microphonePermission != .granted || appState.accessibilityPermission != .granted {
                return "Setup Required"
            }
            return appState.isModelDownloaded ? "Ready" : "Loading Model..."
        case .recording:
            return "Recording..."
        case .transcribing:
            return "Transcribing..."
        case .injecting:
            return "Done!"
        case .error:
            return "Error"
        }
    }

    // MARK: - Error Recovery View

    private func errorRecoveryView(message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.circle")
                .font(.system(size: 28))
                .foregroundStyle(.red)

            Text(message)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            // Recovery actions based on error type
            VStack(spacing: 8) {
                if message.contains("Microphone") {
                    Button("Open Microphone Settings") {
                        openSystemPreferences(pane: "Privacy_Microphone")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                } else if message.contains("Accessibility") {
                    Button("Open Accessibility Settings") {
                        appState.requestAccessibilityPermission()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                } else if message.contains("Model") || message.contains("download") {
                    Button("Retry Download") {
                        appState.clearError()
                        Task {
                            await appState.downloadModel()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }

                // Always show dismiss option
                Button("Dismiss") {
                    appState.clearError()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(.vertical, 8)
    }

    // MARK: - Setup Needed View

    private var setupNeededView: some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 28))
                .foregroundStyle(.orange)

            Text("Setup Required")
                .font(.system(size: 14, weight: .semibold))

            // Show specific missing permissions
            VStack(alignment: .leading, spacing: 6) {
                if appState.microphonePermission != .granted {
                    permissionRow("Microphone", granted: false)
                }
                if appState.accessibilityPermission != .granted {
                    permissionRow("Accessibility", granted: false)
                }
            }
            .padding(.vertical, 4)

            Button("Open Setup") {
                AppDelegate.shared?.showOnboarding()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)
        }
        .padding(.vertical, 8)
    }

    private func permissionRow(_ name: String, granted: Bool) -> some View {
        HStack(spacing: 8) {
            Image(systemName: granted ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(granted ? .green : .red)
                .font(.system(size: 12))
            Text(name)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Model Loading View

    private var modelLoadingView: some View {
        VStack(spacing: 12) {
            ProgressView()
                .scaleEffect(0.9)

            Text("Loading speech model...")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)

            Text(appState.selectedModel)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.tertiary)

            // Show retry if stuck for too long
            Button("Retry") {
                Task {
                    await appState.downloadModel()
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .padding(.top, 4)
        }
        .padding(.vertical, 12)
    }

    // MARK: - Main Content

    private var mainContentView: some View {
        VStack(spacing: 12) {
            // Waveform when recording
            if appState.recordingState == .recording {
                WaveformView(level: appState.audioLevel)
                    .frame(height: 36)
            }

            // Transcription preview
            if !appState.partialTranscription.isEmpty || !appState.finalTranscription.isEmpty {
                Text(appState.finalTranscription.isEmpty ? appState.partialTranscription : appState.finalTranscription)
                    .font(.system(size: 12))
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(Color.secondary.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .lineLimit(4)
            } else if appState.recordingState == .idle {
                VStack(spacing: 6) {
                    Text("Hold **Fn** or **Ctrl+Space** to record")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 12)
            }
        }
    }

    // MARK: - Footer

    private var footerSection: some View {
        HStack {
            // Model indicator
            HStack(spacing: 4) {
                Circle()
                    .fill(appState.isModelDownloaded ? .green : .orange)
                    .frame(width: 6, height: 6)
                Text(appState.selectedModel)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Reset button (for stuck states)
            Button {
                appState.resetState()
            } label: {
                Image(systemName: "arrow.counterclockwise")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Reset if stuck")

            // Settings
            SettingsLink {
                Image(systemName: "gear")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .padding(.leading, 6)

            // Quit
            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Image(systemName: "power")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .padding(.leading, 6)
        }
    }

    // MARK: - Helpers

    private func openSystemPreferences(pane: String) {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)")!
        NSWorkspace.shared.open(url)
    }
}

#Preview {
    MenuBarView()
        .environmentObject(AppState())
}
