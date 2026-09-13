# Fast metadata smoke check for templates/claude-md-os/skills-library/*/SKILL.md - name
# pattern, description length/presence, frontmatter well-formedness. Ported concept from
# srednoff-os (Codex sibling): quick-validate-all-skills.ps1 "fast" mode (their "full" mode
# shells out to an external Codex-specific validator we don't have and don't need - our
# skills are pre-vetted at import time, this check just guards against future drift/typos).
# ASCII-only on purpose: Windows PowerShell 5.1 misparses non-ASCII .ps1 without BOM.
param(
    [string]$SkillsRoot = "$PSScriptRoot\..\skills-library",
    [switch]$Json
)

$ErrorActionPreference = "Stop"

if (-not (Test-Path -LiteralPath $SkillsRoot)) {
    Write-Output "skills-library not found: $SkillsRoot (nothing to validate)"
    if ($Json) { @{ ok = 0; failed = 0 } | ConvertTo-Json }
    exit 0
}

$SkillDirs = Get-ChildItem -LiteralPath $SkillsRoot -Directory |
    Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName "SKILL.md") }

$Ok = 0
$Failures = New-Object System.Collections.Generic.List[object]

foreach ($Skill in $SkillDirs) {
    $SkillFile = Join-Path $Skill.FullName "SKILL.md"
    $Text = Get-Content -LiteralPath $SkillFile -Raw -Encoding UTF8
    $Lines = $Text -split "`r?`n"
    $NameOk = $false
    $DescriptionOk = $false
    for ($i = 0; $i -lt $Lines.Count; $i++) {
        $Line = $Lines[$i]
        if ($Line -match '^\s*---\s*$' -and $i -gt 0) { break }
        # -cmatch (case-sensitive): PowerShell's default -match is case-insensitive,
        # which would accept "Name: BadUpperCaseName" as a valid lowercase name - a real
        # Claude Code skill name must be lowercase (official docs), and bash's grep -Eq
        # (case-sensitive by default) already rejects this correctly. An unqualified
        # -match here would silently let an invalid skill pass on Windows while bash
        # correctly failed it - a real platform-parity bug, not cosmetic.
        if ($Line -cmatch '^\s*name:\s*[a-z0-9][a-z0-9-]{1,62}\s*$') { $NameOk = $true }
        if ($Line -match '^\s*description:\s*(.+)$') {
            $Value = $Matches[1].Trim()
            if ($Value -in @(">", "|", ">-", "|-", ">+", "|+")) {
                # YAML block scalar - the actual description is the indented lines that
                # follow, not this marker itself. None of the 303 currently-imported
                # skills use this form, but it's a standard YAML pattern real skills in
                # this ecosystem do use (confirmed in the donor catalog) - treating it as
                # a 1-character description would be a false failure on a well-formed skill.
                $BlockLines = @()
                for ($Child = $i + 1; $Child -lt $Lines.Count; $Child++) {
                    if ($Lines[$Child] -match '^\s*---\s*$') { break }
                    if ($Lines[$Child] -match '^\s+\S') { $BlockLines += $Lines[$Child].Trim() } else { break }
                }
                $BlockValue = ($BlockLines -join " ").Trim()
                $DescriptionOk = ($BlockValue.Length -ge 20) -and ($BlockValue.Length -le 1024)
            } else {
                $Value = $Value.Trim('"').Trim("'")
                $DescriptionOk = ($Value.Length -ge 20) -and ($Value.Length -le 1024)
            }
        }
    }
    $Errors = @()
    if (-not $Text.StartsWith("---")) { $Errors += "missing frontmatter start" }
    if ($Skill.Name -ne $Skill.Name.ToLowerInvariant()) { $Errors += "directory name must be lowercase" }
    if (-not $NameOk) { $Errors += "missing or invalid name (lowercase, alnum+hyphen, 2-63 chars)" }
    if (-not $DescriptionOk) { $Errors += "missing, too-short (<20 chars), or too-long (>1024 chars) description" }

    # Broken-link check. A SKILL.md can cite a reference file that was never shipped and
    # every check above still passes, because the frontmatter is perfectly valid - the
    # skill just promises content that is not in the directory. So: extract markdown link
    # targets and require each relative one to resolve inside the skill's own directory.
    #
    # Only targets carrying a file extension are checked. SKILL.md files legitimately
    # contain markdown *syntax examples* in prose - telegram-bot-builder documents
    # MarkdownV2 formatting as `[link](url)` - where "url" is a placeholder word, not a
    # path, and flagging it would be a false failure. Requiring a "." in the target keeps
    # those out. Checked against all 309 skills: with the rule, 3 findings and all 3 are
    # genuine; without it, that same prose example is a fourth, bogus finding.
    for ($i = 0; $i -lt $Lines.Count; $i++) {
        foreach ($LinkMatch in [regex]::Matches($Lines[$i], '\]\(([^)]+)\)')) {
            $Target = $LinkMatch.Groups[1].Value
            if ($Target -match '://' -or $Target -match '^(mailto:|tel:|#)') { continue }
            $LinkPath = ($Target -split '#')[0]
            $LinkPath = ($LinkPath -split ' ')[0]
            if ([string]::IsNullOrEmpty($LinkPath)) { continue }
            if ($LinkPath -notmatch '\.') { continue }
            if (-not (Test-Path -LiteralPath (Join-Path $Skill.FullName $LinkPath))) {
                $Errors += "broken link (line $($i + 1)): $LinkPath"
            }
        }
    }

    if ($Errors.Count -eq 0) {
        $Ok++
    } else {
        $Failures.Add([pscustomobject]@{ skill = $Skill.Name; errors = ($Errors -join "; ") }) | Out-Null
    }
}

if ($Json) {
    [ordered]@{ ok = $Ok; failed = $Failures.Count; failures = $Failures } | ConvertTo-Json -Depth 4
} else {
    Write-Output "skills-library validation: ok=$Ok failed=$($Failures.Count)"
    foreach ($f in $Failures) { Write-Output "  FAIL $($f.skill): $($f.errors)" }
}

if ($Failures.Count -gt 0) { exit 1 }
exit 0
