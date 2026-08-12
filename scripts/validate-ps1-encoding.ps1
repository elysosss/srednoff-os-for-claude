# Verifies every *.ps1 in the repo is safe for Windows PowerShell 5.1 to parse (Windows port
# of validate-ps1-encoding.sh). A file passes if it is pure ASCII, or if it starts with a
# UTF-8 BOM.
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
# ASCII-only on purpose: Windows PowerShell 5.1 misparses non-ASCII .ps1 without BOM.
param(
    [string]$RepoRoot = "$PSScriptRoot\..",
    [switch]$Json
)

if (-not (Test-Path -LiteralPath $RepoRoot)) {
    Write-Output "repo root not found: $RepoRoot"
    exit 1
}

$Root = (Resolve-Path -LiteralPath $RepoRoot).Path
$Checked = 0
$Bad = New-Object System.Collections.Generic.List[object]

$Files = Get-ChildItem -LiteralPath $Root -Filter *.ps1 -File -Recurse -ErrorAction SilentlyContinue |
    Where-Object { $_.FullName -notmatch '\\\.git\\' } |
    Sort-Object FullName

foreach ($File in $Files) {
    $Checked++
    # Read bytes, not text: any decoding step here would paper over the exact problem
    # this check exists to find.
    $Bytes = [System.IO.File]::ReadAllBytes($File.FullName)
    if ($Bytes.Length -ge 3 -and $Bytes[0] -eq 0xEF -and $Bytes[1] -eq 0xBB -and $Bytes[2] -eq 0xBF) {
        continue
    }

    $LineNumber = 1
    $HitLines = New-Object System.Collections.Generic.List[int]
    for ($i = 0; $i -lt $Bytes.Length; $i++) {
        if ($Bytes[$i] -eq 0x0A) {
            $LineNumber++
        } elseif ($Bytes[$i] -gt 0x7F) {
            if (-not $HitLines.Contains($LineNumber)) { $HitLines.Add($LineNumber) | Out-Null }
        }
    }

    if ($HitLines.Count -gt 0) {
        $Relative = $File.FullName
        if ($Relative.StartsWith($Root)) { $Relative = $Relative.Substring($Root.Length).TrimStart('\', '/') }
        $Bad.Add([pscustomobject]@{ path = ($Relative -replace '\\', '/'); lines = ($HitLines -join ",") }) | Out-Null
    }
}

if ($Json) {
    [ordered]@{ checked = $Checked; failed = $Bad.Count; files = $Bad } | ConvertTo-Json -Depth 4
} else {
    if ($Bad.Count -eq 0) {
        Write-Output "ps1 encoding check: ok - $Checked file(s), all pure ASCII or UTF-8 with BOM"
    } else {
        Write-Output "ps1 encoding check: FAILED - $($Bad.Count) of $Checked file(s) hold non-ASCII bytes without a UTF-8 BOM"
        foreach ($Entry in $Bad) { Write-Output "  $($Entry.path) (line(s): $($Entry.lines))" }
        Write-Output "fix by replacing the character with a code-point construction ([char]0x2014), or by saving the file as UTF-8 with BOM"
    }
}

if ($Bad.Count -gt 0) { exit 1 }
exit 0
