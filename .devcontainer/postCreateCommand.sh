#!/usr/bin/env bash
# .devcontainer/postCreateCommand.sh
# Runs once after the dev container is created.
set -euo pipefail

# ── Colours ──────────────────────────────────────────────────────────────────
BOLD='\033[1m'
CYAN='\033[1;36m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RESET='\033[0m'

hr() { printf "${CYAN}%s${RESET}\n" "────────────────────────────────────────────────"; }
ok() { printf "  ${GREEN}✔${RESET}  %s\n" "$*"; }
info() { printf "  ${YELLOW}▸${RESET}  %s\n" "$*"; }

hr
printf "${BOLD}  CDM Platform – Dev Container Setup${RESET}\n"
hr

# ── 1. Git safe directory ─────────────────────────────────────────────────────
info "Configuring Git safe directory …"
git config --global --add safe.directory "${containerWorkspaceFolder:-/workspaces/complete-device-management}"
ok "Git safe directory set"

# ── 2. pre-commit hooks ───────────────────────────────────────────────────────
info "Installing pre-commit hooks …"
pre-commit install --install-hooks
ok "pre-commit hooks installed"

# ── 3. Environment summary ────────────────────────────────────────────────────
hr
printf "${BOLD}  Tool Versions${RESET}\n"
hr

_ver() {
    local label="$1"; shift
    local version
    version=$("$@" 2>/dev/null | head -1) || version="(not found)"
    printf "  %-22s %s\n" "${label}" "${version}"
}

_ver "Python"          python3 --version
_ver "pip"             pip3 --version
_ver "uv"              uv --version
_ver "ruff"            ruff --version
_ver "mypy"            mypy --version
_ver "pre-commit"      pre-commit --version
_ver "Node.js"         node --version
_ver "npm"             npm --version
_ver "Git"             git --version
_ver "GitHub CLI"      gh --version
_ver "Docker CLI"      docker --version
_ver "Docker Compose"  docker compose version

hr
printf "${BOLD}  Workspace:${RESET} %s\n" "${containerWorkspaceFolder:-/workspaces/complete-device-management}"
hr
echo ""
