# OpenEar

A sleek, fully local speech-to-text app for macOS. Hold a hotkey, speak, release — your words appear in any text field.

![macOS](https://img.shields.io/badge/macOS-14.0+-black?logo=apple)
![Swift](https://img.shields.io/badge/Swift-5.9+-orange?logo=swift)
![License](https://img.shields.io/badge/License-MIT-blue)

## Features

- **100% Local** — All processing happens on-device using WhisperKit. No data leaves your Mac.
- **Real-time Transcription** — See your words appear as you speak with streaming transcription.
- **Universal Text Injection** — Works in any app: Notes, browsers, Slack, VS Code, Terminal, everywhere.
- **Dynamic Island UI** — Beautiful notch-style overlay inspired by Apple's design language.
- **Multiple Hotkeys** — Use Fn key (hold) or Ctrl+Space for push-to-talk.

## Requirements

- macOS 14.0 (Sonoma) or later
- Apple Silicon Mac (M1/M2/M3) recommended
- ~200MB for the speech model

## Installation

### Download

Download the latest release from [Releases](https://github.com/yourusername/OpenEar/releases).

### Build from Source

```bash
git clone https://github.com/yourusername/OpenEar.git
cd OpenEar
open OpenEar.xcodeproj
```

Build and run with Xcode (⌘R).

## Usage

1. **Grant Permissions** — On first launch, grant microphone and accessibility permissions.
2. **Hold Fn** (or Ctrl+Space) — Start recording.
3. **Speak** — Watch your words appear in the Dynamic Island overlay.
4. **Release** — Text is automatically typed into the active text field.

## Permissions

OpenEar requires two permissions:

| Permission | Why |
|------------|-----|
| **Microphone** | To capture your voice for transcription |
| **Accessibility** | To type text into other applications |

Both permissions are requested during onboarding with clear explanations.

## Privacy

- All speech processing happens **locally** on your Mac
- No audio is sent to any server
- No telemetry or analytics (yet)
- Your transcriptions are never stored

## Tech Stack

| Component | Technology |
|-----------|------------|
| Framework | SwiftUI |
| Speech Recognition | [WhisperKit](https://github.com/argmaxinc/WhisperKit) |
| Model | whisper-base.en (~140MB) |
| Hotkeys | [KeyboardShortcuts](https://github.com/sindresorhus/KeyboardShortcuts) + IOKit |

## Architecture

```
OpenEar/
├── App/
│   ├── OpenEarApp.swift      # Main app entry
│   └── AppState.swift        # Central state management
├── Core/
│   ├── Audio/                # Microphone capture
│   ├── Transcription/        # WhisperKit integration
│   ├── TextInjection/        # Clipboard + keyboard simulation
│   └── Hotkey/               # Fn key + keyboard shortcuts
└── UI/
    ├── MenuBar/              # Menu bar interface
    ├── Recording/            # Dynamic Island overlay
    ├── Onboarding/           # First-launch setup
    └── Settings/             # Preferences
```

## Roadmap

- [ ] Telemetry & crash reporting
- [ ] Auto-updates (Sparkle)
- [ ] Multiple language support
- [ ] Custom vocabulary/corrections
- [ ] Larger model options
- [ ] App Store release

## Contributing

Contributions welcome! Please open an issue first to discuss what you'd like to change.

## License

MIT License — see [LICENSE](LICENSE) for details.

## Acknowledgments

- [WhisperKit](https://github.com/argmaxinc/WhisperKit) by Argmax for the incredible on-device Whisper implementation
- [KeyboardShortcuts](https://github.com/sindresorhus/KeyboardShortcuts) by Sindre Sorhus
- Apple's Dynamic Island for design inspiration
