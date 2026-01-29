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
    }

    func transcribeChunk(_ audioChunk: [Float]) async -> String? {
        guard isStreaming else { return nil }

        streamingBuffer.append(contentsOf: audioChunk)

        // Only transcribe when we have enough audio (~0.5 seconds)
        // 16kHz * 0.5s = 8000 samples
        guard streamingBuffer.count >= 8000 else { return nil }

        guard let whisperKit = whisperKit else { return nil }

        do {
            let results = try await whisperKit.transcribe(audioArray: streamingBuffer)

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

        do {
            // Final transcription with full audio for best accuracy
            let options = DecodingOptions(
                verbose: false,
                task: .transcribe,
                language: "en",
                temperatureFallbackCount: 3,
                sampleLength: 224,
                usePrefillPrompt: true,
                usePrefillCache: true,
                skipSpecialTokens: true,
                withoutTimestamps: true
            )

            let results = try await whisperKit.transcribe(
                audioArray: fullAudio,
                decodeOptions: options
            )

            if let text = results.first?.text {
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
    }
}
