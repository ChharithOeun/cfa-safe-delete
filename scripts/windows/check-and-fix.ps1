#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Check-And-Fix: Diagnose and resolve Windows Defender CFA blocking folder deletion.

.DESCRIPTION
    This is the original script that solved the problem — 280.4 GB freed on one run.

    The discovery: Windows Defender Controlled Folder Access (CFA) silently blocks
    deletion of files in protected folders (Documents, Desktop, Pictures) even for
    Administrators/SYSTEM. The ACL looks fine. No processes are locking the files.
    rmdir just says "Access is denied." The fix is three lines:
      1. Read CFA state
      2. Disable CFA
      3. Delete
      4. Restore CFA

    This script diagnoses first, then fixes. Safe to run on any protected folder.

.PARAMETER Path
    Folder to delete. Must exist. Will be gone after this runs.

.EXAMPLE
    # Check and fix a specific folder
    .\check-and-fix.ps1 -Path "C:\Users\User\Documents\SomeHugeFolder"

.EXAMPLE
    # Dry run (diagnose only, no deletion)
    .\check-and-fix.ps1 -Path "C:\Users\User\Documents\SomeHugeFolder" -WhatIf

.NOTES
    Author  : BBoy-PopTart / Chharbot
    Version : 1.0.0
    Repo    : https://github.com/BBoy-PopTart/cfa-safe-delete
    Real result: Samsung SmartSwitch 266.6 GB + Steam Backup 9 GB + BFD Drums 4.8 GB
                 = 280.4 GB freed. C: went from 84.4 GB free to 364.8 GB free.
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
    [string]$Path
)

# ── Diagnostics ──────────────────────────────────────────────────────────────

Write-Host ""
Write-Host "=== CFA Check-And-Fix Diagnostics ===" -ForegroundColor Cyan
Write-Host ""

# 1. Path exists?
if (-not (Test-Path $Path)) {
    Write-Host "[ERROR] Path not found: $Path" -ForegroundColor Red
    exit 1
}
Write-Host "[OK]  Path exists: $Path" -ForegroundColor Green

# 2. Path length
$len = $Path.Length
$flag = if ($len -gt 260) { "[WARN] > 260 chars - long-path bypass needed" } else { "[OK]" }
Write-Host "$flag  Path length: $len chars" -ForegroundColor $(if ($len -gt 260) { "Yellow" } else { "Green" })

# 3. CFA state -- THIS IS THE KEY CHECK
$cfaState = (Get-MpPreference).EnableControlledFolderAccess
$cfaLabel = switch ($cfaState) {
    0 { "DISABLED" }
    1 { "ENABLED -- THIS IS THE BLOCKER" }
    2 { "AUDIT MODE" }
    default { "UNKNOWN ($cfaState)" }
}
$cfaColor = if ($cfaState -eq 1) { "Red" } else { "Green" }
Write-Host "      Controlled Folder Access: $cfaLabel" -ForegroundColor $cfaColor

# 4. ACL check
Write-Host ""
Write-Host "--- ACL / Permissions ---" -ForegroundColor Gray
try {
    $acl = Get-Acl $Path
    foreach ($ace in $acl.Access) {
        Write-Host "  $($ace.IdentityReference) : $($ace.FileSystemRights) [$($ace.AccessControlType)]"
    }
} catch {
    Write-Host "  [WARN] Could not read ACL: $_" -ForegroundColor Yellow
}

# 5. File locks
Write-Host ""
Write-Host "--- Checking for process locks ---" -ForegroundColor Gray
$lockers = @("SearchIndexer","MsMpEng","SmartSwitch","SamsungDeX","WSearch")
foreach ($proc in $lockers) {
    $running = Get-Process -Name $proc -ErrorAction SilentlyContinue
    if ($running) {
        Write-Host "  [INFO] Running: $proc (PID $($running.Id))" -ForegroundColor Yellow
    }
}
Write-Host "  (Only CFA matters -- locks are a red herring if CFA is on)" -ForegroundColor Gray

# ── Fix ───────────────────────────────────────────────────────────────────────

Write-Host ""
Write-Host "=== Applying Fix ===" -ForegroundColor Cyan
Write-Host ""

if ($cfaState -ne 0) {
    if ($PSCmdlet.ShouldProcess("Windows Defender", "Disable Controlled Folder Access")) {
        Write-Host "[1/3] Disabling CFA..." -ForegroundColor Yellow
        Set-MpPreference -EnableControlledFolderAccess Disabled
        Start-Sleep -Seconds 2
        Write-Host "      CFA disabled." -ForegroundColor Green
    }
}

try {
    if ($PSCmdlet.ShouldProcess($Path, "Delete folder")) {
        Write-Host "[2/3] Deleting: $Path" -ForegroundColor Yellow

        $before = (Get-PSDrive C).Free

        # Try standard removal first
        Remove-Item -LiteralPath $Path -Recurse -Force -ErrorAction SilentlyContinue

        # Fallback: long-path UNC prefix
        if (Test-Path $Path) {
            Write-Host "      Standard removal failed, trying long-path prefix..." -ForegroundColor Yellow
            cmd /c "rmdir /S /Q `"\\?\$Path`"" 2>$null
        }

        if (Test-Path $Path) {
            Write-Host "      [ERROR] Folder still exists after deletion attempt." -ForegroundColor Red
        } else {
            $after  = (Get-PSDrive C).Free
            $freedGB = [math]::Round(($after - $before) / 1GB, 2)
            Write-Host "      [SUCCESS] Deleted. $freedGB GB freed on C:\" -ForegroundColor Green
            Write-Host "      C: free space: $([math]::Round($after/1GB,1)) GB" -ForegroundColor Green
        }
    }
} finally {
    if ($cfaState -ne 0) {
        Write-Host "[3/3] Restoring CFA to original state ($cfaState)..." -ForegroundColor Yellow
        Set-MpPreference -EnableControlledFolderAccess $cfaState
        Write-Host "      CFA restored." -ForegroundColor Green
    }
}

Write-Host ""
