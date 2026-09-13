#requires -Version 5.1
<#
.SYNOPSIS
  Initialize Claude MD OS files into a target project (Windows / PowerShell).
.DESCRIPTION
  Copies the Claude MD OS template package into the given project directory.
  - Only ever ships the OS's project-bootstrap surface (CLAUDE.md, code_review.md, AGENTS.md,
    .claude/rules|skills|commands|hooks, .claude/settings*.example.json, .agent/**). The OS
    repo's own about-itself files (README*, LICENSE, .gitignore, QUALITY.md, RELEASE.md,
    docs/**, benchmarks/**, registry/**, skills-library/**) are NEVER copied into a target
    project - registry/skills-library are meant to be consumed via the global registry
    symlink/install, not duplicated per project.
  - Never overwrites a file already tracked in the target's own git history that differs
    from the template: it is left untouched and reported, not backed-up-and-clobbered.
    Pass -Force to opt back into backup+overwrite for tracked files that differ.
  - Untracked existing files that differ still get the old backup+overwrite treatment.
  - Never deletes anything.
  - Never creates an active .claude/settings.json (only settings.example.json is copied).
  - Reports created / updated(backed up) / skipped / kept(tracked) files.
.PARAMETER ProjectPath
  Target project directory. Defaults to current directory.
.PARAMETER SkipExistingClaudeMd
  If the project already has its own CLAUDE.md, leave it completely untouched
  (do not back up or replace). Use this when rolling the OS into existing projects
  that have a tailored CLAUDE.md you want to keep active.
.PARAMETER Force
  Overwrite existing git-tracked files that differ from the template instead of skipping
  them (still backs them up first). Opt-in only.
.EXAMPLE
  .\init-claude-project.ps1 .
  .\init-claude-project.ps1 "C:\my-workspace\my-nextjs-app"
  .\init-claude-project.ps1 "C:\my-workspace\my-project" -SkipExistingClaudeMd
#>
[CmdletBinding()]
param(
  [Parameter(Position = 0)]
  [string]$ProjectPath = ".",
  [switch]$SkipExistingClaudeMd,
  [switch]$Force
)

$ErrorActionPreference = "Stop"

# Template root = parent of this scripts/ folder
$TemplateRoot = Split-Path -Parent $PSScriptRoot
$Target = (Resolve-Path -LiteralPath $ProjectPath).Path
$Stamp = Get-Date -Format "yyyyMMdd-HHmmss"

if (-not (Test-Path -LiteralPath $TemplateRoot)) {
  Write-Error "Template root not found: $TemplateRoot"
  exit 1
}

# Hard safety guard: never let target resolve to $HOME/$env:USERPROFILE itself. This
# tool deploys a full project structure (rules/hooks/skills/CLAUDE.md/etc.) - the user's
# profile root is a global config location, never a "project". Defense in depth, added
# after a real incident where init-claude-project.sh (which had extra git-root-walking
# logic this script never had) resolved a scratch path to $HOME and deployed there.
$HomeResolved = (Resolve-Path -LiteralPath $env:USERPROFILE).Path.TrimEnd('\')
if ($Target.TrimEnd('\') -ieq $HomeResolved) {
  Write-Error "init-claude-project: refusing to init directly into `$env:USERPROFILE ($HomeResolved) - this is not a project directory. Pass an explicit project path."
  exit 1
}

Write-Host "Claude MD OS init" -ForegroundColor Cyan
Write-Host "  Template: $TemplateRoot"
Write-Host "  Target:   $Target"
Write-Host ""

# Collect only the template files in the project-bootstrap allow-list. Everything else in
# the template (README*, LICENSE, .gitignore, QUALITY.md, RELEASE.md, docs/, benchmarks/,
# registry/, skills-library/, scripts/, .git/, .github/, .claude-plugin/, top-level hooks/,
# .claude/settings.json) is the OS repo's own tooling/about-itself content and is never
# copied into a target project - registry/skills-library are consumed via the global
# registry install, not duplicated per project.
$created = @()
$updated = @()
$skipped = @()

$files = Get-ChildItem -LiteralPath $TemplateRoot -Recurse -File -Force | Where-Object {
  $rel = $_.FullName.Substring($TemplateRoot.Length).TrimStart('\','/')
  ($rel -eq "CLAUDE.md") -or ($rel -eq "code_review.md") -or ($rel -eq "AGENTS.md") -or
  ($rel -like ".claude\rules\*") -or ($rel -like ".claude\skills\*") -or
  ($rel -like ".claude\commands\*") -or ($rel -like ".claude\hooks\*") -or
  ($rel -eq ".claude\settings.example.json") -or ($rel -eq ".claude\settings.windows.example.json") -or
  ($rel -like ".agent\*")
}

$preserved = @()
$keptTracked = @()

# Determine once whether the target is inside a git work tree, and if so, resolve `git`.
$gitCmd = Get-Command git -ErrorAction SilentlyContinue
$targetIsGitRepo = $false
if ($gitCmd) {
  & git -C $Target rev-parse --is-inside-work-tree *> $null
  $targetIsGitRepo = ($LASTEXITCODE -eq 0)
}

foreach ($f in $files) {
  $rel = $f.FullName.Substring($TemplateRoot.Length).TrimStart('\','/')

  # Keep a project's own CLAUDE.md active if requested.
  if ($SkipExistingClaudeMd -and ($rel -eq "CLAUDE.md")) {
    $existingClaude = Join-Path $Target "CLAUDE.md"
    if (Test-Path -LiteralPath $existingClaude) {
      $preserved += $rel
      continue
    }
  }

  $dest = Join-Path $Target $rel
  $destDir = Split-Path -Parent $dest
  if (-not (Test-Path -LiteralPath $destDir)) {
    New-Item -ItemType Directory -Force -Path $destDir | Out-Null
  }

  if (Test-Path -LiteralPath $dest) {
    # Compare content; if identical, skip. Otherwise back up then copy (unless the file is
    # already tracked in the target's own git history - then it is left untouched, matching
    # the .sh port, unless -Force was passed).
    $same = $false
    try {
      $a = Get-FileHash -LiteralPath $dest -Algorithm SHA256
      $b = Get-FileHash -LiteralPath $f.FullName -Algorithm SHA256
      $same = ($a.Hash -eq $b.Hash)
    } catch { $same = $false }

    if ($same) {
      $skipped += $rel
      continue
    }

    $tracked = $false
    if (-not $Force -and $targetIsGitRepo) {
      & git -C $Target ls-files --error-unmatch -- $rel *> $null
      $tracked = ($LASTEXITCODE -eq 0)
    }

    if ($tracked) {
      $keptTracked += $rel
      continue
    }

    $backup = "$dest.bak.$Stamp"
    Copy-Item -LiteralPath $dest -Destination $backup -Force
    Copy-Item -LiteralPath $f.FullName -Destination $dest -Force
    $updated += "$rel  (backup: $(Split-Path -Leaf $backup))"
  }
  else {
    Copy-Item -LiteralPath $f.FullName -Destination $dest -Force
    $created += $rel
  }
}

Write-Host "Created ($($created.Count)):" -ForegroundColor Green
$created | ForEach-Object { Write-Host "  + $_" }
Write-Host ""
Write-Host "Updated / backed up ($($updated.Count)):" -ForegroundColor Yellow
$updated | ForEach-Object { Write-Host "  ~ $_" }
Write-Host ""
Write-Host "Skipped (identical) ($($skipped.Count)):" -ForegroundColor DarkGray
$skipped | ForEach-Object { Write-Host "  = $_" }
Write-Host ""
if ($preserved.Count -gt 0) {
  Write-Host "Preserved (kept project's own, untouched) ($($preserved.Count)):" -ForegroundColor Magenta
  $preserved | ForEach-Object { Write-Host "  ! $_" }
  Write-Host ""
}
if ($keptTracked.Count -gt 0) {
  Write-Host "Kept (tracked in your git history, differs from template - pass -Force to overwrite) ($($keptTracked.Count)):" -ForegroundColor Magenta
  $keptTracked | ForEach-Object { Write-Host "  ! $_" }
  Write-Host ""
}
Write-Host "Done. Hooks are NOT active. To enable them:" -ForegroundColor Cyan
Write-Host "  Copy-Item .claude\settings.example.json .claude\settings.json"

# Generate PROFILE.lock (cached skill selection for the stack), if the registry is available.
$genLock = Join-Path $PSScriptRoot "gen-profile-lock.ps1"
$coreReg = Join-Path $env:USERPROFILE ".claude\registry\CORE-300.md"
if ((Test-Path $genLock) -and (Test-Path $coreReg)) {
  Write-Host ""
  & $genLock $Target
}
