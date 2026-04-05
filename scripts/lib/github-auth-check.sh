#!/usr/bin/env bash
set -euo pipefail

clawoss_expected_github_user() {
    if [ -n "${GITHUB_USERNAME:-}" ]; then
        printf '%s\n' "$GITHUB_USERNAME"
        return 0
    fi

    if [ -n "${GITHUB_TOKEN:-}" ]; then
        GH_TOKEN="$GITHUB_TOKEN" gh api user --jq .login 2>/dev/null || true
        return 0
    fi

    printf '\n'
}

clawoss_require_matching_github_token() {
    local expected actual

    if [ -z "${GITHUB_TOKEN:-}" ]; then
        echo "Error: GITHUB_TOKEN is required for autonomous PR creation."
        echo "Refusing to fall back to an arbitrary gh-authenticated account."
        return 1
    fi

    if ! actual="$(GH_TOKEN="$GITHUB_TOKEN" gh api user --jq .login 2>/dev/null)"; then
        echo "Error: GITHUB_TOKEN is set but failed GitHub API auth."
        return 1
    fi

    expected="$(clawoss_expected_github_user)"
    if [ "$actual" != "$expected" ]; then
        echo "Error: GITHUB_TOKEN belongs to '$actual', but GITHUB_USERNAME expects '$expected'."
        echo "Autonomous PR creation is blocked until the token matches the intended account."
        return 1
    fi
}
