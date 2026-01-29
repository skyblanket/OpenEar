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
            if appState.microphonePermission != .granted {
                setupNeededView
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
            if appState.microphonePermission != .granted {
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
            if appState.microphonePermission != .granted {
                return "Setup Required"
            }
            return appState.isModelDownloaded ? "Ready" : "Loading Model..."
        case .recording:
            return "Recording..."
        case .transcribing:
            return "Transcribing..."
        case .injecting:
            return "Done!"
        case .error(let msg):
            return msg
        }
    }

    // MARK: - Setup Needed View

    private var setupNeededView: some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 28))
                .foregroundStyle(.orange)

            Text("Setup Required")
                .font(.system(size: 14, weight: .semibold))

            Text("Complete setup to start using OpenEar")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button("Open Setup") {
                AppDelegate.shared?.showOnboarding()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)
        }
        .padding(.vertical, 8)
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
                // Instructions or loading state
                if !appState.isModelDownloaded {
                    VStack(spacing: 8) {
                        ProgressView()
                            .scaleEffect(0.8)
                        Text("Loading speech model...")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 12)
                } else {
                    VStack(spacing: 6) {
                        Text("Hold **Fn** or **Ctrl+Space** to record")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 12)
                }
            }

            // Permission warnings
            if appState.accessibilityPermission != .granted {
                warningBadge("Accessibility needed", icon: "keyboard")
                    .onTapGesture {
                        appState.requestAccessibilityPermission()
                    }
            }
        }
    }

    private func warningBadge(_ text: String, icon: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 10))
            Text(text)
                .font(.system(size: 10))
            Image(systemName: "chevron.right")
                .font(.system(size: 8))
        }
        .foregroundStyle(.orange)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.orange.opacity(0.1))
        .clipShape(Capsule())
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

            // Settings
            SettingsLink {
                Image(systemName: "gear")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)

            // Quit
            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Image(systemName: "power")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .padding(.leading, 8)
        }
    }
}

#Preview {
    MenuBarView()
        .environmentObject(AppState())
}
