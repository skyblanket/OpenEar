import Foundation
import WhisperKit

/// Manages WhisperKit model downloads and selection
@MainActor
final class ModelManager: ObservableObject {

    // MARK: - Types

    struct ModelInfo: Identifiable, Hashable {
        let id: String
        let name: String
        let size: String
        let description: String

        var displayName: String {
            "\(name) (\(size))"
        }
    }

    // MARK: - Available Models

    static let availableModels: [ModelInfo] = [
        ModelInfo(
            id: "tiny.en",
            name: "Tiny",
            size: "~40MB",
            description: "Fastest, lower accuracy. Good for testing."
        ),
        ModelInfo(
            id: "base.en",
            name: "Base",
            size: "~140MB",
            description: "Fast with good accuracy. Recommended for most users."
        ),
        ModelInfo(
            id: "small.en",
            name: "Small",
            size: "~460MB",
            description: "Moderate speed, better accuracy."
        ),
        ModelInfo(
            id: "medium.en",
            name: "Medium",
            size: "~1.5GB",
            description: "Slower, best accuracy. Requires more RAM."
        ),
        ModelInfo(
            id: "large-v3",
            name: "Large v3",
            size: "~3GB",
            description: "Highest accuracy, multilingual. Requires 16GB+ RAM."
        ),
        ModelInfo(
            id: "distil-large-v3",
            name: "Distil Large v3",
            size: "~1GB",
            description: "Distilled version, faster than large with similar accuracy."
        )
    ]

    static let defaultModel = "base.en"

    // MARK: - Properties

    @Published var downloadedModels: Set<String> = []
    @Published var downloadProgress: [String: Double] = [:]
    @Published var isDownloading: Bool = false
    @Published var currentDownload: String?

    private let modelsDirectory: URL

    // MARK: - Initialization

    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        modelsDirectory = appSupport.appendingPathComponent("OpenEar/Models")

        // Create models directory if needed
        try? FileManager.default.createDirectory(at: modelsDirectory, withIntermediateDirectories: true)

        // Scan for existing models
        scanForDownloadedModels()
    }

    // MARK: - Model Management

    func scanForDownloadedModels() {
        // WhisperKit stores models in its own location
        // We check for model availability through WhisperKit
        Task {
            for model in Self.availableModels {
                // Check if model files exist
                let modelPath = modelsDirectory.appendingPathComponent(model.id)
                if FileManager.default.fileExists(atPath: modelPath.path) {
                    downloadedModels.insert(model.id)
                }
            }
        }
    }

    func isModelDownloaded(_ modelId: String) -> Bool {
        downloadedModels.contains(modelId)
    }

    func downloadModel(_ modelId: String) async throws {
        guard !isDownloading else { return }

        isDownloading = true
        currentDownload = modelId
        downloadProgress[modelId] = 0.0

        defer {
            isDownloading = false
            currentDownload = nil
        }

        // WhisperKit handles model download automatically during initialization
        let config = WhisperKitConfig(
            model: modelId,
            verbose: false,
            prewarm: false,
            load: false
        )

        _ = try await WhisperKit(config)

        downloadedModels.insert(modelId)
        downloadProgress[modelId] = 1.0
    }

    func deleteModel(_ modelId: String) throws {
        let modelPath = modelsDirectory.appendingPathComponent(modelId)
        if FileManager.default.fileExists(atPath: modelPath.path) {
            try FileManager.default.removeItem(at: modelPath)
            downloadedModels.remove(modelId)
        }
    }

    func modelInfo(for modelId: String) -> ModelInfo? {
        Self.availableModels.first { $0.id == modelId }
    }
}
