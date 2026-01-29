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
    @Published var selectedModel: String = "base.en"

    // MARK: - Dependencies

    private var audioCaptureManager: AudioCaptureManager?
    private var transcriptionEngine: TranscriptionEngine?
    private var textInjector: TextInjector?
    private var fnKeyMonitor: FnKeyMonitor?
    private var hotkeyManager: HotkeyManager?

    private var cancellables = Set<AnyCancellable>()
    private var audioBuffer: [Float] = []
    private var hasSetup = false

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
        // Show onboarding if any required permission is missing
        if microphonePermission != .granted || accessibilityPermission != .granted {
            showOnboarding = true
            print("OpenEar: Permissions missing - showing onboarding")
        }
    }

    func completeOnboarding() {
        UserDefaults.standard.set(true, forKey: "hasLaunchedBefore")
        showOnboarding = false
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
            let granted = await AVCaptureDevice.requestAccess(for: .audio)
            return granted ? .granted : .denied
        case .denied, .restricted:
            return .denied
        @unknown default:
            return .unknown
        }
    }

    private func checkAccessibilityPermission() -> PermissionState {
        let trusted = AXIsProcessTrusted()
        return trusted ? .granted : .denied
    }

    func requestAccessibilityPermission() {
        // Try the prompt first
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        AXIsProcessTrustedWithOptions(options as CFDictionary)

        // Also open System Settings directly - try multiple URL schemes for compatibility
        // macOS 13+ uses different URL scheme
        let urls = [
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility",
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Accessibility"
        ]

        for urlString in urls {
            if let url = URL(string: urlString) {
                let success = NSWorkspace.shared.open(url)
                print("OpenEar: Trying to open \(urlString) - success: \(success)")
                if success { break }
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

    func downloadModelWithProgress() async throws {
        guard let engine = transcriptionEngine else {
            throw NSError(domain: "OpenEar", code: 1, userInfo: [NSLocalizedDescriptionKey: "Engine not initialized"])
        }

        print("OpenEar: Loading model \(selectedModel)...")
        try await engine.loadModel(selectedModel)
        isModelDownloaded = true
        print("OpenEar: Model loaded successfully!")
    }

    private func streamAudioChunk(_ buffer: [Float]) async {
        guard recordingState == .recording else { return }

        // Stream chunks to transcription engine for real-time partial results
        if let partialText = await transcriptionEngine?.transcribeChunk(buffer) {
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
                await self?.startRecording()
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
                await self?.startRecording()
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

    func startRecording() async {
        print("OpenEar: startRecording called, current state: \(recordingState)")
        guard recordingState == .idle else {
            print("OpenEar: Not idle, ignoring")
            return
        }
        guard microphonePermission == .granted else {
            print("OpenEar: Mic permission not granted!")
            recordingState = .error("Microphone permission required")
            return
        }
        guard isModelDownloaded else {
            print("OpenEar: Model not downloaded!")
            recordingState = .error("Model not downloaded")
            return
        }

        print("OpenEar: Starting recording...")
        recordingState = .recording
        audioBuffer = []
        partialTranscription = ""
        finalTranscription = ""

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
            RecordingOverlayController.shared.hide()
        }
    }

    func stopRecording() async {
        print("OpenEar: stopRecording called, current state: \(recordingState)")
        guard recordingState == .recording else { return }

        recordingState = .transcribing
        print("OpenEar: Transcribing \(audioBuffer.count) samples...")

        // Stop audio capture
        audioCaptureManager?.stopCapture()

        // Finalize transcription
        if let finalText = await transcriptionEngine?.finishStreaming(audioBuffer) {
            finalTranscription = finalText.trimmingCharacters(in: .whitespacesAndNewlines)
            print("OpenEar: Transcription result: \(finalTranscription)")
        }

        // Inject text if we have any
        if !finalTranscription.isEmpty {
            recordingState = .injecting
            print("OpenEar: Injecting text...")

            guard accessibilityPermission == .granted else {
                print("OpenEar: Accessibility permission not granted!")
                recordingState = .error("Accessibility permission required for text injection")
                return
            }

            textInjector?.injectText(finalTranscription)
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
}

// Import required for AVCaptureDevice
import AVFoundation
import ApplicationServices
