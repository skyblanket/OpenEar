import SwiftUI
import Combine

/// Central state machine for the OpenEar app
@MainActor
final class AppState: ObservableObject {

    // MARK: - Types

    enum RecordingState: Equatable {
        case idle
        case recording
        case transcribing
        case injecting
        case error(String)

        var isActive: Bool {
            switch self {
            case .recording, .transcribing, .injecting:
                return true
            default:
                return false
            }
        }
    }

    enum PermissionState {
        case unknown
        case granted
        case denied
    }

    // MARK: - Published State

    @Published var recordingState: RecordingState = .idle
    @Published var partialTranscription: String = ""
    @Published var finalTranscription: String = ""
    @Published var audioLevel: Float = 0.0
    @Published var isModelDownloaded: Bool = false
    @Published var modelDownloadProgress: Double = 0.0
    @Published var microphonePermission: PermissionState = .unknown
    @Published var accessibilityPermission: PermissionState = .unknown
    @Published var showOnboarding: Bool = false
    @Published var selectedModel: String = "tiny.en"  // Faster for real-time, slightly less accurate

    // MARK: - Dependencies

    private var audioCaptureManager: AudioCaptureManager?
    private var transcriptionEngine: TranscriptionEngine?
    private var textInjector: TextInjector?
    private var fnKeyMonitor: FnKeyMonitor?
    private var hotkeyManager: HotkeyManager?

    private var cancellables = Set<AnyCancellable>()
    private var audioBuffer: [Float] = []
    private var hasSetup = false
    private var recordingStartTime: Date?
    private var recordingTrigger: String = "unknown"
    private var firstWordTime: Date?
    private var hasTrackedFirstWord = false

    // MARK: - Initialization

    init() {
        checkFirstLaunch()
    }

    // MARK: - Setup

    func setup() async {
        guard !hasSetup else { return }
        hasSetup = true

        print("OpenEar: Starting setup...")
        await checkPermissions()
        print("OpenEar: Permissions checked - Mic: \(microphonePermission), Accessibility: \(accessibilityPermission)")

        // Show onboarding if permissions are missing
        checkIfOnboardingNeeded()
        setupAudioCapture()
        print("OpenEar: Audio capture ready")
        await setupTranscriptionEngine()
        print("OpenEar: Transcription engine ready, model downloaded: \(isModelDownloaded)")
        setupTextInjector()
        print("OpenEar: Text injector ready")
        setupHotkeyMonitoring()
        print("OpenEar: Hotkey monitoring ready")

        // Setup recording overlay
        RecordingOverlayController.shared.setup(appState: self)
        print("OpenEar: Setup complete! Hold Fn or Ctrl+Space to record.")
    }

    private func checkFirstLaunch() {
        let hasLaunched = UserDefaults.standard.bool(forKey: "hasLaunchedBefore")
        print("OpenEar: hasLaunchedBefore = \(hasLaunched)")
        if !hasLaunched {
            showOnboarding = true
            print("OpenEar: First launch - will show onboarding")
        }
    }

    /// Check if onboarding should be shown (permissions not granted)
    func checkIfOnboardingNeeded() {
        // Show onboarding if any required permission is missing or unknown
        if microphonePermission != .granted || accessibilityPermission != .granted {
            showOnboarding = true
            print("OpenEar: Permissions missing (mic: \(microphonePermission), acc: \(accessibilityPermission)) - showing onboarding")
        }
    }

    func completeOnboarding() {
        UserDefaults.standard.set(true, forKey: "hasLaunchedBefore")
        showOnboarding = false

        // Run remaining setup that was skipped during onboarding
        Task {
            await finishSetupAfterOnboarding()
        }
    }

    /// Setup components that weren't initialized during onboarding
    private func finishSetupAfterOnboarding() async {
        guard !hasSetup else { return }
        hasSetup = true

        print("OpenEar: Finishing setup after onboarding...")
        setupAudioCapture()
        print("OpenEar: Audio capture ready")
        // Model already downloaded during onboarding, just ensure engine is ready
        if transcriptionEngine == nil {
            transcriptionEngine = TranscriptionEngine()
        }
        setupTextInjector()
        print("OpenEar: Text injector ready")
        setupHotkeyMonitoring()
        print("OpenEar: Hotkey monitoring ready")
        RecordingOverlayController.shared.setup(appState: self)
        print("OpenEar: Setup complete after onboarding!")
    }

    /// Reset onboarding (for testing)
    func resetOnboarding() {
        UserDefaults.standard.set(false, forKey: "hasLaunchedBefore")
        showOnboarding = true
    }

    // MARK: - Permissions

    func checkPermissions() async {
        // Check microphone permission
        microphonePermission = await checkMicrophonePermission()

        // Check accessibility permission
        accessibilityPermission = checkAccessibilityPermission()
    }

    private func checkMicrophonePermission() async -> PermissionState {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return .granted
        case .notDetermined:
            return .unknown  // Don't auto-request, let user trigger it
        case .denied, .restricted:
            return .denied
        @unknown default:
            return .unknown
        }
    }

    /// Explicitly request microphone permission (called when user clicks Continue)
    func requestMicrophonePermission() async {
        print("OpenEar: Requesting microphone permission...")
        let granted = await AVCaptureDevice.requestAccess(for: .audio)
        microphonePermission = granted ? .granted : .denied
        print("OpenEar: Microphone permission result: \(microphonePermission)")
    }

    private func checkAccessibilityPermission() -> PermissionState {
        let trusted = AXIsProcessTrusted()
        return trusted ? .granted : .denied
    }

    func requestAccessibilityPermission() {
        // Use AXIsProcessTrustedWithOptions to:
        // 1. Add the app to the Accessibility list (if not already there)
        // 2. Open System Settings > Privacy > Accessibility
        // The prompt option both adds the app AND opens settings - don't open settings separately
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        let _ = AXIsProcessTrustedWithOptions(options)
        print("OpenEar: Requested accessibility permission (opens System Settings)")

        // Bring System Settings to front after a small delay
        bringSystemSettingsToFront()
    }

    /// Bring System Settings to front so it's visible above onboarding
    private func bringSystemSettingsToFront() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            let runningApps = NSWorkspace.shared.runningApplications
            for app in runningApps {
                if app.bundleIdentifier == "com.apple.systempreferences" ||
                   app.bundleIdentifier == "com.apple.Preferences" {
                    app.activate(options: .activateIgnoringOtherApps)
                    print("OpenEar: Brought System Settings to front")
                    return
                }
            }
        }
    }

    /// Called when accessibility permission is granted - bring app to front
    func onAccessibilityGranted() {
        print("OpenEar: Accessibility granted, bringing app to front")

        // Close System Settings
        let runningApps = NSWorkspace.shared.runningApplications
        for app in runningApps {
            if app.bundleIdentifier == "com.apple.systempreferences" ||
               app.bundleIdentifier == "com.apple.Preferences" ||
               app.bundleIdentifier == "com.apple.systempreferences.universal-access" {
                app.terminate()
            }
        }

        // Small delay to let System Settings close
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            // Bring our app to front
            NSApp.activate(ignoringOtherApps: true)

            // Restore and show onboarding window
            for window in NSApp.windows {
                if window.title == "OpenEar Setup" {
                    // Deminiaturize if it was minimized
                    if window.isMiniaturized {
                        window.deminiaturize(nil)
                    }
                    window.makeKeyAndOrderFront(nil)
                    window.orderFrontRegardless()
                }
            }
        }
    }

    // MARK: - Audio Capture

    private func setupAudioCapture() {
        audioCaptureManager = AudioCaptureManager()

        audioCaptureManager?.onAudioLevel = { [weak self] level in
            Task { @MainActor in
                self?.audioLevel = level
            }
        }

        audioCaptureManager?.onAudioBuffer = { [weak self] buffer in
            Task { @MainActor in
                self?.audioBuffer.append(contentsOf: buffer)
                // Stream to transcription engine for real-time results
                await self?.streamAudioChunk(buffer)
            }
        }
    }

    // MARK: - Transcription

    private func setupTranscriptionEngine() async {
        transcriptionEngine = TranscriptionEngine()

        // Auto-load the model (downloads automatically if needed, caches for future)
        do {
            print("OpenEar: Auto-loading transcription model...")
            try await transcriptionEngine?.loadModel(selectedModel)
            isModelDownloaded = true
            print("OpenEar: Model ready!")
        } catch {
            print("OpenEar: Model loading failed: \(error)")
            // Don't block setup - user can still grant permissions
            // Model will retry when they try to record
        }
    }

    func downloadModel() async {
        guard let engine = transcriptionEngine else { return }

        do {
            print("OpenEar: Loading model \(selectedModel)...")
            try await engine.loadModel(selectedModel)
            isModelDownloaded = true
            print("OpenEar: Model loaded successfully!")
        } catch {
            print("OpenEar: Model loading failed: \(error)")
            recordingState = .error("Failed to load model: \(error.localizedDescription)")
        }
    }

    func downloadModelWithProgress(
        _ progressHandler: @escaping (Progress) -> Void,
        onDownloadComplete: (() -> Void)? = nil
    ) async throws {
        // Ensure transcription engine exists
        if transcriptionEngine == nil {
            transcriptionEngine = TranscriptionEngine()
        }

        guard let engine = transcriptionEngine else {
            throw NSError(domain: "OpenEar", code: 1, userInfo: [NSLocalizedDescriptionKey: "Engine not initialized"])
        }

        print("OpenEar: Loading model \(selectedModel) with progress...")
        try await engine.loadModelWithProgress(
            selectedModel,
            progressHandler: progressHandler,
            onDownloadComplete: onDownloadComplete
        )
        isModelDownloaded = true
        print("OpenEar: Model loaded successfully!")
    }

    private func streamAudioChunk(_ buffer: [Float]) async {
        guard recordingState == .recording else { return }

        // Stream chunks to transcription engine for real-time partial results
        if let partialText = await transcriptionEngine?.transcribeChunk(buffer) {
            // Track time to first word (when we first get non-empty text)
            if !hasTrackedFirstWord && !partialText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                hasTrackedFirstWord = true
                if let startTime = recordingStartTime {
                    let latencyMs = Int(Date().timeIntervalSince(startTime) * 1000)
                    Analytics.shared.trackTimeToFirstWord(latencyMs: latencyMs, model: selectedModel)
                }
            }
            partialTranscription = partialText
        }
    }

    // MARK: - Text Injection

    private func setupTextInjector() {
        textInjector = TextInjector()
    }

    // MARK: - Hotkey Monitoring

    private func setupHotkeyMonitoring() {
        // Try Fn key monitoring first (cleanest - no character output)
        fnKeyMonitor = FnKeyMonitor()

        fnKeyMonitor?.onFnDown = { [weak self] in
            Task { @MainActor in
                await self?.startRecording(trigger: "fn_key")
            }
        }

        fnKeyMonitor?.onFnUp = { [weak self] in
            Task { @MainActor in
                await self?.stopRecording()
            }
        }

        // Start Fn monitoring
        let fnStarted = fnKeyMonitor?.start() ?? false

        if fnStarted {
            print("OpenEar: Using Fn (Globe) key for recording")
        } else {
            print("OpenEar: Fn key unavailable, setting up fallback hotkey")
        }

        // Also setup fallback hotkey (Ctrl+Space - doesn't type characters)
        hotkeyManager = HotkeyManager()

        hotkeyManager?.onHotkeyDown = { [weak self] in
            Task { @MainActor in
                await self?.startRecording(trigger: "ctrl_space")
            }
        }

        hotkeyManager?.onHotkeyUp = { [weak self] in
            Task { @MainActor in
                await self?.stopRecording()
            }
        }

        // Register fallback hotkey
        hotkeyManager?.registerHotkey()
        print("OpenEar: Fallback hotkey also available (check Settings to customize)")
    }

    // MARK: - Recording Control

    func startRecording(trigger: String = "unknown") async {
        print("OpenEar: startRecording called, current state: \(recordingState)")
        guard recordingState == .idle else {
            print("OpenEar: Not idle, ignoring")
            return
        }
        guard microphonePermission == .granted else {
            print("OpenEar: Mic permission not granted!")
            recordingState = .error("Microphone permission required")
            Analytics.shared.trackRecordingFailed(error: "Microphone permission required", state: "idle")
            return
        }
        guard isModelDownloaded else {
            print("OpenEar: Model not downloaded!")
            recordingState = .error("Model not downloaded")
            Analytics.shared.trackRecordingFailed(error: "Model not downloaded", state: "idle")
            return
        }

        print("OpenEar: Starting recording...")
        recordingState = .recording
        audioBuffer = []
        partialTranscription = ""
        finalTranscription = ""
        recordingStartTime = Date()
        recordingTrigger = trigger
        hasTrackedFirstWord = false
        firstWordTime = nil

        // Track recording start with trigger source
        Analytics.shared.trackRecordingStarted(trigger: trigger)
        Analytics.shared.trackHotkeyUsed(trigger)

        // Show recording overlay near the input field
        RecordingOverlayController.shared.show()

        // Start streaming transcription
        await transcriptionEngine?.startStreaming()

        // Start audio capture
        do {
            try audioCaptureManager?.startCapture()
            print("OpenEar: Recording started!")
        } catch {
            print("OpenEar: Failed to start: \(error)")
            recordingState = .error("Failed to start recording: \(error.localizedDescription)")
            Analytics.shared.trackRecordingFailed(error: error.localizedDescription, state: "starting")
            RecordingOverlayController.shared.hide()
        }
    }

    func stopRecording() async {
        print("OpenEar: stopRecording called, current state: \(recordingState)")
        guard recordingState == .recording else { return }

        recordingState = .transcribing
        let recordingDuration = recordingStartTime.map { Date().timeIntervalSince($0) } ?? 0
        let audioDuration = Double(audioBuffer.count) / 16000.0  // 16kHz sample rate
        print("OpenEar: Transcribing \(audioBuffer.count) samples...")

        // Track recording completed
        Analytics.shared.trackRecordingCompleted(durationSeconds: recordingDuration, audioSamples: audioBuffer.count)

        // Stop audio capture
        audioCaptureManager?.stopCapture()

        // Finalize transcription
        let transcriptionStart = Date()
        if let finalText = await transcriptionEngine?.finishStreaming(audioBuffer) {
            finalTranscription = finalText.trimmingCharacters(in: .whitespacesAndNewlines)
            print("OpenEar: Transcription result: \(finalTranscription)")

            let transcriptionDuration = Date().timeIntervalSince(transcriptionStart)
            let wordCount = finalTranscription.split(separator: " ").count

            // Track transcription with full metrics
            Analytics.shared.trackTranscriptionCompleted(
                durationSeconds: transcriptionDuration,
                characterCount: finalTranscription.count,
                wordCount: wordCount,
                audioDurationSeconds: audioDuration,
                model: selectedModel
            )

            // Track latency ratio
            Analytics.shared.trackTranscriptionLatency(
                audioDurationSeconds: audioDuration,
                processingTimeSeconds: transcriptionDuration,
                model: selectedModel
            )

            // Track empty transcription (user spoke but got nothing)
            if finalTranscription.isEmpty && audioDuration > 1.0 {
                Analytics.shared.trackTranscriptionEmpty(audioDurationSeconds: audioDuration)
            }
        }

        // Inject text if we have any
        if !finalTranscription.isEmpty {
            recordingState = .injecting
            print("OpenEar: Injecting text...")

            guard accessibilityPermission == .granted else {
                print("OpenEar: Accessibility permission not granted!")
                recordingState = .error("Accessibility permission required for text injection")
                Analytics.shared.trackTextInjectionFailed(error: "Accessibility permission not granted")
                return
            }

            textInjector?.injectText(finalTranscription)
            Analytics.shared.trackTextInjected(characterCount: finalTranscription.count)
            print("OpenEar: Text injected!")
        } else {
            print("OpenEar: No transcription to inject")
        }

        // Hide overlay and reset state
        RecordingOverlayController.shared.hide()
        recordingState = .idle
        audioLevel = 0.0
    }

    func cancelRecording() {
        let durationBeforeCancel = recordingStartTime.map { Date().timeIntervalSince($0) } ?? 0
        Analytics.shared.trackRecordingCancelled(durationSeconds: durationBeforeCancel)

        RecordingOverlayController.shared.hide()
        audioCaptureManager?.stopCapture()
        Task {
            await transcriptionEngine?.cancelStreaming()
        }
        recordingState = .idle
        audioBuffer = []
        partialTranscription = ""
        audioLevel = 0.0
    }

    // MARK: - Error Recovery

    /// Clear current error state
    func clearError() {
        if case .error = recordingState {
            recordingState = .idle
        }
    }

    /// Reset app to clean state (for stuck states)
    func resetState() {
        print("OpenEar: Resetting state...")

        // Cancel any ongoing recording
        RecordingOverlayController.shared.hide()
        audioCaptureManager?.stopCapture()
        Task {
            await transcriptionEngine?.cancelStreaming()
        }

        // Reset all state
        recordingState = .idle
        audioBuffer = []
        partialTranscription = ""
        finalTranscription = ""
        audioLevel = 0.0

        // Re-check permissions
        Task {
            await checkPermissions()
        }

        Analytics.shared.trackError("manual_reset", context: "user_triggered")
        print("OpenEar: State reset complete")
    }

    /// Retry model download after failure
    func retryModelDownload() async {
        clearError()
        await downloadModel()
    }
}

// Import required for AVCaptureDevice
import AVFoundation
import ApplicationServices
