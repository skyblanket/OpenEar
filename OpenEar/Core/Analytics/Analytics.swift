import Foundation
import PostHog
import IOKit

/// Comprehensive analytics for OpenEar
/// Tracks funnel, engagement, performance, and errors
final class Analytics {
    static let shared = Analytics()

    private var sessionStartTime: Date?
    private var installDate: Date {
        get {
            if let date = UserDefaults.standard.object(forKey: "analytics_install_date") as? Date {
                return date
            }
            let now = Date()
            UserDefaults.standard.set(now, forKey: "analytics_install_date")
            return now
        }
    }

    private var totalRecordingsCount: Int {
        get { UserDefaults.standard.integer(forKey: "analytics_total_recordings") }
        set { UserDefaults.standard.set(newValue, forKey: "analytics_total_recordings") }
    }

    private var firstRecordingCompleted: Bool {
        get { UserDefaults.standard.bool(forKey: "analytics_first_recording_done") }
        set { UserDefaults.standard.set(newValue, forKey: "analytics_first_recording_done") }
    }

    private var lastMilestoneTracked: Int {
        get { UserDefaults.standard.integer(forKey: "analytics_last_milestone") }
        set { UserDefaults.standard.set(newValue, forKey: "analytics_last_milestone") }
    }

    private var lastActiveDate: String {
        get { UserDefaults.standard.string(forKey: "analytics_last_active_date") ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: "analytics_last_active_date") }
    }

    private init() {}

    // MARK: - Setup

    func configure() {
        let config = PostHogConfig(
            apiKey: "phc_6iYOO3WpaEzpNtq7Bh69Kq5oUAbKNQOg96rGJ0YAnfd",
            host: "https://us.i.posthog.com"
        )
        config.captureApplicationLifecycleEvents = true
        config.captureScreenViews = false

        PostHogSDK.shared.setup(config)

        // Get device info
        let deviceInfo = getDeviceInfo()

        // Set user properties for segmentation
        PostHogSDK.shared.identify(getOrCreateUserId(), userProperties: [
            // Platform
            "platform": "macOS",
            "os_version": ProcessInfo.processInfo.operatingSystemVersionString,
            "app_version": Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown",
            "build_number": Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "unknown",
            "install_date": ISO8601DateFormatter().string(from: installDate),
            // Device
            "mac_model": deviceInfo.model,
            "chip_type": deviceInfo.chipType,
            "ram_gb": deviceInfo.ramGB,
            "cpu_cores": ProcessInfo.processInfo.processorCount,
            // Engagement
            "total_recordings": totalRecordingsCount,
            "days_since_install": Calendar.current.dateComponents([.day], from: installDate, to: Date()).day ?? 0
        ])

        // Track daily active user
        trackDailyActive()

        // Track device info as event (for historical tracking)
        trackDeviceInfo(deviceInfo)

        print("OpenEar: Analytics configured - \(deviceInfo.model) / \(deviceInfo.chipType)")
    }

    // MARK: - Device Info

    private struct DeviceInfo {
        let model: String
        let chipType: String
        let ramGB: Int
        let diskFreeGB: Int
    }

    private func getDeviceInfo() -> DeviceInfo {
        // Get Mac model
        var size = 0
        sysctlbyname("hw.model", nil, &size, nil, 0)
        var model = [CChar](repeating: 0, count: size)
        sysctlbyname("hw.model", &model, &size, nil, 0)
        let modelString = String(cString: model)

        // Get chip type (Apple Silicon vs Intel)
        var chipType = "Unknown"
        #if arch(arm64)
        chipType = "Apple Silicon"
        // Try to get specific chip
        var chipSize = 0
        sysctlbyname("machdep.cpu.brand_string", nil, &chipSize, nil, 0)
        if chipSize > 0 {
            var chipBrand = [CChar](repeating: 0, count: chipSize)
            sysctlbyname("machdep.cpu.brand_string", &chipBrand, &chipSize, nil, 0)
            let brand = String(cString: chipBrand)
            if brand.contains("M1") { chipType = "M1" }
            else if brand.contains("M2") { chipType = "M2" }
            else if brand.contains("M3") { chipType = "M3" }
            else if brand.contains("M4") { chipType = "M4" }
            else { chipType = "Apple Silicon" }
        }
        #else
        chipType = "Intel"
        #endif

        // Get RAM
        let ramBytes = ProcessInfo.processInfo.physicalMemory
        let ramGB = Int(ramBytes / (1024 * 1024 * 1024))

        // Get free disk space
        var diskFreeGB = 0
        if let attrs = try? FileManager.default.attributesOfFileSystem(forPath: NSHomeDirectory()),
           let freeSpace = attrs[.systemFreeSize] as? Int64 {
            diskFreeGB = Int(freeSpace / (1024 * 1024 * 1024))
        }

        return DeviceInfo(model: modelString, chipType: chipType, ramGB: ramGB, diskFreeGB: diskFreeGB)
    }

    private func trackDeviceInfo(_ info: DeviceInfo) {
        PostHogSDK.shared.capture("device_info", properties: [
            "mac_model": info.model,
            "chip_type": info.chipType,
            "ram_gb": info.ramGB,
            "disk_free_gb": info.diskFreeGB,
            "cpu_cores": ProcessInfo.processInfo.processorCount
        ])
    }

    // MARK: - Daily Active Tracking

    private func trackDailyActive() {
        let today = ISO8601DateFormatter().string(from: Date()).prefix(10) // YYYY-MM-DD
        let todayString = String(today)

        if lastActiveDate != todayString {
            lastActiveDate = todayString
            PostHogSDK.shared.capture("daily_active", properties: [
                "date": todayString,
                "days_since_install": Calendar.current.dateComponents([.day], from: installDate, to: Date()).day ?? 0,
                "total_recordings": totalRecordingsCount
            ])
        }
    }

    private func getOrCreateUserId() -> String {
        if let userId = UserDefaults.standard.string(forKey: "analytics_user_id") {
            return userId
        }
        let userId = UUID().uuidString
        UserDefaults.standard.set(userId, forKey: "analytics_user_id")
        return userId
    }

    // MARK: - Context Properties

    private var contextProperties: [String: Any] {
        [
            "days_since_install": Calendar.current.dateComponents([.day], from: installDate, to: Date()).day ?? 0,
            "total_recordings": totalRecordingsCount,
            "model": UserDefaults.standard.string(forKey: "selectedModel") ?? "unknown"
        ]
    }

    // MARK: - App Lifecycle

    func trackAppLaunched() {
        sessionStartTime = Date()
        PostHogSDK.shared.capture("app_launched", properties: contextProperties.merging([
            "version": Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown",
            "build": Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "unknown"
        ]) { _, new in new })
    }

    func trackAppReady(launchDurationMs: Int) {
        PostHogSDK.shared.capture("app_ready", properties: [
            "duration_ms": launchDurationMs
        ])
    }

    func trackSessionStarted() {
        sessionStartTime = Date()
        PostHogSDK.shared.capture("session_started", properties: contextProperties)
    }

    // MARK: - Onboarding Funnel

    func trackOnboardingStarted() {
        PostHogSDK.shared.capture("onboarding_started", properties: contextProperties)
    }

    func trackOnboardingStepViewed(_ step: Int, name: String) {
        PostHogSDK.shared.capture("onboarding_step_viewed", properties: [
            "step": step,
            "step_name": name
        ])
    }

    func trackOnboardingStep(_ step: Int, name: String) {
        PostHogSDK.shared.capture("onboarding_step_completed", properties: [
            "step": step,
            "step_name": name
        ])
    }

    func trackOnboardingAbandoned(atStep: Int, stepName: String) {
        PostHogSDK.shared.capture("onboarding_abandoned", properties: [
            "step": atStep,
            "step_name": stepName
        ])
    }

    func trackOnboardingCompleted() {
        PostHogSDK.shared.capture("onboarding_completed", properties: contextProperties)
    }

    // MARK: - Permissions

    func trackPermissionGranted(_ permission: String) {
        PostHogSDK.shared.capture("permission_granted", properties: [
            "permission": permission
        ])
    }

    func trackPermissionDenied(_ permission: String) {
        PostHogSDK.shared.capture("permission_denied", properties: [
            "permission": permission
        ])
    }

    func trackPermissionPromptShownAgain(_ permission: String, count: Int) {
        PostHogSDK.shared.capture("permission_prompt_shown_again", properties: [
            "permission": permission,
            "count": count
        ])
    }

    // MARK: - Model Management

    func trackModelSelected(_ model: String) {
        PostHogSDK.shared.capture("model_selected", properties: [
            "model": model
        ])
    }

    func trackModelChanged(from: String, to: String) {
        PostHogSDK.shared.capture("model_changed", properties: [
            "from": from,
            "to": to
        ])
    }

    func trackModelDownloadStarted(_ model: String) {
        PostHogSDK.shared.capture("model_download_started", properties: [
            "model": model
        ])
    }

    func trackModelDownloadCompleted(_ model: String, durationSeconds: Double) {
        PostHogSDK.shared.capture("model_download_completed", properties: [
            "model": model,
            "duration_seconds": durationSeconds
        ])
    }

    func trackModelDownloadFailed(_ model: String, error: String) {
        PostHogSDK.shared.capture("model_download_failed", properties: [
            "model": model,
            "error": error
        ])
    }

    func trackModelDownloadRetry(_ model: String, attemptNumber: Int, error: String) {
        PostHogSDK.shared.capture("model_download_retry", properties: [
            "model": model,
            "attempt_number": attemptNumber,
            "error": error
        ])
    }

    func trackModelLoadTime(_ model: String, durationSeconds: Double) {
        PostHogSDK.shared.capture("model_load_time", properties: [
            "model": model,
            "duration_seconds": durationSeconds
        ])
    }

    // MARK: - Recording

    func trackRecordingStarted(trigger: String) {
        PostHogSDK.shared.capture("recording_started", properties: [
            "trigger": trigger  // "fn_key", "hotkey", "menu"
        ])
    }

    func trackRecordingCompleted(durationSeconds: Double, audioSamples: Int) {
        totalRecordingsCount += 1

        var properties: [String: Any] = [
            "duration_seconds": durationSeconds,
            "audio_samples": audioSamples,
            "recording_number": totalRecordingsCount
        ]

        // Track first recording - activation moment!
        if !firstRecordingCompleted {
            firstRecordingCompleted = true
            let timeToFirstRecording = Date().timeIntervalSince(installDate)
            properties["is_first_recording"] = true
            properties["time_to_first_recording_seconds"] = timeToFirstRecording

            PostHogSDK.shared.capture("first_recording_completed", properties: [
                "time_to_first_recording_seconds": timeToFirstRecording,
                "days_since_install": Calendar.current.dateComponents([.day], from: installDate, to: Date()).day ?? 0
            ])
        }

        PostHogSDK.shared.capture("recording_completed", properties: properties)

        // Track if recording was too short (< 0.5s = likely accident)
        if durationSeconds < 0.5 {
            PostHogSDK.shared.capture("recording_too_short", properties: [
                "duration_ms": Int(durationSeconds * 1000)
            ])
        }

        // Track milestones
        checkAndTrackMilestone()

        // Update user properties with new count
        PostHogSDK.shared.identify(getOrCreateUserId(), userProperties: [
            "total_recordings": totalRecordingsCount
        ])
    }

    private func checkAndTrackMilestone() {
        let milestones = [1, 5, 10, 25, 50, 100, 250, 500, 1000]
        for milestone in milestones {
            if totalRecordingsCount >= milestone && lastMilestoneTracked < milestone {
                lastMilestoneTracked = milestone
                PostHogSDK.shared.capture("recordings_milestone", properties: [
                    "milestone": milestone,
                    "days_to_reach": Calendar.current.dateComponents([.day], from: installDate, to: Date()).day ?? 0
                ])
                break
            }
        }
    }

    func trackRecordingCancelled(durationSeconds: Double) {
        PostHogSDK.shared.capture("recording_cancelled", properties: [
            "duration_before_cancel": durationSeconds
        ])
    }

    func trackRecordingFailed(error: String, state: String) {
        PostHogSDK.shared.capture("recording_failed", properties: [
            "error": error,
            "state": state
        ])
    }

    // MARK: - Transcription Performance

    func trackTimeToFirstWord(latencyMs: Int, model: String) {
        PostHogSDK.shared.capture("time_to_first_word", properties: [
            "latency_ms": latencyMs,
            "model": model
        ])
    }

    func trackTranscriptionCompleted(
        durationSeconds: Double,
        characterCount: Int,
        wordCount: Int,
        audioDurationSeconds: Double,
        model: String
    ) {
        PostHogSDK.shared.capture("transcription_completed", properties: [
            "processing_duration_seconds": durationSeconds,
            "audio_duration_seconds": audioDurationSeconds,
            "character_count": characterCount,
            "word_count": wordCount,
            "model": model,
            "realtime_factor": audioDurationSeconds > 0 ? durationSeconds / audioDurationSeconds : 0
        ])
    }

    func trackTranscriptionEmpty(audioDurationSeconds: Double) {
        PostHogSDK.shared.capture("transcription_empty", properties: [
            "audio_duration_seconds": audioDurationSeconds
        ])
    }

    func trackTranscriptionLatency(audioDurationSeconds: Double, processingTimeSeconds: Double, model: String) {
        PostHogSDK.shared.capture("transcription_latency", properties: [
            "audio_duration_seconds": audioDurationSeconds,
            "processing_time_seconds": processingTimeSeconds,
            "model": model,
            "latency_ratio": audioDurationSeconds > 0 ? processingTimeSeconds / audioDurationSeconds : 0
        ])
    }

    // MARK: - Text Injection

    func trackTextInjected(characterCount: Int) {
        PostHogSDK.shared.capture("text_injected", properties: [
            "character_count": characterCount
        ])
    }

    func trackTextInjectionFailed(error: String) {
        PostHogSDK.shared.capture("text_injection_failed", properties: [
            "error": error
        ])
    }

    // MARK: - Settings & Preferences

    func trackSettingsOpened() {
        PostHogSDK.shared.capture("settings_opened")
    }

    func trackHotkeyChanged(from: String, to: String) {
        PostHogSDK.shared.capture("hotkey_changed", properties: [
            "from": from,
            "to": to
        ])
    }

    // MARK: - Engagement

    func trackAppOpenedButUnused(sessionDurationSeconds: Double) {
        PostHogSDK.shared.capture("app_opened_but_unused", properties: [
            "session_duration_seconds": sessionDurationSeconds
        ])
    }

    func trackDailyRecordingsCount(_ count: Int) {
        PostHogSDK.shared.capture("daily_recordings_count", properties: [
            "count": count,
            "date": ISO8601DateFormatter().string(from: Date())
        ])
    }

    // MARK: - Errors

    func trackError(_ error: String, context: String) {
        PostHogSDK.shared.capture("error", properties: [
            "error": error,
            "context": context
        ])
    }

    func trackGatekeeperBlocked() {
        PostHogSDK.shared.capture("gatekeeper_blocked")
    }

    // MARK: - Hotkey Usage

    func trackHotkeyUsed(_ hotkey: String) {
        PostHogSDK.shared.capture("hotkey_used", properties: [
            "hotkey": hotkey
        ])
    }

    // MARK: - Menu Bar

    func trackMenuBarOpened(state: String) {
        PostHogSDK.shared.capture("menu_bar_opened", properties: [
            "state": state  // "ready", "recording", "transcribing", "error", "setup_needed"
        ])
    }

    // MARK: - Injection Target

    func trackInjectionTarget(bundleId: String?) {
        // Categorize the target app for privacy
        let category: String
        if let bundleId = bundleId {
            if bundleId.contains("safari") || bundleId.contains("chrome") || bundleId.contains("firefox") || bundleId.contains("browser") || bundleId.contains("arc") {
                category = "browser"
            } else if bundleId.contains("slack") || bundleId.contains("discord") || bundleId.contains("telegram") || bundleId.contains("messages") || bundleId.contains("whatsapp") {
                category = "chat"
            } else if bundleId.contains("code") || bundleId.contains("xcode") || bundleId.contains("sublime") || bundleId.contains("atom") || bundleId.contains("jetbrains") {
                category = "editor"
            } else if bundleId.contains("notes") || bundleId.contains("notion") || bundleId.contains("obsidian") || bundleId.contains("bear") {
                category = "notes"
            } else if bundleId.contains("terminal") || bundleId.contains("iterm") || bundleId.contains("warp") {
                category = "terminal"
            } else if bundleId.contains("mail") || bundleId.contains("outlook") || bundleId.contains("gmail") {
                category = "email"
            } else if bundleId.contains("word") || bundleId.contains("pages") || bundleId.contains("docs") {
                category = "document"
            } else {
                category = "other"
            }
        } else {
            category = "unknown"
        }

        PostHogSDK.shared.capture("injection_target", properties: [
            "category": category
        ])
    }
}
