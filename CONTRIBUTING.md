# Contributing

Thank you for helping improve Xuemei Optimizer.

1. Keep cleanup behavior conservative. New deletion rules must have a narrow, documented allowlist.
2. Do not weaken protections for browser/account data, Keychains, SSH, wallets, source trees, Docker, IOTA/Bittensor/Macrocosmos, or personal folders.
3. Keep the version synchronized across `Info.plist`, `main.m`, and `engine.sh`.
4. Run `./scripts/check-source.sh` before opening a pull request.
5. On macOS, run `./scripts/build-app.sh` and verify the app launches before requesting merge.
6. Never include real secrets, personal scan reports, or local absolute user paths in tests/issues.

Bug reports should include the macOS version, the app version, the page/action involved, expected behavior, actual behavior, and a redacted log excerpt where useful.
