#!/usr/bin/env bash
# join_env.sh – Update tenant-stack .env with values from a join-info file.
#
# Usage:
#   ./scripts/join_env.sh <join-file> [--env <path-to-.env>]
#
# The join-file contains KEY=VALUE pairs (one per line).
# Lines starting with # and blank lines are ignored.
# Each key is upserted into the .env file:
#   – If the key already exists (commented-out or not) it is replaced.
#   – If it is absent it is appended at the end.
#
# Example join-file (acme.env):
#   TENANT_ID=acme-devices
#   TENANT_DISPLAY_NAME=ACME Devices Fürth
#   PROVIDER_URL=https://example.com/api
#   JOIN_KEY=137K-TRF7-SWG0-IUGM

set -euo pipefail

# ── Argument parsing ──────────────────────────────────────────────────────────
JOIN_FILE=""
ENV_FILE="$(dirname "$0")/../.env"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --env)
            ENV_FILE="$2"
            shift 2
            ;;
        -*)
            echo "Unknown option: $1" >&2
            echo "Usage: $0 <join-file> [--env <path>]" >&2
            exit 1
            ;;
        *)
            if [[ -z "$JOIN_FILE" ]]; then
                JOIN_FILE="$1"
            else
                echo "Unexpected argument: $1" >&2
                exit 1
            fi
            shift
            ;;
    esac
done

if [[ -z "$JOIN_FILE" ]]; then
    echo "Error: no join-file specified." >&2
    echo "Usage: $0 <join-file> [--env <path>]" >&2
    exit 1
fi

if [[ ! -f "$JOIN_FILE" ]]; then
    echo "Error: join-file not found: $JOIN_FILE" >&2
    exit 1
fi

if [[ ! -f "$ENV_FILE" ]]; then
    EXAMPLE_FILE="${ENV_FILE%.env}.env.example"
    # Also check sibling .env.example when ENV_FILE is named just ".env"
    [[ -f "$EXAMPLE_FILE" ]] || EXAMPLE_FILE="$(dirname "$ENV_FILE")/.env.example"
    if [[ -f "$EXAMPLE_FILE" ]]; then
        cp "$EXAMPLE_FILE" "$ENV_FILE"
        echo ">>> $(basename "$ENV_FILE") not found – created from $(basename "$EXAMPLE_FILE")."
    else
        echo "Error: .env file not found and no .env.example available at: $(dirname "$ENV_FILE")" >&2
        exit 1
    fi
fi

# ── Helper: upsert one KEY=VALUE into .env ────────────────────────────────────
upsert_env() {
    local key="$1"
    local value="$2"
    local env="$3"

    if grep -qE "^#?[[:space:]]*${key}[[:space:]]*=" "$env" 2>/dev/null; then
        # Key found: replace the FIRST matching line (commented or not) and
        # silently drop any further occurrences to prevent duplicates.
        awk -v key="$key" -v val="$value" '
            BEGIN { done = 0 }
            $0 ~ ("^#?[[:space:]]*" key "[[:space:]]*=") {
                if (!done) { print key "=" val; done = 1 }
                next
            }
            { print }
        ' "$env" > "${env}.tmp" && mv "${env}.tmp" "$env"
        printf "  Updated : %s=%s\n" "$key" "$value"
    else
        # Key absent: append at end of file.
        [[ -z "$(tail -c1 "$env")" ]] || printf '\n' >> "$env"
        printf '%s=%s\n' "$key" "$value" >> "$env"
        printf "  Added   : %s=%s\n" "$key" "$value"
    fi
}

# ── Process join-file ─────────────────────────────────────────────────────────
echo ">>> Applying $(basename "$JOIN_FILE") → $(basename "$ENV_FILE") ..."

while IFS= read -r line || [[ -n "$line" ]]; do
    # Skip blank lines and comments
    [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue

    # Must be KEY=VALUE
    if [[ "$line" =~ ^([A-Za-z_][A-Za-z0-9_]*)=(.*)$ ]]; then
        key="${BASH_REMATCH[1]}"
        val="${BASH_REMATCH[2]}"
        # Strip optional inline comment (everything after  #  preceded by whitespace)
        val=$(printf '%s' "$val" | sed 's/[[:space:]]*#.*$//')
        # Strip surrounding whitespace
        val=$(printf '%s' "$val" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        upsert_env "$key" "$val" "$ENV_FILE"
    else
        echo "  Skipped (not KEY=VALUE): $line"
    fi
done < "$JOIN_FILE"

echo ">>> .env updated."
