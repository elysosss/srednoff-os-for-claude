# Verifies every tracked *.sh file is recorded in git as mode 100755 (Windows port of
# validate-exec-bits.sh).
#
# Windows has no execute bit of its own, and core.filemode=false is the Git-for-Windows
# default - so a chmod here is never recorded, and nothing on this platform notices that a
# script shipped mode 100644 to every Linux/macOS clone. The mode git recorded is readable
# on both platforms with `git ls-files -s`, which makes this the one form of the check that
# behaves identically on the machine that cannot chmod and the machine that can.
#
# Fix a failure with:  git update-index --chmod=+x <path>
# ASCII-only on purpose: Windows PowerShell 5.1 misparses non-ASCII .ps1 without BOM.
param(
    [string]$RepoRoot = "$PSScriptRoot\..",
    [switch]$Json
)

$Bad = New-Object System.Collections.Generic.List[object]

Push-Location -LiteralPath $RepoRoot
try {
    # Single quotes keep the glob from being touched by PowerShell; git expands it itself.
    $Entries = & git ls-files -s -- '*.sh'
    if ($LASTEXITCODE -ne 0) {
        Write-Output "not a git work tree: $RepoRoot"
        exit 1
    }
    foreach ($Entry in $Entries) {
        # "<mode> <object> <stage>`t<path>"
        if ($Entry -match '^(\d+)\s+\S+\s+\d+\t(.+)$') {
            if ($Matches[1] -ne "100755") {
                $Bad.Add([pscustomobject]@{ path = $Matches[2]; mode = $Matches[1] }) | Out-Null
            }
        }
    }
} finally {
    Pop-Location
}

if ($Json) {
    [ordered]@{ failed = $Bad.Count; files = $Bad } | ConvertTo-Json -Depth 4
} else {
    if ($Bad.Count -eq 0) {
        Write-Output "exec-bit check: ok - every tracked *.sh file is mode 100755"
    } else {
        Write-Output "exec-bit check: FAILED - $($Bad.Count) tracked *.sh file(s) are not mode 100755"
        foreach ($Entry in $Bad) { Write-Output "  $($Entry.path) (mode $($Entry.mode))" }
        Write-Output "fix with: git update-index --chmod=+x <path>"
    }
}

if ($Bad.Count -gt 0) { exit 1 }
exit 0
