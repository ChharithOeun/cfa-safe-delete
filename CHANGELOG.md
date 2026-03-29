# Changelog

All notable changes to cfa-safe-delete are documented here.

## [1.0.0] — 2026-03-28

### Added
- `scripts/windows/cfa-safe-delete.ps1` — Main Windows script with CFA toggle
- `scripts/windows/diagnose.ps1` — Diagnostic tool (no side effects)
- `scripts/linux/cfa-safe-delete.sh` — Linux equivalent (chattr, AppArmor, SELinux)
- `scripts/macos/cfa-safe-delete.sh` — macOS equivalent (xattr, quarantine, TCC, chflags)
- `-WhatIf` dry-run support
- `-Verbose` detailed output
- `-SkipCFACheck` for environments without Windows Defender
- `try/finally` pattern guarantees CFA is always re-enabled
- `\\?\` long-path prefix for paths >260 chars
- Pipeline input support for batch deletion

### Real-World Metrics (v1.0.0 Discovery Session)
- **Space freed:** 280.4 GB in a single run
- **Folders deleted:** 3 (Samsung SmartSwitch 266.6 GB, Steam Backup 9.0 GB, BFD Drums 4.8 GB)
- **Failed conventional attempts:** 5 (takeown, icacls, icacls /reset, process kill, service stop)
- **Root cause confirmed:** Windows Defender Controlled Folder Access = ENABLED
- **Fix time after root cause identified:** < 30 seconds

### Known Issues
- Tamper Protection (Windows Security Center) may prevent CFA toggle via PowerShell in some enterprise environments. Workaround: disable via Windows Security UI, or use Group Policy.
