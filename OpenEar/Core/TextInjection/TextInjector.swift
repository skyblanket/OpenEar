import AppKit
import Carbon.HIToolbox

/// Handles text injection into active applications via clipboard + paste simulation
final class TextInjector {

    // MARK: - Properties

    private var previousClipboardContent: String?

    // MARK: - Text Injection

    /// Injects text into the currently focused text field
    /// Uses clipboard + simulated Cmd+V for universal compatibility
    func injectText(_ text: String) {
        guard !text.isEmpty else { return }

        // Save current clipboard content
        saveClipboard()

        // Copy text to clipboard
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        // Small delay to ensure clipboard is ready
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            // Simulate Cmd+V paste
            self?.simulatePaste()

            // Restore clipboard after a short delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                self?.restoreClipboard()
            }
        }
    }

    // MARK: - Clipboard Management

    private func saveClipboard() {
        let pasteboard = NSPasteboard.general
        previousClipboardContent = pasteboard.string(forType: .string)
    }

    private func restoreClipboard() {
        guard let content = previousClipboardContent else { return }

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(content, forType: .string)

        previousClipboardContent = nil
    }

    // MARK: - Keyboard Simulation

    private func simulatePaste() {
        // Create Cmd+V key event
        let source = CGEventSource(stateID: .hidSystemState)

        // Key code for 'V' is 9
        let keyCodeV: CGKeyCode = 9

        // Key down with Command modifier
        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCodeV, keyDown: true) else {
            print("Failed to create key down event")
            return
        }
        keyDown.flags = .maskCommand

        // Key up
        guard let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCodeV, keyDown: false) else {
            print("Failed to create key up event")
            return
        }
        keyUp.flags = .maskCommand

        // Post events to the system
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
    }

    // MARK: - Alternative Methods

    /// Alternative: Type text character by character (slower but doesn't use clipboard)
    func typeText(_ text: String) {
        let source = CGEventSource(stateID: .hidSystemState)

        for character in text {
            guard let unicodeScalar = character.unicodeScalars.first else { continue }

            // Create key event with Unicode character
            guard let event = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true) else {
                continue
            }

            var unicodeChar = UniChar(unicodeScalar.value)
            event.keyboardSetUnicodeString(stringLength: 1, unicodeString: &unicodeChar)
            event.post(tap: .cghidEventTap)

            // Key up
            guard let upEvent = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false) else {
                continue
            }
            upEvent.post(tap: .cghidEventTap)

            // Small delay between characters
            usleep(1000) // 1ms
        }
    }

    /// Check if we can inject text (accessibility permission required)
    static func canInjectText() -> Bool {
        return AXIsProcessTrusted()
    }

    /// Prompt user to grant accessibility permission
    static func requestAccessibilityPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        AXIsProcessTrustedWithOptions(options as CFDictionary)
    }
}
