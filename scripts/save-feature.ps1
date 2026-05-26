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

function Get-GitLines {
    $output = & git @args

    if ($LASTEXITCODE -ne 0) {
        throw "git $($args -join ' ') failed with exit code $LASTEXITCODE"
    }

    return @(
        $output |
            ForEach-Object { "$($_)".Trim() } |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    )
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

function Get-PatchIdFromFile {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    $output = Get-Content -LiteralPath $Path -Raw | & git patch-id --stable

    if ($LASTEXITCODE -ne 0) {
        throw "git patch-id failed for patch file: $Path"
    }

    $lines = @($output)

    if ($lines.Count -eq 0) {
        return ""
    }

    $firstLine = "$($lines[0])".Trim()

    if ([string]::IsNullOrWhiteSpace($firstLine)) {
        return ""
    }

    return (($firstLine -split '\s+')[0])
}

function Get-PatchIdFromCommit {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Commit
    )

    $output = & git show --format=medium --patch --binary $Commit | & git patch-id --stable

    if ($LASTEXITCODE -ne 0) {
        throw "git patch-id failed for commit: $Commit"
    }

    $lines = @($output)

    if ($lines.Count -eq 0) {
        return ""
    }

    $firstLine = "$($lines[0])".Trim()

    if ([string]::IsNullOrWhiteSpace($firstLine)) {
        return ""
    }

    return (($firstLine -split '\s+')[0])
}

function Add-CommitIfMissing {
    param(
        [ValidateNotNull()]
        [System.Collections.Generic.List[string]]$List,

        [ValidateNotNull()]
        [hashtable]$Set,

        [Parameter(Mandatory = $true)]
        [string]$Commit
    )

    if (-not $Set.ContainsKey($Commit)) {
        $Set[$Commit] = $true
        $List.Add($Commit) | Out-Null
    }
}

function Get-CommitSummary {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Commit
    )

    $shortHash = Get-GitOutput rev-parse --short $Commit
    $subject = Get-GitOutput show -s "--format=%s" $Commit

    return "$shortHash $subject"
}

function Write-SelectedCommitList {
    param(
        [ValidateNotNull()]
        [System.Collections.Generic.List[string]]$Commits
    )

    foreach ($commit in $Commits) {
        Write-Host "  $(Get-CommitSummary $commit)"
    }
}

function Save-SelectedCommitsAsPatches {
    param(
        [ValidateNotNull()]
        [System.Collections.Generic.List[string]]$Commits,

        [Parameter(Mandatory = $true)]
        [string]$OutputDir
    )

    $patchNumber = 1

    foreach ($commit in $Commits) {
        $oneCommitDir = Join-Path $OutputDir ("commit-$patchNumber")
        New-Item -ItemType Directory -Force -Path $oneCommitDir | Out-Null

        Invoke-Git format-patch --zero-commit --start-number $patchNumber "-1" $commit -o $oneCommitDir

        $generatedPatches = @(Get-ChildItem -Path $oneCommitDir -Filter "*.patch" -File -ErrorAction SilentlyContinue)

        if ($generatedPatches.Count -ne 1) {
            throw "Expected exactly one generated patch for commit $commit, but found $($generatedPatches.Count)."
        }

        Move-Item -LiteralPath $generatedPatches[0].FullName -Destination (Join-Path $OutputDir $generatedPatches[0].Name) -Force
        Remove-Item -LiteralPath $oneCommitDir -Recurse -Force

        $patchNumber += 1
    }
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

$existingPatches = @(
    Get-ChildItem -Path $PatchDir -Filter "*.patch" -File -ErrorAction SilentlyContinue |
        Sort-Object Name
)
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
        Write-Host
        Write-Host "Existing patches found."
        Write-Host "Finding this feature's already-applied commits by patch-id instead of using the last commits on HEAD."

        $historyCommits = @(Get-GitLines rev-list --reverse "$ResolvedBaseRef..HEAD")
        $commitByPatchId = @{}

        foreach ($commit in $historyCommits) {
            $patchId = Get-PatchIdFromCommit $commit

            if ([string]::IsNullOrWhiteSpace($patchId)) {
                continue
            }

            if (-not $commitByPatchId.ContainsKey($patchId)) {
                $commitByPatchId[$patchId] = @()
            }

            $commitByPatchId[$patchId] = @($commitByPatchId[$patchId]) + $commit
        }

        $selectedCommits = New-Object System.Collections.Generic.List[string]
        $selectedCommitSet = @{}
        $missingPatchMatches = New-Object System.Collections.Generic.List[string]

        foreach ($patch in $existingPatches) {
            $patchId = Get-PatchIdFromFile $patch.FullName

            if ([string]::IsNullOrWhiteSpace($patchId) -or -not $commitByPatchId.ContainsKey($patchId)) {
                $missingPatchMatches.Add($patch.Name) | Out-Null
                continue
            }

            $candidate = @(
                $commitByPatchId[$patchId] |
                    Where-Object { -not $selectedCommitSet.ContainsKey($_) } |
                    Select-Object -First 1
            )

            if ($candidate.Count -eq 0) {
                $missingPatchMatches.Add($patch.Name) | Out-Null
                continue
            }

            Add-CommitIfMissing $selectedCommits $selectedCommitSet $candidate[0]
        }

        if ($missingPatchMatches.Count -gt 0) {
            Write-Host
            Write-Host "ERROR: Could not safely find the applied commit(s) for these existing patch file(s):"

            foreach ($patchName in $missingPatchMatches) {
                Write-Host "  $patchName"
            }

            Write-Host
            Write-Host "The patch folder was not modified."
            Write-Host "Make sure the feature's current patches are applied to this LLVM checkout before saving."
            exit 1
        }

        foreach ($commit in $historyCommits) {
            $subject = Get-GitOutput show -s "--format=%s" $commit

            if ($subject -eq $DefaultAddMessage -or $subject -eq $DefaultUpdateMessage) {
                Add-CommitIfMissing $selectedCommits $selectedCommitSet $commit
            }
        }

        if ($newCommitCreated) {
            $headCommit = Get-GitOutput rev-parse HEAD
            Add-CommitIfMissing $selectedCommits $selectedCommitSet $headCommit
        }

        if ($selectedCommits.Count -eq 0) {
            Write-Host
            Write-Host "ERROR: No commits were selected for this feature."
            Write-Host "The patch folder was not modified."
            exit 1
        }

        Write-Host
        Write-Host "Saving these commits as the updated feature patch stack:"
        Write-SelectedCommitList $selectedCommits

        Save-SelectedCommitsAsPatches $selectedCommits $tmpPatchDir
    }
    else {
        if ($newCommitCreated) {
            Write-Host
            Write-Host "No existing patches found."
            Write-Host "Saving the new feature commit as the first patch."

            Invoke-Git format-patch --zero-commit "-1" -o $tmpPatchDir
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
            Write-Host "WARNING: This can include other feature commits if this checkout already has patch stacks applied."

            Invoke-Git format-patch --zero-commit $ResolvedBaseRef -o $tmpPatchDir
        }
    }

    $newPatches = @(
        Get-ChildItem -Path $tmpPatchDir -Filter "*.patch" -File -ErrorAction SilentlyContinue |
            Sort-Object Name
    )

    if ($newPatches.Count -eq 0) {
        Write-Host
        Write-Host "ERROR: No patch files were generated."
        exit 1
    }

    if ($existingPatchCount -gt 0) {
        $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
        $backupDir = "$PatchDir.backup.$timestamp"
        New-Item -ItemType Directory -Force -Path $backupDir | Out-Null

        foreach ($patch in $existingPatches) {
            Copy-Item -LiteralPath $patch.FullName -Destination $backupDir -Force
        }

        Write-Host
        Write-Host "Backed up previous patches to:"
        Write-Host "  $backupDir"
    }

    Get-ChildItem -Path $PatchDir -Filter "*.patch" -File -ErrorAction SilentlyContinue |
        Remove-Item -Force

    foreach ($patch in $newPatches) {
        Copy-Item -LiteralPath $patch.FullName -Destination $PatchDir -Force
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
