param(
    [Parameter(Position = 0)]
    [string]$FeatureName = "",

    [Parameter(Position = 1)]
    [string]$BaseRef = "origin/main"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Write-Usage {
    Write-Host "Usage: $($MyInvocation.MyCommand.Name) <feature-name> [base-ref]"
}

function Invoke-Git {
    & git @args

    if ($LASTEXITCODE -ne 0) {
        throw "git $($args -join ' ') failed with exit code $LASTEXITCODE"
    }
}

function Test-GitCommand {
    & git @args *> $null
    return $LASTEXITCODE -eq 0
}

function Get-GitOutput {
    $output = & git @args

    if ($LASTEXITCODE -ne 0) {
        throw "git $($args -join ' ') failed with exit code $LASTEXITCODE"
    }

    return ($output -join "`n").Trim()
}

function Get-GitDir {
    $gitDir = & git rev-parse --git-dir 2>$null

    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace(($gitDir -join "`n"))) {
        Write-Host "ERROR: This must be run from inside the LLVM git checkout."
        exit 1
    }

    $gitDir = ($gitDir | Select-Object -First 1).Trim()

    if ([System.IO.Path]::IsPathRooted($gitDir)) {
        return $gitDir
    }

    return (Resolve-Path $gitDir).Path
}

function Resolve-BaseRef {
    param(
        [string]$RequestedRef
    )

    $currentBranch = (& git branch --show-current 2>$null | Select-Object -First 1)

    if ($LASTEXITCODE -ne 0) {
        $currentBranch = ""
    }

    $currentBranch = "$currentBranch".Trim()

    # If the caller passed the current checked-out branch, using that as a
    # range base is wrong because the branch moves when we commit.
    # Prefer its upstream, like origin/main.
    if (-not [string]::IsNullOrWhiteSpace($currentBranch) -and $RequestedRef -eq $currentBranch) {
        $upstreamRef = (& git rev-parse --abbrev-ref --symbolic-full-name "@{u}" 2>$null | Select-Object -First 1)

        if ($LASTEXITCODE -eq 0) {
            $upstreamRef = "$upstreamRef".Trim()

            if (-not [string]::IsNullOrWhiteSpace($upstreamRef)) {
                return $upstreamRef
            }
        }

        $originRef = "origin/$currentBranch"

        if (Test-GitCommand rev-parse --verify $originRef) {
            return $originRef
        }
    }

    return $RequestedRef
}

if ([string]::IsNullOrWhiteSpace($FeatureName) -or $FeatureName -eq "-h" -or $FeatureName -eq "--help") {
    Write-Usage
    exit 1
}

$ScriptDir = $PSScriptRoot

if ([string]::IsNullOrWhiteSpace($ScriptDir)) {
    $ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
}

$RootDir = Resolve-Path (Join-Path $ScriptDir "..")
$PatchDir = Join-Path $RootDir "patches/$FeatureName"

$DefaultAddMessage = "clang-mg: add $FeatureName"
$DefaultUpdateMessage = "clang-mg: update $FeatureName"

New-Item -ItemType Directory -Force -Path $PatchDir | Out-Null

$insideWorkTree = & git rev-parse --is-inside-work-tree 2>$null

if ($LASTEXITCODE -ne 0 -or "$insideWorkTree".Trim() -ne "true") {
    Write-Host "ERROR: This must be run from inside the LLVM git checkout."
    exit 1
}

$GitDir = Get-GitDir

if ((Test-Path (Join-Path $GitDir "rebase-merge")) -or (Test-Path (Join-Path $GitDir "rebase-apply"))) {
    Write-Host "ERROR: A rebase or git-am operation is currently in progress."
    Write-Host "Finish or abort it before saving feature patches."
    exit 1
}

if (Test-Path (Join-Path $GitDir "MERGE_HEAD")) {
    Write-Host "ERROR: A merge is currently in progress."
    Write-Host "Finish or abort it before saving feature patches."
    exit 1
}

if (Test-Path (Join-Path $GitDir "CHERRY_PICK_HEAD")) {
    Write-Host "ERROR: A cherry-pick is currently in progress."
    Write-Host "Finish or abort it before saving feature patches."
    exit 1
}

$ResolvedBaseRef = Resolve-BaseRef $BaseRef

if (-not (Test-GitCommand rev-parse --verify $ResolvedBaseRef)) {
    Write-Host "ERROR: Base ref does not exist: $ResolvedBaseRef"
    Write-Host
    Write-Host "Try one of:"
    Write-Host "  git fetch origin --tags"
    Write-Host "  $($MyInvocation.MyCommand.Name) $FeatureName origin/main"
    Write-Host "  $($MyInvocation.MyCommand.Name) $FeatureName llvmorg-19.1.0"
    exit 1
}

$existingPatches = @(Get-ChildItem -Path $PatchDir -Filter "*.patch" -File -ErrorAction SilentlyContinue)
$existingPatchCount = $existingPatches.Count
$newCommitCreated = $false

Write-Host "=== save feature ==="
Write-Host "Feature:              $FeatureName"
Write-Host "Requested base ref:   $BaseRef"
Write-Host "Resolved base ref:    $ResolvedBaseRef"
Write-Host "Patch dir:            $PatchDir"
Write-Host "Existing patch count: $existingPatchCount"
Write-Host

$status = & git status --porcelain

if ($LASTEXITCODE -ne 0) {
    Write-Host "ERROR: Failed to check git status."
    exit 1
}

if (-not [string]::IsNullOrWhiteSpace(($status -join "`n"))) {
    Write-Host "Found uncommitted changes."
    Write-Host "Creating a commit before saving patches..."

    Invoke-Git add -A

    & git diff --cached --quiet
    $diffExitCode = $LASTEXITCODE

    if ($diffExitCode -eq 0) {
        Write-Host "No staged changes after git add."
    }
    elseif ($diffExitCode -eq 1) {
        if ($existingPatchCount -gt 0) {
            $commitMessage = if ($env:COMMIT_MSG) { $env:COMMIT_MSG } else { $DefaultUpdateMessage }
        }
        else {
            $commitMessage = if ($env:COMMIT_MSG) { $env:COMMIT_MSG } else { $DefaultAddMessage }
        }

        Invoke-Git commit -m $commitMessage
        $newCommitCreated = $true
    }
    else {
        Write-Host "ERROR: Failed to check staged changes."
        exit 1
    }
}
else {
    Write-Host "No uncommitted changes found."
}

$tmpPatchDir = Join-Path ([System.IO.Path]::GetTempPath()) ("clang-mg-save-feature-" + [Guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Force -Path $tmpPatchDir | Out-Null

try {
    if ($existingPatchCount -gt 0) {
        $patchCount = $existingPatchCount

        if ($newCommitCreated) {
            $patchCount += 1
        }

        Write-Host
        Write-Host "Existing patches found."
        Write-Host "Saving the last $patchCount commit(s) as the updated feature patch stack."

        Invoke-Git format-patch --zero-commit "-$patchCount" -o $tmpPatchDir
    }
    else {
        if ($newCommitCreated) {
            Write-Host
            Write-Host "No existing patches found."
            Write-Host "Saving the new feature commit as the first patch."

            Invoke-Git format-patch --zero-commit -1 -o $tmpPatchDir
        }
        else {
            $commitsSinceBaseText = Get-GitOutput rev-list --count "$ResolvedBaseRef..HEAD"
            $commitsSinceBase = [int]$commitsSinceBaseText

            if ($commitsSinceBase -eq 0) {
                Write-Host
                Write-Host "ERROR: There are no commits to save for this feature."
                Write-Host "Make changes first, then run:"
                Write-Host "  $($MyInvocation.MyCommand.Name) $FeatureName $ResolvedBaseRef"
                exit 1
            }

            Write-Host
            Write-Host "No existing patches found."
            Write-Host "No new commit was created, so saving commits from $ResolvedBaseRef..HEAD."

            Invoke-Git format-patch --zero-commit $ResolvedBaseRef -o $tmpPatchDir
        }
    }

    $newPatches = @(Get-ChildItem -Path $tmpPatchDir -Filter "*.patch" -File -ErrorAction SilentlyContinue)

    if ($newPatches.Count -eq 0) {
        Write-Host
        Write-Host "ERROR: No patch files were generated."
        exit 1
    }

    Get-ChildItem -Path $PatchDir -Filter "*.patch" -File -ErrorAction SilentlyContinue |
        Remove-Item -Force

    foreach ($patch in $newPatches) {
        Copy-Item -Path $patch.FullName -Destination $PatchDir -Force
    }

    Write-Host
    Write-Host "Saved patches for feature: $FeatureName"
    Write-Host "Patch dir: $PatchDir"
    Write-Host

    Get-ChildItem -Path $PatchDir -Filter "*.patch" -File |
        Sort-Object Name |
        ForEach-Object { Write-Host $_.FullName }
}
finally {
    if (Test-Path $tmpPatchDir) {
        Remove-Item -Recurse -Force $tmpPatchDir
    }
}
