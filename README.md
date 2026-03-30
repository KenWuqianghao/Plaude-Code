# Plaude Code

Menu bar macOS app that maps a **DualSense** (and similar) controller to keyboard shortcuts and pointer events, aimed at driving **[Claude Code](https://docs.anthropic.com/en/docs/claude-code)** inside **[Ghostty](https://ghostty.org/)** and nearby workflows.

## Features

- Controller button-to-action mappings with profiles persisted on disk
- Optional **DualSense touchpad as mouse** (pointer, click, two-finger scroll) using HID reports when Game Controller axes are unreliable
- **Cheatsheet** overlay for quick reference to bindings
- **Injection toggle** so you can leave the app running without sending keys until you want to

## Requirements

- **macOS 14** or later
- **Swift 5.10+** (for building from source)
- Prebuilt **DMG** releases are **Apple Silicon (arm64)**; Intel Macs can build locally with `swift build`

## Install

1. Open the **[latest release](https://github.com/KenWuqianghao/Plaude-Code/releases/latest)** and download `PlaudeCode-*.dmg`.
2. Open the disk image and drag **Plaude Code** into **Applications**.
3. Launch the app. When macOS prompts you, grant **Accessibility** (and related permissions as shown in the menu bar window) so key and pointer injection can work.

> Unsigned builds may require **Right-click → Open** the first time you run the app, or approval under **Privacy & Security** in System Settings.

## Development

```bash
git clone https://github.com/KenWuqianghao/Plaude-Code.git
cd Plaude-Code
swift run PlaudeCode
```

Release binary:

```bash
swift build -c release
.build/arm64-apple-macosx/release/PlaudeCode
```

### Packaging a DMG

```bash
./scripts/build-dmg.sh 1.0.0   # version argument; outputs dist/PlaudeCode-1.0.0.dmg
```

## License

No license file is bundled in this repository yet; treat usage as **all rights reserved** until one is added.
