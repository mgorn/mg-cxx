Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$ScriptDir = if ($PSScriptRoot) {
    $PSScriptRoot
} else {
    Split-Path -Parent $MyInvocation.MyCommand.Path
}

$RootDir = Split-Path -Parent $ScriptDir

$WorkDir = if ($env:WORK_DIR) {
    $env:WORK_DIR
} else {
    Join-Path $RootDir "work"
}

$LlvmDir = if ($env:LLVM_DIR) {
    $env:LLVM_DIR
} else {
    Join-Path $WorkDir "llvm-project"
}

$FeatureName = if ($args.Count -ge 1) {
    $args[0]
} else {
    ""
}

# Set to 0 if you want to apply patches without rewriting the patch files.
$RefreshPatches = if ($env:REFRESH_PATCHES) {
    $env:REFRESH_PATCHES
} else {
    "1"
}

function Show-Usage {
    @"
Usage:
  scripts/apply-feature.ps1 <feature-name>

Examples:
  scripts/apply-feature.ps1 core
  scripts/apply-feature.ps1 curlinclude
  scripts/apply-feature.ps1 if-constexpr-members

Environment variables:
  LLVM_DIR=$LlvmDir
  WORK_DIR=$WorkDir
  REFRESH_PATCHES=$RefreshPatches

Conflict workflow:
  If git am hits a conflict, this script will pause.
  Resolve the conflict, run git add on the fixed files, then choose continue.
  After all patches apply, the feature patch directory is refreshed automatically.
"@ | Write-Host
}

function Show-Features {
    Write-Host "Available features:"

    $PatchesRoot = Join-Path $RootDir "patches"

    if (-not (Test-Path $PatchesRoot -PathType Container)) {
        Write-Host "  No patches directory found."
        return
    }

    Get-ChildItem -Path $PatchesRoot -Directory |
        Sort-Object Name |
        ForEach-Object { Write-Host "  $($_.Name)" }
}

function Show-ConflictHelp {
    @"

A patch conflict happened.

Resolve it like this:

  1. Open the conflicted files and fix the conflict markers.
  2. Check the result:
       git status
       git diff
  3. Stage the resolved files:
       git add <files>
  4. Come back here and choose:
       c) continue

Useful commands:

  git am --show-current-patch=diff
  git status
  git diff
  git diff --name-only --diff-filter=U

"@ | Write-Host
}

function Open-ResolutionShell {
    Write-Host ""
    Write-Host "Opening a shell in:"
    Write-Host "  $LlvmDir"
    Write-Host ""
    Write-Host "When done resolving conflicts, exit the shell to return here."
    Write-Host ""

    $shellCommand = $null

    if (Get-Command pwsh -ErrorAction SilentlyContinue) {
        $shellCommand = "pwsh"
    } elseif (Get-Command powershell -ErrorAction SilentlyContinue) {
        $shellCommand = "powershell"
    } elseif ($env:SHELL) {
        $shellCommand = $env:SHELL
    } else {
        Write-Host "ERROR: Could not find a shell to open."
        return
    }

    & $shellCommand
}

function Continue-Am {
    Write-Host ""
    Write-Host "Continuing git am..."

    & git am --continue
    if ($LASTEXITCODE -eq 0) {
        Write-Host "git am completed successfully."
        return $true
    }

    Write-Host ""
    Write-Host "git am still needs attention."
    return $false
}

function Skip-Am {
    Write-Host ""
    Write-Host "Skipping current patch..."

    & git am --skip
    if ($LASTEXITCODE -eq 0) {
        Write-Host "Patch skipped and git am completed successfully."
        return $true
    }

    Write-Host ""
    Write-Host "git am still needs attention."
    return $false
}

function Invoke-InteractiveAmResolution {
    Show-ConflictHelp

    if (-not [Environment]::UserInteractive) {
        Write-Host "ERROR: No interactive terminal is available."
        Write-Host ""
        Write-Host "Resolve manually inside LLVM with:"
        Write-Host "  git status"
        Write-Host "  git diff --name-only --diff-filter=U"
        Write-Host "  git add <files>"
        Write-Host "  git am --continue"
        Write-Host ""
        Write-Host "Or abort with:"
        Write-Host "  git am --abort"
        return $false
    }

    while (Test-Path ".git/rebase-apply" -PathType Container) {
        @"

Conflict menu:
  s) show status
  u) show unresolved files
  p) show current patch
  d) show diff
  a) git add -A
  c) continue git am
  k) skip current patch
  x) abort git am
  sh) open shell

"@ | Write-Host

        try {
            $choice = Read-Host "Choose an action"
        } catch {
            Write-Host ""
            Write-Host "ERROR: Could not read from terminal."
            Write-Host "Leaving git am in progress so you can resolve it manually."
            return $false
        }

        switch ($choice) {
            "s" {
                & git status
            }
            "u" {
                & git diff --name-only --diff-filter=U
            }
            "p" {
                & git --no-pager am --show-current-patch=diff
            }
            "d" {
                & git diff
            }
            "a" {
                & git add -A
                if ($LASTEXITCODE -ne 0) {
                    Write-Host "git add failed."
                } else {
                    Write-Host "Staged all changes."
                }
            }
            "c" {
                if (Continue-Am) {
                    return $true
                }
            }
            "k" {
                if (Skip-Am) {
                    return $true
                }
            }
            "x" {
                Write-Host ""
                Write-Host "Aborting git am..."
                & git am --abort
                return $false
            }
            "sh" {
                Open-ResolutionShell
            }
            "" {
                Write-Host "No option entered."
            }
            default {
                Write-Host "Unknown option: $choice"
            }
        }
    }

    return $true
}

function Refresh-FeaturePatches {
    param(
        [Parameter(Mandatory = $true)]
        [string]$StartCommit
    )

    if ($RefreshPatches -ne "1") {
        Write-Host ""
        Write-Host "Skipping patch refresh because REFRESH_PATCHES=$RefreshPatches"
        return
    }

    Write-Host ""
    Write-Host "Refreshing feature patches from applied commits..."

    $TempDir = Join-Path $RootDir (".patch-refresh-$FeatureName." + [Guid]::NewGuid().ToString("N"))
    New-Item -ItemType Directory -Path $TempDir -Force | Out-Null

    & git format-patch --zero-commit --no-stat --output-directory $TempDir "$StartCommit..HEAD" *> $null
    if ($LASTEXITCODE -ne 0) {
        Write-Host "ERROR: Failed to regenerate patches."
        Remove-Item -Path $TempDir -Recurse -Force -ErrorAction SilentlyContinue
        exit 1
    }

    $RegeneratedPatches = @(Get-ChildItem -Path $TempDir -Filter "*.patch" -File | Sort-Object Name)
    if ($RegeneratedPatches.Count -eq 0) {
        Write-Host "ERROR: No regenerated patches were produced."
        Remove-Item -Path $TempDir -Recurse -Force -ErrorAction SilentlyContinue
        exit 1
    }

    $BackupDir = "$PatchDir.backup.$(Get-Date -Format 'yyyyMMdd-HHmmss')"

    New-Item -ItemType Directory -Path $BackupDir -Force | Out-Null
    Copy-Item -Path (Join-Path $PatchDir "*.patch") -Destination $BackupDir -Force

    Remove-Item -Path (Join-Path $PatchDir "*.patch") -Force
    Copy-Item -Path (Join-Path $TempDir "*.patch") -Destination $PatchDir -Force
    Remove-Item -Path $TempDir -Recurse -Force

    Write-Host ""
    Write-Host "Updated patch collection:"
    Write-Host "  $PatchDir"
    Write-Host ""
    Write-Host "Backup of old patches:"
    Write-Host "  $BackupDir"
}

if ($FeatureName -eq "-h" -or $FeatureName -eq "--help" -or [string]::IsNullOrWhiteSpace($FeatureName)) {
    Show-Usage
    Write-Host ""
    Show-Features
    exit 0
}

if ($FeatureName -eq "list" -or $FeatureName -eq "--list") {
    Show-Features
    exit 0
}

$PatchDir = Join-Path (Join-Path $RootDir "patches") $FeatureName

Write-Host "=== apply feature ==="
Write-Host "Feature:   $FeatureName"
Write-Host "Patch dir: $PatchDir"
Write-Host "LLVM dir:  $LlvmDir"
Write-Host ""

if (-not (Test-Path (Join-Path $LlvmDir ".git") -PathType Container)) {
    Write-Host "ERROR: LLVM repo is not cloned:"
    Write-Host "$LlvmDir"
    Write-Host ""
    Write-Host "Run:"
    Write-Host "  ./build.ps1 clone"
    Write-Host ""
    Write-Host "or:"
    Write-Host "  ./build.ps1 bootstrap"
    exit 1
}

if (-not (Test-Path $PatchDir -PathType Container)) {
    Write-Host "ERROR: Feature patch directory does not exist:"
    Write-Host "$PatchDir"
    Write-Host ""
    Show-Features
    exit 1
}

$Patches = @(Get-ChildItem -Path $PatchDir -Filter "*.patch" -File | Sort-Object Name)
if ($Patches.Count -eq 0) {
    Write-Host "ERROR: No .patch files found in:"
    Write-Host "$PatchDir"
    exit 1
}

Push-Location $LlvmDir
try {
    if (Test-Path ".git/rebase-merge" -PathType Container) {
        Write-Host "ERROR: A rebase is currently in progress."
        Write-Host "Finish or abort it before applying feature patches."
        exit 1
    }

    if (Test-Path ".git/rebase-apply" -PathType Container) {
        Write-Host "ERROR: A patch application or rebase is already in progress."
        Write-Host ""
        Write-Host "Run one of these inside LLVM first:"
        Write-Host "  git am --continue"
        Write-Host "  git am --abort"
        Write-Host "  git rebase --continue"
        Write-Host "  git rebase --abort"
        exit 1
    }

    if (Test-Path ".git/MERGE_HEAD" -PathType Leaf) {
        Write-Host "ERROR: A merge is currently in progress."
        Write-Host "Finish or abort it before applying feature patches."
        exit 1
    }

    if (Test-Path ".git/CHERRY_PICK_HEAD" -PathType Leaf) {
        Write-Host "ERROR: A cherry-pick is currently in progress."
        Write-Host "Finish or abort it before applying feature patches."
        exit 1
    }

    $GitStatus = & git status --porcelain
    if ($LASTEXITCODE -ne 0) {
        Write-Host "ERROR: Failed to read git status."
        exit 1
    }

    if ($GitStatus) {
        Write-Host "ERROR: LLVM has uncommitted changes."
        Write-Host ""
        Write-Host "Save or commit your current work before applying feature patches."
        Write-Host ""
        Write-Host "Useful commands:"
        Write-Host "  git status"
        Write-Host "  git diff"
        Write-Host "  git add ."
        Write-Host '  git commit -m "clang-mg: describe current work"'
        Write-Host ""
        Write-Host "Apply cancelled."
        exit 1
    }

    $PatchPaths = @($Patches | ForEach-Object { $_.FullName })
    $StartCommit = (& git rev-parse HEAD).Trim()
    if ($LASTEXITCODE -ne 0) {
        Write-Host "ERROR: Failed to read current commit."
        exit 1
    }

    Write-Host "Applying feature patches..."

    & git am --3way @PatchPaths
    if ($LASTEXITCODE -ne 0) {
        if (Test-Path ".git/rebase-apply" -PathType Container) {
            if (-not (Invoke-InteractiveAmResolution)) {
                Write-Host ""
                Write-Host "Apply cancelled."
                exit 1
            }
        } else {
            Write-Host ""
            Write-Host "ERROR: git am failed, but no patch application state was found."
            exit 1
        }
    }

    Write-Host ""
    Write-Host "Applied feature successfully: $FeatureName"

    Refresh-FeaturePatches -StartCommit $StartCommit

    Write-Host ""
    Write-Host "Recent commits:"
    & git --no-pager log --oneline -5
} finally {
    Pop-Location
}
