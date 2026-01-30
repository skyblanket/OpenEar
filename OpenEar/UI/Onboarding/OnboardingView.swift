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
    @State private var selectedModelOption: ModelOption = .balanced

    // Download state
    @State private var isDownloading = false
    @State private var downloadProgress: Double = 0
    @State private var downloadedMB: Double = 0
    @State private var totalMB: Double = 0
    @State private var downloadSpeed: Double = 0
    @State private var downloadError: String?
    @State private var downloadComplete = false
    @State private var isPreparing = false  // Loading model after download
    @State private var lastDownloadedBytes: Int64 = 0
    @State private var lastSpeedUpdate: Date = Date()
    @State private var retryCount: Int = 0

    private let totalSteps = 5

    enum ModelOption: String, CaseIterable {
        case fast = "tiny.en"
        case balanced = "base.en"
        case accurate = "small.en"

        var displayName: String {
            switch self {
            case .fast: return "Fast"
            case .balanced: return "Balanced"
            case .accurate: return "Accurate"
            }
        }

        var description: String {
            switch self {
            case .fast: return "~0.3s latency • 39MB"
            case .balanced: return "~0.5s latency • 142MB"
            case .accurate: return "~1s latency • 466MB"
            }
        }

        var detail: String {
            switch self {
            case .fast: return "Best for quick commands"
            case .balanced: return "Good balance of speed & accuracy"
            case .accurate: return "Best transcription quality"
            }
        }

        var icon: String {
            switch self {
            case .fast: return "hare"
            case .balanced: return "scalemass"
            case .accurate: return "text.magnifyingglass"
            }
        }
    }

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
        .onAppear {
            Analytics.shared.trackOnboardingStarted()
            Analytics.shared.trackOnboardingStepViewed(0, name: "microphone")
            startPermissionPolling()
        }
        .onDisappear {
            stopAllTimers()
            // Track if abandoned (not completed)
            if currentStep < totalSteps - 1 {
                let stepNames = ["microphone", "accessibility", "model_selection", "download", "ready"]
                Analytics.shared.trackOnboardingAbandoned(atStep: currentStep, stepName: stepNames[currentStep])
            }
        }
        .onChange(of: currentStep) { _, newStep in
            let stepNames = ["microphone", "accessibility", "model_selection", "download", "ready"]
            if newStep < stepNames.count {
                Analytics.shared.trackOnboardingStepViewed(newStep, name: stepNames[newStep])
            }
        }
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
        case 2: return "cpu"
        case 3:
            if downloadComplete { return "checkmark.circle.fill" }
            if isPreparing { return "gearshape.2" }
            return "arrow.down.circle"
        case 4: return "checkmark.circle.fill"
        default: return "circle"
        }
    }

    private var iconColor: Color {
        switch currentStep {
        case 0: return appState.microphonePermission == .granted ? .green : .blue
        case 1: return appState.accessibilityPermission == .granted ? .green : .orange
        case 2: return .purple
        case 3:
            if downloadComplete { return .green }
            if isPreparing { return .orange }
            return .blue
        case 4: return .green
        default: return .secondary
        }
    }

    // MARK: - Text

    private var titleText: String {
        switch currentStep {
        case 0: return "Microphone Access"
        case 1: return "Accessibility Access"
        case 2: return "Choose Your Model"
        case 3:
            if downloadComplete { return "Download Complete" }
            if isPreparing { return "Preparing Model" }
            return "Downloading Model"
        case 4: return "Ready to Go"
        default: return ""
        }
    }

    private var subtitleText: String {
        switch currentStep {
        case 0: return "OpenEar needs microphone access to transcribe your speech. Audio is processed locally."
        case 1: return "Accessibility access is required to type transcribed text and detect the global hotkey."
        case 2: return "Select a transcription model based on your preference. You can change this later in Settings."
        case 3:
            if downloadComplete { return "The \(selectedModelOption.displayName) model is ready to use." }
            if isPreparing { return "Loading \(selectedModelOption.displayName) model into memory..." }
            return "Downloading \(selectedModelOption.displayName) model..."
        case 4: return "Hold the Fn key or press Control-Space to start recording."
        default: return ""
        }
    }

    // MARK: - Content Card

    @ViewBuilder
    private var contentCard: some View {
        switch currentStep {
        case 0: microphoneCard
        case 1: accessibilityCard
        case 2: modelSelectionCard
        case 3: downloadCard
        case 4: readyCard
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

    private var modelSelectionCard: some View {
        VStack(spacing: 8) {
            ForEach(ModelOption.allCases, id: \.self) { option in
                ModelOptionRow(
                    option: option,
                    isSelected: selectedModelOption == option,
                    action: { selectedModelOption = option }
                )
            }
        }
    }

    private var downloadCard: some View {
        AppleGlassCard {
            VStack(spacing: 20) {
                if let error = downloadError {
                    // Error state with recovery options
                    VStack(spacing: 14) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 28))
                            .foregroundStyle(.red)

                        Text("Download Failed")
                            .font(.system(size: 13, weight: .semibold))

                        Text(simplifyError(error))
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .lineLimit(2)

                        VStack(spacing: 8) {
                            Button("Retry Download") {
                                downloadError = nil
                                retryCount += 1
                                Analytics.shared.trackModelDownloadRetry(
                                    selectedModelOption.rawValue,
                                    attemptNumber: retryCount,
                                    error: error
                                )
                                startDownload()
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)

                            // Offer to try smaller model if not already on smallest
                            if selectedModelOption != .fast {
                                Button("Try Smaller Model (\(ModelOption.fast.displayName))") {
                                    downloadError = nil
                                    selectedModelOption = .fast
                                    startDownload()
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            }

                            Button("Go Back") {
                                downloadError = nil
                                withAnimation {
                                    currentStep = 2  // Back to model selection
                                }
                            }
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                        }
                    }
                } else if downloadComplete {
                    // Complete state
                    VStack(spacing: 12) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 32))
                            .foregroundStyle(.green)

                        Text("Model ready")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.primary)
                    }
                } else if isPreparing {
                    // Preparing/Loading state after download
                    VStack(spacing: 16) {
                        ProgressView()
                            .scaleEffect(1.2)
                            .tint(.blue)

                        Text("Preparing model...")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.primary)

                        Text("This may take a moment")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                } else {
                    // Downloading state
                    VStack(spacing: 16) {
                        // Progress bar
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                // Track
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(Color.primary.opacity(0.1))
                                    .frame(height: 8)

                                // Fill
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(
                                        LinearGradient(
                                            colors: [.blue, .blue.opacity(0.8)],
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        )
                                    )
                                    .frame(width: geo.size.width * downloadProgress, height: 8)
                                    .animation(.easeOut(duration: 0.3), value: downloadProgress)
                            }
                        }
                        .frame(height: 8)

                        // Stats row
                        HStack {
                            // Downloaded / Total
                            Text("\(String(format: "%.1f", downloadedMB)) / \(String(format: "%.1f", totalMB)) MB")
                                .font(.system(size: 11, weight: .medium, design: .monospaced))
                                .foregroundStyle(.secondary)

                            Spacer()

                            // Speed
                            if downloadSpeed > 0 {
                                HStack(spacing: 4) {
                                    Image(systemName: "arrow.down")
                                        .font(.system(size: 9, weight: .semibold))
                                    Text("\(String(format: "%.1f", downloadSpeed)) MB/s")
                                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                                }
                                .foregroundStyle(.secondary)
                            }
                        }

                        // Percentage
                        Text("\(Int(downloadProgress * 100))%")
                            .font(.system(size: 24, weight: .semibold, design: .rounded))
                            .foregroundStyle(.primary)
                    }
                }
            }
        }
        .onAppear {
            if !downloadComplete && !isDownloading {
                startDownload()
            }
        }
    }

    private func startDownload() {
        isDownloading = true
        downloadProgress = 0
        downloadedMB = 0
        downloadError = nil
        lastDownloadedBytes = 0
        lastSpeedUpdate = Date()

        // Set total size based on model
        switch selectedModelOption {
        case .fast: totalMB = 39
        case .balanced: totalMB = 142
        case .accurate: totalMB = 466
        }

        let downloadStartTime = Date()
        Analytics.shared.trackModelSelected(selectedModelOption.rawValue)
        Analytics.shared.trackModelDownloadStarted(selectedModelOption.rawValue)

        Task {
            do {
                // Apply the model selection
                appState.selectedModel = selectedModelOption.rawValue

                // Use WhisperKit to download with progress
                try await appState.downloadModelWithProgress(
                    { progress in
                        Task { @MainActor in
                            self.downloadProgress = progress.fractionCompleted
                            let downloadedBytes = Int64(progress.fractionCompleted * totalMB * 1024 * 1024)
                            self.downloadedMB = Double(downloadedBytes) / (1024 * 1024)

                            // Calculate speed
                            let now = Date()
                            let elapsed = now.timeIntervalSince(lastSpeedUpdate)
                            if elapsed >= 0.5 {
                                let bytesDiff = downloadedBytes - lastDownloadedBytes
                                self.downloadSpeed = Double(bytesDiff) / elapsed / (1024 * 1024)
                                self.lastDownloadedBytes = downloadedBytes
                                self.lastSpeedUpdate = now
                            }
                        }
                    },
                    onDownloadComplete: {
                        Task { @MainActor in
                            // Download done, now preparing/loading model
                            self.downloadProgress = 1.0
                            self.downloadedMB = self.totalMB
                            self.isDownloading = false
                            self.isPreparing = true
                        }
                    }
                )

                await MainActor.run {
                    isPreparing = false
                    downloadComplete = true
                    let duration = Date().timeIntervalSince(downloadStartTime)
                    Analytics.shared.trackModelDownloadCompleted(selectedModelOption.rawValue, durationSeconds: duration)
                }
            } catch {
                await MainActor.run {
                    downloadError = error.localizedDescription
                    isDownloading = false
                    isPreparing = false
                    Analytics.shared.trackModelDownloadFailed(selectedModelOption.rawValue, error: error.localizedDescription)
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
            return "Download & Continue"
        case 3:
            return downloadComplete ? "Continue" : "Downloading..."
        case 4:
            return "Done"
        default:
            return "Continue"
        }
    }

    private var isButtonDisabled: Bool {
        switch currentStep {
        case 1: return appState.accessibilityPermission != .granted
        case 3: return !downloadComplete
        default: return false
        }
    }

    // MARK: - Actions

    private func handleNext() {
        // Track step completion
        let stepNames = ["microphone", "accessibility", "model_selection", "download", "ready"]
        if currentStep < stepNames.count {
            Analytics.shared.trackOnboardingStep(currentStep, name: stepNames[currentStep])
        }

        // Step 0: Microphone permission
        if currentStep == 0 && appState.microphonePermission != .granted {
            Task {
                await appState.requestMicrophonePermission()
                // If granted, wait 2 seconds to show success, then advance
                if appState.microphonePermission == .granted {
                    Analytics.shared.trackPermissionGranted("microphone")
                    // Wait 2 seconds so user sees the success state
                    try? await Task.sleep(nanoseconds: 2_000_000_000)
                    await MainActor.run {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            currentStep += 1
                        }
                    }
                } else {
                    Analytics.shared.trackPermissionDenied("microphone")
                }
            }
            return
        }

        if currentStep == totalSteps - 1 {
            Analytics.shared.trackOnboardingCompleted()
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
        // Minimize/hide the onboarding window so System Settings is visible
        if let window = NSApp.windows.first(where: { $0.title == "OpenEar Setup" }) {
            window.miniaturize(nil)
        }
        appState.requestAccessibilityPermission()
    }

    // MARK: - Timers

    private func startPermissionPolling() {
        // Stop any existing timer
        permissionCheckTimer?.invalidate()

        // Poll every 0.5 seconds for faster response
        let timer = Timer(timeInterval: 0.5, repeats: true) { _ in
            Task { @MainActor in
                let oldMic = appState.microphonePermission
                let oldAcc = appState.accessibilityPermission

                await appState.checkPermissions()

                // Track permission changes and handle UI
                if oldMic != appState.microphonePermission && appState.microphonePermission == .granted {
                    Analytics.shared.trackPermissionGranted("microphone")
                }
                if oldAcc != appState.accessibilityPermission && appState.accessibilityPermission == .granted {
                    Analytics.shared.trackPermissionGranted("accessibility")
                    // Bring app to front and close System Settings
                    appState.onAccessibilityGranted()
                }
            }
        }
        // Schedule on main run loop
        RunLoop.main.add(timer, forMode: .common)
        permissionCheckTimer = timer

        // Fire immediately too
        Task {
            await appState.checkPermissions()
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

    /// Convert technical errors to user-friendly messages
    private func simplifyError(_ error: String) -> String {
        let lowercased = error.lowercased()
        if lowercased.contains("network") || lowercased.contains("internet") || lowercased.contains("offline") {
            return "No internet connection. Please check your network."
        } else if lowercased.contains("timeout") {
            return "Download timed out. Please try again."
        } else if lowercased.contains("space") || lowercased.contains("disk") || lowercased.contains("storage") {
            return "Not enough storage space. Free up some space and try again."
        } else if lowercased.contains("cancelled") || lowercased.contains("canceled") {
            return "Download was cancelled."
        } else if error.count > 80 {
            return "Something went wrong. Please try again."
        }
        return error
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

// MARK: - Model Option Row

struct ModelOptionRow: View {
    let option: OnboardingView.ModelOption
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                // Icon
                Image(systemName: option.icon)
                    .font(.system(size: 18))
                    .foregroundStyle(isSelected ? .white : .secondary)
                    .frame(width: 36, height: 36)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(isSelected ? Color.accentColor : Color.secondary.opacity(0.1))
                    )

                // Text
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(option.displayName)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.primary)

                        if option == .balanced {
                            Text("Recommended")
                                .font(.system(size: 9, weight: .medium))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.accentColor.opacity(0.8))
                                .clipShape(Capsule())
                        }
                    }

                    Text(option.detail)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                // Size/Speed info
                Text(option.description)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(.tertiary)

                // Checkmark
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 18))
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary.opacity(0.5))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isSelected ? Color.accentColor.opacity(0.1) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(isSelected ? Color.accentColor.opacity(0.3) : Color.primary.opacity(0.1), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    OnboardingView()
        .environmentObject(AppState())
}
