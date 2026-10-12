#!/usr/bin/env bash
# os-module - install, enable, switch and remove OS modules in a PROJECT (never in ~/.claude).
# Linux/macOS/Git-Bash port of os-module.ps1; same behaviour, same exit codes.
# Spec: docs/specs/E1-module-format.md. Requires: jq.
#
# Usage:
#   os-module.sh new <id>
#   os-module.sh validate <id>
#   os-module.sh list    [--project P]
#   os-module.sh install <id> [--project P]
#   os-module.sh enable  <id> [--project P] [--shared]
#   os-module.sh mode    <id> <mode> [--project P]
#   os-module.sh disable <id> [--project P]
#   os-module.sh uninstall <id> [--project P] [--purge]
#   os-module.sh status  [<id>] [--project P]
#
# Exit codes: 0 ok | 1 other | 2 compatibility refusal or rewrites conflict | 3 settings file
# does not parse (nothing was changed).
set -uo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
os_root="$(cd "$script_dir/.." && pwd)"
modules_dir="${SREDNOFF_OS_MODULES_DIR:-$os_root/modules}"

die() { echo "os-module: $1" >&2; exit "${2:-1}"; }
command -v jq >/dev/null 2>&1 || die "jq is required" 1

cmd="${1:-}"; [ "$#" -gt 0 ] && shift
project="."; shared=0; purge=0
pos=()
while [ "$#" -gt 0 ]; do
  case "$1" in
    --project) [ "$#" -ge 2 ] || die "--project needs a path"; project="$2"; shift ;;
    --shared) shared=1 ;;
    --purge) purge=1 ;;
    *) pos+=("$1") ;;
  esac
  shift
done
arg1="${pos[0]:-}"; arg2="${pos[1]:-}"

is_windows=0
case "$(uname -s 2>/dev/null)" in MINGW*|MSYS*|CYGWIN*) is_windows=1 ;; esac

now() { date -u +%Y-%m-%dT%H:%M:%SZ; }

# Absolute path in the form the hook runner can use (C:/... under Git Bash).
native_path() {
  if [ "$is_windows" -eq 1 ] && command -v cygpath >/dev/null 2>&1; then cygpath -m "$1"; else printf '%s' "$1"; fi
}

check_id() {
  printf '%s' "$1" | grep -Eq '^[a-z][a-z0-9-]{0,30}$' || die "invalid module id '$1' (lowercase letters, digits, hyphen; 1-31 chars)" 1
}

# ---- project paths ----------------------------------------------------------------------
resolve_project() {
  [ -d "$project" ] || die "project directory not found: $project" 1
  project="$(cd "$project" && pwd)"
  local home_resolved
  home_resolved="$(cd "$HOME" && pwd)"
  [ "$project" = "$home_resolved" ] && die "refusing to use \$HOME ($home_resolved) as a project: modules are installed per project, never into ~/.claude" 1
  claude_dir="$project/.claude"
  om="$claude_dir/os-modules"
  inst="$om/installed.json"
  settings_rel=".claude/settings.local.json"
  [ "$shared" -eq 1 ] && settings_rel=".claude/settings.json"
  settings="$project/$settings_rel"
}

inst_read() {
  if [ -f "$inst" ]; then cat "$inst"
  else jq -nc --arg r "$(native_path "$os_root")" '{schema:1, osRoot:$r, modules:{}, settings:{}}'
  fi
}
inst_write() { # stdin -> installed.json (atomic)
  mkdir -p "$om"; local tmp; tmp="$(mktemp "$om/.inst.XXXXXX")" || die "cannot write $om" 1
  jq '.' > "$tmp" && mv "$tmp" "$inst" || { rm -f "$tmp"; die "cannot write installed.json" 1; }
}
inst_has() { [ -f "$inst" ] && jq -e --arg id "$1" '.modules[$id] != null' "$inst" >/dev/null 2>&1; }
inst_get() { jq -r --arg id "$1" ".modules[\$id] | ($2)" "$inst"; }   # $2 is a jq filter applied to .modules[id]

# ---- manifest ---------------------------------------------------------------------------
manifest_of() { printf '%s/.claude-plugin/plugin.json' "$1"; }

validate_dir() { # $1 = module dir; prints problems, returns 1 if any
  local d="$1" m errs="" f
  m="$(manifest_of "$d")"
  [ -f "$m" ] || { echo "missing .claude-plugin/plugin.json"; return 1; }
  jq -e . "$m" >/dev/null 2>&1 || { echo ".claude-plugin/plugin.json is not valid JSON"; return 1; }
  local id; id="$(jq -r '.metadata.srednoffOs.id // empty' "$m")"
  [ -n "$id" ] || errs="${errs}metadata.srednoffOs.id missing\n"
  jq -e '.name | type == "string" and length > 0' "$m" >/dev/null 2>&1 || errs="${errs}name missing\n"
  jq -e '.metadata.srednoffOs.schema == 1' "$m" >/dev/null 2>&1 || errs="${errs}metadata.srednoffOs.schema must be 1\n"
  jq -e '.metadata.srednoffOs | (.modes | type == "array" and index("off") != null) and (.defaultMode as $dm | .modes | index($dm) != null)' "$m" >/dev/null 2>&1 \
    || errs="${errs}modes must include \"off\" and defaultMode\n"
  jq -e '.metadata.srednoffOs.platforms | type == "array" and length > 0' "$m" >/dev/null 2>&1 || errs="${errs}platforms missing\n"
  jq -e '.metadata.srednoffOs.rewrites | type == "object"' "$m" >/dev/null 2>&1 || errs="${errs}rewrites must be an object\n"
  for f in $(jq -r '.metadata.srednoffOs | [.config.default, .doctor, .hooksSource.default] | .[] | select(. != null)' "$m" | tr -d '\r'); do
    [ -f "$d/$f" ] || errs="${errs}declared file missing: $f\n"
  done
  if [ "$(basename "$d")" != "_template" ] && [ -n "$id" ] && [ "$(basename "$d")" != "$id" ]; then
    errs="${errs}directory name '$(basename "$d")' differs from id '$id'\n"
  fi
  if [ -n "$errs" ]; then printf '%b' "$errs"; return 1; fi
  return 0
}

# ---- settings helpers ---------------------------------------------------------------------
settings_must_parse() { # exit 3 when the file exists and is not an object
  [ -f "$settings" ] || return 0
  jq -e 'type == "object"' "$settings" >/dev/null 2>&1 || die "$settings_rel does not parse as a JSON object; nothing was changed" 3
}
write_settings() { # stdin -> settings (atomic)
  mkdir -p "$(dirname "$settings")"
  local tmp; tmp="$(mktemp "$(dirname "$settings")/.set.XXXXXX")" || die "cannot write settings" 1
  jq --indent 2 '.' > "$tmp" && mv "$tmp" "$settings" || { rm -f "$tmp"; die "cannot write $settings_rel" 1; }
}

# ---- components (skills/commands/agents) -------------------------------------------------------
components_remove() { # $1 = id ; removes what installed.json lists, then clears the lists
  local id="$1" p
  while IFS= read -r p; do
    [ -n "$p" ] || continue
    case "$p" in
      .claude/skills/"$id"--*|.claude/agents/"$id"--*) rm -rf "${project:?}/$p" ;;
      .claude/commands/*) rm -f "${project:?}/$p" ;;
    esac
  done < <(inst_get "$id" '(.skills + .commands + .agents)[]' | tr -d '\r')
  inst_read | jq --arg id "$id" '.modules[$id] |= (.skills = [] | .commands = [] | .agents = [])' | inst_write
  rmdir "$project/.claude/skills" "$project/.claude/commands" "$project/.claude/agents" 2>/dev/null
  return 0
}
components_install() { # $1 = id
  local id="$1" mdir="$om/$1" name f skills=() commands=() agents=() dest
  if [ -d "$mdir/skills" ]; then
    for f in "$mdir/skills"/*/; do
      [ -d "$f" ] || continue
      name="$(basename "$f")"; dest=".claude/skills/$id--$name"
      rm -rf "${project:?}/$dest"; mkdir -p "$project/.claude/skills"; cp -R "${f%/}" "$project/$dest"
      skills+=("$dest")
    done
  fi
  if [ -d "$mdir/commands" ]; then
    for f in "$mdir/commands"/*.md; do
      [ -f "$f" ] || continue
      name="$(basename "$f")"; dest=".claude/commands/$name"
      if [ -e "$project/$dest" ] && ! cmp -s "$f" "$project/$dest"; then
        echo "os-module: command $name already exists in the project and differs; not overwritten" >&2; continue
      fi
      mkdir -p "$project/.claude/commands"; cp "$f" "$project/$dest"; commands+=("$dest")
    done
  fi
  if [ -d "$mdir/agents" ]; then
    for f in "$mdir/agents"/*.md; do
      [ -f "$f" ] || continue
      name="$(basename "$f")"; dest=".claude/agents/$id--$name"
      mkdir -p "$project/.claude/agents"; cp "$f" "$project/$dest"; agents+=("$dest")
    done
  fi
  inst_read | jq --arg id "$id" \
    --argjson s "$(printf '%s\n' ${skills[@]+"${skills[@]}"} | jq -R . | jq -sc 'map(select(length>0))')" \
    --argjson c "$(printf '%s\n' ${commands[@]+"${commands[@]}"} | jq -R . | jq -sc 'map(select(length>0))')" \
    --argjson a "$(printf '%s\n' ${agents[@]+"${agents[@]}"} | jq -R . | jq -sc 'map(select(length>0))')" \
    '.modules[$id] |= (.skills = $s | .commands = $c | .agents = $a)' | inst_write
}
components_sync() { # $1 = id ; present iff enabled and mode != off
  local id="$1" mode enabled
  enabled="$(inst_get "$id" '.enabled')"
  mode="$(jq -r '.mode // "off"' "$om/$id/state.json" 2>/dev/null || echo off)"
  components_remove "$id"
  if [ "$enabled" = "true" ] && [ "$mode" != "off" ]; then components_install "$id"; fi
}

# ---- gitignore for .state -------------------------------------------------------------------
GI_LINE=".claude/os-modules/.state/"
gitignore_ensure() {
  local gi="$project/.gitignore" existed=0 added=0
  [ -f "$gi" ] && existed=1
  if [ "$existed" -eq 0 ] || ! grep -qxF "$GI_LINE" "$gi" 2>/dev/null; then
    [ "$existed" -eq 1 ] && [ -n "$(tail -c1 "$gi" 2>/dev/null)" ] && printf '\n' >> "$gi"
    printf '%s\n' "$GI_LINE" >> "$gi"; added=1
  fi
  if command -v git >/dev/null 2>&1 && git -C "$project" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    git -C "$project" check-ignore -q "$om/.state/x" 2>/dev/null       || die "git does not ignore $GI_LINE (check .gitignore); refusing to continue" 1
  fi
  if ! jq -e '.gitignore != null' "$inst" >/dev/null 2>&1; then
    inst_read | jq --argjson e "$existed" --argjson a "$added" '.gitignore = {existed: ($e == 1), added: ($a == 1)}' | inst_write
  fi
}
gitignore_cleanup() { # last module gone
  local gi="$project/.gitignore"
  if [ "$(jq -r '.gitignore.added // false' "$inst" 2>/dev/null)" = "true" ] && [ -f "$gi" ]; then
    grep -vxF "$GI_LINE" "$gi" > "$gi.tmp" 2>/dev/null; mv "$gi.tmp" "$gi"
    if [ "$(jq -r 'if .gitignore.existed == false then "false" else "true" end' "$inst")" = "false" ] && [ ! -s "$gi" ]; then rm -f "$gi"; fi
  fi
}

# ---- compatibility --------------------------------------------------------------------------
os_version() { jq -r '.version // "v0"' "$os_root/registry/version.json" 2>/dev/null | sed 's/^v//'; }
ver_ge() { # $1 >= $2 on dotted numbers
  local a="$1" b="$2" i x y
  for i in 1 2 3; do
    x="$(printf '%s' "$a" | cut -d. -f$i)"; y="$(printf '%s' "$b" | cut -d. -f$i)"
    x="${x:-0}"; y="${y:-0}"
    [ "$x" -gt "$y" ] && return 0; [ "$x" -lt "$y" ] && return 1
  done
  return 0
}
check_compat() { # $1 = manifest
  local m="$1" need plat have
  need="$(jq -r '.metadata.srednoffOs.osCompat // empty' "$m" | sed 's/^>=//')"
  if [ -n "$need" ] && ! ver_ge "$(os_version)" "$need"; then die "module needs OS >= $need, this checkout is $(os_version)" 2; fi
  plat="linux"
  case "$(uname -s 2>/dev/null)" in Darwin) plat="macos" ;; MINGW*|MSYS*|CYGWIN*) plat="windows" ;; esac
  jq -e --arg p "$plat" '.metadata.srednoffOs.platforms | index($p) != null' "$m" >/dev/null 2>&1 \
    || die "module does not support platform '$plat'" 2
  for have in $(jq -r '.metadata.srednoffOs.requires.bins[]?' "$m" | tr -d '\r'); do
    command -v "$have" >/dev/null 2>&1 || die "required executable not found in PATH: $have" 2
  done
  for have in $(jq -r '.metadata.srednoffOs.requires.modules[]?' "$m" | tr -d '\r'); do
    inst_has "$have" || die "required module not installed in this project: $have" 2
  done
}

# ---- commands ---------------------------------------------------------------------------------
cmd_new() {
  check_id "$arg1"
  [ -d "$modules_dir/_template" ] || die "template not found: $modules_dir/_template" 1
  [ -e "$modules_dir/$arg1" ] && die "module already exists: modules/$arg1" 1
  cp -R "$modules_dir/_template" "$modules_dir/$arg1"
  local f
  while IFS= read -r f; do
    sed "s/__ID__/$arg1/g" "$f" > "$f.tmp" && mv "$f.tmp" "$f"
  done < <(grep -rIl '__ID__' "$modules_dir/$arg1" 2>/dev/null)
  echo "created modules/$arg1"
}

cmd_validate() {
  check_id "$arg1"
  local out; out="$(validate_dir "$modules_dir/$arg1")" && { echo "ok: $arg1"; return 0; }
  printf '%s\n' "$out" >&2; exit 1
}

cmd_list() {
  resolve_project
  local d id st
  for d in "$modules_dir"/*/; do
    [ -d "$d" ] || continue; id="$(basename "$d")"; [ "$id" = "_template" ] && continue
    st="not installed"
    if inst_has "$id"; then
      st="installed, $( [ "$(inst_get "$id" '.enabled')" = "true" ] && echo enabled || echo disabled ), mode $(jq -r '.mode // "off"' "$om/$id/state.json" 2>/dev/null)"
    fi
    echo "$id  $st"
  done
}

cmd_install() {
  check_id "$arg1"; resolve_project
  local src="$modules_dir/$arg1" m
  [ -d "$src" ] || die "module not found: modules/$arg1" 1
  validate_dir "$src" >/dev/null || { validate_dir "$src" >&2; die "module manifest is invalid" 1; }
  m="$(manifest_of "$src")"; check_compat "$m"
  local ver prev_mode="" prev_cfg=""
  ver="$(jq -r '.version // "0.0.0"' "$m")"
  mkdir -p "$om"
  gitignore_ensure
  local dest="$om/$arg1"
  if [ -d "$dest" ]; then   # update in place: keep state.json and user config
    [ -f "$dest/state.json" ] && prev_mode="$(cat "$dest/state.json")"
    [ -f "$dest/config/user.json" ] && prev_cfg="$(cat "$dest/config/user.json")"
    rm -rf "$dest"
  fi
  mkdir -p "$dest"
  cp -R "$src/." "$dest/"
  rm -rf "${dest:?}/tests" "${dest:?}/src" "${dest:?}/ci"
  find "$dest" -name .gitkeep -type f -delete
  if [ -n "$prev_mode" ]; then printf '%s\n' "$prev_mode" > "$dest/state.json"
  else jq -n --arg m "$(jq -r '.metadata.srednoffOs.defaultMode' "$m")" --arg t "$(now)" '{schema:1, mode:$m, changedAt:$t, changedBy:"os-module"}' > "$dest/state.json"; fi
  [ -n "$prev_cfg" ] && { mkdir -p "$dest/config"; printf '%s\n' "$prev_cfg" > "$dest/config/user.json"; }
  inst_read | jq --arg id "$arg1" --arg v "$ver" --arg t "$(now)" \
    '.modules[$id] = ((.modules[$id] // {}) + {version:$v, installedAt:$t, enabled:(.modules[$id].enabled // false), settingsFile:(.modules[$id].settingsFile // null), hooks:(.modules[$id].hooks // []), skills:(.modules[$id].skills // []), commands:(.modules[$id].commands // []), agents:(.modules[$id].agents // [])})' | inst_write
  [ "$(inst_get "$arg1" '.enabled')" = "true" ] && components_sync "$arg1"
  echo "installed $arg1 $ver into $project/.claude/os-modules/$arg1 (hooks not wired; run enable)"
}

# Two rewrites declarations overlap when they name the same key and a tool of one matches a tool of the other.
conflicts_with() { # $1 = new manifest, $2 = other manifest ; prints "key tool" per conflict
  jq -rn --slurpfile a "$1" --slurpfile b "$2" '
    ($a[0].metadata.srednoffOs.rewrites // {}) as $ra | ($b[0].metadata.srednoffOs.rewrites // {}) as $rb
    | $ra | to_entries[] | .key as $k | .value[] as $x
    | ($rb[$k] // [])[] as $y
    | select($x == $y or ($y | test("^(" + $x + ")$")) or ($x | test("^(" + $y + ")$")))
    | "\($k) \($x)"' 2>/dev/null | tr -d '\r'
}

cmd_enable() {
  check_id "$arg1"; resolve_project
  inst_has "$arg1" || die "module not installed in this project: $arg1 (run install first)" 1
  local mdir="$om/$arg1" m other hits
  m="$(manifest_of "$mdir")"
  if [ "$(inst_get "$arg1" '.enabled')" = "true" ]; then echo "$arg1 is already enabled"; return 0; fi
  # 1. rewrites conflict with any other enabled module
  for other in $(jq -r --arg id "$arg1" '.modules | to_entries[] | select(.key != $id and .value.enabled == true) | .key' "$inst" | tr -d '\r'); do
    hits="$(conflicts_with "$m" "$(manifest_of "$om/$other")")"
    if [ -n "$hits" ]; then
      printf 'os-module: module %s rewrites the same tool I/O as enabled module %s:\n%s\n' "$arg1" "$other" "$hits" >&2
      exit 2
    fi
  done
  # 2. settings must parse
  settings_must_parse
  # 3. remember the original file once per settings file
  local rec_key="$settings_rel" orig_dir="$om/.state/settings-orig" existed=0
  if ! jq -e --arg k "$rec_key" '.settings[$k] != null' "$inst" >/dev/null 2>&1; then
    mkdir -p "$orig_dir"
    if [ -f "$settings" ]; then existed=1; cp "$settings" "$orig_dir/$(basename "$settings").orig"; fi
    inst_read | jq --arg k "$rec_key" --argjson e "$existed" '.settings[$k] = {existed: ($e == 1)}' | inst_write
  fi
  # 4. build hook entries from the module template
  local src_rel hooks_file md_native
  if [ "$is_windows" -eq 1 ]; then src_rel="$(jq -r '.metadata.srednoffOs.hooksSource.windows // .metadata.srednoffOs.hooksSource.default // empty' "$m")"
  else src_rel="$(jq -r '.metadata.srednoffOs.hooksSource.default // empty' "$m")"; fi
  md_native="$(native_path "$mdir")"
  local new_entries='[]'
  if [ -n "$src_rel" ] && [ -f "$mdir/$src_rel" ]; then
    new_entries="$(jq -c --arg md "$md_native" '
      (.hooks // .) | to_entries | map(select(.value | type == "array"))
      | map(.key as $e | .value[] | {event: $e, entry: .})
      | walk(if type == "string" then gsub("\\{\\{MODULE_DIR\\}\\}"; $md) else . end)' "$mdir/$src_rel" | tr -d '\r')" || die "hooks template does not parse: $src_rel" 1
  fi
  # 5. merge into settings (identical entries already present are not duplicated and not recorded)
  local base='{}'
  [ -f "$settings" ] && base="$(cat "$settings")"
  local merged recorded
  merged="$(printf '%s' "$base" | jq --argjson n "$new_entries" '
    reduce $n[] as $h (.; if ((.hooks[$h.event] // []) | index($h.entry)) != null then . else .hooks[$h.event] = ((.hooks[$h.event] // []) + [$h.entry]) end)')" || die "merge failed" 1
  recorded="$(jq -nc --argjson n "$new_entries" --argjson b "$base" '[ $n[] | . as $h | select((($b.hooks[$h.event] // []) | index($h.entry)) == null) ]')"
  if [ "$new_entries" != "[]" ]; then printf '%s' "$merged" | write_settings; fi
  inst_read | jq --arg id "$arg1" --arg sf "$settings_rel" --argjson r "$recorded" \
    '.modules[$id] |= (.enabled = true | .settingsFile = $sf | .hooks = $r)' | inst_write
  components_sync "$arg1"
  echo "enabled $arg1 (mode $(jq -r '.mode' "$mdir/state.json")), hooks merged into $settings_rel: $(printf '%s' "$recorded" | jq 'length')"
}

cmd_mode() {
  check_id "$arg1"; resolve_project
  inst_has "$arg1" || die "module not installed in this project: $arg1" 1
  local mdir="$om/$arg1" newmode="$arg2"
  [ -n "$newmode" ] || die "usage: mode <id> <mode>" 1
  jq -e --arg m "$newmode" '.metadata.srednoffOs.modes | index($m) != null' "$(manifest_of "$mdir")" >/dev/null 2>&1 \
    || die "unknown mode '$newmode'; this module declares: $(jq -r '.metadata.srednoffOs.modes | join(", ")' "$(manifest_of "$mdir")")" 1
  jq -n --arg m "$newmode" --arg t "$(now)" '{schema:1, mode:$m, changedAt:$t, changedBy:"os-module"}' > "$mdir/state.json"
  components_sync "$arg1"
  echo "$arg1 mode = $newmode"
}

cmd_disable() {
  check_id "$arg1"; resolve_project
  inst_has "$arg1" || die "module not installed in this project: $arg1" 1
  local sf; sf="$(inst_get "$arg1" '.settingsFile // empty')"
  if [ -n "$sf" ]; then
    settings_rel="$sf"; settings="$project/$sf"
    settings_must_parse
    if [ -f "$settings" ]; then
      local cur; cur="$(jq --argjson h "$(inst_get "$arg1" '.hooks' | jq -c .)" '
        def rm1($e): (map(. == $e) | index(true)) as $i | if $i == null then . else del(.[$i]) end;
        reduce $h[] as $x (.; if .hooks[$x.event] then .hooks[$x.event] |= rm1($x.entry) else . end)
        | if .hooks then .hooks |= with_entries(select(.value | length > 0)) else . end
        | if (.hooks // null) == {} then del(.hooks) else . end' "$settings")" || die "cannot edit $settings_rel" 1
      printf '%s' "$cur" | write_settings
    fi
    # last user of this settings file: restore it as it was before the first module
    local others; others="$(jq --arg id "$arg1" --arg sf "$sf" '[.modules | to_entries[] | select(.key != $id and .value.settingsFile == $sf and (.value.hooks | length) > 0)] | length' "$inst")"
    if [ "$others" = "0" ]; then
      local orig existed
      orig="$om/.state/settings-orig/$(basename "$settings").orig"
      existed="$(jq -r --arg k "$sf" 'if .settings[$k].existed == false then "false" else "true" end' "$inst")"
      if [ "$existed" = "true" ] && [ -f "$orig" ] && [ -f "$settings" ]; then
        if [ "$(jq -S -c . "$settings")" = "$(jq -S -c . "$orig")" ]; then cp "$orig" "$settings"; fi
      elif [ "$existed" = "false" ] && [ -f "$settings" ] && [ "$(jq -c . "$settings")" = "{}" ]; then
        rm -f "$settings"
      fi
      rm -f "$orig"
      inst_read | jq --arg k "$sf" 'del(.settings[$k])' | inst_write
    fi
  fi
  inst_read | jq --arg id "$arg1" '.modules[$id] |= (.enabled = false | .hooks = [] | .settingsFile = null)' | inst_write
  components_sync "$arg1"
  echo "disabled $arg1"
}

cmd_uninstall() {
  check_id "$arg1"; resolve_project
  inst_has "$arg1" || die "module not installed in this project: $arg1" 1
  [ "$(inst_get "$arg1" '.enabled')" = "true" ] && cmd_disable >/dev/null
  components_remove "$arg1"
  local state_dir; state_dir="$(jq -r '.metadata.srednoffOs.stateDir // empty' "$(manifest_of "$om/$arg1")" 2>/dev/null)"
  rm -rf "${om:?}/$arg1"
  inst_read | jq --arg id "$arg1" 'del(.modules[$id])' | inst_write
  if [ "$purge" -eq 1 ]; then
    rm -rf "$om/.state/$arg1"
    state_dir="${state_dir/#\~/$HOME}"
    case "$state_dir" in */.claude/logs/os-modules/"$arg1") rm -rf "$state_dir" ;; esac
  fi
  if [ "$(jq '.modules | length' "$inst")" = "0" ]; then
    gitignore_cleanup
    rm -f "$inst"; rm -rf "$om/.state/settings-orig"
    rmdir "$om/.state" 2>/dev/null; rmdir "$om" 2>/dev/null; rmdir "$claude_dir" 2>/dev/null
  fi
  echo "uninstalled $arg1"
}

cmd_status() {
  resolve_project
  [ -f "$inst" ] || { echo "no modules installed in $project"; return 0; }
  local id
  for id in $( [ -n "$arg1" ] && echo "$arg1" || jq -r '.modules | keys[]' "$inst" | tr -d '\r'); do
    inst_has "$id" || { echo "$id  not installed"; continue; }
    echo "$id  version $(inst_get "$id" '.version')  enabled $(inst_get "$id" '.enabled')  mode $(jq -r '.mode // "off"' "$om/$id/state.json" 2>/dev/null)  hooks $(inst_get "$id" '.hooks | length')  skills $(inst_get "$id" '.skills | length')  commands $(inst_get "$id" '.commands | length')  agents $(inst_get "$id" '.agents | length')"
  done
}

case "$cmd" in
  new) [ -n "$arg1" ] || die "usage: new <id>"; cmd_new ;;
  validate) [ -n "$arg1" ] || die "usage: validate <id>"; cmd_validate ;;
  list) cmd_list ;;
  install) [ -n "$arg1" ] || die "usage: install <id> [--project P]"; cmd_install ;;
  enable) [ -n "$arg1" ] || die "usage: enable <id> [--project P] [--shared]"; cmd_enable ;;
  mode) [ -n "$arg1" ] || die "usage: mode <id> <mode> [--project P]"; cmd_mode ;;
  disable) [ -n "$arg1" ] || die "usage: disable <id> [--project P]"; cmd_disable ;;
  uninstall) [ -n "$arg1" ] || die "usage: uninstall <id> [--project P] [--purge]"; cmd_uninstall ;;
  status) cmd_status ;;
  *) die "usage: os-module.sh new|validate|list|install|enable|mode|disable|uninstall|status ... (see docs/specs/E1-module-format.md)" 1 ;;
esac
