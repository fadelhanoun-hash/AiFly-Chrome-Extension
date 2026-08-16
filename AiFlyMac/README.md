# AiFly for Mac

AiFly for Mac is a native, keyboard-first launcher that combines the existing AiFly AI assistant with Alfred-style Spotlight file search.

## Run locally

1. Open `Package.swift` in Xcode.
2. Select the `AiFlyMac` scheme and run it.
3. Open the menu-bar sparkle and choose **Settings**.
4. Choose a global hotkey and add an OpenAI or Gemini API key.

The default shortcut is **Option + Space**. File search uses the Mac Spotlight index, opens the selected result with Return, and supports arrow-key navigation. The Ask AI tab keeps recent conversation context in memory. API keys are stored in Keychain.

## App-store packaging

The Swift package is intentionally dependency-free. For distribution, create a macOS App target in Xcode using the files in `Sources/AiFlyMac`, add an app icon, enable outgoing network connections in App Sandbox, then sign and notarize the archive.
