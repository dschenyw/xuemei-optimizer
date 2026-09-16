# Changelog

## 4.1.5 — Unknown-source deep classification

- Treats `/private/var/folders` as system cache rather than normal installer storage.
- Classifies `/opt`, `/usr/local`, and `/Library/Developer` as developer-tool locations.
- Recognizes Application Support, frameworks, resources, runtimes, SDKs, toolchains, package/runtime trees and VM-related paths as protected support/tool resources.
- Unknown ZIP/DMG/ISO/PKG items are shown as other compressed resources and are view-only by default.
- Protected compressed resources are excluded from the true installer count.

## 4.1.4 — Source classification refinement

- Added a source column for full-disk results.
- Distinguishes application-internal, system, temporary, cache, Xcode, developer-tool, personal, Library and other sources.
- Developer-tool archives are protected instead of treated as normal installers.

## 4.1.3 — Full-disk classification correction

- Application bundle resources no longer count as normal installers.
- System resources receive explicit protection labels.
- Installer candidate scanning avoids application/system/developer roots where deletion would be unsafe.
- Corrected `/System/Volumes/Data` path normalization for user-cache allowlists.

## 4.1.2 — One-click installer detection

- One-click safe cleanup can reuse the last installer-cleanup folder and falls back to Downloads when appropriate.
- Installer candidates are scanned before confirmation and summarized by installed/damaged/stale status.

## 4.0.0 — System optimizer center

- Expanded from a cleaner into a broader macOS optimizer with overview, smart optimization, full scan, installer cleanup, large files, app management, startup items, memory, network, health, protection, updates and about pages.

Earlier history is preserved in `docs/release-history-legacy.txt`.
