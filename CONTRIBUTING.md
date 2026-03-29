# Contributing to cfa-safe-delete

Thanks for contributing. This tool was born from a real pain point — here's how to help make it better.

## What We Need

- Additional Windows Defender edge cases (Tamper Protection, policy-locked CFA)
- macOS TCC improvements (Full Disk Access flow)
- Linux SELinux / AppArmor profiles
- Language ports: Python, Go, Rust, C#
- Real-world test cases with metrics

## Ground Rules

1. **No `robocopy /MOVE`** — caused data loss in production. Never.
2. **No Unicode in .ps1 files** — PowerShell 5.1 UTF-8 BOM breaks scripts silently.
3. **Always restore CFA state** — the `finally` block is safety-critical.
4. **Show real metrics** — if you test it, share actual numbers (GB freed, files, time).
5. **ASCII-only in PowerShell** — no emoji, no box-drawing chars, no curly quotes.

## Submitting a PR

1. Fork → branch → code → test
2. Run `diagnose.ps1` on your test case and include output
3. Update CHANGELOG.md with your change
4. PRs without test evidence get lower priority

## Bug Reports

Use the issue template. Include `diagnose.ps1` output — it tells us everything we need.
