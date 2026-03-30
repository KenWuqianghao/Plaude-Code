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

### First launch: “Apple could not verify…” (Gatekeeper)

GitHub DMGs are **ad-hoc signed**, not **notarized**. macOS may say the app **can’t be verified** or **may harm your Mac**. That is Gatekeeper blocking apps that are not on Apple's “allowed” list—not a claim that the build contains malware.

**Ways to open it anyway (pick one):**

1. **Finder → Applications → Plaude Code** — **Control-click** (or right-click) the app → **Open** → confirm **Open** in the dialog. You only need to do this once.
2. If you already tried to open it: **System Settings → Privacy & Security** — scroll to the message about Plaude Code → **Open Anyway** (may require login).

There is **no way in this repo** to remove that warning for strangers downloading the DMG without a **paid Apple Developer** account: you must **Developer ID sign** the app and **notarize** the disk image (Apple scans it, then you “staple” the ticket). Public releases here stay ad-hoc until a maintainer runs that pipeline.

### Notarized builds (maintainers)

1. Enroll in the **[Apple Developer Program](https://developer.apple.com/programs/)** and install a **Developer ID Application** certificate in Keychain.
2. Build the DMG with signing (replace identity string from Keychain / `security find-identity -v -p codesigning`):

   ```bash
   export CODESIGN_IDENTITY="Developer ID Application: Your Name (XXXXXXXXXX)"
   ./scripts/build-dmg.sh 1.0.0
   ```

3. Save **notarytool** credentials once ([Apple: Notarize with notarytool](https://developer.apple.com/documentation/securitynotaryapi)):  
   `xcrun notarytool store-credentials "plaude-notary" --apple-id "..." --team-id "..." --password "..."`

4. Submit and staple:

   ```bash
   NOTARY_PROFILE=plaude-notary ./scripts/notarize-dmg.sh dist/PlaudeCode-1.0.0.dmg
   ```

After stapling, upload **that** DMG to GitHub Releases; downloaders should **not** see the verification warning (assuming default Gatekeeper settings).

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

The script builds a **proper `.app`** with `AppIcon.icns`, **`PkgInfo`**, and **`codesign`**, then lays out a **read/write HFS+** disk image and converts it to a compressed DMG (more reliable than `hdiutil create -srcfolder` alone). The DMG includes an **Applications** shortcut for drag-install.

Set **`CODESIGN_IDENTITY`** to a **Developer ID Application** identity before running the script to produce a build that Apple will accept after **notarization** (see above).

## Logo

Minimal mark (touchpad + code brackets) for menus, Dock, and GitHub:

| File | Use |
|------|-----|
| [`Packaging/Logo/AppIcon-1024.png`](Packaging/Logo/AppIcon-1024.png) | Raster master (~1024²); derive `.icns` / asset sizes in Xcode or `iconutil` |
| [`Packaging/Logo/PlaudeCode-mark.svg`](Packaging/Logo/PlaudeCode-mark.svg) | Vector variant (flat colors: `#0d1117` / `#f0e6d2`) |

The shipping menu bar item still uses the system **gamecontroller** symbol until a bundled template image is wired into the target.

## License

No license file is bundled in this repository yet; treat usage as **all rights reserved** until one is added.
