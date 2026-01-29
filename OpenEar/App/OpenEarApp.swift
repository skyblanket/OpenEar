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
        print("OpenEar: applicationDidFinishLaunching")
        Task {
            await appState.setup()

            // Show onboarding immediately if first launch
            print("OpenEar: showOnboarding flag = \(appState.showOnboarding)")
            if appState.showOnboarding {
                showOnboarding()
            }
        }
    }

    func showOnboarding() {
        print("OpenEar: showOnboarding called")

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
        window.level = .floating
        window.backgroundColor = .windowBackgroundColor
        window.isReleasedWhenClosed = false

        self.onboardingWindow = window

        // Bring to front
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        print("OpenEar: Onboarding window shown")
    }

    func closeOnboarding() {
        onboardingWindow?.close()
        onboardingWindow = nil
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
