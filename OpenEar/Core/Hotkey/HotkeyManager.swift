import Foundation
import KeyboardShortcuts
import AppKit
import ApplicationServices

// Define the keyboard shortcut name
extension KeyboardShortcuts.Name {
    static let toggleRecording = Self("toggleRecording")
}

/// Manages keyboard shortcuts using the KeyboardShortcuts library
/// Provides fallback Option+Space hotkey when Fn key detection isn't available
final class HotkeyManager {

    // MARK: - Properties

    /// Called when hotkey is pressed down
    var onHotkeyDown: (() -> Void)?

    /// Called when hotkey is released
    var onHotkeyUp: (() -> Void)?

    private var keyDownMonitor: Any?
    private var keyUpMonitor: Any?
    private var isHotkeyPressed = false
    private var cachedKeyCode: UInt16?
    private var cachedModifiers: NSEvent.ModifierFlags?

    // Default: Ctrl + Space (doesn't type any character)
    private let defaultModifiers: NSEvent.ModifierFlags = .control
    private let defaultKeyCode: UInt16 = 49 // Space bar

    // Cache the effective shortcut as primitive values so we can match off-main safely
    @MainActor private func updateCachedShortcut() {
        if let shortcut = KeyboardShortcuts.getShortcut(for: .toggleRecording),
           let key = shortcut.key {
            cachedKeyCode = UInt16(key.rawValue)
            cachedModifiers = shortcut.modifiers.intersection(.deviceIndependentFlagsMask)
        } else {
            cachedKeyCode = defaultKeyCode
            cachedModifiers = defaultModifiers.intersection(.deviceIndependentFlagsMask)
        }
    }

    // MARK: - Initialization

    init() {
        // Set default shortcut if not already set (Ctrl+Space - no character output)
        if KeyboardShortcuts.getShortcut(for: .toggleRecording) == nil {
            KeyboardShortcuts.setShortcut(.init(.space, modifiers: .control), for: .toggleRecording)
        }
        Task { @MainActor in self.updateCachedShortcut() }
    }

    deinit {
        unregisterHotkey()
    }

    // MARK: - Hotkey Registration

    func registerHotkey() {
        print("OpenEar: Registering hotkey (Option+Space)...")

        // Check if we have accessibility permission (required for global monitoring)
        let trusted = AXIsProcessTrusted()
        print("OpenEar: Accessibility trusted: \(trusted)")

        if !trusted {
            print("OpenEar: ⚠️ Accessibility NOT granted - global hotkey won't work outside the app!")
            print("OpenEar: Go to System Settings → Privacy & Security → Accessibility → Enable OpenEar")
        }

        // Monitor key down globally
        keyDownMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handleKeyDown(event)
        }

        // Monitor key up globally
        keyUpMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyUp) { [weak self] event in
            self?.handleKeyUp(event)
        }

        // Also monitor local events (when our app is focused)
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handleKeyDown(event)
            return event
        }

        NSEvent.addLocalMonitorForEvents(matching: .keyUp) { [weak self] event in
            self?.handleKeyUp(event)
            return event
        }

        print("OpenEar: Hotkey registered. Cached keyCode: \(cachedKeyCode ?? 0), modifiers: \(cachedModifiers?.rawValue ?? 0)")
    }

    func unregisterHotkey() {
        if let monitor = keyDownMonitor {
            NSEvent.removeMonitor(monitor)
            keyDownMonitor = nil
        }
        if let monitor = keyUpMonitor {
            NSEvent.removeMonitor(monitor)
            keyUpMonitor = nil
        }
    }

    // MARK: - Event Handling

    private func handleKeyDown(_ event: NSEvent) {
        // Debug: log all key events to see if monitoring works
        print("OpenEar: Key down - code: \(event.keyCode), modifiers: \(event.modifierFlags.rawValue), expecting code: \(cachedKeyCode ?? 999)")

        guard matchesHotkey(event) else {
            print("OpenEar: Key doesn't match hotkey")
            return
        }
        guard !isHotkeyPressed else { return } // Ignore key repeat

        print("OpenEar: ✓ Hotkey pressed!")
        isHotkeyPressed = true
        DispatchQueue.main.async { [weak self] in
            self?.onHotkeyDown?()
        }
    }

    private func handleKeyUp(_ event: NSEvent) {
        guard matchesHotkey(event) else { return }
        guard isHotkeyPressed else { return }

        print("OpenEar: ✓ Hotkey released!")
        isHotkeyPressed = false
        DispatchQueue.main.async { [weak self] in
            self?.onHotkeyUp?()
        }
    }

    private func matchesHotkey(_ event: NSEvent) -> Bool {
        // Use cached values to avoid main-actor isolated API from background monitors
        if let keyCode = cachedKeyCode, let modifiers = cachedModifiers {
            // Check key code
            guard event.keyCode == keyCode else { return false }
            // Check modifiers (allowing for slight differences in how they're reported)
            let eventModifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            let requiredModifiers = modifiers.intersection(.deviceIndependentFlagsMask)
            return eventModifiers == requiredModifiers
        }
        // Fallback to default Option+Space if cache not ready
        return event.keyCode == defaultKeyCode &&
               event.modifierFlags.contains(defaultModifiers) &&
               !event.modifierFlags.contains(.command) &&
               !event.modifierFlags.contains(.control) &&
               !event.modifierFlags.contains(.shift)
    }

    // MARK: - Shortcut Management

    func setShortcut(_ shortcut: KeyboardShortcuts.Shortcut?) {
        KeyboardShortcuts.setShortcut(shortcut, for: .toggleRecording)
        Task { @MainActor in self.updateCachedShortcut() }
    }

    @MainActor func getShortcut() -> KeyboardShortcuts.Shortcut? {
        KeyboardShortcuts.getShortcut(for: .toggleRecording)
    }

    func resetToDefault() {
        KeyboardShortcuts.setShortcut(.init(.space, modifiers: .control), for: .toggleRecording)
        Task { @MainActor in self.updateCachedShortcut() }
    }

    /// Returns a human-readable string for the current shortcut
    @MainActor func shortcutDisplayString() -> String {
        if let shortcut = getShortcut() {
            return shortcut.description
        }
        return "⌃ Space"
    }
}

// MARK: - Modifier Flags Extension

extension NSEvent.ModifierFlags {
    var asKeyboardShortcutsModifiers: NSEvent.ModifierFlags {
        var result: NSEvent.ModifierFlags = []
        if contains(.command) { result.insert(.command) }
        if contains(.option) { result.insert(.option) }
        if contains(.control) { result.insert(.control) }
        if contains(.shift) { result.insert(.shift) }
        return result
    }
}
