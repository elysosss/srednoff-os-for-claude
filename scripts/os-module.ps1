<#
.SYNOPSIS
  os-module - install, enable, switch and remove OS modules in a PROJECT (never in ~/.claude).
.DESCRIPTION
  Windows PowerShell 5.1 port of os-module.sh; same behaviour, same exit codes.
  Spec: docs/specs/E1-module-format.md. No jq needed. ASCII-only on purpose.

  os-module.ps1 new <id>
  os-module.ps1 validate <id>
  os-module.ps1 list      [-Project P]
  os-module.ps1 install   <id> [-Project P]
  os-module.ps1 enable    <id> [-Project P] [-Shared]
  os-module.ps1 mode      <id> <mode> [-Project P]
  os-module.ps1 disable   <id> [-Project P]
  os-module.ps1 uninstall <id> [-Project P] [-Purge]
  os-module.ps1 status    [<id>] [-Project P]

  Exit codes: 0 ok | 1 other | 2 compatibility refusal or rewrites conflict | 3 settings file
  does not parse (nothing was changed).
#>
param(
  [Parameter(Position = 0)][string]$Command = "",
  [Parameter(Position = 1)][string]$Arg1 = "",
  [Parameter(Position = 2)][string]$Arg2 = "",
  [string]$Project = ".",
  [switch]$Shared,
  [switch]$Purge
)

$ErrorActionPreference = "Stop"
$OsRoot = Split-Path -Parent $PSScriptRoot
$ModulesDir = if ($env:SREDNOFF_OS_MODULES_DIR) { $env:SREDNOFF_OS_MODULES_DIR } else { Join-Path $OsRoot "modules" }
$Utf8 = New-Object System.Text.UTF8Encoding($false)

function Die([string]$Msg, [int]$Code = 1) {
  [Console]::Error.WriteLine("os-module: $Msg")
  exit $Code
}
function NowUtc { (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ") }

# ---- JSON helpers: plain ordered dictionaries and lists, deterministic 2-space output ---------
function ConvertTo-Plain($o) {
  if ($null -eq $o) { return $null }
  if ($o -is [System.Management.Automation.PSCustomObject]) {
    $d = [ordered]@{}
    foreach ($p in $o.PSObject.Properties) { $d[$p.Name] = ConvertTo-Plain $p.Value }
    return $d
  }
  if (($o -is [System.Collections.IEnumerable]) -and ($o -isnot [string])) {
    $l = New-Object System.Collections.Generic.List[object]
    foreach ($i in $o) { $l.Add((ConvertTo-Plain $i)) }
    return , $l
  }
  return $o
}
function Read-JsonFile([string]$Path) {
  $text = [System.IO.File]::ReadAllText($Path)
  if (-not $text.Trim()) { throw "empty" }
  return (ConvertTo-Plain ($text | ConvertFrom-Json))
}
function Esc([string]$s) {
  $sb = New-Object System.Text.StringBuilder
  [void]$sb.Append('"')
  foreach ($c in $s.ToCharArray()) {
    switch ($c) {
      '"' { [void]$sb.Append('\"') }
      '\' { [void]$sb.Append('\\') }
      "`n" { [void]$sb.Append('\n') }
      "`r" { [void]$sb.Append('\r') }
      "`t" { [void]$sb.Append('\t') }
      default {
        if ([int]$c -lt 32) { [void]$sb.AppendFormat('\u{0:x4}', [int]$c) } else { [void]$sb.Append($c) }
      }
    }
  }
  [void]$sb.Append('"')
  return $sb.ToString()
}
function Format-Json($v, [int]$Level = 0) {
  $pad = '  ' * $Level; $pad2 = '  ' * ($Level + 1)
  if ($null -eq $v) { return 'null' }
  if ($v -is [bool]) { if ($v) { return 'true' } else { return 'false' } }
  if ($v -is [string]) { return (Esc $v) }
  if ($v -is [System.Collections.IDictionary]) {
    if ($v.Count -eq 0) { return '{}' }
    $parts = @()
    foreach ($k in $v.Keys) { $parts += ($pad2 + (Esc ([string]$k)) + ': ' + (Format-Json $v[$k] ($Level + 1))) }
    return "{`n" + ($parts -join ",`n") + "`n$pad}"
  }
  if ($v -is [System.Collections.IEnumerable]) {
    $items = Arr $v
    if ($items.Count -eq 0) { return '[]' }
    $parts = @()
    foreach ($i in $items) { $parts += ($pad2 + (Format-Json $i ($Level + 1))) }
    return "[`n" + ($parts -join ",`n") + "`n$pad]"
  }
  if ($v -is [double] -or $v -is [single] -or $v -is [decimal]) { return ([System.Convert]::ToString($v, [System.Globalization.CultureInfo]::InvariantCulture)) }
  return ([string]$v)
}
function Write-JsonFile([string]$Path, $Obj) {
  $dir = Split-Path -Parent $Path
  if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
  $tmp = Join-Path $dir (".tmp." + [guid]::NewGuid().ToString("N"))
  [System.IO.File]::WriteAllText($tmp, ((Format-Json $Obj) + "`n"), $Utf8)
  Move-Item -LiteralPath $tmp -Destination $Path -Force
}
function Test-JsonEqual($a, $b) {
  if ($null -eq $a -or $null -eq $b) { return ($null -eq $a -and $null -eq $b) }
  if (($a -is [System.Collections.IDictionary]) -and ($b -is [System.Collections.IDictionary])) {
    if ($a.Count -ne $b.Count) { return $false }
    foreach ($k in $a.Keys) {
      if (-not $b.Contains($k)) { return $false }
      if (-not (Test-JsonEqual $a[$k] $b[$k])) { return $false }
    }
    return $true
  }
  if (($a -is [System.Collections.IDictionary]) -or ($b -is [System.Collections.IDictionary])) { return $false }
  $aList = ($a -is [System.Collections.IEnumerable]) -and ($a -isnot [string])
  $bList = ($b -is [System.Collections.IEnumerable]) -and ($b -isnot [string])
  if ($aList -and $bList) {
    $x = Arr $a; $y = Arr $b
    if ($x.Count -ne $y.Count) { return $false }
    for ($i = 0; $i -lt $x.Count; $i++) { if (-not (Test-JsonEqual $x[$i] $y[$i])) { return $false } }
    return $true
  }
  if ($aList -or $bList) { return $false }
  if ($a -is [string] -or $b -is [string]) { return ([string]$a -ceq [string]$b) }
  return ($a -eq $b)
}
function Replace-Strings($o, [string]$From, [string]$To) {
  if ($null -eq $o) { return $null }
  if ($o -is [string]) { return $o.Replace($From, $To) }
  if ($o -is [System.Collections.IDictionary]) {
    $d = [ordered]@{}
    foreach ($k in $o.Keys) { $d[$k] = Replace-Strings $o[$k] $From $To }
    return $d
  }
  if ($o -is [System.Collections.IEnumerable]) {
    $l = New-Object System.Collections.Generic.List[object]
    foreach ($i in $o) { $l.Add((Replace-Strings $i $From $To)) }
    return , $l
  }
  return $o
}
function Arr($v) {   # @($list) throws on Generic.List[object] in Windows PowerShell 5.1 here
  if ($null -eq $v) { return , @() }
  if ($v -is [System.Collections.Generic.List[object]]) { return , ($v.ToArray()) }
  return , @($v)
}
function Is-List($v) { return (($null -ne $v) -and ($v -is [System.Collections.IEnumerable]) -and ($v -isnot [string]) -and ($v -isnot [System.Collections.IDictionary])) }
# A list returned from a function is unrolled by the pipeline; the unary comma keeps it one object.
function Get-Prop($d, [string]$Key) {
  if ($d -is [System.Collections.IDictionary] -and $d.Contains($Key)) {
    $v = $d[$Key]
    if (Is-List $v) { return , $v }
    return $v
  }
  return $null
}
function Get-Path($d, [string[]]$Keys) {
  $cur = $d
  foreach ($k in $Keys) { $cur = Get-Prop $cur $k; if ($null -eq $cur) { return $null } }
  if (Is-List $cur) { return , $cur }
  return $cur
}
function NewList { return , (New-Object System.Collections.Generic.List[object]) }

# ---- project paths ----------------------------------------------------------------------------
function Test-Id([string]$Id) { if ($Id -cnotmatch '^[a-z][a-z0-9-]{0,30}$') { Die "invalid module id '$Id' (lowercase letters, digits, hyphen; 1-31 chars)" 1 } }

function Resolve-ProjectPaths {
  if (-not (Test-Path -LiteralPath $Project)) { Die "project directory not found: $Project" 1 }
  $script:ProjectDir = (Resolve-Path -LiteralPath $Project).Path.TrimEnd('\', '/')
  $homeResolved = (Resolve-Path -LiteralPath $env:USERPROFILE).Path.TrimEnd('\', '/')
  if ($script:ProjectDir -ieq $homeResolved) { Die "refusing to use `$env:USERPROFILE ($homeResolved) as a project: modules are installed per project, never into ~/.claude" 1 }
  $script:ClaudeDir = Join-Path $script:ProjectDir ".claude"
  $script:Om = Join-Path $script:ClaudeDir "os-modules"
  $script:InstFile = Join-Path $script:Om "installed.json"
  $script:SettingsRel = if ($Shared) { ".claude/settings.json" } else { ".claude/settings.local.json" }
  $script:SettingsFile = Join-Path $script:ProjectDir ($script:SettingsRel -replace '/', '\')
}
function Fwd([string]$p) { return ($p -replace '\\', '/') }

function Inst-Read {
  if (Test-Path -LiteralPath $script:InstFile) { return (Read-JsonFile $script:InstFile) }
  return ([ordered]@{ schema = 1; osRoot = (Fwd $OsRoot); modules = ([ordered]@{}); settings = ([ordered]@{}) })
}
function Inst-Write($Inst) { Write-JsonFile $script:InstFile $Inst }
function Inst-Has([string]$Id) {
  if (-not (Test-Path -LiteralPath $script:InstFile)) { return $false }
  $i = Inst-Read
  return ($null -ne (Get-Path $i @("modules", $Id)))
}
function Mod-Get([string]$Id) { return (Get-Path (Inst-Read) @("modules", $Id)) }

function Manifest-Of([string]$Dir) { return (Join-Path $Dir ".claude-plugin\plugin.json") }

function Validate-Dir([string]$Dir) {   # returns list of problems (empty = ok)
  $errs = New-Object System.Collections.Generic.List[string]
  $mf = Manifest-Of $Dir
  if (-not (Test-Path -LiteralPath $mf)) { $errs.Add("missing .claude-plugin/plugin.json"); return , $errs }
  try { $m = Read-JsonFile $mf } catch { $errs.Add(".claude-plugin/plugin.json is not valid JSON"); return , $errs }
  $o = Get-Path $m @("metadata", "srednoffOs")
  if ($null -eq $o) { $errs.Add("metadata.srednoffOs missing"); return , $errs }
  $id = [string](Get-Prop $o "id")
  if (-not $id) { $errs.Add("metadata.srednoffOs.id missing") }
  if (-not [string](Get-Prop $m "name")) { $errs.Add("name missing") }
  if ((Get-Prop $o "schema") -ne 1) { $errs.Add("metadata.srednoffOs.schema must be 1") }
  $modes = Arr (Get-Prop $o "modes")
  if (($modes -cnotcontains "off") -or ($modes -cnotcontains [string](Get-Prop $o "defaultMode"))) { $errs.Add("modes must include `"off`" and defaultMode") }
  if ((Arr (Get-Prop $o "platforms")).Count -eq 0) { $errs.Add("platforms missing") }
  if (-not ((Get-Prop $o "rewrites") -is [System.Collections.IDictionary])) { $errs.Add("rewrites must be an object") }
  foreach ($f in @((Get-Path $o @("config", "default")), (Get-Prop $o "doctor"), (Get-Path $o @("hooksSource", "default")))) {
    if ($f -and -not (Test-Path -LiteralPath (Join-Path $Dir ([string]$f -replace '/', '\')))) { $errs.Add("declared file missing: $f") }
  }
  $leaf = Split-Path -Leaf $Dir
  if ($leaf -ne "_template" -and $id -and $leaf -ne $id) { $errs.Add("directory name '$leaf' differs from id '$id'") }
  return , $errs
}

function Test-SettingsParse {
  if (-not (Test-Path -LiteralPath $script:SettingsFile)) { return }
  $ok = $true
  try { $s = Read-JsonFile $script:SettingsFile; if ($s -isnot [System.Collections.IDictionary]) { $ok = $false } } catch { $ok = $false }
  if (-not $ok) { Die "$($script:SettingsRel) does not parse as a JSON object; nothing was changed" 3 }
}

# ---- components: skills, commands, agents ---------------------------------------------------
function Components-Remove([string]$Id) {
  $inst = Inst-Read
  $mod = Get-Path $inst @("modules", $Id)
  foreach ($key in @("skills", "commands", "agents")) {
    foreach ($rel in (Arr (Get-Prop $mod $key))) {
      if (-not $rel) { continue }
      $full = Join-Path $script:ProjectDir (([string]$rel) -replace '/', '\')
      if (([string]$rel) -like ".claude/skills/$Id--*" -or ([string]$rel) -like ".claude/agents/$Id--*" -or ([string]$rel) -like ".claude/commands/*") {
        if (Test-Path -LiteralPath $full) { Remove-Item -LiteralPath $full -Recurse -Force }
      }
    }
    $mod[$key] = NewList
  }
  Inst-Write $inst
  foreach ($d in @("skills", "commands", "agents")) {
    $p = Join-Path $script:ClaudeDir $d
    if ((Test-Path -LiteralPath $p) -and -not (Get-ChildItem -LiteralPath $p -Force | Select-Object -First 1)) { Remove-Item -LiteralPath $p -Force }
  }
}
function Components-Install([string]$Id) {
  $mdir = Join-Path $script:Om $Id
  $skills = NewList; $commands = NewList; $agents = NewList
  $sd = Join-Path $mdir "skills"
  if (Test-Path -LiteralPath $sd) {
    foreach ($d in Get-ChildItem -LiteralPath $sd -Directory) {
      $dest = Join-Path $script:ClaudeDir ("skills\$Id--" + $d.Name)
      if (Test-Path -LiteralPath $dest) { Remove-Item -LiteralPath $dest -Recurse -Force }
      New-Item -ItemType Directory -Force -Path (Split-Path -Parent $dest) | Out-Null
      Copy-Item -LiteralPath $d.FullName -Destination $dest -Recurse
      $skills.Add(".claude/skills/$Id--" + $d.Name)
    }
  }
  $cd = Join-Path $mdir "commands"
  if (Test-Path -LiteralPath $cd) {
    foreach ($f in Get-ChildItem -LiteralPath $cd -Filter *.md -File) {
      $dest = Join-Path $script:ClaudeDir ("commands\" + $f.Name)
      if ((Test-Path -LiteralPath $dest) -and ((Get-FileHash -LiteralPath $dest).Hash -ne (Get-FileHash -LiteralPath $f.FullName).Hash)) {
        [Console]::Error.WriteLine("os-module: command $($f.Name) already exists in the project and differs; not overwritten"); continue
      }
      New-Item -ItemType Directory -Force -Path (Split-Path -Parent $dest) | Out-Null
      Copy-Item -LiteralPath $f.FullName -Destination $dest -Force
      $commands.Add(".claude/commands/" + $f.Name)
    }
  }
  $ad = Join-Path $mdir "agents"
  if (Test-Path -LiteralPath $ad) {
    foreach ($f in Get-ChildItem -LiteralPath $ad -Filter *.md -File) {
      $dest = Join-Path $script:ClaudeDir ("agents\$Id--" + $f.Name)
      New-Item -ItemType Directory -Force -Path (Split-Path -Parent $dest) | Out-Null
      Copy-Item -LiteralPath $f.FullName -Destination $dest -Force
      $agents.Add(".claude/agents/$Id--" + $f.Name)
    }
  }
  $inst = Inst-Read
  $mod = Get-Path $inst @("modules", $Id)
  $mod["skills"] = $skills; $mod["commands"] = $commands; $mod["agents"] = $agents
  Inst-Write $inst
}
function Components-Sync([string]$Id) {
  $mod = Mod-Get $Id
  $mode = "off"
  $sf = Join-Path (Join-Path $script:Om $Id) "state.json"
  try { $mode = [string](Get-Prop (Read-JsonFile $sf) "mode") } catch { $mode = "off" }
  if (-not $mode) { $mode = "off" }
  Components-Remove $Id
  if (($mod["enabled"] -eq $true) -and ($mode -cne "off")) { Components-Install $Id }
}

# ---- .gitignore for .state ------------------------------------------------------------------------
$GiLine = ".claude/os-modules/.state/"
function Git-Run([string[]]$GitArgs) {
  $prev = $ErrorActionPreference; $ErrorActionPreference = "Continue"
  try { $null = & git @GitArgs 2>&1; return $LASTEXITCODE } finally { $ErrorActionPreference = $prev }
}
function Gitignore-Ensure {
  $gi = Join-Path $script:ProjectDir ".gitignore"
  $existed = Test-Path -LiteralPath $gi
  $added = $false
  $lines = @()
  if ($existed) { $lines = @([System.IO.File]::ReadAllText($gi) -split "`r?`n") }
  if ((-not $existed) -or ($lines -cnotcontains $GiLine)) {
    $text = ""
    if ($existed) { $text = [System.IO.File]::ReadAllText($gi); if ($text.Length -gt 0 -and -not $text.EndsWith("`n")) { $text += "`n" } }
    [System.IO.File]::WriteAllText($gi, ($text + $GiLine + "`n"), $Utf8)
    $added = $true
  }
  if (Get-Command git -ErrorAction SilentlyContinue) {
    if ((Git-Run @("-C", $script:ProjectDir, "rev-parse", "--is-inside-work-tree")) -eq 0) {
      if ((Git-Run @("-C", $script:ProjectDir, "check-ignore", "-q", ".claude/os-modules/.state/x")) -ne 0) { Die "git does not ignore $GiLine (check .gitignore); refusing to continue" 1 }
    }
  }
  $inst = Inst-Read
  if ($null -eq (Get-Prop $inst "gitignore")) {
    $inst["gitignore"] = [ordered]@{ existed = [bool]$existed; added = [bool]$added }
    Inst-Write $inst
  }
}
function Gitignore-Cleanup {
  $inst = Inst-Read
  $gi = Join-Path $script:ProjectDir ".gitignore"
  if (((Get-Path $inst @("gitignore", "added")) -eq $true) -and (Test-Path -LiteralPath $gi)) {
    $kept = @([System.IO.File]::ReadAllText($gi) -split "`r?`n" | Where-Object { $_ -cne $GiLine })
    $body = ($kept -join "`n").TrimEnd("`n")
    if ($body.Length -gt 0) { $body += "`n" }
    [System.IO.File]::WriteAllText($gi, $body, $Utf8)
    if ((Get-Path $inst @("gitignore", "existed")) -eq $false -and $body.Length -eq 0) { Remove-Item -LiteralPath $gi -Force }
  }
}

# ---- compatibility -------------------------------------------------------------------------------------
function Check-Compat($Manifest, $Inst) {
  $o = Get-Path $Manifest @("metadata", "srednoffOs")
  $need = ([string](Get-Prop $o "osCompat")) -replace '^>=', ''
  if ($need) {
    $osv = "0"
    try { $osv = (([string](Get-Prop (Read-JsonFile (Join-Path $OsRoot "registry\version.json")) "version")) -replace '^v', '') } catch {}
    if ([version]$osv -lt [version]$need) { Die "module needs OS >= $need, this checkout is $osv" 2 }
  }
  if ((Arr (Get-Prop $o "platforms")) -cnotcontains "windows") { Die "module does not support platform 'windows'" 2 }
  foreach ($b in (Arr (Get-Path $o @("requires", "bins")))) {
    if ($b -and -not (Get-Command ([string]$b) -ErrorAction SilentlyContinue)) { Die "required executable not found in PATH: $b" 2 }
  }
  foreach ($r in (Arr (Get-Path $o @("requires", "modules")))) {
    if ($r -and $null -eq (Get-Path $Inst @("modules", [string]$r))) { Die "required module not installed in this project: $r" 2 }
  }
}

# ---- commands --------------------------------------------------------------------------------------------
function Cmd-New {
  Test-Id $Arg1
  $tpl = Join-Path $ModulesDir "_template"
  if (-not (Test-Path -LiteralPath $tpl)) { Die "template not found: $tpl" 1 }
  $dest = Join-Path $ModulesDir $Arg1
  if (Test-Path -LiteralPath $dest) { Die "module already exists: modules/$Arg1" 1 }
  Copy-Item -LiteralPath $tpl -Destination $dest -Recurse
  foreach ($f in Get-ChildItem -LiteralPath $dest -Recurse -File -Force) {
    $bytes = [System.IO.File]::ReadAllBytes($f.FullName)
    if ($bytes -contains 0) { continue }
    $text = $Utf8.GetString($bytes)
    if ($text.Contains("__ID__")) { [System.IO.File]::WriteAllText($f.FullName, $text.Replace("__ID__", $Arg1), $Utf8) }
  }
  Write-Output "created modules/$Arg1"
}
function Cmd-Validate {
  Test-Id $Arg1
  $errs = Validate-Dir (Join-Path $ModulesDir $Arg1)
  if ($errs.Count -eq 0) { Write-Output "ok: $Arg1"; return }
  foreach ($e in $errs) { [Console]::Error.WriteLine($e) }
  exit 1
}
function Cmd-List {
  Resolve-ProjectPaths
  foreach ($d in Get-ChildItem -LiteralPath $ModulesDir -Directory) {
    if ($d.Name -eq "_template") { continue }
    $st = "not installed"
    if (Inst-Has $d.Name) {
      $mod = Mod-Get $d.Name
      $mode = "off"; try { $mode = [string](Get-Prop (Read-JsonFile (Join-Path (Join-Path $script:Om $d.Name) "state.json")) "mode") } catch {}
      $st = "installed, " + $(if ($mod["enabled"] -eq $true) { "enabled" } else { "disabled" }) + ", mode $mode"
    }
    Write-Output "$($d.Name)  $st"
  }
}
function Cmd-Install {
  Test-Id $Arg1; Resolve-ProjectPaths
  $src = Join-Path $ModulesDir $Arg1
  if (-not (Test-Path -LiteralPath $src)) { Die "module not found: modules/$Arg1" 1 }
  $errs = Validate-Dir $src
  if ($errs.Count -gt 0) { foreach ($e in $errs) { [Console]::Error.WriteLine($e) }; Die "module manifest is invalid" 1 }
  $m = Read-JsonFile (Manifest-Of $src)
  Check-Compat $m (Inst-Read)
  $ver = [string](Get-Prop $m "version"); if (-not $ver) { $ver = "0.0.0" }
  New-Item -ItemType Directory -Force -Path $script:Om | Out-Null
  Gitignore-Ensure
  $dest = Join-Path $script:Om $Arg1
  $prevState = $null; $prevCfg = $null
  if (Test-Path -LiteralPath $dest) {
    $sp = Join-Path $dest "state.json"; if (Test-Path -LiteralPath $sp) { $prevState = [System.IO.File]::ReadAllText($sp) }
    $cp = Join-Path $dest "config\user.json"; if (Test-Path -LiteralPath $cp) { $prevCfg = [System.IO.File]::ReadAllText($cp) }
    Remove-Item -LiteralPath $dest -Recurse -Force
  }
  Copy-Item -LiteralPath $src -Destination $dest -Recurse
  foreach ($x in @("tests", "src", "ci")) { $p = Join-Path $dest $x; if (Test-Path -LiteralPath $p) { Remove-Item -LiteralPath $p -Recurse -Force } }
  Get-ChildItem -LiteralPath $dest -Recurse -Force -File -Filter ".gitkeep" | Remove-Item -Force
  if ($null -ne $prevState) { [System.IO.File]::WriteAllText((Join-Path $dest "state.json"), $prevState, $Utf8) }
  else {
    $dm = [string](Get-Path $m @("metadata", "srednoffOs", "defaultMode"))
    Write-JsonFile (Join-Path $dest "state.json") ([ordered]@{ schema = 1; mode = $dm; changedAt = (NowUtc); changedBy = "os-module" })
  }
  if ($null -ne $prevCfg) { New-Item -ItemType Directory -Force -Path (Join-Path $dest "config") | Out-Null; [System.IO.File]::WriteAllText((Join-Path $dest "config\user.json"), $prevCfg, $Utf8) }
  $inst = Inst-Read
  $old = Get-Path $inst @("modules", $Arg1)
  $entry = [ordered]@{
    version = $ver; installedAt = (NowUtc)
    enabled = $(if ($old -and $old["enabled"] -eq $true) { $true } else { $false })
    settingsFile = $(if ($old) { $old["settingsFile"] } else { $null })
    hooks = $(if ($old -and $old["hooks"]) { $old["hooks"] } else { NewList })
    skills = $(if ($old -and $old["skills"]) { $old["skills"] } else { NewList })
    commands = $(if ($old -and $old["commands"]) { $old["commands"] } else { NewList })
    agents = $(if ($old -and $old["agents"]) { $old["agents"] } else { NewList })
  }
  $inst["modules"][$Arg1] = $entry
  Inst-Write $inst
  if ($entry["enabled"] -eq $true) { Components-Sync $Arg1 }
  Write-Output "installed $Arg1 $ver into $($script:Om)\$Arg1 (hooks not wired; run enable)"
}
function Test-Overlap($New, $Other) {
  $a = Get-Path $New @("metadata", "srednoffOs", "rewrites"); $b = Get-Path $Other @("metadata", "srednoffOs", "rewrites")
  $hits = New-Object System.Collections.Generic.List[string]
  if ($null -eq $a -or $null -eq $b) { return , $hits }
  foreach ($k in $a.Keys) {
    if (-not $b.Contains($k)) { continue }
    foreach ($x in (Arr $a[$k])) { foreach ($y in (Arr $b[$k])) {
      $hit = ([string]$x -ceq [string]$y)
      if (-not $hit) { try { $hit = ([string]$y -cmatch ("^(" + [string]$x + ")$")) -or ([string]$x -cmatch ("^(" + [string]$y + ")$")) } catch {} }
      if ($hit) { $hits.Add("$k $x") }
    } }
  }
  return , $hits
}
function Cmd-Enable {
  Test-Id $Arg1; Resolve-ProjectPaths
  if (-not (Inst-Has $Arg1)) { Die "module not installed in this project: $Arg1 (run install first)" 1 }
  $mdir = Join-Path $script:Om $Arg1
  $m = Read-JsonFile (Manifest-Of $mdir)
  $inst = Inst-Read
  $mod = $inst["modules"][$Arg1]
  if ($mod["enabled"] -eq $true) { Write-Output "$Arg1 is already enabled"; return }
  foreach ($other in @($inst["modules"].Keys)) {
    if ($other -ceq $Arg1) { continue }
    if ($inst["modules"][$other]["enabled"] -ne $true) { continue }
    $hits = Test-Overlap $m (Read-JsonFile (Manifest-Of (Join-Path $script:Om $other)))
    if ($hits.Count -gt 0) {
      [Console]::Error.WriteLine("os-module: module $Arg1 rewrites the same tool I/O as enabled module ${other}:")
      foreach ($h in $hits) { [Console]::Error.WriteLine($h) }
      exit 2
    }
  }
  Test-SettingsParse
  $key = $script:SettingsRel
  if ($null -eq (Get-Path $inst @("settings", $key))) {
    $origDir = Join-Path $script:Om ".state\settings-orig"
    New-Item -ItemType Directory -Force -Path $origDir | Out-Null
    $existed = Test-Path -LiteralPath $script:SettingsFile
    if ($existed) { Copy-Item -LiteralPath $script:SettingsFile -Destination (Join-Path $origDir ((Split-Path -Leaf $script:SettingsFile) + ".orig")) -Force }
    if ($null -eq (Get-Prop $inst "settings")) { $inst["settings"] = [ordered]@{} }
    $inst["settings"][$key] = [ordered]@{ existed = [bool]$existed }
    Inst-Write $inst
  }
  $hs = Get-Path $m @("metadata", "srednoffOs", "hooksSource")
  $srcRel = [string](Get-Prop $hs "windows"); if (-not $srcRel) { $srcRel = [string](Get-Prop $hs "default") }
  $newEntries = NewList
  if ($srcRel -and (Test-Path -LiteralPath (Join-Path $mdir ($srcRel -replace '/', '\')))) {
    try { $tpl = Read-JsonFile (Join-Path $mdir ($srcRel -replace '/', '\')) } catch { Die "hooks template does not parse: $srcRel" 1 }
    $hooksRoot = Get-Prop $tpl "hooks"; if ($null -eq $hooksRoot) { $hooksRoot = $tpl }
    $tpl2 = Replace-Strings $hooksRoot "{{MODULE_DIR}}" (Fwd $mdir)
    foreach ($ev in $tpl2.Keys) {
      $v = $tpl2[$ev]
      if (($v -is [System.Collections.IEnumerable]) -and ($v -isnot [string]) -and ($v -isnot [System.Collections.IDictionary])) {
        foreach ($g in $v) { $newEntries.Add([ordered]@{ event = $ev; entry = $g }) }
      }
    }
  }
  $settings = [ordered]@{}
  if (Test-Path -LiteralPath $script:SettingsFile) { $settings = Read-JsonFile $script:SettingsFile }
  $recorded = NewList
  foreach ($h in $newEntries) {
    if ($null -eq (Get-Prop $settings "hooks")) { $settings["hooks"] = [ordered]@{} }
    $list = Get-Prop $settings["hooks"] $h.event
    if ($null -eq $list) { $list = NewList; $settings["hooks"][$h.event] = $list }
    $dup = $false
    foreach ($e in $list) { if (Test-JsonEqual $e $h.entry) { $dup = $true; break } }
    if (-not $dup) { $list.Add($h.entry); $recorded.Add($h) }
  }
  if ($newEntries.Count -gt 0) { Write-JsonFile $script:SettingsFile $settings }
  $inst = Inst-Read
  $mod = $inst["modules"][$Arg1]
  $mod["enabled"] = $true; $mod["settingsFile"] = $key; $mod["hooks"] = $recorded
  Inst-Write $inst
  Components-Sync $Arg1
  $mode = ""; try { $mode = [string](Get-Prop (Read-JsonFile (Join-Path $mdir "state.json")) "mode") } catch {}
  Write-Output "enabled $Arg1 (mode $mode), hooks merged into ${key}: $($recorded.Count)"
}
function Cmd-Mode {
  Test-Id $Arg1; Resolve-ProjectPaths
  if (-not (Inst-Has $Arg1)) { Die "module not installed in this project: $Arg1" 1 }
  if (-not $Arg2) { Die "usage: mode <id> <mode>" 1 }
  $mdir = Join-Path $script:Om $Arg1
  $modes = Arr (Get-Path (Read-JsonFile (Manifest-Of $mdir)) @("metadata", "srednoffOs", "modes"))
  if ($modes -cnotcontains $Arg2) { Die "unknown mode '$Arg2'; this module declares: $($modes -join ', ')" 1 }
  Write-JsonFile (Join-Path $mdir "state.json") ([ordered]@{ schema = 1; mode = $Arg2; changedAt = (NowUtc); changedBy = "os-module" })
  Components-Sync $Arg1
  Write-Output "$Arg1 mode = $Arg2"
}
function Cmd-Disable {
  Test-Id $Arg1; Resolve-ProjectPaths
  if (-not (Inst-Has $Arg1)) { Die "module not installed in this project: $Arg1" 1 }
  $inst = Inst-Read
  $mod = $inst["modules"][$Arg1]
  $sf = [string]$mod["settingsFile"]
  if ($sf) {
    $script:SettingsRel = $sf
    $script:SettingsFile = Join-Path $script:ProjectDir ($sf -replace '/', '\')
    Test-SettingsParse
    if (Test-Path -LiteralPath $script:SettingsFile) {
      $cur = Read-JsonFile $script:SettingsFile
      foreach ($x in (Arr $mod["hooks"])) {
        $list = Get-Path $cur @("hooks", [string]$x.event)
        if ($null -eq $list) { continue }
        for ($i = 0; $i -lt $list.Count; $i++) { if (Test-JsonEqual $list[$i] $x.entry) { $list.RemoveAt($i); break } }
        if ($list.Count -eq 0) { $cur["hooks"].Remove([string]$x.event) }
      }
      if ($cur.Contains("hooks") -and $cur["hooks"].Count -eq 0) { $cur.Remove("hooks") }
      Write-JsonFile $script:SettingsFile $cur
    }
    $others = 0
    foreach ($k in @($inst["modules"].Keys)) {
      if ($k -ceq $Arg1) { continue }
      $mm = $inst["modules"][$k]
      if (([string]$mm["settingsFile"] -ceq $sf) -and ((Arr $mm["hooks"]).Count -gt 0)) { $others++ }
    }
    if ($others -eq 0) {
      $orig = Join-Path $script:Om (".state\settings-orig\" + (Split-Path -Leaf $script:SettingsFile) + ".orig")
      $existed = $true
      if ((Get-Path $inst @("settings", $sf, "existed")) -eq $false) { $existed = $false }
      if ($existed -and (Test-Path -LiteralPath $orig) -and (Test-Path -LiteralPath $script:SettingsFile)) {
        if (Test-JsonEqual (Read-JsonFile $script:SettingsFile) (Read-JsonFile $orig)) { Copy-Item -LiteralPath $orig -Destination $script:SettingsFile -Force }
      }
      elseif ((-not $existed) -and (Test-Path -LiteralPath $script:SettingsFile)) {
        if ((Read-JsonFile $script:SettingsFile).Count -eq 0) { Remove-Item -LiteralPath $script:SettingsFile -Force }
      }
      if (Test-Path -LiteralPath $orig) { Remove-Item -LiteralPath $orig -Force }
      $inst = Inst-Read
      if ($inst["settings"] -and $inst["settings"].Contains($sf)) { $inst["settings"].Remove($sf) }
      Inst-Write $inst
    }
  }
  $inst = Inst-Read
  $mod = $inst["modules"][$Arg1]
  $mod["enabled"] = $false; $mod["hooks"] = NewList; $mod["settingsFile"] = $null
  Inst-Write $inst
  Components-Sync $Arg1
  Write-Output "disabled $Arg1"
}
function Cmd-Uninstall {
  Test-Id $Arg1; Resolve-ProjectPaths
  if (-not (Inst-Has $Arg1)) { Die "module not installed in this project: $Arg1" 1 }
  if ((Mod-Get $Arg1)["enabled"] -eq $true) { $null = Cmd-Disable }
  Components-Remove $Arg1
  $stateDir = ""
  try { $stateDir = [string](Get-Path (Read-JsonFile (Manifest-Of (Join-Path $script:Om $Arg1))) @("metadata", "srednoffOs", "stateDir")) } catch {}
  $mdir = Join-Path $script:Om $Arg1
  if (Test-Path -LiteralPath $mdir) { Remove-Item -LiteralPath $mdir -Recurse -Force }
  $inst = Inst-Read
  $inst["modules"].Remove($Arg1)
  Inst-Write $inst
  if ($Purge) {
    $sp = Join-Path $script:Om ".state\$Arg1"
    if (Test-Path -LiteralPath $sp) { Remove-Item -LiteralPath $sp -Recurse -Force }
    if ($stateDir.StartsWith("~")) { $stateDir = $env:USERPROFILE + $stateDir.Substring(1) }
    $sd = ($stateDir -replace '\\', '/')
    if ($sd -like "*/.claude/logs/os-modules/$Arg1" -and (Test-Path -LiteralPath $stateDir)) { Remove-Item -LiteralPath $stateDir -Recurse -Force }
  }
  if ((Inst-Read)["modules"].Count -eq 0) {
    Gitignore-Cleanup
    Remove-Item -LiteralPath $script:InstFile -Force
    $so = Join-Path $script:Om ".state\settings-orig"
    if (Test-Path -LiteralPath $so) { Remove-Item -LiteralPath $so -Recurse -Force }
    foreach ($d in @((Join-Path $script:Om ".state"), $script:Om, $script:ClaudeDir)) {
      if ((Test-Path -LiteralPath $d) -and -not (Get-ChildItem -LiteralPath $d -Force | Select-Object -First 1)) { Remove-Item -LiteralPath $d -Force }
    }
  }
  Write-Output "uninstalled $Arg1"
}
function Cmd-Status {
  Resolve-ProjectPaths
  if (-not (Test-Path -LiteralPath $script:InstFile)) { Write-Output "no modules installed in $($script:ProjectDir)"; return }
  $inst = Inst-Read
  $ids = if ($Arg1) { @($Arg1) } else { @($inst["modules"].Keys) }
  foreach ($id in $ids) {
    $mod = Get-Path $inst @("modules", $id)
    if ($null -eq $mod) { Write-Output "$id  not installed"; continue }
    $mode = "off"; try { $mode = [string](Get-Prop (Read-JsonFile (Join-Path (Join-Path $script:Om $id) "state.json")) "mode") } catch {}
    $en = if ($mod["enabled"] -eq $true) { "true" } else { "false" }
    Write-Output ("{0}  version {1}  enabled {2}  mode {3}  hooks {4}  skills {5}  commands {6}  agents {7}" -f $id, $mod["version"], $en, $mode, (Arr $mod["hooks"]).Count, (Arr $mod["skills"]).Count, (Arr $mod["commands"]).Count, (Arr $mod["agents"]).Count)
  }
}

switch ($Command) {
  "new"       { if (-not $Arg1) { Die "usage: new <id>" }; Cmd-New }
  "validate"  { if (-not $Arg1) { Die "usage: validate <id>" }; Cmd-Validate }
  "list"      { Cmd-List }
  "install"   { if (-not $Arg1) { Die "usage: install <id> [-Project P]" }; Cmd-Install }
  "enable"    { if (-not $Arg1) { Die "usage: enable <id> [-Project P] [-Shared]" }; Cmd-Enable }
  "mode"      { if (-not $Arg1) { Die "usage: mode <id> <mode> [-Project P]" }; Cmd-Mode }
  "disable"   { if (-not $Arg1) { Die "usage: disable <id> [-Project P]" }; Cmd-Disable }
  "uninstall" { if (-not $Arg1) { Die "usage: uninstall <id> [-Project P] [-Purge]" }; Cmd-Uninstall }
  "status"    { Cmd-Status }
  default     { Die "usage: os-module.ps1 new|validate|list|install|enable|mode|disable|uninstall|status ... (see docs/specs/E1-module-format.md)" 1 }
}
