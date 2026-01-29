import SwiftUI
import AVFoundation

/// Apple HIG-compliant onboarding with authentic liquid glass
struct OnboardingView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    @State private var currentStep = 0
    @State private var micLevel: Float = 0
    @State private var permissionCheckTimer: Timer?
    @State private var audioEngine: AVAudioEngine?

    private let totalSteps = 3

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
                .frame(height: 48)

            // Icon
            iconView
                .padding(.bottom, 24)

            // Title
            Text(titleText)
                .font(.system(size: 26, weight: .bold, design: .default))
                .multilineTextAlignment(.center)
                .padding(.bottom, 8)

            // Subtitle
            Text(subtitleText)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineSpacing(2)
                .frame(maxWidth: 280)
                .padding(.bottom, 32)

            // Content card
            contentCard
                .padding(.horizontal, 40)
                .padding(.bottom, 32)

            Spacer()

            // Page indicator
            pageIndicator
                .padding(.bottom, 24)

            // Button
            primaryButton
                .padding(.horizontal, 40)
                .padding(.bottom, 40)
        }
        .frame(width: 480, height: 520)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear { startPermissionPolling() }
        .onDisappear { stopAllTimers() }
    }

    // MARK: - Icon

    @ViewBuilder
    private var iconView: some View {
        ZStack {
            // Outer ring with glass effect
            Circle()
                .fill(.ultraThinMaterial)
                .frame(width: 64, height: 64)
                .shadow(color: .black.opacity(0.06), radius: 12, y: 4)
                .overlay(
                    Circle()
                        .strokeBorder(
                            LinearGradient(
                                colors: [.white.opacity(0.5), .white.opacity(0.1)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 0.5
                        )
                )

            // Icon
            Image(systemName: iconName)
                .font(.system(size: 28, weight: .medium))
                .foregroundStyle(iconColor)
                .symbolRenderingMode(.hierarchical)
        }
    }

    private var iconName: String {
        switch currentStep {
        case 0: return appState.microphonePermission == .granted ? "checkmark.circle.fill" : "mic.fill"
        case 1: return appState.accessibilityPermission == .granted ? "checkmark.circle.fill" : "hand.raised.fill"
        case 2: return "checkmark.circle.fill"
        default: return "circle"
        }
    }

    private var iconColor: Color {
        switch currentStep {
        case 0: return appState.microphonePermission == .granted ? .green : .blue
        case 1: return appState.accessibilityPermission == .granted ? .green : .orange
        case 2: return .green
        default: return .secondary
        }
    }

    // MARK: - Text

    private var titleText: String {
        switch currentStep {
        case 0: return "Microphone Access"
        case 1: return "Accessibility Access"
        case 2: return "Ready to Go"
        default: return ""
        }
    }

    private var subtitleText: String {
        switch currentStep {
        case 0: return "OpenEar needs microphone access to transcribe your speech. Audio is processed locally."
        case 1: return "Accessibility access is required to type transcribed text and detect the global hotkey."
        case 2: return "Hold the Fn key or press Control-Space to start recording."
        default: return ""
        }
    }

    // MARK: - Content Card

    @ViewBuilder
    private var contentCard: some View {
        switch currentStep {
        case 0: microphoneCard
        case 1: accessibilityCard
        case 2: readyCard
        default: EmptyView()
        }
    }

    private var microphoneCard: some View {
        AppleGlassCard {
            if appState.microphonePermission == .granted {
                VStack(spacing: 16) {
                    // Waveform
                    HStack(spacing: 3) {
                        ForEach(0..<20, id: \.self) { i in
                            RoundedRectangle(cornerRadius: 1.5)
                                .fill(micLevel > 0.05 ? Color.green : Color.secondary.opacity(0.3))
                                .frame(width: 4, height: barHeight(for: i, of: 20))
                        }
                    }
                    .frame(height: 32)
                    .animation(.easeOut(duration: 0.08), value: micLevel)

                    Text(micLevel > 0.05 ? "Microphone is working" : "Speak to test microphone")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .onAppear { startMicTest() }
                .onDisappear { stopMicTest() }
            } else {
                VStack(spacing: 16) {
                    Image(systemName: "mic.badge.plus")
                        .font(.system(size: 32))
                        .foregroundStyle(.secondary)
                        .symbolRenderingMode(.hierarchical)

                    Text("Click Continue to grant access")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var accessibilityCard: some View {
        AppleGlassCard {
            if appState.accessibilityPermission == .granted {
                VStack(spacing: 12) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 32))
                        .foregroundStyle(.green)

                    Text("Accessibility enabled")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            } else {
                VStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 12) {
                        instructionRow(number: "1", text: "Click Open System Settings")
                        instructionRow(number: "2", text: "Find OpenEar in the list")
                        instructionRow(number: "3", text: "Toggle the switch on")
                    }

                    Button(action: openAccessibilitySettings) {
                        Text("Open System Settings")
                            .font(.system(size: 13, weight: .medium))
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.regular)
                }
            }
        }
    }

    private var readyCard: some View {
        AppleGlassCard {
            HStack(spacing: 20) {
                keyCapView("Fn")
                Text("or")
                    .font(.system(size: 12))
                    .foregroundStyle(.tertiary)
                HStack(spacing: 4) {
                    keyCapView("⌃")
                    keyCapView("Space")
                }
            }
        }
    }

    private func instructionRow(number: String, text: String) -> some View {
        HStack(spacing: 12) {
            Text(number)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
                .frame(width: 20, height: 20)
                .background(Color.secondary)
                .clipShape(Circle())

            Text(text)
                .font(.system(size: 13))
                .foregroundStyle(.primary)

            Spacer()
        }
    }

    private func keyCapView(_ key: String) -> some View {
        Text(key)
            .font(.system(size: 13, weight: .medium, design: .rounded))
            .foregroundStyle(.primary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
                    .shadow(color: .black.opacity(0.1), radius: 1, y: 1)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.1), lineWidth: 0.5)
            )
    }

    private func barHeight(for index: Int, of total: Int) -> CGFloat {
        let center = total / 2
        let dist = abs(index - center)
        let factor = 1.0 - (CGFloat(dist) / CGFloat(center)) * 0.6
        return 4 + 28 * CGFloat(micLevel) * factor
    }

    // MARK: - Page Indicator

    private var pageIndicator: some View {
        HStack(spacing: 8) {
            ForEach(0..<totalSteps, id: \.self) { index in
                Circle()
                    .fill(index == currentStep ? Color.primary : Color.primary.opacity(0.2))
                    .frame(width: 6, height: 6)
                    .animation(.easeInOut(duration: 0.2), value: currentStep)
            }
        }
    }

    // MARK: - Primary Button

    private var primaryButton: some View {
        Button(action: handleNext) {
            Text(buttonTitle)
                .font(.system(size: 14, weight: .medium))
                .frame(maxWidth: .infinity)
                .frame(height: 44)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .disabled(isButtonDisabled)
    }

    private var buttonTitle: String {
        switch currentStep {
        case 0:
            return appState.microphonePermission == .granted ? "Continue" : "Continue"
        case 1:
            return appState.accessibilityPermission == .granted ? "Continue" : "Waiting for Permission..."
        case 2:
            return "Done"
        default:
            return "Continue"
        }
    }

    private var isButtonDisabled: Bool {
        switch currentStep {
        case 1: return appState.accessibilityPermission != .granted
        default: return false
        }
    }

    // MARK: - Actions

    private func handleNext() {
        if currentStep == 0 && appState.microphonePermission != .granted {
            Task { await appState.checkPermissions() }
            return
        }

        if currentStep == totalSteps - 1 {
            appState.completeOnboarding()
            AppDelegate.shared?.closeOnboarding()
            dismiss()
        } else {
            withAnimation(.easeInOut(duration: 0.3)) {
                currentStep += 1
            }
        }
    }

    private func openAccessibilitySettings() {
        // Lower window level so System Settings appears on top
        NSApp.windows.forEach { window in
            if window.title == "OpenEar Setup" {
                window.level = .normal
            }
        }
        appState.requestAccessibilityPermission()
    }

    // MARK: - Timers

    private func startPermissionPolling() {
        permissionCheckTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            Task { @MainActor in
                await appState.checkPermissions()
            }
        }
    }

    private func stopAllTimers() {
        permissionCheckTimer?.invalidate()
        permissionCheckTimer = nil
        stopMicTest()
    }

    private func startMicTest() {
        stopMicTest()
        audioEngine = AVAudioEngine()
        guard let audioEngine = audioEngine else { return }

        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            guard let channelData = buffer.floatChannelData?[0] else { return }
            let frames = buffer.frameLength
            var sum: Float = 0
            for i in 0..<Int(frames) { sum += channelData[i] * channelData[i] }
            let rms = sqrt(sum / Float(frames))
            let db = 20 * log10(max(rms, 0.0001))
            let normalized = max(0, min(1, (db + 50) / 50))
            DispatchQueue.main.async { self.micLevel = normalized }
        }

        do { try audioEngine.start() } catch { print("Mic test error: \(error)") }
    }

    private func stopMicTest() {
        audioEngine?.stop()
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine = nil
        micLevel = 0
    }
}

// MARK: - Apple Glass Card

struct AppleGlassCard<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme
    let content: () -> Content

    init(@ViewBuilder content: @escaping () -> Content) {
        self.content = content
    }

    var body: some View {
        content()
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 24)
            .padding(.vertical, 20)
            .background(glassBackground)
    }

    private var glassBackground: some View {
        ZStack {
            // Base material
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.regularMaterial)

            // Top highlight (light refraction)
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(
                    LinearGradient(
                        stops: [
                            .init(color: .white.opacity(colorScheme == .dark ? 0.08 : 0.5), location: 0),
                            .init(color: .clear, location: 0.4)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

            // Border
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [
                            .white.opacity(colorScheme == .dark ? 0.2 : 0.6),
                            .white.opacity(colorScheme == .dark ? 0.05 : 0.2)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 0.5
                )
        }
        .shadow(color: .black.opacity(0.08), radius: 16, y: 6)
    }
}

#Preview {
    OnboardingView()
        .environmentObject(AppState())
}
