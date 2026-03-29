## What does this PR do?

## Platform(s) affected
- [ ] Windows
- [ ] Linux
- [ ] macOS
- [ ] All / Cross-platform

## Checklist
- [ ] No Unicode/emoji in .ps1 files (PS 5.1 breaks on UTF-8 BOM)
- [ ] CFA is restored in a `finally` block (if modified)
- [ ] `\\?\` prefix used for all Windows path deletions
- [ ] No `robocopy /MOVE`
- [ ] `#Requires -RunAsAdministrator` present in Windows scripts
- [ ] `diagnose.ps1` output included in this PR (if Windows change)
- [ ] CHANGELOG.md updated
- [ ] Real test metrics included (GB freed, OS version, file count)

## Test Evidence
```
paste script output / diagnose output here
```

## Metrics
- OS version:
- Space freed:
- Files affected:
- Edge case handled:
