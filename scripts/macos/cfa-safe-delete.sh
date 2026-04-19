#!/usr/bin/env bash
# shellcheck disable=SC2015
# cfa-safe-delete.sh — macOS equivalent of CFA safe delete
# Handles: quarantine flags, extended attributes (xattr), SIP, TCC restrictions
#
# Author:  Chharith Oeun (BBoy-PopTart)
# Repo:    https://github.com/BBoy-PopTart/cfa-safe-delete
# License: MIT
#
# macOS "Access is denied" equivalents:
#   - com.apple.quarantine xattr (Gatekeeper quarantine flag)
#   - com.apple.metadata:kMDItemWhereFroms (download origin tracking)
#   - System Integrity Protection (SIP) — blocks /System, /usr, /sbin
#   - TCC (Transparency, Consent, Control) — blocks ~/Desktop, ~/Documents, ~/Downloads
#     unless Full Disk Access is granted in System Settings → Privacy & Security

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

usage() {
    echo "Usage: $0 <path> [path2] [path3] ..."
    echo ""
    echo "Note: For ~/Documents, ~/Desktop, ~/Downloads, grant Full Disk Access to Terminal:"
    echo "  System Settings → Privacy & Security → Full Disk Access → add Terminal"
    echo ""
    echo "Examples:"
    echo "  $0 ~/Documents/Samsung"
    echo "  sudo $0 /Library/Application\\ Support/SomeTool"
    exit 1
}

get_free_gb() {
    local path="$1"
    df -g "$path" 2>/dev/null | tail -1 | awk '{print $4}' || echo "unknown"
}

diagnose_path() {
    local target="$1"
    echo -e "${CYAN}[DIAGNOSE] $target${NC}"

    # Check quarantine
    if xattr "$target" 2>/dev/null | grep -q 'com.apple.quarantine'; then
        echo -e "  ${YELLOW}WARN: Quarantine flag set — Gatekeeper is blocking deletion${NC}"
    fi

    # Check SIP
    local sip_status
    sip_status=$(csrutil status 2>/dev/null || echo "unknown")
    if echo "$sip_status" | grep -q "enabled"; then
        echo -e "  ${YELLOW}INFO: SIP is enabled — /System, /usr, /sbin paths are protected${NC}"
    fi

    # TCC check
    if [[ "$target" == ~/Documents* ]] || [[ "$target" == ~/Desktop* ]] || [[ "$target" == ~/Downloads* ]]; then
        echo -e "  ${YELLOW}INFO: TCC-protected path — Terminal needs Full Disk Access${NC}"
        echo -e "  ${YELLOW}      System Settings → Privacy & Security → Full Disk Access${NC}"
    fi
}

safe_delete() {
    local target="$1"
    local expanded_target
    expanded_target="${target/#\~/$HOME}"
    local name
    name=$(basename "$expanded_target")

    if [[ ! -e "$expanded_target" ]]; then
        echo -e "  ${GREEN}[$name] Not found — already gone${NC}"
        return 0
    fi

    echo -e "${CYAN}[$name] Removing blockers...${NC}"

    # Step 1: Remove all extended attributes (quarantine, metadata, etc.)
    xattr -cr "$expanded_target" 2>/dev/null && echo -e "  Extended attributes cleared" || true

    # Step 2: Specifically remove quarantine flag
    xattr -rd com.apple.quarantine "$expanded_target" 2>/dev/null || true

    # Step 3: Fix permissions
    chmod -R u+rwX "$expanded_target" 2>/dev/null || true

    # Step 4: Unlock any BSD locked files
    chflags -R nouchg,nouappnd,noschg,nosappnd "$expanded_target" 2>/dev/null || true
    if command -v chflags &>/dev/null; then
        echo -e "  BSD flags cleared"
    fi

    # Step 5: Delete
    echo -e "${CYAN}[$name] Deleting...${NC}"
    if rm -rf "$expanded_target" 2>/dev/null; then
        if [[ ! -e "$expanded_target" ]]; then
            echo -e "  ${GREEN}[$name] DELETED OK${NC}"
            return 0
        fi
    fi

    echo -e "  ${RED}[$name] FAILED${NC}"
    echo -e "  ${YELLOW}Options:${NC}"
    echo -e "  ${YELLOW}  1. Grant Terminal Full Disk Access in System Settings${NC}"
    echo -e "  ${YELLOW}  2. Reboot into Recovery Mode and disable SIP (if system path)${NC}"
    echo -e "  ${YELLOW}  3. sudo rm -rf $expanded_target${NC}"
    return 1
}

main() {
    if [[ $# -eq 0 ]]; then usage; fi

    echo ""
    echo -e "${CYAN}=== CFA SAFE DELETE (macOS) ===${NC}"
    echo -e "github.com/BBoy-PopTart/cfa-safe-delete"
    echo ""

    local first_target="${1/#\~/$HOME}"
    local free_before
    free_before=$(get_free_gb "$first_target")
    echo -e "${YELLOW}Free before: ~${free_before}G${NC}"
    echo ""

    local success=0
    local fail=0

    for target in "$@"; do
        diagnose_path "$target" || true
        if safe_delete "$target"; then
            ((success++)) || true
        else
            ((fail++)) || true
        fi
        echo ""
    done

    local first_parent
    first_parent=$(dirname "${first_target/#\~/$HOME}")
    local free_after
    free_after=$(get_free_gb "$first_parent")

    echo -e "${CYAN}=== RESULTS ===${NC}"
    echo -e "${GREEN}Free after: ~${free_after}G${NC}"
    echo -e "Deleted: $success / $((success + fail))"
    echo ""
}

main "$@"
