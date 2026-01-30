import Foundation
import WhisperKit

/// Wrapper around WhisperKit for streaming transcription
actor TranscriptionEngine {

    // MARK: - Properties

    private var whisperKit: WhisperKit?
    private var isStreaming = false
    private var streamingBuffer: [Float] = []
    private var lastTranscription: String = ""
    private var isLoading = false
    private var lastTranscribedSampleCount = 0

    // MARK: - Model Management

    /// Check if WhisperKit is ready to use
    var isReady: Bool {
        whisperKit != nil
    }

    /// Initialize and load the model (downloads automatically if needed)
    func loadModel(_ modelName: String = "base.en") async throws {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }

        print("OpenEar: Loading WhisperKit model '\(modelName)'...")

        // WhisperKit handles downloading and caching automatically
        let config = WhisperKitConfig(
            model: modelName,
            verbose: true,
            prewarm: true,
            load: true
        )

        whisperKit = try await WhisperKit(config)
        print("OpenEar: WhisperKit model loaded successfully!")
    }

    /// Load model with progress callback for download tracking
    func loadModelWithProgress(
        _ modelName: String,
        progressHandler: @escaping (Progress) -> Void,
        onDownloadComplete: (() -> Void)? = nil
    ) async throws {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }

        print("OpenEar: Loading WhisperKit model '\(modelName)' with progress...")

        // First download the model with progress tracking
        let modelFolder = try await WhisperKit.download(
            variant: modelName,
            progressCallback: { progress in
                progressHandler(progress)
            }
        )

        print("OpenEar: Model downloaded to \(modelFolder), now loading...")

        // Notify that download is complete, now preparing
        onDownloadComplete?()

        // Then create WhisperKit with the downloaded model
        let config = WhisperKitConfig(
            modelFolder: modelFolder.path,
            verbose: true,
            prewarm: true,
            load: true
        )

        whisperKit = try await WhisperKit(config)
        print("OpenEar: WhisperKit model loaded successfully!")
    }

    /// Legacy method for compatibility
    func isModelAvailable(_ modelName: String) async -> Bool {
        return whisperKit != nil
    }

    /// Legacy method - just calls loadModel
    func downloadModel(_ modelName: String) async throws {
        try await loadModel(modelName)
    }

    // MARK: - Streaming Transcription

    func startStreaming() async {
        isStreaming = true
        streamingBuffer = []
        lastTranscription = ""
        lastTranscribedSampleCount = 0
    }

    func transcribeChunk(_ audioChunk: [Float]) async -> String? {
        guard isStreaming else { return nil }

        streamingBuffer.append(contentsOf: audioChunk)

        // Thresholds (at 16kHz sample rate):
        // - First transcription: 0.1s = 1600 samples (2 chunks at 50ms)
        // - Subsequent: every 0.2s = 3200 samples of NEW audio
        let initialThreshold = 1600  // ~100ms - just 2 audio chunks
        let updateInterval = 3200

        // Not enough audio yet for first transcription
        if streamingBuffer.count < initialThreshold {
            return nil
        }

        // Throttle: only transcribe when we have enough NEW audio since last time
        let samplesSinceLastTranscribe = streamingBuffer.count - lastTranscribedSampleCount
        if lastTranscribedSampleCount > 0 && samplesSinceLastTranscribe < updateInterval {
            return nil
        }

        guard let whisperKit = whisperKit else { return nil }

        // Mark that we're transcribing at this sample count
        lastTranscribedSampleCount = streamingBuffer.count

        do {
            // Optimized for streaming: skip fallbacks, use greedy decoding
            let options = DecodingOptions(
                verbose: false,
                task: .transcribe,
                language: "en",
                temperature: 0, // Greedy decoding (fastest)
                temperatureFallbackCount: 0, // No fallbacks for speed
                sampleLength: 224,
                usePrefillPrompt: true,
                usePrefillCache: true,
                skipSpecialTokens: true,
                withoutTimestamps: true
            )

            let results = try await whisperKit.transcribe(
                audioArray: streamingBuffer,
                decodeOptions: options
            )

            if let text = results.first?.text {
                lastTranscription = text
                return text
            }
        } catch {
            print("Streaming transcription error: \(error)")
        }

        return nil
    }

    func finishStreaming(_ fullAudio: [Float]) async -> String? {
        isStreaming = false

        guard let whisperKit = whisperKit else { return lastTranscription }
        guard !fullAudio.isEmpty else { return lastTranscription }

        // For short audio, pad with silence to help WhisperKit
        // WhisperKit works better with at least 0.5s of audio
        let minSamples = 8000  // 0.5 seconds at 16kHz
        var audioToTranscribe = fullAudio

        if fullAudio.count < minSamples {
            // Pad with silence at the end
            let padding = [Float](repeating: 0, count: minSamples - fullAudio.count)
            audioToTranscribe = fullAudio + padding
            print("OpenEar: Padded short audio from \(fullAudio.count) to \(audioToTranscribe.count) samples")
        }

        do {
            // Final transcription with full audio for best accuracy
            let options = DecodingOptions(
                verbose: false,
                task: .transcribe,
                language: "en",
                temperature: 0,  // Greedy for short audio
                temperatureFallbackCount: 2,
                sampleLength: 224,
                usePrefillPrompt: true,
                usePrefillCache: true,
                skipSpecialTokens: true,
                withoutTimestamps: true,
                suppressBlank: true  // Avoid blank outputs
            )

            let results = try await whisperKit.transcribe(
                audioArray: audioToTranscribe,
                decodeOptions: options
            )

            if let text = results.first?.text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return text
            }
        } catch {
            print("Final transcription error: \(error)")
        }

        return lastTranscription
    }

    func cancelStreaming() {
        isStreaming = false
        streamingBuffer = []
        lastTranscription = ""
        lastTranscribedSampleCount = 0
    }
}
