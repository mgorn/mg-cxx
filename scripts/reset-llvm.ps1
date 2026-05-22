param(
    [string]$BaseRef = "origin/main"
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

function Invoke-GitIgnoreFailure {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$Arguments
    )

    try {
        & git @Arguments 2>$null | Out-Null
    }
    catch {
        # Ignore cleanup failures. These commands only matter if an operation
        # is currently in progress.
    }
}

Write-Host "Resetting LLVM checkout to: $BaseRef"

Invoke-GitIgnoreFailure @("am", "--abort")
Invoke-GitIgnoreFailure @("rebase", "--abort")
Invoke-GitIgnoreFailure @("merge", "--abort")

& git checkout main
& git fetch origin
& git reset --hard $BaseRef
& git clean -fd

Write-Host "LLVM checkout reset."
