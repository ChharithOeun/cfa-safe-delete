---
name: Bug Report
about: Script didn't work / still getting Access is denied
title: '[BUG] '
labels: bug
assignees: BBoy-PopTart
---

## Describe the Bug
What happened? What did you expect?

## Diagnose Output
**Run `diagnose.ps1` first and paste the full output here:**
```
paste diagnose.ps1 output here
```

## Script Output
```
paste cfa-safe-delete.ps1 output here
```

## Environment
- OS: [e.g. Windows 11 23H2]
- PowerShell version: (`$PSVersionTable.PSVersion`)
- Ran as Administrator: Yes / No
- Windows Defender enabled: Yes / No
- CFA state before running: (`(Get-MpPreference).EnableControlledFolderAccess`)
- Tamper Protection enabled: Yes / No / Unknown

## Target Path (redacted if needed)
e.g. `C:\Users\User\Documents\[folder type]` — Samsung backup, Steam, etc.

## What You Tried Before This
List any other deletion methods you attempted.

## True Metrics
- Folder size: XX GB
- Approximate file count: XX,XXX
- Path depth / longest path length: ~XXX chars
