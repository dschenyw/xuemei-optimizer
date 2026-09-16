# Security Policy

## Supported source snapshot

The current public source snapshot is v4.1.5.

## Reporting a vulnerability

Please do not publish credentials, private user paths, browser sessions, Keychain contents, wallet material, or other sensitive data in a public issue. Report the behavior with a minimal reproduction and redact personal data.

## Security design

Xuemei Optimizer follows a conservative local-cleanup model:

- no `sudo` requirement for normal cleanup;
- no `docker prune` automation;
- sensitive directories and account/browser data are protected by default;
- broad scans are read-only discovery/classification;
- permanent deletion is restricted to explicit allowlists and requires confirmation;
- update candidates are version-checked, locally compiled, backed up, and designed to roll back on failure.

## Repository hygiene

Do not commit:

- API keys, tokens, cookies, passwords, certificates, private keys or provisioning profiles;
- personal scan reports containing absolute user paths;
- `~/Library/Application Support/雪梅清理` state, logs, backups, or update caches;
- build products or signed application bundles.
