#!/usr/bin/env bash
# Verifies every *.ps1 in the repo is safe for Windows PowerShell 5.1 to parse (Linux/macOS
# port of validate-ps1-encoding.ps1). A file passes if it is pure ASCII, or if it starts
# with a UTF-8 BOM.
#
# Why this is a real gate and not style policing: PowerShell 5.1 decodes a BOM-less script
# using the system ANSI codepage, while pwsh 7 and Linux/macOS assume UTF-8. A literal
# em-dash (U+2014, bytes e2 80 94) inside a string in a BOM-less registry/gen-catalog-json.ps1
# therefore reached the 5.1 parser as three unrelated characters, broke the string literal
# it sat in, and cascaded into "Missing ')' in method call" plus six further parse errors -
# none of which pointed anywhere near the actual cause. The parse check already in CI caught
# the symptom; this check names the cause.
#
# Two ways to satisfy it:
#   1. Keep the file pure ASCII - build any non-ASCII character by code point, e.g.
#      " " + [char]0x2014 + " " rather than a literal em-dash. This is what the .ps1 files
#      in this repo do today.
#   2. Save the file as UTF-8 *with* a BOM - 5.1 honours the BOM and decodes correctly.
#      Use this when a script genuinely needs literal non-ASCII text, such as Russian
#      output strings.
#
# Usage:
#   ./validate-ps1-encoding.sh [path-to-repo] [--json]
set -uo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$script_dir/.."
json=0
for arg in "$@"; do
  case "$arg" in
    --json) json=1 ;;
    *) repo_root="$arg" ;;
  esac
done

if [ ! -d "$repo_root" ]; then
  echo "repo root not found: $repo_root" >&2
  exit 1
fi
# Canonicalise so the reported paths come out repo-relative rather than full of "..".
repo_root="$(cd "$repo_root" && pwd)"

# Byte-level detection with `tr` and POSIX octal ranges rather than a grep character class:
# grep's handling of high bytes and of \xNN escapes varies between GNU, BSD, busybox and
# ugrep, and this check is worthless if it silently matches nothing.
has_non_ascii() {
  [ -n "$(LC_ALL=C tr -d '\000-\177' < "$1")" ]
}

has_utf8_bom() {
  [ "$(LC_ALL=C od -An -tx1 -N3 < "$1" | tr -d ' \n')" = "efbbbf" ]
}

checked=0
bad_files=()
bad_lines=()

while IFS= read -r ps_file; do
  [ -n "$ps_file" ] || continue
  checked=$((checked + 1))
  has_utf8_bom "$ps_file" && continue
  has_non_ascii "$ps_file" || continue
  # Slow path only for files that already failed: walk the lines to report where.
  lineno=0
  hits=""
  while IFS= read -r file_line || [ -n "$file_line" ]; do
    lineno=$((lineno + 1))
    if [ -n "$(printf '%s' "$file_line" | LC_ALL=C tr -d '\000-\177')" ]; then
      if [ -z "$hits" ]; then hits="$lineno"; else hits="$hits,$lineno"; fi
    fi
  done < "$ps_file"
  bad_files+=("${ps_file#"$repo_root"/}")
  bad_lines+=("$hits")
done < <(find "$repo_root" -name '*.ps1' -not -path '*/.git/*' -type f | LC_ALL=C sort)

failed="${#bad_files[@]}"

if [ "$json" -eq 1 ]; then
  printf '{"checked":%d,"failed":%d,"files":[' "$checked" "$failed"
  i=0
  while [ "$i" -lt "$failed" ]; do
    [ "$i" -eq 0 ] || printf ','
    printf '{"path":"%s","lines":"%s"}' "${bad_files[$i]}" "${bad_lines[$i]}"
    i=$((i + 1))
  done
  printf ']}\n'
else
  if [ "$failed" -eq 0 ]; then
    echo "ps1 encoding check: ok - $checked file(s), all pure ASCII or UTF-8 with BOM"
  else
    echo "ps1 encoding check: FAILED - $failed of $checked file(s) hold non-ASCII bytes without a UTF-8 BOM"
    i=0
    while [ "$i" -lt "$failed" ]; do
      echo "  ${bad_files[$i]} (line(s): ${bad_lines[$i]})"
      i=$((i + 1))
    done
    echo "fix by replacing the character with a code-point construction ([char]0x2014), or by saving the file as UTF-8 with BOM"
  fi
fi

[ "$failed" -eq 0 ] || exit 1
exit 0
