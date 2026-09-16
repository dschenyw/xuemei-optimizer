# 雪梅优化 / Xuemei Optimizer

A native macOS cleanup and system-optimization utility built with Objective-C/AppKit and a zsh backend. The project emphasizes conservative cleanup rules: protected personal data and developer/security directories are excluded by default, while broad disk scans remain read-only until the user explicitly selects a safe action.

> Current source snapshot: **v4.1.5**. Minimum macOS version: **12.0**.

## What it does

- System overview and smart cleanup
- Read-only full-disk candidate browser with search/filtering
- Installer/archive cleanup with source classification
- Large-file discovery
- App, startup-item, memory, network, and system-health views
- Protection Center for sensitive paths and account/browser data
- Local/HTTPS update workflow with version consistency checks, SHA-256 validation, backup, and rollback

## Safety model

The cleanup engine is designed to avoid sensitive areas such as SSH keys, Keychains, browser/TikTok data, ChatGPT/OpenAI configuration, Docker data, IOTA/Bittensor/Macrocosmos data, wallets/keys, source trees, and personal folders. Full-disk discovery is primarily a read-only classification workflow; destructive actions are restricted to explicit allowlisted locations and require user confirmation.

No API keys, passwords, cookies, access tokens, or private keys are required by the application.

## Architecture

- `src/main.m` — native AppKit UI and result browser
- `src/engine.sh` — zsh scan, cleanup, diagnostics, update, backup and rollback logic
- `app/Info.plist` — macOS bundle metadata
- `app/Resources/` — branding and application icons
- `scripts/build-app.sh` — reproducible local app-bundle build on macOS
- `scripts/check-source.sh` — version and source-safety checks

The native binary is intentionally **not** committed. Build it locally from source.

## Build

Requirements:

- macOS 12 or later
- Xcode Command Line Tools (`xcode-select --install`)

```bash
./scripts/check-source.sh
./scripts/build-app.sh
open "build/雪梅优化.app"
```

The build script uses Apple `clang`, Cocoa/AppKit, and ad-hoc code signing. It does not use `sudo` and does not install anything outside the repository.

## Version consistency

Release updates are accepted only when these three values match:

1. `CFBundleShortVersionString` in `app/Info.plist`
2. `XMCVersion` in `src/main.m`
3. `VERSION` in `src/engine.sh`

For this snapshot all three are `4.1.5`.

## Privacy

The application works locally. It does not need an account, API key, telemetry service, or cloud database for its core cleanup functions. Some system locations may be inaccessible because of macOS privacy controls; the app is designed to skip protected areas rather than forcing broad permissions.

## Project status

This repository publishes the source snapshot used for the v4.1.5 app package. The project is being cleaned up from an application-bundle-oriented layout into a conventional open-source repository. Contributions that improve safety, testability, and macOS compatibility are welcome.

## License

MIT. See `LICENSE`.
