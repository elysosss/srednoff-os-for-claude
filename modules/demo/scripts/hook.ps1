# Template PreToolUse hook. Replace the body after the mode check with the module's logic.
# Contract (docs/specs/E1-module-format.md): first action is reading the mode; off, a missing
# or a broken state file -> exit 0 with empty stdout. Failing closed must be implemented here
# (own timeout + explicit deny), Claude Code treats a hook timeout or crash as fail-open.
$ErrorActionPreference = "SilentlyContinue"
$here = Split-Path -Parent $PSScriptRoot
$mode = [string](& (Join-Path $PSScriptRoot "mode.ps1"))
if (-not $mode) { $mode = "off" }
if ($mode.Trim() -eq "off") { exit 0 }

$raw = [Console]::In.ReadToEnd()
$tool = "unknown"
try { $tool = [string]($raw | ConvertFrom-Json).tool_name } catch {}
if (-not $tool) { $tool = "unknown" }
$stateDir = Join-Path (Join-Path (Split-Path -Parent $here) ".state") (Split-Path -Leaf $here)
New-Item -ItemType Directory -Force -Path $stateDir | Out-Null
Add-Content -LiteralPath (Join-Path $stateDir "calls.log") -Value ("{0}`t{1}" -f $mode.Trim(), $tool)
exit 0
