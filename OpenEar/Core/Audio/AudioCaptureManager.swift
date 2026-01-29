import AVFoundation
import Accelerate

/// Manages audio capture from the microphone with 16kHz resampling for WhisperKit
final class AudioCaptureManager {

    // MARK: - Properties

    private var audioEngine: AVAudioEngine?
    private var inputNode: AVAudioInputNode?
    private let targetSampleRate: Double = 16000.0 // WhisperKit requirement

    /// Callback for audio level updates (0.0 - 1.0)
    var onAudioLevel: ((Float) -> Void)?

    /// Callback for audio buffer chunks (16kHz mono float samples)
    var onAudioBuffer: (([Float]) -> Void)?

    private var converter: AVAudioConverter?
    private var isCapturing = false
    private var configObserver: NSObjectProtocol?

    // MARK: - Initialization

    init() {
        setupAudioSession()
        setupDeviceChangeObserver()
    }

    deinit {
        stopCapture()
        if let observer = configObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    // MARK: - Setup

    private func setupAudioSession() {
        // macOS doesn't require explicit audio session configuration like iOS
        audioEngine = AVAudioEngine()
    }

    private func setupDeviceChangeObserver() {
        // Listen for audio device changes (AirPods connecting, etc.)
        configObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: audioEngine,
            queue: .main
        ) { [weak self] _ in
            print("OpenEar: Audio device configuration changed")
            self?.handleDeviceChange()
        }
    }

    private func handleDeviceChange() {
        guard isCapturing else { return }

        print("OpenEar: Restarting audio capture due to device change...")

        // Stop and restart capture with new device
        stopCapture()

        // Small delay to let the system settle
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            do {
                try self?.startCapture()
                print("OpenEar: Audio capture restarted successfully")
            } catch {
                print("OpenEar: Failed to restart audio capture: \(error)")
            }
        }
    }

    // MARK: - Capture Control

    func startCapture() throws {
        guard !isCapturing else { return }
        guard let audioEngine = audioEngine else {
            throw AudioCaptureError.engineNotInitialized
        }

        let inputNode = audioEngine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)

        // Create output format at 16kHz mono for WhisperKit
        guard let outputFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: targetSampleRate,
            channels: 1,
            interleaved: false
        ) else {
            throw AudioCaptureError.invalidFormat
        }

        // Create converter for resampling
        guard let converter = AVAudioConverter(from: inputFormat, to: outputFormat) else {
            throw AudioCaptureError.converterCreationFailed
        }
        self.converter = converter

        // Calculate buffer sizes
        // Process ~100ms chunks for responsive streaming
        let inputBufferSize = AVAudioFrameCount(inputFormat.sampleRate * 0.1)
        let outputBufferSize = AVAudioFrameCount(targetSampleRate * 0.1)

        // Install tap on input node
        inputNode.installTap(onBus: 0, bufferSize: inputBufferSize, format: inputFormat) { [weak self] buffer, _ in
            self?.processAudioBuffer(buffer, outputFormat: outputFormat, outputBufferSize: outputBufferSize)
        }

        // Start the engine
        audioEngine.prepare()
        try audioEngine.start()
        isCapturing = true
    }

    func stopCapture() {
        guard isCapturing else { return }

        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        isCapturing = false
        converter = nil

        // Recreate engine for fresh state on next capture
        audioEngine = AVAudioEngine()
    }

    // MARK: - Audio Processing

    private func processAudioBuffer(
        _ inputBuffer: AVAudioPCMBuffer,
        outputFormat: AVAudioFormat,
        outputBufferSize: AVAudioFrameCount
    ) {
        guard let converter = converter else { return }

        // Calculate the required output buffer size based on sample rate ratio
        let ratio = targetSampleRate / inputBuffer.format.sampleRate
        let estimatedOutputFrames = AVAudioFrameCount(Double(inputBuffer.frameLength) * ratio)

        // Create output buffer
        guard let outputBuffer = AVAudioPCMBuffer(
            pcmFormat: outputFormat,
            frameCapacity: max(estimatedOutputFrames, outputBufferSize)
        ) else { return }

        // Convert (resample) the audio
        var error: NSError?
        let inputBlock: AVAudioConverterInputBlock = { _, outStatus in
            outStatus.pointee = .haveData
            return inputBuffer
        }

        let status = converter.convert(to: outputBuffer, error: &error, withInputFrom: inputBlock)

        guard status != .error, error == nil else {
            print("Audio conversion error: \(error?.localizedDescription ?? "unknown")")
            return
        }

        // Extract float samples
        guard let channelData = outputBuffer.floatChannelData?[0] else { return }
        let frameLength = Int(outputBuffer.frameLength)
        let samples = Array(UnsafeBufferPointer(start: channelData, count: frameLength))

        // Calculate RMS level
        let level = calculateRMSLevel(samples)

        // Dispatch callbacks
        DispatchQueue.main.async { [weak self] in
            self?.onAudioLevel?(level)
            self?.onAudioBuffer?(samples)
        }
    }

    private func calculateRMSLevel(_ samples: [Float]) -> Float {
        guard !samples.isEmpty else { return 0.0 }

        var rms: Float = 0.0
        vDSP_rmsqv(samples, 1, &rms, vDSP_Length(samples.count))

        // Convert to decibels and normalize to 0-1 range
        // Typical speech is around -20dB to -6dB
        let db = 20 * log10(max(rms, 0.0001))
        let normalized = (db + 50) / 50 // Map -50dB to 0dB → 0.0 to 1.0
        return max(0.0, min(1.0, normalized))
    }
}

// MARK: - Errors

enum AudioCaptureError: LocalizedError {
    case engineNotInitialized
    case invalidFormat
    case converterCreationFailed

    var errorDescription: String? {
        switch self {
        case .engineNotInitialized:
            return "Audio engine not initialized"
        case .invalidFormat:
            return "Could not create audio format"
        case .converterCreationFailed:
            return "Could not create audio converter"
        }
    }
}
