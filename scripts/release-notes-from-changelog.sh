#!/usr/bin/env bash

set -euo pipefail

previous_ref="${1:-}"
current_ref="${2:?Usage: $0 [previous-ref] current-ref}"

if [[ -n "$previous_ref" ]]; then
    notes="$({
        git diff --no-ext-diff --unified=0 "$previous_ref" "$current_ref" -- CHANGELOG.md
    } | awk '
        /^\+\+\+ b\/CHANGELOG\.md$/ { in_changelog = 1; next }
        /^diff --git / { in_changelog = 0 }
        in_changelog && /^\+/ {
            sub(/^\+/, "")
            print
        }
    ')"
else
    notes="$(git show "$current_ref:CHANGELOG.md" | sed -n '/^## /,$p')"
fi

if [[ -z "${notes//[[:space:]]/}" ]]; then
    echo "No changelog entries were added between ${previous_ref:-the beginning of history} and ${current_ref}." >&2
    exit 1
fi

printf '%s\n' "$notes"
