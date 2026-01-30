import SwiftUI
import KeyboardShortcuts

@main
struct OpenEarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
                .environmentObject(appDelegate.appState)
        } label: {
            MenuBarIcon(state: appDelegate.appState.recordingState)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environmentObject(appDelegate.appState)
        }

        Window("OpenEar Setup", id: "onboarding") {
            OnboardingView()
                .environmentObject(appDelegate.appState)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .defaultSize(width: 480, height: 520)
    }
}

// MARK: - App Delegate

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate, ObservableObject {
    static var shared: AppDelegate!

    let appState = AppState()
    private var onboardingWindow: NSWindow?

    override init() {
        super.init()
        AppDelegate.shared = self
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        log("applicationDidFinishLaunching")

        // Initialize analytics
        Analytics.shared.configure()
        Analytics.shared.trackAppLaunched()
        Task {
            // First just check permissions (fast)
            await appState.checkPermissions()
            appState.checkIfOnboardingNeeded()

            log("showOnboarding flag = \(appState.showOnboarding), mic = \(appState.microphonePermission), acc = \(appState.accessibilityPermission)")

            // Show onboarding BEFORE any slow operations (like model download)
            if appState.showOnboarding {
                log("Showing onboarding first...")
                await MainActor.run {
                    showOnboarding()
                }
                // Don't run full setup yet - onboarding will handle model download
                return
            }

            // Only run full setup if not showing onboarding
            await appState.setup()
        }
    }

    private func log(_ message: String) {
        let msg = "OpenEar: \(message)"
        print(msg)
        // Also write to file for debugging
        let logFile = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("openear_debug.log")
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let line = "[\(timestamp)] \(msg)\n"
        if let data = line.data(using: .utf8) {
            if FileManager.default.fileExists(atPath: logFile.path) {
                if let handle = try? FileHandle(forWritingTo: logFile) {
                    handle.seekToEndOfFile()
                    handle.write(data)
                    handle.closeFile()
                }
            } else {
                try? data.write(to: logFile)
            }
        }
    }

    func showOnboarding() {
        log("showOnboarding called")

        // Close existing window if any
        onboardingWindow?.close()
        onboardingWindow = nil

        // Create and show the onboarding window
        let onboardingView = OnboardingView()
            .environmentObject(appState)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 520),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.center()
        window.contentView = NSHostingView(rootView: onboardingView)
        window.title = "OpenEar Setup"
        window.level = .modalPanel  // Higher level than .floating
        window.backgroundColor = .windowBackgroundColor
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        self.onboardingWindow = window

        // For menu bar apps, we need to temporarily become a regular app to show windows
        NSApp.setActivationPolicy(.regular)

        // Bring to front forcefully
        window.orderFrontRegardless()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        log("Onboarding window shown at level \(window.level.rawValue)")
    }

    func closeOnboarding() {
        onboardingWindow?.close()
        onboardingWindow = nil

        // Return to menu bar only mode (hide from dock)
        NSApp.setActivationPolicy(.accessory)
    }
}

// MARK: - Menu Bar Icon

struct MenuBarIcon: View {
    let state: AppState.RecordingState

    var body: some View {
        Image(systemName: iconName)
            .symbolRenderingMode(.hierarchical)
    }

    private var iconName: String {
        switch state {
        case .idle:
            return "waveform.circle"
        case .recording:
            return "waveform.circle.fill"
        case .transcribing:
            return "text.bubble"
        case .injecting:
            return "checkmark.circle"
        case .error:
            return "exclamationmark.circle"
        }
    }
}
