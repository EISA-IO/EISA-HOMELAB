#!/usr/bin/env bash
# =============================================================================
# EISA HOMELAB - One-click start (macOS)
# Runs setup.ps1 -StartOnly via pwsh (auto-launches Docker Desktop if needed,
# renders configs, brings the chosen profiles up, wires the *arr/Seerr stack)
# and then opens Heimdall in your default browser.
#
# Use MAC-HOMELAB-MANAGER.COMMAND for the menu-driven first-run wizard,
# stop/list, and the LLM manager. MAC_HOMELAB_START.command is intentionally
# a no-questions launcher - double-click and walk away.
# =============================================================================

set -u
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SETUP_PS1="$SCRIPT_DIR/files/scripts/setup.ps1"
HEIMDALL_URL="http://hub.localhost"

# ANSI colours (green like the Windows .bat).
GREEN=$'\033[32m'
RESET=$'\033[0m'

echo
echo "${GREEN} ============================================================${RESET}"
echo "${GREEN}  EISA HOMELAB - Starting${RESET}"
echo "${GREEN} ============================================================${RESET}"
echo
echo "${GREEN}  Docker auto-start  -  stack up  -  Heimdall dashboard${RESET}"
echo

if ! command -v pwsh >/dev/null 2>&1; then
    echo "  [X] PowerShell (pwsh) is required on macOS."
    echo "      Install:  brew install --cask powershell"
    echo
    read -rp "  Press Enter to close..."
    exit 1
fi

if [ ! -f "$SETUP_PS1" ]; then
    echo "  [X] Could not find setup.ps1 at:"
    echo "      $SETUP_PS1"
    echo "      Run MAC_HOMELAB_START.command from the homelab repo root."
    echo
    read -rp "  Press Enter to close..."
    exit 1
fi

pwsh -NoProfile -ExecutionPolicy Bypass -File "$SETUP_PS1" -StartOnly
EXITCODE=$?

if [ $EXITCODE -eq 0 ]; then
    echo
    echo "${GREEN}  [OK] Stack started. Opening Heimdall in your browser...${RESET}"
    open "$HEIMDALL_URL" 2>/dev/null || true
    # Brief hold so the user sees the OK line before Terminal closes.
    sleep 3
    exit 0
else
    echo
    echo "  [!] Start failed with code $EXITCODE."
    echo "      Open MAC-HOMELAB-MANAGER.COMMAND for diagnostics, stop/list,"
    echo "      and the first-run wizard."
    echo
    read -rp "  Press Enter to close..."
    exit $EXITCODE
fi
