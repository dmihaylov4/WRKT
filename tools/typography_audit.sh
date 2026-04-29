#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-.}"
TARGET_DIRS=(App Core DesignSystem Features Shared)
INCLUDE_GLOB='*.swift'

cd "$ROOT"

echo "Typography audit"
echo

printf 'DS helpers (.dsFont): '
{ rg -g"$INCLUDE_GLOB" -o '\.dsFont\(' "${TARGET_DIRS[@]}" || true; } | wc -l

printf 'DS typography direct calls: '
{ rg -g"$INCLUDE_GLOB" -o 'DS\.Typography' "${TARGET_DIRS[@]}" || true; } | wc -l

printf 'Raw SwiftUI text-style fonts: '
{ rg -g"$INCLUDE_GLOB" -o '^[[:space:]]*\.font\(\.(largeTitle|title|title2|title3|headline|subheadline|body|callout|footnote|caption|caption2)' "${TARGET_DIRS[@]}" || true; } | wc -l

printf 'Raw system/custom font calls: '
{ rg -g"$INCLUDE_GLOB" -o '^[[:space:]]*\.font\(\.system\(|^[[:space:]]*\.font\(\.custom\(|UIFont\.systemFont|UIFont\(name:' "${TARGET_DIRS[@]}" || true; } | wc -l

echo
echo "Top files still using raw SwiftUI text-style fonts:"
{ rg -g"$INCLUDE_GLOB" -l '^[[:space:]]*\.font\(\.(largeTitle|title|title2|title3|headline|subheadline|body|callout|footnote|caption|caption2)' "${TARGET_DIRS[@]}" || true; } \
    | while read -r file; do
        [ -n "$file" ] || continue
        count=$(rg -g"$INCLUDE_GLOB" -o '^[[:space:]]*\.font\(\.(largeTitle|title|title2|title3|headline|subheadline|body|callout|footnote|caption|caption2)' "$file" | wc -l | tr -d ' ')
        printf '%5s %s\n' "$count" "$file"
    done \
    | sort -rn \
    | head -20
