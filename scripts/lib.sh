#!/bin/bash
# Shared library for home security stack scripts.
# Source this file; do not execute it directly.
#
# Usage:
#   SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
#   source "${SCRIPT_DIR}/lib.sh"

set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# --- Colors ---
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m'

# --- Logging ---
log_info()  { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_step()  { echo -e "${BLUE}[STEP]${NC} $1"; }

# --- Test result tracking ---
_TEST_PASSED=0
_TEST_FAILED=0
_TEST_WARNED=0

test_pass() {
    echo -e "${GREEN}[PASS]${NC} $1"
    _TEST_PASSED=$((_TEST_PASSED + 1))
}

test_fail() {
    echo -e "${RED}[FAIL]${NC} $1"
    _TEST_FAILED=$((_TEST_FAILED + 1))
}

test_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
    _TEST_WARNED=$((_TEST_WARNED + 1))
}

test_summary() {
    local label="${1:-Results}"
    echo ""
    echo "======================================"
    echo "$label"
    echo "======================================"
    echo "Passed: $_TEST_PASSED"
    [[ $_TEST_WARNED -gt 0 ]] && echo "Warned: $_TEST_WARNED"
    echo "Failed: $_TEST_FAILED"
    echo ""

    if [[ $_TEST_FAILED -eq 0 ]]; then
        echo -e "${GREEN}All tests passed!${NC}"
        [[ $_TEST_WARNED -gt 0 ]] && echo -e "${YELLOW}Some warnings noted above.${NC}"
        return 0
    else
        echo -e "${RED}Some tests failed.${NC}"
        return 1
    fi
}

# --- Environment ---
# Loads .env from project root. Dies if .env is missing or a required var is unset/placeholder.
load_env() {
    local env_file="${PROJECT_DIR}/.env"
    if [[ ! -f "$env_file" ]]; then
        log_error ".env not found. Copy .env.example to .env and fill in values."
        exit 1
    fi
    # shellcheck disable=SC1090
    source "$env_file"
}

require_env() {
    local missing=0
    for var in "$@"; do
        local val="${!var:-}"
        if [[ -z "$val" || "$val" == *"x.x"* || "$val" == *"password_here"* || "$val" == *"changeme"* ]]; then
            log_error "Missing or placeholder value for: $var"
            missing=1
        fi
    done
    if [[ $missing -eq 1 ]]; then
        exit 1
    fi
}

# --- Prerequisites ---
# Checks that a list of commands are available on PATH.
require_commands() {
    local missing=""
    for cmd in "$@"; do
        if ! command -v "$cmd" &>/dev/null; then
            missing="$missing $cmd"
        fi
    done
    if [[ -n "$missing" ]]; then
        log_error "Missing required commands:$missing"
        return 1
    fi
}
