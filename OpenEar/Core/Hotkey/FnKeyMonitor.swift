import Foundation
import AppKit

/// Monitors the Fn (Globe) key using NSEvent modifier flags
/// This is a simpler approach that detects Fn as a modifier key
final class FnKeyMonitor {

    // MARK: - Properties

    private var flagsMonitor: Any?
    private var lastFnState = false
    private var isMonitoring = false

    /// Called when Fn key is pressed down
    var onFnDown: (() -> Void)?

    /// Called when Fn key is released
    var onFnUp: (() -> Void)?

    // MARK: - Initialization

    deinit {
        stop()
    }

    // MARK: - Monitoring Control

    /// Start monitoring for Fn key events
    /// - Returns: true if monitoring started successfully
    @discardableResult
    func start() -> Bool {
        guard !isMonitoring else { return true }

        print("OpenEar: Starting Fn key monitor (modifier flags approach)...")

        // Monitor for flags changed events (modifier keys)
        flagsMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handleFlagsChanged(event)
        }

        // Also monitor local events
        NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handleFlagsChanged(event)
            return event
        }

        if flagsMonitor != nil {
            isMonitoring = true
            print("OpenEar: Fn key monitor started successfully")
            return true
        } else {
            print("OpenEar: Failed to start Fn key monitor")
            return false
        }
    }

    func stop() {
        if let monitor = flagsMonitor {
            NSEvent.removeMonitor(monitor)
            flagsMonitor = nil
        }
        isMonitoring = false
    }

    // MARK: - Event Handling

    private func handleFlagsChanged(_ event: NSEvent) {
        // Check for Fn/Globe modifier flag
        let fnPressed = event.modifierFlags.contains(.function)

        if fnPressed != lastFnState {
            lastFnState = fnPressed

            if fnPressed {
                print("OpenEar: ✓ Fn key pressed!")
                DispatchQueue.main.async { [weak self] in
                    self?.onFnDown?()
                }
            } else {
                print("OpenEar: ✓ Fn key released!")
                DispatchQueue.main.async { [weak self] in
                    self?.onFnUp?()
                }
            }
        }
    }
}
