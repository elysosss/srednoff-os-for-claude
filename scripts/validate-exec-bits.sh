#!/usr/bin/env bash
# Verifies every tracked *.sh file is recorded in git as mode 100755 (Linux/macOS port of
# validate-exec-bits.ps1).
#
# Reads the mode git recorded, via `git ls-files -s` - deliberately not the mode on disk.
# `core.filemode=false` is the Git-for-Windows default, so a chmod in the working copy is
# never recorded there, and the file ships mode 100644 to every clone. A dozen scripts in
# this repo document the direct `./script.sh` form in their own usage headers, and that
# form fails outright without the bit; `bash script.sh` works either way, which is why the
# problem stays invisible until someone follows the documented invocation.
#
# Fix a failure with:  git update-index --chmod=+x <path>
#
# Usage:
#   ./validate-exec-bits.sh [path-to-repo] [--json]
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

if ! git -C "$repo_root" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "not a git work tree: $repo_root" >&2
  exit 1
fi

bad_paths=()
bad_modes=()

# `git ls-files -s` prints "<mode> <object> <stage>\t<path>", so the mode is everything
# before the first space and the path is everything after the tab - parsed with shell
# expansions rather than awk/cut so a path containing spaces still comes through whole.
while IFS= read -r entry; do
  [ -n "$entry" ] || continue
  entry_mode="${entry%% *}"
  entry_path="${entry#*$'\t'}"
  [ "$entry_mode" = "100755" ] && continue
  bad_paths+=("$entry_path")
  bad_modes+=("$entry_mode")
done < <(git -C "$repo_root" ls-files -s -- '*.sh')

failed="${#bad_paths[@]}"

if [ "$json" -eq 1 ]; then
  printf '{"failed":%d,"files":[' "$failed"
  i=0
  while [ "$i" -lt "$failed" ]; do
    [ "$i" -eq 0 ] || printf ','
    printf '{"path":"%s","mode":"%s"}' "${bad_paths[$i]}" "${bad_modes[$i]}"
    i=$((i + 1))
  done
  printf ']}\n'
else
  if [ "$failed" -eq 0 ]; then
    echo "exec-bit check: ok - every tracked *.sh file is mode 100755"
  else
    echo "exec-bit check: FAILED - $failed tracked *.sh file(s) are not mode 100755"
    i=0
    while [ "$i" -lt "$failed" ]; do
      echo "  ${bad_paths[$i]} (mode ${bad_modes[$i]})"
      i=$((i + 1))
    done
    echo "fix with: git update-index --chmod=+x <path>"
  fi
fi

[ "$failed" -eq 0 ] || exit 1
exit 0
