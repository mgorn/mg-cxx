[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [string]$InputPath = "",

    [Alias("h")]
    [switch]$Help
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$ScriptDir = Split-Path -Parent $PSCommandPath
$RootDir = [System.IO.Path]::GetFullPath((Join-Path $ScriptDir ".."))

$ClangSuffix = if ($env:CLANG_SUFFIX) { $env:CLANG_SUFFIX } else { "mg" }
$WorkDir = if ($env:WORK_DIR) { $env:WORK_DIR } else { Join-Path $RootDir "work" }
$BuildDir = if ($env:BUILD_DIR) { $env:BUILD_DIR } else { Join-Path $WorkDir "build" }
$ProfileFile = if ($env:PROFILE_FILE) { $env:PROFILE_FILE } else { "" }

# Windows behavior:
#   Auto    = Machine PATH if elevated. If not elevated, ask to elevate. If declined, User PATH.
#   User    = persistent PATH for current user.
#   Machine = machine-wide PATH. If not elevated, ask to elevate.
#   Global  = alias for Machine.
#   Both    = User PATH plus Machine PATH, asking to elevate if needed.
$PathScope = if ($env:CLANG_MG_PATH_SCOPE) { $env:CLANG_MG_PATH_SCOPE } else { "Auto" }

$MarkerBegin = "# >>> clang-mg path >>>"
$MarkerEnd = "# <<< clang-mg path <<<"
$LegacyMarker = "# Added by build-clang-mg.sh"
$ExeBaseName = "clang-$ClangSuffix"

function Show-Usage {
    Write-Host @"
Usage:
  scripts/install-clang-mg.ps1 [clang-mg-executable | build-dir | bin-dir]

Examples:
  scripts/install-clang-mg.ps1
  scripts/install-clang-mg.ps1 work/build/bin/clang-mg.exe
  scripts/install-clang-mg.ps1 work/build
  scripts/install-clang-mg.ps1 work/build/bin

Environment variables:
  CLANG_SUFFIX=mg
  BUILD_DIR=$BuildDir
  PROFILE_FILE=<custom shell/profile path>
  CLANG_MG_PATH_SCOPE=Auto|User|Machine|Global|Both

Windows behavior:
  Auto:
    Uses Machine PATH if running as Administrator.
    If not elevated, asks to elevate through UAC.
    If elevation is declined, falls back to User PATH.

  Machine / Global:
    Adds clang-mg to the machine-wide PATH.
    If not elevated, asks to elevate through UAC.

  User:
    Adds clang-mg to the persistent PATH for the current Windows user.

  Both:
    Adds clang-mg to User PATH.
    Also asks to elevate for Machine PATH if needed.

Important:
  Existing cmd.exe windows do not update their PATH after this script runs.
  Open a brand-new terminal after install.
"@
}

function Test-IsWindowsPlatform {
    return $env:OS -eq "Windows_NT"
}

function Test-IsMacOSPlatform {
    if (Get-Variable -Name IsMacOS -Scope Global -ErrorAction SilentlyContinue) {
        return $IsMacOS
    }

    return [System.Runtime.InteropServices.RuntimeInformation]::IsOSPlatform(
        [System.Runtime.InteropServices.OSPlatform]::OSX
    )
}

function Test-IsAdministrator {
    if (-not (Test-IsWindowsPlatform)) {
        return $false
    }

    $identity = [System.Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [System.Security.Principal.WindowsPrincipal]::new($identity)
    return $principal.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Test-CanPrompt {
    try {
        return [Environment]::UserInteractive -and -not [Console]::IsInputRedirected
    }
    catch {
        return $false
    }
}

function Escape-PowerShellSingleQuotedString {
    param([Parameter(Mandatory = $true)][string]$Value)

    return $Value.Replace("'", "''")
}

function Get-PowerShellExecutable {
    $currentProcessPath = (Get-Process -Id $PID).Path

    if (-not [string]::IsNullOrWhiteSpace($currentProcessPath) -and (Test-Path $currentProcessPath -PathType Leaf)) {
        return $currentProcessPath
    }

    $pwsh = Get-Command "pwsh.exe" -ErrorAction SilentlyContinue

    if ($pwsh) {
        return $pwsh.Source
    }

    $powershell = Get-Command "powershell.exe" -ErrorAction SilentlyContinue

    if ($powershell) {
        return $powershell.Source
    }

    return "powershell.exe"
}

function Convert-ToEncodedPowerShellCommand {
    param([Parameter(Mandatory = $true)][string]$Command)

    $bytes = [System.Text.Encoding]::Unicode.GetBytes($Command)
    return [Convert]::ToBase64String($bytes)
}

function Start-ElevatedInstall {
    param(
        [Parameter(Mandatory = $true)][string]$ResolvedInputPath,
        [Parameter(Mandatory = $true)][string]$TargetScope
    )

    if (-not (Test-IsWindowsPlatform)) {
        return $false
    }

    $scriptPath = [System.IO.Path]::GetFullPath($PSCommandPath)
    $workingDirectory = (Get-Location).Path
    $escapedScriptPath = Escape-PowerShellSingleQuotedString $scriptPath
    $escapedInputPath = Escape-PowerShellSingleQuotedString $ResolvedInputPath
    $escapedTargetScope = Escape-PowerShellSingleQuotedString $TargetScope
    $escapedClangSuffix = Escape-PowerShellSingleQuotedString $ClangSuffix
    $escapedBuildDir = Escape-PowerShellSingleQuotedString $BuildDir

    $command = @"
`$ErrorActionPreference = 'Stop'
`$env:CLANG_MG_PATH_SCOPE = '$escapedTargetScope'
`$env:CLANG_SUFFIX = '$escapedClangSuffix'
`$env:BUILD_DIR = '$escapedBuildDir'
& '$escapedScriptPath' '$escapedInputPath'
`$exitCode = `$LASTEXITCODE
Write-Host ''
Write-Host 'Elevated clang-mg PATH install finished. Press Enter to close this window.'
try { [void](Read-Host) } catch {}
exit `$exitCode
"@

    $encoded = Convert-ToEncodedPowerShellCommand $command
    $psExe = Get-PowerShellExecutable

    try {
        Start-Process `
            -FilePath $psExe `
            -ArgumentList @("-NoProfile", "-ExecutionPolicy", "Bypass", "-EncodedCommand", $encoded) `
            -WorkingDirectory $workingDirectory `
            -Verb RunAs | Out-Null

        return $true
    }
    catch {
        Write-Host "Elevation was cancelled or failed: $($_.Exception.Message)" -ForegroundColor Yellow
        return $false
    }
}

function Request-ElevationForMachinePath {
    param([Parameter(Mandatory = $true)][string]$ResolvedInputPath)

    if (Test-IsAdministrator) {
        return $false
    }

    if (-not (Test-CanPrompt)) {
        Write-Host "Machine PATH install requires Administrator, but this session cannot prompt for elevation." -ForegroundColor Yellow
        return $false
    }

    Write-Host
    Write-Host "Adding clang-mg to the global Machine PATH requires Administrator privileges."
    $answer = Read-Host "Relaunch this installer elevated through UAC now? [Y/n]"

    if ([string]::IsNullOrWhiteSpace($answer) -or $answer -match '^(y|Y|yes|YES|Yes)$') {
        if (Start-ElevatedInstall $ResolvedInputPath "Machine") {
            Write-Host
            Write-Host "Elevated installer launched."
            Write-Host "Approve the UAC prompt, then open a brand-new terminal and run:"
            Write-Host "  where $ExeBaseName"
            Write-Host "  $ExeBaseName --version"
            return $true
        }
    }

    return $false
}

function Get-ShellName {
    if ($env:SHELL) {
        return [System.IO.Path]::GetFileName($env:SHELL)
    }

    if (Test-IsWindowsPlatform) {
        return "powershell"
    }

    return "sh"
}

function Get-DetectedShellProfile {
    $shellName = Get-ShellName

    switch ($shellName) {
        "zsh" {
            return Join-Path $HOME ".zshrc"
        }
        "bash" {
            if (Test-IsMacOSPlatform) {
                return Join-Path $HOME ".bash_profile"
            }

            return Join-Path $HOME ".bashrc"
        }
        "fish" {
            return Join-Path $HOME ".config/fish/config.fish"
        }
        default {
            if (Test-IsWindowsPlatform) {
                return $PROFILE
            }

            return Join-Path $HOME ".profile"
        }
    }
}

function Test-FileExists {
    param([Parameter(Mandatory = $true)][string]$Path)
    return [System.IO.File]::Exists([System.IO.Path]::GetFullPath($Path))
}

function Resolve-FullPathLoose {
    param([Parameter(Mandatory = $true)][string]$Path)

    if ([System.IO.Path]::IsPathRooted($Path)) {
        return [System.IO.Path]::GetFullPath($Path)
    }

    return [System.IO.Path]::GetFullPath((Join-Path (Get-Location) $Path))
}

function Get-ClangExeCandidatesInDir {
    param([Parameter(Mandatory = $true)][string]$Dir)

    $candidates = @()

    if (Test-IsWindowsPlatform) {
        $candidates += (Join-Path $Dir "$ExeBaseName.exe")
    }

    $candidates += (Join-Path $Dir $ExeBaseName)

    if (-not (Test-IsWindowsPlatform)) {
        $candidates += (Join-Path $Dir "$ExeBaseName.exe")
    }

    return $candidates
}

function Resolve-ClangExePath {
    param([string]$PathValue)

    if ([string]::IsNullOrWhiteSpace($PathValue)) {
        $binDir = Join-Path $BuildDir "bin"

        foreach ($candidate in Get-ClangExeCandidatesInDir $binDir) {
            if (Test-FileExists $candidate) {
                return (Resolve-FullPathLoose $candidate)
            }
        }

        if (Test-IsWindowsPlatform) {
            return (Resolve-FullPathLoose (Join-Path $binDir "$ExeBaseName.exe"))
        }

        return (Resolve-FullPathLoose (Join-Path $binDir $ExeBaseName))
    }

    $fullInputPath = Resolve-FullPathLoose $PathValue

    if ([System.IO.Directory]::Exists($fullInputPath)) {
        $nestedBinDir = Join-Path $fullInputPath "bin"

        if ([System.IO.Directory]::Exists($nestedBinDir)) {
            foreach ($candidate in Get-ClangExeCandidatesInDir $nestedBinDir) {
                if (Test-FileExists $candidate) {
                    return (Resolve-FullPathLoose $candidate)
                }
            }
        }

        foreach ($candidate in Get-ClangExeCandidatesInDir $fullInputPath) {
            if (Test-FileExists $candidate) {
                return (Resolve-FullPathLoose $candidate)
            }
        }
    }

    return $fullInputPath
}

function Get-ComparablePath {
    param([Parameter(Mandatory = $true)][string]$Path)

    $fullPath = Resolve-FullPathLoose $Path
    $trimmed = $fullPath.TrimEnd(
        [System.IO.Path]::DirectorySeparatorChar,
        [System.IO.Path]::AltDirectorySeparatorChar
    )

    if (Test-IsWindowsPlatform) {
        return $trimmed.ToLowerInvariant()
    }

    return $trimmed
}

function Test-PathListContainsDir {
    param(
        [string]$PathValue,
        [Parameter(Mandatory = $true)][string]$Dir
    )

    if ([string]::IsNullOrWhiteSpace($PathValue)) {
        return $false
    }

    $target = Get-ComparablePath $Dir
    $parts = $PathValue -split [regex]::Escape([System.IO.Path]::PathSeparator)

    foreach ($part in $parts) {
        if ([string]::IsNullOrWhiteSpace($part)) {
            continue
        }

        try {
            if ((Get-ComparablePath $part) -eq $target) {
                return $true
            }
        }
        catch {
            continue
        }
    }

    return $false
}

function Add-DirToCurrentProcessPath {
    param([Parameter(Mandatory = $true)][string]$BinDir)

    if (-not (Test-PathListContainsDir $env:Path $BinDir)) {
        if ([string]::IsNullOrEmpty($env:Path)) {
            $env:Path = $BinDir
        }
        else {
            $env:Path = "$BinDir$([System.IO.Path]::PathSeparator)$env:Path"
        }
    }
}

function Send-WindowsEnvironmentChanged {
    if (-not (Test-IsWindowsPlatform)) {
        return
    }

    $typeName = "ClangMg.NativeMethods"

    if (-not ($typeName -as [type])) {
        Add-Type @"
using System;
using System.Runtime.InteropServices;

namespace ClangMg {
    public static class NativeMethods {
        [DllImport("user32.dll", SetLastError = true, CharSet = CharSet.Auto)]
        public static extern IntPtr SendMessageTimeout(
            IntPtr hWnd,
            UInt32 Msg,
            UIntPtr wParam,
            string lParam,
            UInt32 fuFlags,
            UInt32 uTimeout,
            out UIntPtr lpdwResult
        );
    }
}
"@
    }

    $hwndBroadcast = [IntPtr]0xffff
    $wmSettingChange = 0x001A
    $smtoAbortIfHung = 0x0002
    $result = [UIntPtr]::Zero

    [void][ClangMg.NativeMethods]::SendMessageTimeout(
        $hwndBroadcast,
        $wmSettingChange,
        [UIntPtr]::Zero,
        "Environment",
        $smtoAbortIfHung,
        5000,
        [ref]$result
    )
}

function Add-WindowsPathTarget {
    param(
        [Parameter(Mandatory = $true)][string]$BinDir,
        [Parameter(Mandatory = $true)]
        [ValidateSet("User", "Machine")]
        [string]$TargetName
    )

    $target = if ($TargetName -eq "Machine") {
        [System.EnvironmentVariableTarget]::Machine
    }
    else {
        [System.EnvironmentVariableTarget]::User
    }

    if ($TargetName -eq "Machine" -and -not (Test-IsAdministrator)) {
        throw "Machine PATH install requires Administrator."
    }

    $currentPath = [System.Environment]::GetEnvironmentVariable("Path", $target)

    if (Test-PathListContainsDir $currentPath $BinDir) {
        Write-Host "clang-mg bin directory is already in the persistent $TargetName PATH."
    }
    else {
        if ([string]::IsNullOrWhiteSpace($currentPath)) {
            $updatedPath = $BinDir
        }
        else {
            $updatedPath = "$BinDir$([System.IO.Path]::PathSeparator)$currentPath"
        }

        [System.Environment]::SetEnvironmentVariable("Path", $updatedPath, $target)
        Write-Host "Added clang-mg bin directory to the persistent $TargetName PATH."
    }

    $verifiedPath = [System.Environment]::GetEnvironmentVariable("Path", $target)

    if (-not (Test-PathListContainsDir $verifiedPath $BinDir)) {
        throw "PATH update failed. $BinDir was not found in the persistent $TargetName PATH after writing it."
    }

    Write-Host "Verified persistent $TargetName PATH contains:"
    Write-Host "  $BinDir"
}

function Add-WindowsPersistentPath {
    param(
        [Parameter(Mandatory = $true)][string]$BinDir,
        [Parameter(Mandatory = $true)][string]$ResolvedInputPath
    )

    switch -Regex ($PathScope) {
        '^(Auto|auto|AUTO)$' {
            if (Test-IsAdministrator) {
                Add-WindowsPathTarget $BinDir "Machine"
            }
            else {
                if (Request-ElevationForMachinePath $ResolvedInputPath) {
                    exit 0
                }

                Write-Host
                Write-Host "Falling back to persistent User PATH."
                Add-WindowsPathTarget $BinDir "User"
            }
            break
        }

        '^(User|user|USER)$' {
            Add-WindowsPathTarget $BinDir "User"
            break
        }

        '^(Machine|machine|MACHINE|Global|global|GLOBAL)$' {
            if (-not (Test-IsAdministrator)) {
                if (Request-ElevationForMachinePath $ResolvedInputPath) {
                    exit 0
                }

                throw "Machine PATH install requires Administrator and elevation was not completed."
            }

            Add-WindowsPathTarget $BinDir "Machine"
            break
        }

        '^(Both|both|BOTH)$' {
            Add-WindowsPathTarget $BinDir "User"

            if (Test-IsAdministrator) {
                Add-WindowsPathTarget $BinDir "Machine"
            }
            else {
                if (Request-ElevationForMachinePath $ResolvedInputPath) {
                    exit 0
                }

                Write-Host "Machine PATH was not updated because elevation was not completed."
            }
            break
        }

        default {
            throw "Invalid CLANG_MG_PATH_SCOPE value: $PathScope. Use Auto, User, Machine, Global, or Both."
        }
    }

    Add-DirToCurrentProcessPath $BinDir
    Send-WindowsEnvironmentChanged

    Write-Host
    Write-Host "Current process PATH now contains:"
    Write-Host "  $BinDir"
}

function Escape-ShDoubleQuotedString {
    param([Parameter(Mandatory = $true)][string]$Value)

    return $Value.Replace("\", "\\").Replace('"', '\"').Replace('$', '\$').Replace('`', '\`')
}

function Remove-OldBlocks {
    param([Parameter(Mandatory = $true)][string]$FilePath)

    if (-not (Test-Path -LiteralPath $FilePath -PathType Leaf)) {
        return
    }

    $shellName = Get-ShellName
    $lines = Get-Content -LiteralPath $FilePath
    $output = New-Object System.Collections.Generic.List[string]
    $inManaged = $false
    $inLegacy = $false
    $legacyDepth = 0

    foreach ($line in $lines) {
        if ($line -eq $MarkerBegin) {
            $inManaged = $true
            continue
        }

        if ($line -eq $MarkerEnd) {
            $inManaged = $false
            continue
        }

        if ($inManaged) {
            continue
        }

        if ($line -eq $LegacyMarker) {
            $inLegacy = $true
            $legacyDepth = 0
            continue
        }

        if ($inLegacy) {
            if ($shellName -eq "fish") {
                if ($line -match '^\s*if\s+') {
                    $legacyDepth++
                }

                if ($line -match '^\s*end\s*$') {
                    $legacyDepth--

                    if ($legacyDepth -le 0) {
                        $inLegacy = $false
                    }
                }

                continue
            }

            if ($line -match '^\s*if\s+\[') {
                $legacyDepth = 1
            }

            if (($line -match '^\s*fi\s*$') -and ($legacyDepth -eq 1)) {
                $inLegacy = $false
                continue
            }

            continue
        }

        $output.Add($line)
    }

    Set-Content -LiteralPath $FilePath -Value $output -Encoding UTF8
}

function Add-ProfilePathBlock {
    param(
        [Parameter(Mandatory = $true)][string]$FilePath,
        [Parameter(Mandatory = $true)][string]$BinDir
    )

    $shellName = Get-ShellName
    $extension = [System.IO.Path]::GetExtension($FilePath)
    $block = ""

    if (($shellName -eq "fish") -and ($extension -ne ".ps1")) {
        $escapedBinDir = Escape-ShDoubleQuotedString $BinDir
        $block = @"

$MarkerBegin
# Added by install-clang-mg.ps1
if test -d "$escapedBinDir"
    if not contains "$escapedBinDir" `$PATH
        set -gx PATH "$escapedBinDir" `$PATH
    end
end
$MarkerEnd
"@
    }
    elseif ($extension -eq ".ps1" -or $shellName -eq "powershell" -or $shellName -eq "pwsh") {
        $escapedBinDir = Escape-PowerShellSingleQuotedString $BinDir
        $block = @"

$MarkerBegin
# Added by install-clang-mg.ps1
`$clangMgBinDir = '$escapedBinDir'
if (Test-Path -LiteralPath `$clangMgBinDir -PathType Container) {
    `$clangMgPathParts = `$env:Path -split [regex]::Escape([System.IO.Path]::PathSeparator)
    if (`$clangMgPathParts -notcontains `$clangMgBinDir) {
        `$env:Path = "`$clangMgBinDir`$([System.IO.Path]::PathSeparator)`$env:Path"
    }
}
$MarkerEnd
"@
    }
    else {
        $escapedBinDir = Escape-ShDoubleQuotedString $BinDir
        $block = @"

$MarkerBegin
# Added by install-clang-mg.ps1
if [ -d "$escapedBinDir" ]; then
    case ":`$PATH:" in
        *":$($escapedBinDir):"*) ;;
        *) export PATH="$($escapedBinDir):`$PATH" ;;
    esac
fi
$MarkerEnd
"@
    }

    Add-Content -LiteralPath $FilePath -Value $block -Encoding UTF8
}

if ($Help) {
    Show-Usage
    exit 0
}

$ExePath = Resolve-ClangExePath $InputPath

if (-not (Test-FileExists $ExePath)) {
    Write-Host "ERROR: Could not find executable ${ExeBaseName}:" -ForegroundColor Red
    Write-Host "  $ExePath"
    Write-Host
    Write-Host "Build clang-mg first, or pass the executable/build directory:"
    Write-Host "  scripts/install-clang-mg.ps1 work/build/bin/$ExeBaseName"
    Write-Host "  scripts/install-clang-mg.ps1 work/build"
    exit 1
}

$ExePath = Resolve-FullPathLoose $ExePath
$BinDir = Split-Path -Parent $ExePath
$BinDir = Resolve-FullPathLoose $BinDir
$ResolvedInputPath = if ([string]::IsNullOrWhiteSpace($InputPath)) { $ExePath } else { Resolve-FullPathLoose $InputPath }

Write-Host "=== install clang-mg ==="
Write-Host "Executable:   $ExePath"
Write-Host "Binary dir:   $BinDir"

if ((Test-IsWindowsPlatform) -and [string]::IsNullOrWhiteSpace($ProfileFile)) {
    Write-Host "PATH target:  Windows $PathScope PATH"
    Write-Host "Admin:        $(if (Test-IsAdministrator) { 'yes' } else { 'no' })"
}
else {
    if ([string]::IsNullOrWhiteSpace($ProfileFile)) {
        $ProfileFile = Get-DetectedShellProfile
    }

    $ProfileFile = Resolve-FullPathLoose $ProfileFile
    Write-Host "Profile file: $ProfileFile"
}

Write-Host
Write-Host "Checking clang-mg..."
try {
    & $ExePath --version
}
catch {
    Write-Host "WARNING: Could not run '$ExePath --version'. Continuing anyway."
}

if ((Test-IsWindowsPlatform) -and [string]::IsNullOrWhiteSpace($env:PROFILE_FILE)) {
    Write-Host
    Write-Host "Updating Windows PATH..."
    Add-WindowsPersistentPath $BinDir $ResolvedInputPath

    Write-Host
    Write-Host "Install complete."
    Write-Host
    Write-Host "Open a brand-new cmd.exe or Windows Terminal tab."
    Write-Host "Do not test from a cmd.exe that launched this PowerShell; parent terminals cannot inherit child-process environment changes."
    Write-Host
    Write-Host "Then check:"
    Write-Host "  where $ExeBaseName"
    Write-Host "  $ExeBaseName --version"
    Write-Host
    Write-Host "Persistent User PATH check:"
    Write-Host "  powershell -NoProfile -Command `"[Environment]::GetEnvironmentVariable('Path','User') -split ';' | Select-String -SimpleMatch '$BinDir'`""
    Write-Host
    Write-Host "Persistent Machine PATH check:"
    Write-Host "  powershell -NoProfile -Command `"[Environment]::GetEnvironmentVariable('Path','Machine') -split ';' | Select-String -SimpleMatch '$BinDir'`""
    exit 0
}

$ProfileParent = Split-Path -Parent $ProfileFile
if (-not [string]::IsNullOrWhiteSpace($ProfileParent)) {
    New-Item -ItemType Directory -Force -Path $ProfileParent | Out-Null
}

if (-not (Test-Path -LiteralPath $ProfileFile -PathType Leaf)) {
    New-Item -ItemType File -Force -Path $ProfileFile | Out-Null
}

Write-Host
Write-Host "Removing old clang-mg PATH block if present..."
Remove-OldBlocks $ProfileFile

Write-Host "Adding updated clang-mg PATH block..."
Add-ProfilePathBlock $ProfileFile $BinDir
Add-DirToCurrentProcessPath $BinDir

Write-Host
Write-Host "Installed clang-mg PATH entry."
Write-Host
Write-Host "Open a new terminal, or run one of these for the current shell:"

$shellName = Get-ShellName
if ($shellName -eq "fish") {
    Write-Host "  set -gx PATH `"$BinDir`" `$PATH"
}
elseif (([System.IO.Path]::GetExtension($ProfileFile) -eq ".ps1") -or $shellName -eq "powershell" -or $shellName -eq "pwsh") {
    Write-Host "  `$env:Path = `"$BinDir$([System.IO.Path]::PathSeparator)`$env:Path`""
}
else {
    Write-Host "  export PATH=`"$($BinDir):`$PATH`""
}

Write-Host
Write-Host "Then check:"
Write-Host "  $ExeBaseName --version"
