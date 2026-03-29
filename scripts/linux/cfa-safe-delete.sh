#!/usr/bin/env bash
# cfa-safe-delete.sh — Linux equivalent of CFA safe delete
# Handles: immutable flags (chattr +i), AppArmor profiles, SELinux contexts
#
# Author:  Chharith Oeun (BBoy-PopTart)
# Repo:    https://github.com/BBoy-PopTart/cfa-safe-delete
# License: MIT

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

usage() {
    echo "Usage: $0 <path> [path2] [path3] ..."
    echo ""
    echo "Examples:"
    echo "  sudo $0 /home/user/Samsung"
    echo "  sudo $0 /home/user/Folder1 /home/user/Folder2"
    echo ""
    echo "Handles:"
    echo "  - Immutable flags (chattr +i)"
    echo "  - AppArmor confined deletion"
    echo "  - SELinux context issues"
    echo "  - Extended attribute locks (xattr)"
    exit 1
}

check_root() {
    if [[ $EUID -ne 0 ]]; then
        echo -e "${RED}Error: This script requires root (sudo).${NC}"
        exit 1
    fi
}

get_free_gb() {
    local path="$1"
    local mount
    mount=$(df -P "$path" 2>/dev/null | tail -1 | awk '{print $6}')
    df -BG "$mount" 2>/dev/null | tail -1 | awk '{print $4}' | tr -d 'G'
}

diagnose_path() {
    local target="$1"
    echo -e "${CYAN}[DIAGNOSE] $target${NC}"

    # Check immutable flag
    if command -v lsattr &>/dev/null; then
        if lsattr -d "$target" 2>/dev/null | grep -q 'i'; then
            echo -e "  ${YELLOW}WARN: Immutable flag set (chattr +i)${NC}"
            return 1
        fi
    fi

    # Check AppArmor
    if command -v aa-status &>/dev/null && aa-status --enabled 2>/dev/null; then
        echo -e "  ${YELLOW}INFO: AppArmor is active — may restrict deletion${NC}"
    fi

    # Check SELinux
    if command -v getenforce &>/dev/null; then
        local se_state
        se_state=$(getenforce 2>/dev/null || echo "Unknown")
        if [[ "$se_state" == "Enforcing" ]]; then
            echo -e "  ${YELLOW}INFO: SELinux Enforcing — check context with: ls -Z $target${NC}"
        fi
    fi

    return 0
}

safe_delete() {
    local target="$1"
    local name
    name=$(basename "$target")

    if [[ ! -e "$target" ]]; then
        echo -e "  ${GREEN}[$name] Not found — already gone${NC}"
        return 0
    fi

    echo -e "${CYAN}[$name] Removing blockers...${NC}"

    # Step 1: Remove immutable flag recursively
    if command -v chattr &>/dev/null; then
        chattr -R -i "$target" 2>/dev/null || true
        echo -e "  Immutable flags cleared"
    fi

    # Step 2: Remove extended attributes (xattr)
    if command -v xattr &>/dev/null; then
        xattr -cr "$target" 2>/dev/null || true
        echo -e "  Extended attributes cleared"
    fi

    # Step 3: Fix permissions
    chmod -R u+rwX "$target" 2>/dev/null || true

    # Step 4: Delete
    echo -e "${CYAN}[$name] Deleting...${NC}"
    if rm -rf "$target" 2>/dev/null; then
        if [[ ! -e "$target" ]]; then
            echo -e "  ${GREEN}[$name] DELETED OK${NC}"
            return 0
        fi
    fi

    # AppArmor fallback: check if aa-exec available
    if command -v aa-exec &>/dev/null; then
        echo -e "  ${YELLOW}Trying AppArmor unconfined mode...${NC}"
        aa-exec -p unconfined -- rm -rf "$target" 2>/dev/null || true
        if [[ ! -e "$target" ]]; then
            echo -e "  ${GREEN}[$name] DELETED OK (AppArmor unconfined)${NC}"
            return 0
        fi
    fi

    echo -e "  ${RED}[$name] FAILED — still present${NC}"
    echo -e "  ${YELLOW}Try: sudo chattr -R -i $target && sudo rm -rf $target${NC}"
    return 1
}

main() {
    if [[ $# -eq 0 ]]; then usage; fi

    check_root

    echo ""
    echo -e "${CYAN}=== CFA SAFE DELETE (Linux) ===${NC}"
    echo -e "github.com/BBoy-PopTart/cfa-safe-delete"
    echo ""

    # Get free space on first target's filesystem
    local first_target="$1"
    local mount_point
    mount_point=$(df -P "$first_target" 2>/dev/null | tail -1 | awk '{print $6}' || echo "/")
    local free_before
    free_before=$(get_free_gb "$mount_point")
    echo -e "${YELLOW}Free before: ${free_before}G${NC}"
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

    local free_after
    free_after=$(get_free_gb "$mount_point")
    local freed=$((free_after - free_before))

    echo -e "${CYAN}=== RESULTS ===${NC}"
    echo -e "${GREEN}Free after: ${free_after}G  (freed +${freed}G)${NC}"
    echo -e "Deleted: $success / $((success + fail))"
    echo ""
}

main "$@"
