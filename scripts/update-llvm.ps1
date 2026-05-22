param()

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Get-EnvOrDefault {
    param(
        [string]$Name,
        [string]$DefaultValue
    )

    $value = [Environment]::GetEnvironmentVariable($Name)

    if ([string]::IsNullOrWhiteSpace($value)) {
        return $DefaultValue
    }

    return $value
}

function Invoke-Git {
    param(
        [Parameter(ValueFromRemainingArguments = $true)]
        [string[]]$Arguments
    )

    & git @Arguments

    if ($LASTEXITCODE -ne 0) {
        throw "git $($Arguments -join ' ') failed with exit code $LASTEXITCODE"
    }
}

function Test-GitCommand {
    param(
        [Parameter(ValueFromRemainingArguments = $true)]
        [string[]]$Arguments
    )

    & git @Arguments *> $null
    return $LASTEXITCODE -eq 0
}

function Get-GitOutput {
    param(
        [Parameter(ValueFromRemainingArguments = $true)]
        [string[]]$Arguments
    )

    $output = & git @Arguments

    if ($LASTEXITCODE -ne 0) {
        throw "git $($Arguments -join ' ') failed with exit code $LASTEXITCODE"
    }

    return ($output -join "`n").Trim()
}

function Get-GitDir {
    $gitDir = & git rev-parse --git-dir 2>$null

    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace(($gitDir -join "`n"))) {
        throw "Could not resolve git directory."
    }

    $gitDir = ($gitDir | Select-Object -First 1).Trim()

    if ([System.IO.Path]::IsPathRooted($gitDir)) {
        return $gitDir
    }

    return (Resolve-Path $gitDir).Path
}

function Test-LlvmCheckout {
    param(
        [string]$Path
    )

    if (-not (Test-Path $Path)) {
        return $false
    }

    & git -C $Path rev-parse --is-inside-work-tree *> $null
    return $LASTEXITCODE -eq 0
}

$ScriptDir = $PSScriptRoot

if ([string]::IsNullOrWhiteSpace($ScriptDir)) {
    $ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
}

$RootDir = (Resolve-Path (Join-Path $ScriptDir "..")).Path

$LlvmUrl = Get-EnvOrDefault "LLVM_URL" "https://github.com/llvm/llvm-project.git"
$LlvmRef = Get-EnvOrDefault "LLVM_REF" "main"

$WorkDir = Get-EnvOrDefault "WORK_DIR" (Join-Path $RootDir "work")
$LlvmDir = Get-EnvOrDefault "LLVM_DIR" (Join-Path $WorkDir "llvm-project")

$CloneScript = Join-Path $ScriptDir "clone-llvm.ps1"

Write-Host "=== update LLVM ==="
Write-Host "LLVM ref:  $LlvmRef"
Write-Host "LLVM dir:  $LlvmDir"
Write-Host

if (-not (Test-LlvmCheckout $LlvmDir)) {
    Write-Host "LLVM is not cloned yet."

    if (-not (Test-Path $CloneScript)) {
        Write-Host "ERROR: clone script not found:"
        Write-Host $CloneScript
        Write-Host
        Write-Host "Expected PowerShell clone script:"
        Write-Host "  scripts/clone-llvm.ps1"
        exit 1
    }

    Write-Host "Calling clone-llvm.ps1..."
    & $CloneScript $LlvmUrl $LlvmRef $LlvmDir

    if ($LASTEXITCODE -ne 0) {
        exit $LASTEXITCODE
    }

    exit 0
}

Set-Location $LlvmDir

Write-Host "Checking LLVM working tree..."

$GitDir = Get-GitDir

# Check for unfinished git operations first.
if ((Test-Path (Join-Path $GitDir "rebase-merge")) -or (Test-Path (Join-Path $GitDir "rebase-apply"))) {
    Write-Host "ERROR: A rebase is currently in progress."
    Write-Host "Finish or abort it before updating LLVM."
    exit 1
}

if (Test-Path (Join-Path $GitDir "MERGE_HEAD")) {
    Write-Host "ERROR: A merge is currently in progress."
    Write-Host "Finish or abort it before updating LLVM."
    exit 1
}

if ((Test-Path (Join-Path $GitDir "rebase-apply")) -or (Test-Path (Join-Path $GitDir "CHERRY_PICK_HEAD"))) {
    Write-Host "ERROR: A cherry-pick or patch application is currently in progress."
    Write-Host "Finish or abort it before updating LLVM."
    exit 1
}

# Check for uncommitted changes.
$status = & git status --porcelain

if ($LASTEXITCODE -ne 0) {
    Write-Host "ERROR: Failed to check git status."
    exit 1
}

if (-not [string]::IsNullOrWhiteSpace(($status -join "`n"))) {
    Write-Host "ERROR: LLVM has uncommitted changes."
    Write-Host
    Write-Host "You may be working on a feature patch right now."
    Write-Host "Save your feature patches before updating LLVM."
    Write-Host
    Write-Host "Useful commands:"
    Write-Host "  git status"
    Write-Host "  git diff"
    Write-Host "  git add ."
    Write-Host "  git commit -m `"clang-mg: describe feature`""
    Write-Host "  ../clang-mg/scripts/save-feature.ps1 <feature-name> $LlvmRef"
    Write-Host
    Write-Host "Update cancelled."
    exit 1
}

Write-Host "LLVM working tree is clean."
Write-Host

Write-Host "Fetching latest LLVM changes..."
Invoke-Git fetch origin --tags

$currentBranch = & git branch --show-current 2>$null

if ($LASTEXITCODE -ne 0) {
    $currentBranch = ""
}

$currentBranch = "$currentBranch".Trim()

if ([string]::IsNullOrWhiteSpace($currentBranch)) {
    Write-Host "LLVM checkout is detached."
    Write-Host "Checking out requested ref: $LlvmRef"
    Invoke-Git checkout $LlvmRef

    $currentBranch = & git branch --show-current 2>$null

    if ($LASTEXITCODE -ne 0) {
        $currentBranch = ""
    }

    $currentBranch = "$currentBranch".Trim()

    if ([string]::IsNullOrWhiteSpace($currentBranch)) {
        Write-Host "Still detached after checkout."
        Write-Host "Fetch complete, but there is no branch to pull."
        Write-Host "LLVM is at:"
        Invoke-Git --no-pager log --oneline -1
        exit 0
    }
}

Write-Host "Current branch: $currentBranch"

$upstream = & git rev-parse --abbrev-ref --symbolic-full-name "@{u}" 2>$null

if ($LASTEXITCODE -ne 0) {
    $upstream = ""
}

$upstream = "$upstream".Trim()

if (-not [string]::IsNullOrWhiteSpace($upstream)) {
    Write-Host "Pulling from upstream: $upstream"
    Invoke-Git pull --ff-only
}
else {
    Write-Host "No upstream is configured for branch: $currentBranch"

    if (Test-GitCommand show-ref --verify --quiet "refs/remotes/origin/$currentBranch") {
        Write-Host "Found matching remote branch: origin/$currentBranch"
        Write-Host "Pulling with fast-forward only..."
        Invoke-Git pull --ff-only origin $currentBranch
    }
    else {
        Write-Host "No matching remote branch found."
        Write-Host "Fetch completed, but nothing was pulled."
        Write-Host
        Write-Host "You can manually update with something like:"
        Write-Host "  git checkout main"
        Write-Host "  git pull --ff-only origin main"
        exit 0
    }
}

Write-Host
Write-Host "LLVM updated successfully."
Invoke-Git --no-pager log --oneline -1
