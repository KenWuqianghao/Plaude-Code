#!/usr/bin/env bash
set -euo pipefail
# Submit a Developer-ID-signed DMG to Apple and staple the ticket (no more Gatekeeper “cannot verify”).
#
# Prereqs:
#   • Xcode CLI tools
#   • Paid Apple Developer account
#   • notarytool profile (once): xcrun notarytool store-credentials ...
#
# Environment:
#   NOTARY_PROFILE  Keychain profile name (default: plaude-notary)

DMG="${1:?Usage: $0 path/to.dmg}"
PROFILE="${NOTARY_PROFILE:-plaude-notary}"

xcrun notarytool submit "$DMG" --keychain-profile "$PROFILE" --wait
xcrun stapler staple "$DMG"
echo "Stapled $DMG — Gatekeeper should accept this build after download."
