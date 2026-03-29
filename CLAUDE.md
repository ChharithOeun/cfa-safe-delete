# CLAUDE.md — AI Assistant Guide for cfa-safe-delete

This file tells AI assistants (Claude, Copilot, Gemini, etc.) how to work on this repo effectively.

---

## What This Repo Does

Deletes folders that are blocked by Windows Defender Controlled Folder Access (CFA) — the silent "Access is denied" that survives `takeown`, `icacls /reset`, process kills, and service stops.

**The core fix is 3 lines:**
```powershell
$cfa = (Get-MpPreference).EnableControlledFolderAccess
if ($cfa -ne 0) { Set-MpPreference -EnableControlledFolderAccess Disabled }
# ... delete ...
if ($cfa -ne 0) { Set-MpPreference -EnableControlledFolderAccess Enabled }
```

---

## Architecture

```
scripts/
  windows/
    cfa-safe-delete.ps1   # Main script. CmdletBinding, pipeline support, WhatIf
    diagnose.ps1          # Diagnostic-only. No side effects. Safe to run first.
  linux/
    cfa-safe-delete.sh    # Handles chattr +i, AppArmor, SELinux
  macos/
    cfa-safe-delete.sh    # Handles xattr, quarantine flags, TCC, BSD chflags
```

---

## Key Design Decisions

1. **`try/finally` for CFA toggle** — CFA must be re-enabled even if deletion fails. This is safety-critical. Never remove the finally block.

2. **`\\?\` long-path prefix** — Samsung SmartSwitch backups and similar tools create paths >260 chars. Always use `\\?\` prefix for rmdir on Windows.

3. **No `robocopy /MOVE`** — This project previously had data loss from robocopy /MOVE. Never add it back. Copy-verify-delete only.

4. **Report real metrics** — The README shows actual numbers (280.4 GB freed, 5 failed attempts). Keep these real. Don't round or sanitize.

5. **PowerShell 5.1 compatibility** — No emoji or Unicode box-drawing chars in PS1 files. PowerShell 5.1 misreads UTF-8 BOM as stray `"` characters. ASCII only in scripts.

---

## When Handling Issues

If someone reports "still getting Access is denied after running cfa-safe-delete":

1. Ask them to run `diagnose.ps1` first and share output
2. Check if they ran as Administrator (most common mistake)
3. Check if Windows Defender itself is disabled (CFA requires Defender to be running)
4. Check if it's a OneDrive/Dropbox sync conflict (those also cause access denied)
5. Check if folder is a junction/symlink — rmdir behavior differs

---

## PR Review Checklist

- [ ] No Unicode/emoji in .ps1 files (breaks PS 5.1)
- [ ] CFA is always re-enabled in a `finally` block
- [ ] `\\?\` prefix used for all Windows path deletions
- [ ] Metrics in README reflect real-world test data
- [ ] Platform scripts tested on their respective OS
- [ ] `#Requires -RunAsAdministrator` present in Windows scripts
- [ ] No `robocopy /MOVE` anywhere

---

## Testing

**Windows:**
```powershell
# Create a test folder with CFA-protected files
mkdir C:\TestDelete\nested\deep\path
"test" | Out-File C:\TestDelete\nested\deep\path\file.txt
# Enable CFA, verify it blocks normal rmdir, then test our script
.\scripts\windows\cfa-safe-delete.ps1 -Path C:\TestDelete -WhatIf
.\scripts\windows\cfa-safe-delete.ps1 -Path C:\TestDelete
```

**Linux:**
```bash
sudo mkdir -p /tmp/test-delete/nested
sudo chattr +i /tmp/test-delete/nested
sudo ./scripts/linux/cfa-safe-delete.sh /tmp/test-delete
```

**macOS:**
```bash
mkdir -p /tmp/test-delete/nested
xattr -w com.apple.quarantine "0083;00000000;;" /tmp/test-delete/nested
./scripts/macos/cfa-safe-delete.sh /tmp/test-delete
```

---

## Repo Owner

Chharith Oeun | [@BBoy-PopTart](https://github.com/BBoy-PopTart) | Chharbot Project
