# Prints the module mode ("off" when state.json is missing, unreadable or has no mode).
# Shared by every hook of the module: reading the mode is the hook's first action, so a module
# in "off" changes nothing (empty stdout, exit 0). ASCII only: Windows PowerShell 5.1.
$here = Split-Path -Parent $PSScriptRoot
$mode = ""
$stateFile = Join-Path $here "state.json"
if (Test-Path -LiteralPath $stateFile) {
  try { $mode = [string](Get-Content -LiteralPath $stateFile -Raw | ConvertFrom-Json).mode } catch { $mode = "" }
}
if (-not $mode) { $mode = "off" }
Write-Output $mode
