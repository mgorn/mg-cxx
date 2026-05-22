<#
.SYNOPSIS
Clones or updates the LLVM checkout and creates the clang-mg build branch.

.USAGE
pwsh -File scripts/clone-llvm.ps1 <llvm-url> <llvm-ref> <llvm-dir>

.EXAMPLE
pwsh -File scripts/clone-llvm.ps1 https://github.com/llvm/llvm-project.git llvmorg-20.1.0 work/llvm-project
#>

param(
    [Parameter(Mandatory = $true, Position = 0)]
    [string]$LLVMUrl,

    [Parameter(Mandatory = $true, Position = 1)]
    [string]$LLVMRef,

    [Parameter(Mandatory = $true, Position = 2)]
    [string]$LLVMDir
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Invoke-Native {
    param(
        [Parameter(Mandatory = $true)]
        [string]$FilePath,

        [Parameter(ValueFromRemainingArguments = $true)]
        [string[]]$Arguments
    )

    & $FilePath @Arguments

    if ($LASTEXITCODE -ne 0) {
        throw "Command failed with exit code ${LASTEXITCODE}: $FilePath $($Arguments -join ' ')"
    }
}

if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    throw "git was not found. Please install Git and make sure it is available in PATH."
}

$GitDir = Join-Path $LLVMDir ".git"

if (-not (Test-Path -LiteralPath $GitDir -PathType Container)) {
    Write-Host "Cloning LLVM..."

    $ParentDir = Split-Path -Parent $LLVMDir
    if ([string]::IsNullOrWhiteSpace($ParentDir)) {
        $ParentDir = "."
    }

    New-Item -ItemType Directory -Force -Path $ParentDir | Out-Null
    Invoke-Native git clone $LLVMUrl $LLVMDir
} else {
    Write-Host "LLVM checkout already exists."
}

Push-Location $LLVMDir
try {
    Write-Host "Fetching LLVM updates..."
    Invoke-Native git fetch origin --tags

    Write-Host "Checking out LLVM ref: $LLVMRef"
    Invoke-Native git checkout $LLVMRef

    Write-Host "Resetting working tree..."
    Invoke-Native git reset --hard

    Write-Host "Creating clang-mg build branch..."
    Invoke-Native git checkout -B clang-mg-build
} finally {
    Pop-Location
}
