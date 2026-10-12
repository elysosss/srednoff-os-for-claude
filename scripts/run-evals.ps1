#requires -Version 5.1
<#
.SYNOPSIS
  SREDNOFF OS eval runner. Regression-tests the domain router and selector against fixed
  briefs so a routing/tag change can't silently break skill selection. Ported concept from
  srednoff-os (Codex sibling): evals/*.json + doctor -RunEvals.
.EXAMPLE
  .\run-evals.ps1
  .\run-evals.ps1 -Json
#>
param([switch]$Json)
$ErrorActionPreference = "Stop"

$Registry = Join-Path $env:USERPROFILE ".claude\registry"
$ModeRouter = Join-Path $Registry "mode-router.ps1"
$DomainRouter = Join-Path $Registry "domain-router.ps1"
$Selector = Join-Path $Registry "select-skills.ps1"
$ModeFixtures = Join-Path $Registry "evals\mode-fixtures.json"
$QualityModeFixtures = Join-Path $Registry "evals\quality-mode-fixtures.json"
$DomainFixtures = Join-Path $Registry "evals\domain-fixtures.json"
$SelectorFixtures = Join-Path $Registry "evals\selector-fixtures.json"
$SecretFixtures = Join-Path $Registry "evals\secret-pattern-fixtures.json"
$SecretPathFixtures = Join-Path $Registry "evals\secret-path-fixtures.json"
$SourceRankerFixtures = Join-Path $Registry "evals\source-ranker-fixtures.json"
$SourceRanker = Join-Path $Registry "source-ranker.ps1"
$HookLib = Join-Path $env:USERPROFILE ".claude\templates\claude-md-os\.claude\hooks\hook-lib.ps1"
$ProfileTagFixtures = Join-Path $Registry "evals\profile-tag-fixtures.json"
$BlockBashHook = Join-Path $env:USERPROFILE ".claude\templates\claude-md-os\.claude\hooks\block-dangerous-bash.ps1"
$OsModule = Join-Path $env:USERPROFILE ".claude\templates\claude-md-os\scripts\os-module.ps1"
$ModuleTemplate = Join-Path $env:USERPROFILE ".claude\templates\claude-md-os\modules\_template"
$DangerousFixtures = Join-Path $Registry "evals\dangerous-command-fixtures.json"
$GenProfileLock = Join-Path $env:USERPROFILE ".claude\templates\claude-md-os\scripts\gen-profile-lock.ps1"
$InitProject = Join-Path $env:USERPROFILE ".claude\templates\claude-md-os\scripts\init-claude-project.ps1"
$CreateOnlyFixtures = Join-Path $Registry "evals\create-only-fixtures.json"

$results =New-Object System.Collections.Generic.List[object]

# Secret-pattern regression (real gitleaks/vendor fixtures, not invented examples - closes
# a gap found in critical review: patterns were never validated against an independent
# corpus, only against test strings the same author who wrote the regex also wrote).
if ((Test-Path -LiteralPath $SecretFixtures) -and (Test-Path -LiteralPath $HookLib)) {
  . $HookLib
  $fixtures = Get-Content -LiteralPath $SecretFixtures -Raw | ConvertFrom-Json
  foreach ($f in $fixtures) {
    $hits = Find-SecretSignals -Text $f.text
    $got = $hits.Count -gt 0
    $pass = ($got -eq $f.expectMatch)
    $results.Add([pscustomobject]@{ suite = "secret-pattern"; id = $f.id; pass = $pass; expected = "match=$($f.expectMatch)"; got = "match=$got ($($hits -join ','))" }) | Out-Null
  }
}

# Secret-PATH regression. The path rules had no fixtures at all until now, which is how
# `.env.example` stayed denied: only the content rules were ever covered here.
if ((Test-Path -LiteralPath $SecretPathFixtures) -and (Test-Path -LiteralPath $HookLib)) {
  . $HookLib
  $fixtures = Get-Content -LiteralPath $SecretPathFixtures -Raw | ConvertFrom-Json
  foreach ($f in $fixtures) {
    $got = Test-SecretPath -Path $f.path
    $pass = ($got -eq $f.expectMatch)
    $results.Add([pscustomobject]@{ suite = "secret-path"; id = $f.id; pass = $pass; expected = "deny=$($f.expectMatch)"; got = "deny=$got" }) | Out-Null
  }
}

# Project-classification regression. gen-profile-lock's heuristic decides which skills a
# project gets, but its only observable output used to be the PROFILE.lock it writes, so
# nothing tested it - a Python repo came out tagged `backend` and nothing else and no one
# noticed. -PrintTags exists to make it testable; each fixture builds a throwaway project
# tree and asserts the exact tag set.
if ((Test-Path -LiteralPath $ProfileTagFixtures) -and (Test-Path -LiteralPath $GenProfileLock)) {
  $fixtures = Get-Content -LiteralPath $ProfileTagFixtures -Raw | ConvertFrom-Json
  foreach ($f in $fixtures) {
    # Fixed neutral project name inside a random parent: gen-profile-lock also tags by the
    # directory name (fba -> amazon, crm -> sales, ...), and a GUID-named dir contained "fba"
    # in ~0.8% of fixtures - a flaky suite. These fixtures test file-based detection only.
    $tmpRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("srednoff-eval-" + [guid]::NewGuid().ToString("N"))
    $tmpProj = Join-Path $tmpRoot "project"
    New-Item -ItemType Directory -Force -Path $tmpProj | Out-Null
    foreach ($rel in $f.files) {
      $full = Join-Path $tmpProj ($rel -replace '/', '\')
      if ($rel.EndsWith("/")) {
        New-Item -ItemType Directory -Force -Path $full | Out-Null
      } else {
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $full) | Out-Null
        New-Item -ItemType File -Force -Path $full | Out-Null
      }
    }
    $gotRaw = & powershell -NoProfile -ExecutionPolicy Bypass -File $GenProfileLock -ProjectPath $tmpProj -PrintTags 2>$null
    Remove-Item -Recurse -Force -LiteralPath $tmpRoot -ErrorAction SilentlyContinue
    # Order-insensitive exact set comparison.
    $gotSorted = (($gotRaw -split ',' | Where-Object { $_ } | Sort-Object) -join ',')
    $expSorted = ((@($f.expectedTags) | Sort-Object) -join ',')
    $pass = ($gotSorted -eq $expSorted)
    $results.Add([pscustomobject]@{ suite = "profile-tags"; id = $f.id; pass = $pass; expected = $expSorted; got = $gotSorted }) | Out-Null
  }
}

# Create-only regression (#34). init-claude-project and gen-profile-lock used to replace or
# edit files the project already owned (CLAUDE.md, rules, .agent/**). Each fixture builds a
# throwaway project, runs one script and asserts what happened to the files on bytes, so
# "never touches an existing file unless -Force" is not taken from the script's own report.
if ((Test-Path -LiteralPath $CreateOnlyFixtures) -and (Test-Path -LiteralPath $InitProject) -and (Test-Path -LiteralPath $GenProfileLock)) {
  $enc = New-Object System.Text.UTF8Encoding($false)
  $fixtures = Get-Content -LiteralPath $CreateOnlyFixtures -Raw | ConvertFrom-Json
  foreach ($f in $fixtures) {
    $tmpRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("srednoff-eval-" + [guid]::NewGuid().ToString("N"))
    $proj = Join-Path $tmpRoot "project"
    New-Item -ItemType Directory -Force -Path $proj | Out-Null
    $orig = @{}
    if ($f.files) {
      foreach ($prop in $f.files.PSObject.Properties) {
        $full = Join-Path $proj ($prop.Name -replace '/', '\')
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $full) | Out-Null
        [System.IO.File]::WriteAllText($full, [string]$prop.Value, $enc)
        $orig[$prop.Name] = [System.IO.File]::ReadAllBytes($full)
      }
    }
    if ($f.git) {
      # Windows PowerShell 5.1 turns git's stderr warnings (LF->CRLF) into terminating errors
      # under "Stop"; the fixture only needs the repo state.
      $prevEap = $ErrorActionPreference; $ErrorActionPreference = "Continue"
      & git -C $proj init -q *> $null
      if ($f.commit) {
        & git -C $proj add -A *> $null
        & git -C $proj -c user.email=eval@example.invalid -c user.name=eval commit -q -m fixture *> $null
      }
      $ErrorActionPreference = $prevEap
    }
    switch ($f.run) {
      "init"           { & powershell -NoProfile -ExecutionPolicy Bypass -File $InitProject $proj *> $null }
      "init-skip"      { & powershell -NoProfile -ExecutionPolicy Bypass -File $InitProject $proj -SkipExistingClaudeMd *> $null }
      "init-force"     { & powershell -NoProfile -ExecutionPolicy Bypass -File $InitProject $proj -Force *> $null }
      "gen-lock"       { & powershell -NoProfile -ExecutionPolicy Bypass -File $GenProfileLock $proj *> $null }
      "gen-lock-embed" { & powershell -NoProfile -ExecutionPolicy Bypass -File $GenProfileLock $proj -EmbedSelection *> $null }
    }
    $problems = New-Object System.Collections.Generic.List[string]
    $same = {
      param($rel)
      $full = Join-Path $proj ($rel -replace '/', '\')
      if (-not (Test-Path -LiteralPath $full)) { return $false }
      $a = [System.IO.File]::ReadAllBytes($full); $b = $orig[$rel]
      return ([System.Convert]::ToBase64String($a) -eq [System.Convert]::ToBase64String($b))
    }
    foreach ($rel in @($f.expectUnchanged)) { if ($rel -and -not (& $same $rel)) { $problems.Add("changed:$rel") } }
    foreach ($rel in @($f.expectReplaced)) {
      if (-not $rel) { continue }
      $full = Join-Path $proj ($rel -replace '/', '\')
      if (-not ((Test-Path -LiteralPath $full) -and -not (& $same $rel))) { $problems.Add("not-replaced:$rel") }
    }
    foreach ($rel in @($f.expectExists)) {
      if ($rel -and -not (Test-Path -LiteralPath (Join-Path $proj ($rel -replace '/', '\')))) { $problems.Add("missing:$rel") }
    }
    foreach ($rel in @($f.expectNoCR)) {
      if (-not $rel) { continue }
      $full = Join-Path $proj ($rel -replace '/', '\')
      if ((Test-Path -LiteralPath $full) -and ([System.IO.File]::ReadAllText($full).Contains("`r"))) { $problems.Add("has-CR:$rel") }
    }
    if ($f.expectContains) {
      foreach ($prop in $f.expectContains.PSObject.Properties) {
        $text = [System.IO.File]::ReadAllText((Join-Path $proj ($prop.Name -replace '/', '\')))
        foreach ($needle in @($prop.Value)) { if (-not $text.Contains($needle)) { $problems.Add("lacks:$($prop.Name):$needle") } }
      }
    }
    if ($f.expectNoLine) {
      foreach ($prop in $f.expectNoLine.PSObject.Properties) {
        $lines = [System.IO.File]::ReadAllText((Join-Path $proj ($prop.Name -replace '/', '\'))) -split "`r?`n"
        foreach ($needle in @($prop.Value)) { if ($lines -contains $needle) { $problems.Add("has-line:$($prop.Name):$needle") } }
      }
    }
    $bakCount = @(Get-ChildItem -LiteralPath $proj -Recurse -Force -File -Filter "*.bak.*" -ErrorAction SilentlyContinue).Count
    if ($f.expectNoBak -and $bakCount -gt 0) { $problems.Add("bak-files:$bakCount") }
    if ($f.expectBak -and $bakCount -eq 0) { $problems.Add("no-bak") }
    Remove-Item -Recurse -Force -LiteralPath $tmpRoot -ErrorAction SilentlyContinue
    $gotText = if ($problems.Count -eq 0) { "ok" } else { $problems -join " " }
    $results.Add([pscustomobject]@{ suite = "create-only"; id = $f.id; pass = ($problems.Count -eq 0); expected = "files untouched unless -Force"; got = $gotText }) | Out-Null
  }
}

# Dangerous-command regression. The hook only ever saw Bash-tool calls; the PowerShell tool
# (default on Windows) skipped it entirely, and the hook knew no PowerShell syntax. Each
# fixture feeds the real hook a PreToolUse payload and checks the verdict, including
# commands that must stay allowed.
if ((Test-Path -LiteralPath $DangerousFixtures) -and (Test-Path -LiteralPath $BlockBashHook)) {
  $fixtures = Get-Content -LiteralPath $DangerousFixtures -Raw | ConvertFrom-Json
  foreach ($f in $fixtures) {
    $payload = @{ tool_name = $f.tool; tool_input = @{ command = $f.command } } | ConvertTo-Json -Compress -Depth 5
    $out = $payload | & powershell -NoProfile -ExecutionPolicy Bypass -File $BlockBashHook 2>$null
    $got = ("$out" -match '"permissionDecision":"deny"')
    $pass = ($got -eq [bool]$f.expectDeny)
    $results.Add([pscustomobject]@{ suite = "dangerous-command"; id = $f.id; pass = $pass; expected = "deny=$($f.expectDeny)"; got = "deny=$got" }) | Out-Null
  }
}

# OS module format (E1). The installer is exercised end to end on throwaway projects against a
# throwaway modules directory (SREDNOFF_OS_MODULES_DIR), so nothing under the OS checkout changes.
# T1 manifest validity, T2 "off changes nothing", T3 rewrites conflict, T4 uninstall restores
# settings byte for byte, T5 refusal to use the profile directory, plus an unparsable settings
# file (exit 3).
if ((Test-Path -LiteralPath $OsModule) -and (Test-Path -LiteralPath $ModuleTemplate)) {
  $omTmp = Join-Path ([System.IO.Path]::GetTempPath()) ("srednoff-evalmod-" + [guid]::NewGuid().ToString("N"))
  $omMods = Join-Path $omTmp "modules"
  New-Item -ItemType Directory -Force -Path $omMods | Out-Null
  Copy-Item -LiteralPath $ModuleTemplate -Destination (Join-Path $omMods "_template") -Recurse
  $env:SREDNOFF_OS_MODULES_DIR = $omMods
  $omEnc = New-Object System.Text.UTF8Encoding($false)
  $prevEapOm = $ErrorActionPreference; $ErrorActionPreference = "Continue"
  function Omx { & powershell -NoProfile -ExecutionPolicy Bypass -File $OsModule @args *> $null; return $LASTEXITCODE }
  function OmProj([string]$Name) { $p = Join-Path $omTmp $Name; New-Item -ItemType Directory -Force -Path $p | Out-Null; return $p }
  function OmBytes([string]$Path) { return [System.Convert]::ToBase64String([System.IO.File]::ReadAllBytes($Path)) }
  function OmFiles([string[]]$Dirs) { $n = 0; foreach ($d in $Dirs) { if (Test-Path -LiteralPath $d) { $n += @(Get-ChildItem -LiteralPath $d -Recurse -File -Force).Count } }; return $n }
  function OmAdd([string]$Id, [bool]$Pass, [string]$Exp, [string]$Got) {
    $results.Add([pscustomobject]@{ suite = "os-module"; id = $Id; pass = $Pass; expected = $Exp; got = $Got }) | Out-Null
  }
  $userSettings = "{`n  `"hooks`": {`n    `"PreToolUse`": [`n      { `"matcher`": `"Bash`", `"hooks`": [ { `"type`": `"command`", `"command`": `"user-hook`" } ] }`n    ]`n  },`n  `"env`": { `"A`": `"1`" }`n}`n"

  # T1
  $rcNew = Omx new demo
  $rcVal = Omx validate demo
  $planPath = Join-Path $omMods "demo\.claude-plugin\plugin.json"
  $good = [System.IO.File]::ReadAllText($planPath)
  $j = $good | ConvertFrom-Json
  $j.metadata.srednoffOs.modes = @("on")
  [System.IO.File]::WriteAllText($planPath, ($j | ConvertTo-Json -Depth 20), $omEnc)
  $rcBad = Omx validate demo
  [System.IO.File]::WriteAllText($planPath, $good, $omEnc)
  OmAdd "t1_new_module_validates" (($rcNew -eq 0) -and ($rcVal -eq 0) -and ($rcBad -ne 0)) "new=0 validate=0 broken-manifest!=0" "new=$rcNew validate=$rcVal broken=$rcBad"

  # T2
  New-Item -ItemType Directory -Force -Path (Join-Path $omMods "demo\skills\hello") | Out-Null
  [System.IO.File]::WriteAllText((Join-Path $omMods "demo\skills\hello\SKILL.md"), "---`nname: hello`ndescription: demo skill used by the os-module eval`n---`nhi`n", $omEnc)
  [System.IO.File]::WriteAllText((Join-Path $omMods "demo\commands\demo-cmd.md"), "c`n", $omEnc)
  [System.IO.File]::WriteAllText((Join-Path $omMods "demo\agents\helper.md"), "a`n", $omEnc)
  $p = OmProj "t2"
  $null = Omx install demo -Project $p
  $null = Omx enable demo -Project $p
  $calls = (Get-Content -LiteralPath (Join-Path $ModuleTemplate "tests\off-mode-calls.json") -Raw | ConvertFrom-Json).calls
  $badCalls = 0; $nCalls = 0
  $hookPs = Join-Path $p ".claude\os-modules\demo\scripts\hook.ps1"
  foreach ($c in $calls) {
    $nCalls++
    $out = ($c | ConvertTo-Json -Compress -Depth 6) | & powershell -NoProfile -ExecutionPolicy Bypass -File $hookPs 2>$null
    if (($LASTEXITCODE -ne 0) -or ("$out" -ne "")) { $badCalls++ }
  }
  $dirs = @((Join-Path $p ".claude\skills"), (Join-Path $p ".claude\commands"), (Join-Path $p ".claude\agents"))
  $offFiles = OmFiles $dirs
  $callsLog = Join-Path $p ".claude\os-modules\.state\demo\calls.log"
  OmAdd "t2_off_mode_changes_nothing" (($nCalls -eq 20) -and ($badCalls -eq 0) -and ($offFiles -eq 0) -and (-not (Test-Path -LiteralPath $callsLog))) "20 calls exit 0 + empty stdout, 0 module files in .claude" "calls=$nCalls bad=$badCalls files=$offFiles"
  $null = Omx mode demo on -Project $p
  $null = '{"tool_name":"Bash"}' | & powershell -NoProfile -ExecutionPolicy Bypass -File $hookPs 2>$null
  $onFiles = OmFiles $dirs
  $okOn = ($onFiles -eq 3) -and (Test-Path -LiteralPath $callsLog) -and ((Get-Item -LiteralPath $callsLog).Length -gt 0)
  $null = Omx mode demo off -Project $p
  $offAgain = OmFiles $dirs
  if ($offAgain -ne 0) { $okOn = $false }
  OmAdd "t2_on_adds_off_removes_components" $okOn "on: 3 files + hook logs; off: 0 files" "on_files=$onFiles after_off=$offAgain"
  $null = Omx uninstall demo -Project $p -Purge

  # T3
  foreach ($m in @("a", "b")) {
    $null = Omx new "rw$m"
    $pj = Join-Path $omMods "rw$m\.claude-plugin\plugin.json"
    $jj = [System.IO.File]::ReadAllText($pj) | ConvertFrom-Json
    $jj.metadata.srednoffOs.rewrites = [pscustomobject]@{ "PostToolUse.updatedToolOutput" = @("Read", "mcp__.*") }
    [System.IO.File]::WriteAllText($pj, ($jj | ConvertTo-Json -Depth 20), $omEnc)
  }
  $p = OmProj "t3"
  $null = Omx install rwa -Project $p
  $null = Omx install rwb -Project $p
  $rca = Omx enable rwa -Project $p
  $afterA = OmBytes (Join-Path $p ".claude\settings.local.json")
  $rcb = Omx enable rwb -Project $p
  OmAdd "t3_rewrites_conflict_refused" (($rca -eq 0) -and ($rcb -eq 2) -and ((OmBytes (Join-Path $p ".claude\settings.local.json")) -eq $afterA)) "enable a=0, enable b=2, settings unchanged" "a=$rca b=$rcb"

  # T4
  $p = OmProj "t4"
  New-Item -ItemType Directory -Force -Path (Join-Path $p ".claude") | Out-Null
  $sf = Join-Path $p ".claude\settings.local.json"
  [System.IO.File]::WriteAllText($sf, $userSettings, $omEnc)
  $origB = OmBytes $sf
  $null = Omx install demo -Project $p
  $null = Omx enable demo -Project $p
  $null = Omx mode demo on -Project $p
  $midText = [System.IO.File]::ReadAllText($sf)
  $midHas = $midText.Contains("user-hook") -and $midText.Contains("hook.ps1")
  $null = Omx disable demo -Project $p
  $null = Omx uninstall demo -Project $p
  OmAdd "t4_uninstall_restores_settings_bytes" (((OmBytes $sf) -eq $origB) -and $midHas -and (-not (Test-Path -LiteralPath (Join-Path $p ".claude\os-modules")))) "user + module hooks while enabled; original bytes after uninstall" "midHas=$midHas"
  $p = OmProj "t4b"
  $null = Omx install demo -Project $p
  $null = Omx enable demo -Project $p
  $null = Omx uninstall demo -Project $p
  $left = @(Get-ChildItem -LiteralPath $p -Recurse -Force | Where-Object { $_.FullName -notmatch '\\\.git(\\|$)' }).Count
  OmAdd "t4_uninstall_leaves_no_files_when_none_before" ($left -eq 0) "0 files left" "left=$left"

  # T5 + unparsable settings
  $fh = OmProj "fakehome"
  $realProfile = $env:USERPROFILE
  $env:USERPROFILE = $fh
  $rch = Omx install demo -Project $fh
  $env:USERPROFILE = $realProfile
  OmAdd "t5_home_directory_refused" (($rch -ne 0) -and (-not (Test-Path -LiteralPath (Join-Path $fh ".claude")))) "non-zero exit, nothing created under the profile directory" "exit=$rch"
  $p = OmProj "t6"
  New-Item -ItemType Directory -Force -Path (Join-Path $p ".claude") | Out-Null
  $sf = Join-Path $p ".claude\settings.local.json"
  [System.IO.File]::WriteAllText($sf, "{ nope", $omEnc)
  $origB = OmBytes $sf
  $null = Omx install demo -Project $p
  $rc6 = Omx enable demo -Project $p
  OmAdd "t6_unparsable_settings_exit_3_unchanged" (($rc6 -eq 3) -and ((OmBytes $sf) -eq $origB)) "exit 3, file unchanged" "exit=$rc6"

  $ErrorActionPreference = $prevEapOm
  Remove-Item Env:\SREDNOFF_OS_MODULES_DIR -ErrorAction SilentlyContinue
  Remove-Item -Recurse -Force -LiteralPath $omTmp -ErrorAction SilentlyContinue
}

if (Test-Path -LiteralPath $ModeFixtures) {
  $fixtures = Get-Content -LiteralPath $ModeFixtures -Raw | ConvertFrom-Json
  foreach ($f in $fixtures) {
    $out = & powershell -NoProfile -ExecutionPolicy Bypass -File $ModeRouter -Brief $f.brief -Json 2>$null | ConvertFrom-Json
    $pass = ($out.mode -eq $f.expectedMode)
    $results.Add([pscustomobject]@{ suite = "mode"; id = $f.id; pass = $pass; expected = $f.expectedMode; got = $out.mode }) | Out-Null
  }
}

if (Test-Path -LiteralPath $QualityModeFixtures) {
  $fixtures = Get-Content -LiteralPath $QualityModeFixtures -Raw | ConvertFrom-Json
  foreach ($f in $fixtures) {
    $out = & powershell -NoProfile -ExecutionPolicy Bypass -File $ModeRouter -Brief $f.brief -Json 2>$null | ConvertFrom-Json
    $pass = ($out.mode -eq $f.expectedMode) -and ($out.legacy_mode -eq $f.expectedLegacyMode) -and ($out.max_capabilities -eq $f.expectedMaxCapabilities)
    $expected = "mode=$($f.expectedMode),legacy=$($f.expectedLegacyMode),max=$($f.expectedMaxCapabilities)"
    $got = "mode=$($out.mode),legacy=$($out.legacy_mode),max=$($out.max_capabilities)"
    $results.Add([pscustomobject]@{ suite = "quality-mode"; id = $f.id; pass = $pass; expected = $expected; got = $got }) | Out-Null
  }
}

if (Test-Path -LiteralPath $DomainFixtures) {
  $fixtures = Get-Content -LiteralPath $DomainFixtures -Raw | ConvertFrom-Json
  foreach ($f in $fixtures) {
    $out = & powershell -NoProfile -ExecutionPolicy Bypass -File $DomainRouter -Brief $f.brief -Json 2>$null | ConvertFrom-Json
    $got = @($out.domains)
    $pass = $false
    foreach ($exp in $f.expectedDomains) { if ($got -contains $exp) { $pass = $true; break } }
    $results.Add([pscustomobject]@{ suite = "domain"; id = $f.id; pass = $pass; expected = ($f.expectedDomains -join ","); got = ($got -join ",") }) | Out-Null
  }
}

if (Test-Path -LiteralPath $SelectorFixtures) {
  $fixtures = Get-Content -LiteralPath $SelectorFixtures -Raw | ConvertFrom-Json
  foreach ($f in $fixtures) {
    $out = & powershell -NoProfile -ExecutionPolicy Bypass -File $Selector -Brief $f.brief -Budget $f.budget -Json -NoLog 2>$null | ConvertFrom-Json
    $gotNames = @($out.picked | ForEach-Object { $_.name })
    $pass = $false
    foreach ($exp in $f.expectedAny) { if ($gotNames -contains $exp) { $pass = $true; break } }
    $results.Add([pscustomobject]@{ suite = "selector"; id = $f.id; pass = $pass; expected = ($f.expectedAny -join ","); got = ($gotNames -join ",") }) | Out-Null
  }
}

if ((Test-Path -LiteralPath $SourceRankerFixtures) -and (Test-Path -LiteralPath $SourceRanker)) {
  $fixtures = Get-Content -LiteralPath $SourceRankerFixtures -Raw | ConvertFrom-Json
  foreach ($f in $fixtures) {
    # External process invocation silently drops an empty-string argument value (found
    # while adding the empty-brief fixture) - omit -Brief entirely rather than pass "",
    # since source-ranker.ps1's own default for -Brief is already "".
    $rankerArgs = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $SourceRanker)
    if ($f.brief) { $rankerArgs += @("-Brief", $f.brief) }
    $rankerArgs += "-Json"
    $out = & powershell @rankerArgs 2>$null | ConvertFrom-Json
    $ranked = @($out.ranked_sources)
    $pass = $true
    $expected = ""
    $got = ""

    if ($f.expectedTop) {
      $topId = if ($ranked.Count -gt 0) { $ranked[0].id } else { $null }
      $expectedTops = @($f.expectedTop)
      $pass = $expectedTops -contains $topId
      $expected = "top in [$($expectedTops -join ',')]"
      $got = "top=$topId"
    } elseif ($f.expectedIdPresent) {
      $ids = @($ranked | ForEach-Object { $_.id })
      $pass = $ids -contains $f.expectedIdPresent
      $expected = "id present: $($f.expectedIdPresent)"
      $got = "ids=$($ids -join ',')"
      if ($pass -and $f.expectedGateOnId) {
        $match = $ranked | Where-Object { $_.id -eq $f.expectedGateOnId.id } | Select-Object -First 1
        $hasGate = $match -and (@($match.gates) -contains $f.expectedGateOnId.gate)
        $pass = $pass -and $hasGate
        $expected += "; gate '$($f.expectedGateOnId.gate)' on $($f.expectedGateOnId.id)"
        $got += "; gates=$(@($match.gates) -join ',')"
      }
    } elseif ($f.expectedDomains) {
      $gotDomains = @($out.domains)
      $pass = $false
      foreach ($exp in $f.expectedDomains) { if ($gotDomains -contains $exp) { $pass = $true; break } }
      $expected = "domain in [$($f.expectedDomains -join ',')]"
      $got = "domains=$($gotDomains -join ',')"
    }

    $results.Add([pscustomobject]@{ suite = "source-ranker"; id = $f.id; pass = $pass; expected = $expected; got = $got }) | Out-Null
  }
}

# Quota invariant: "lean" budget must never surface a G3 (heavyweight) record - that's the
# whole point of lean. This guards the budget-quota math itself, not just name matching.
$leanOut = & powershell -NoProfile -ExecutionPolicy Bypass -File $Selector -Brief "add Stripe checkout to the Next.js app" -Budget lean -Max 12 -Json -NoLog 2>$null | ConvertFrom-Json
$leanG3Count = @($leanOut.picked | Where-Object { $_.group -eq 3 }).Count
$results.Add([pscustomobject]@{ suite = "invariant"; id = "lean_budget_no_g3"; pass = ($leanG3Count -eq 0); expected = "0 G3 records"; got = "$leanG3Count G3 records" }) | Out-Null

$passCount = @($results | Where-Object pass).Count
$total = $results.Count

if ($Json) {
  [ordered]@{ pass = $passCount; total = $total; results = $results } | ConvertTo-Json -Depth 8
  exit 0
}

foreach ($r in $results) {
  $mark = if ($r.pass) { "OK  " } else { "FAIL" }
  Write-Output ("[$mark] $($r.suite)/$($r.id)  expected one of: $($r.expected)")
  if (-not $r.pass) { Write-Output ("        got: $($r.got)") }
}
Write-Output ""
Write-Output ("SREDNOFF OS evals: $passCount/$total passed")
if ($passCount -lt $total) { exit 1 }
exit 0
