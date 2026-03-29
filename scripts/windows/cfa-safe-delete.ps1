#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Safely delete folders that are blocked by Windows Defender Controlled Folder Access (CFA).

.DESCRIPTION
    Windows Defender's Controlled Folder Access silently blocks deletion of files in
    protected directories (Documents, Desktop, Pictures, etc.) — even for Administrators
    and even after takeown + icacls + killing all processes.

    This script:
    1. Detects if CFA is enabled
    2. Temporarily disables it (if enabled)
    3. Deletes the target paths
    4. Re-enables CFA (always — even on error)
    5. Reports freed space

    Real-world result: 280.4 GB freed in one run after 5 failed conventional attempts.

.PARAMETER Path
    One or more folder paths to delete. Accepts pipeline input.

.PARAMETER WhatIf
    Show what would be deleted without deleting anything. CFA is not modified.

.PARAMETER SkipCFACheck
    Skip the CFA check (use if you already know CFA is disabled).

.EXAMPLE
    .\cfa-safe-delete.ps1 -Path "C:\Users\User\Documents\Samsung"

.EXAMPLE
    .\cfa-safe-delete.ps1 -Path @("C:\Path1", "C:\Path2", "C:\Path3")

.EXAMPLE
    # Dry run
    .\cfa-safe-delete.ps1 -Path "C:\BigFolder" -WhatIf

.NOTES
    Author:  Chharith Oeun (BBoy-PopTart)
    Repo:    https://github.com/BBoy-PopTart/cfa-safe-delete
    License: MIT
    Requires: Windows 10 1709+ / Windows 11, PowerShell 5.1+, Administrator
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
    [string[]]$Path,

    [switch]$SkipCFACheck
)

begin {
    $targets = @()
    $cfaOriginalState = $null
    $cfaWasDisabled = $false

    function Get-FolderSizeGB($p) {
        if (-not (Test-Path $p)) { return 0 }
        $bytes = (Get-ChildItem $p -Recurse -Force -ErrorAction SilentlyContinue |
                  Measure-Object -Property Length -Sum).Sum
        return [math]::Round($bytes / 1GB, 2)
    }

    function Write-Status($msg, $color = "White") {
        Write-Host $msg -ForegroundColor $color
    }

    # Check admin
    $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator)
    if (-not $isAdmin) {
        Write-Error "This script requires Administrator privileges. Right-click PowerShell and Run as Administrator."
        exit 1
    }
}

process {
    $targets += $Path
}

end {
    Write-Status ""
    Write-Status "=== CFA SAFE DELETE ===" Cyan
    Write-Status "github.com/BBoy-PopTart/cfa-safe-delete" DarkGray
    Write-Status ""

    # --- Snapshot C: free space before ---
    $driveLetter = ($targets[0] -replace '\\.*','').TrimEnd(':')
    $driveBefore = Get-PSDrive $driveLetter -ErrorAction SilentlyContinue
    $freeBefore = if ($driveBefore) { [math]::Round($driveBefore.Free / 1GB, 2) } else { 0 }
    Write-Status "${driveLetter}: free BEFORE: $freeBefore GB" Yellow

    # --- Validate paths ---
    $validTargets = $targets | Where-Object {
        if (-not (Test-Path $_)) {
            Write-Status "  [SKIP] Not found: $_" DarkGray
            return $false
        }
        return $true
    }

    if (-not $validTargets) {
        Write-Status "No valid paths to delete." Yellow
        return
    }

    # Show what will be deleted
    Write-Status ""
    Write-Status "Targets:" Cyan
    foreach ($t in $validTargets) {
        $sz = Get-FolderSizeGB $t
        Write-Status "  $t  ($sz GB)" White
    }
    Write-Status ""

    if ($WhatIfPreference) {
        Write-Status "[WhatIf] No changes made. Remove -WhatIf to delete." Yellow
        return
    }

    # --- Check and disable CFA ---
    if (-not $SkipCFACheck) {
        try {
            $cfaOriginalState = (Get-MpPreference -ErrorAction Stop).EnableControlledFolderAccess
            $cfaLabel = @{ 0 = "Disabled"; 1 = "Enabled"; 2 = "Audit Mode" }[$cfaOriginalState]
            Write-Status "Controlled Folder Access: $cfaLabel ($cfaOriginalState)" $(if ($cfaOriginalState -eq 1) { "Red" } else { "Green" })

            if ($cfaOriginalState -ne 0) {
                Write-Status "Temporarily disabling CFA..." Yellow
                Set-MpPreference -EnableControlledFolderAccess Disabled -ErrorAction Stop
                $cfaWasDisabled = $true
                Start-Sleep -Milliseconds 500
                Write-Status "CFA disabled." Green
            }
        }
        catch {
            Write-Status "Could not read/modify CFA state: $_" Yellow
            Write-Status "Proceeding without CFA toggle (may still fail if CFA is active)." Yellow
        }
    }

    # --- Delete targets (always in finally so CFA is re-enabled) ---
    $deletedCount = 0
    $failedTargets = @()

    try {
        foreach ($target in $validTargets) {
            $name = Split-Path $target -Leaf
            Write-Status ""
            Write-Status "[$name] Deleting..." Cyan

            # Try standard path first, fall back to \\?\ for paths > 260 chars
            $deleted = $false

            cmd /c "rmdir /S /Q `"$target`"" 2>&1 | Out-Null
            if (-not (Test-Path $target)) {
                $deleted = $true
            }
            else {
                # Long path fallback
                cmd /c "rmdir /S /Q `"\\?\$target`"" 2>&1 | Out-Null
                if (-not (Test-Path $target)) {
                    $deleted = $true
                }
            }

            if ($deleted) {
                Write-Status "  [$name] DELETED" Green
                $deletedCount++
            }
            else {
                Write-Status "  [$name] FAILED - still present after deletion attempt" Red
                $failedTargets += $target
            }
        }
    }
    finally {
        # ALWAYS re-enable CFA — even if deletion failed or threw an error
        if ($cfaWasDisabled) {
            Write-Status ""
            Write-Status "Re-enabling Controlled Folder Access..." Yellow
            try {
                Set-MpPreference -EnableControlledFolderAccess $cfaOriginalState -ErrorAction Stop
                Write-Status "CFA restored to original state ($cfaOriginalState)." Green
            }
            catch {
                Write-Status "WARNING: Could not re-enable CFA: $_" Red
                Write-Status "Manually re-enable: Set-MpPreference -EnableControlledFolderAccess Enabled" Red
            }
        }
    }

    # --- Results ---
    $driveAfter = Get-PSDrive $driveLetter -ErrorAction SilentlyContinue
    $freeAfter = if ($driveAfter) { [math]::Round($driveAfter.Free / 1GB, 2) } else { 0 }
    $freed = [math]::Round($freeAfter - $freeBefore, 2)

    Write-Status ""
    Write-Status "=== RESULTS ===" Cyan
    Write-Status "${driveLetter}: free: $freeAfter GB  (freed +$freed GB)" Green
    Write-Status "Deleted: $deletedCount / $($validTargets.Count) folders" $(if ($deletedCount -eq $validTargets.Count) { "Green" } else { "Yellow" })

    if ($failedTargets) {
        Write-Status ""
        Write-Status "Failed targets:" Red
        $failedTargets | ForEach-Object { Write-Status "  $_" Red }
        Write-Status "Try running diagnose.ps1 for more details." Yellow
    }
}
