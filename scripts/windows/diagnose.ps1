#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Diagnose why a folder cannot be deleted on Windows.

.DESCRIPTION
    Runs through the full diagnostic chain:
    - Path length check (MAX_PATH = 260)
    - NTFS permissions / ACL analysis
    - File lock detection (open handles)
    - Windows Defender CFA state
    - Attribute flags (R/H/S)
    - Recommends the correct fix

.PARAMETER Path
    Folder path to diagnose.

.EXAMPLE
    .\diagnose.ps1 -Path "C:\Users\User\Documents\Samsung"

.NOTES
    Author:  Chharith Oeun (BBoy-PopTart)
    Repo:    https://github.com/BBoy-PopTart/cfa-safe-delete
#>

param(
    [Parameter(Mandatory)]
    [string]$Path
)

Write-Host ""
Write-Host "=== DELETION BLOCKER DIAGNOSIS ===" -ForegroundColor Cyan
Write-Host "Target: $Path" -ForegroundColor White
Write-Host ""

if (-not (Test-Path $Path)) {
    Write-Host "Path does not exist — nothing to diagnose." -ForegroundColor Green
    exit 0
}

$issues = @()

# --- 1. Path length ---
Write-Host "[1] Checking path lengths..." -ForegroundColor Cyan
$longPaths = Get-ChildItem $Path -Recurse -Force -ErrorAction SilentlyContinue |
             Where-Object { $_.FullName.Length -gt 260 }
$longCount = ($longPaths | Measure-Object).Count
if ($longCount -gt 0) {
    Write-Host "  WARN: $longCount paths exceed MAX_PATH (260 chars)" -ForegroundColor Yellow
    Write-Host "  Fix: Use \\?\ prefix in rmdir" -ForegroundColor Yellow
    $issues += "MAX_PATH exceeded ($longCount files)"
} else {
    Write-Host "  OK: All paths within 260 chars" -ForegroundColor Green
}

# --- 2. Permissions ---
Write-Host ""
Write-Host "[2] Checking ACL / permissions..." -ForegroundColor Cyan
try {
    $acl = Get-Acl $Path -ErrorAction Stop
    $hasFullControl = $acl.Access | Where-Object {
        $_.IdentityReference -match "Administrators" -and
        $_.FileSystemRights -match "FullControl" -and
        $_.AccessControlType -eq "Allow"
    }
    $hasDeny = $acl.Access | Where-Object { $_.AccessControlType -eq "Deny" }
    if ($hasFullControl) {
        Write-Host "  OK: Administrators have FullControl" -ForegroundColor Green
    } else {
        Write-Host "  WARN: Administrators do NOT have FullControl" -ForegroundColor Yellow
        $issues += "Missing Admin FullControl ACE"
    }
    if ($hasDeny) {
        Write-Host "  WARN: DENY entries present:" -ForegroundColor Yellow
        $hasDeny | ForEach-Object { Write-Host "    DENY: $($_.IdentityReference) -> $($_.FileSystemRights)" -ForegroundColor Yellow }
        $issues += "Explicit DENY ACEs present"
    }
    Write-Host "  Owner: $($acl.Owner)" -ForegroundColor DarkGray
} catch {
    Write-Host "  ERROR: Could not read ACL: $_" -ForegroundColor Red
    $issues += "Cannot read ACL"
}

# --- 3. File locks ---
Write-Host ""
Write-Host "[3] Checking for file locks (open handles)..." -ForegroundColor Cyan
# Check for processes that commonly lock files in this path
$suspectProcs = @("SearchIndexer", "MsMpEng", "SmartSwitch", "Samsung", "SWMAgent")
$foundProcs = @()
foreach ($pname in $suspectProcs) {
    $p = Get-Process -Name $pname -ErrorAction SilentlyContinue
    if ($p) {
        $foundProcs += $p
        Write-Host "  WARN: Running: $pname (PID $($p.Id))" -ForegroundColor Yellow
    }
}
if (-not $foundProcs) {
    Write-Host "  OK: No common lock-suspect processes found" -ForegroundColor Green
} else {
    $issues += "Potential locking processes: $($foundProcs.Name -join ', ')"
}

# --- 4. Controlled Folder Access ---
Write-Host ""
Write-Host "[4] Checking Windows Defender Controlled Folder Access..." -ForegroundColor Cyan
try {
    $cfa = (Get-MpPreference -ErrorAction Stop).EnableControlledFolderAccess
    $cfaMap = @{ 0 = "Disabled (OK)"; 1 = "ENABLED - THIS IS LIKELY THE BLOCKER"; 2 = "Audit Mode" }
    $cfaColor = if ($cfa -eq 1) { "Red" } elseif ($cfa -eq 2) { "Yellow" } else { "Green" }
    Write-Host "  CFA state: $($cfaMap[$cfa])" -ForegroundColor $cfaColor
    if ($cfa -ne 0) {
        $issues += "Controlled Folder Access is ENABLED"
        Write-Host "  Fix: Run cfa-safe-delete.ps1 (temporarily disables CFA to delete)" -ForegroundColor Yellow
    }
} catch {
    Write-Host "  Could not query CFA state (Windows Defender may not be running): $_" -ForegroundColor DarkGray
}

# --- 5. Attributes ---
Write-Host ""
Write-Host "[5] Checking NTFS attributes..." -ForegroundColor Cyan
$item = Get-Item $Path -Force -ErrorAction SilentlyContinue
if ($item) {
    $attrs = $item.Attributes
    Write-Host "  Attributes: $attrs" -ForegroundColor $(if ($attrs -band [IO.FileAttributes]::ReadOnly) { "Yellow" } else { "Green" })
    if ($attrs -band [IO.FileAttributes]::ReadOnly) {
        $issues += "Folder has ReadOnly attribute"
        Write-Host "  Fix: attrib -R `"$Path`" /S /D" -ForegroundColor Yellow
    }
    if ($attrs -band [IO.FileAttributes]::System) {
        $issues += "Folder has System attribute"
        Write-Host "  Fix: attrib -S `"$Path`" /S /D" -ForegroundColor Yellow
    }
}

# --- Summary ---
Write-Host ""
Write-Host "=== DIAGNOSIS SUMMARY ===" -ForegroundColor Cyan
if ($issues) {
    Write-Host "Issues found:" -ForegroundColor Yellow
    $issues | ForEach-Object { Write-Host "  - $_" -ForegroundColor Yellow }
    Write-Host ""
    if ($issues -match "Controlled Folder Access") {
        Write-Host "RECOMMENDED FIX:" -ForegroundColor Green
        Write-Host "  .\cfa-safe-delete.ps1 -Path `"$Path`"" -ForegroundColor Green
    }
} else {
    Write-Host "No obvious blockers found." -ForegroundColor Green
    Write-Host "Try: cmd /c `"rmdir /S /Q \`"\\?\$Path\`"`"" -ForegroundColor White
}
Write-Host ""
