#Requires -Version 5.1
param(
    [string]$RootDir,
    [string]$LlvmDir
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Fail {
    param([string]$Message)

    Write-Host $Message
    exit 1
}

function Get-NormalizedPath {
    param([string]$Path)

    return [System.IO.Path]::GetFullPath($Path)
}

function Invoke-Git {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$Arguments
    )

    & git @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "git $($Arguments -join ' ') failed with exit code $LASTEXITCODE."
    }
}

function Test-IgnoredPatchDirectoryName {
    param([string]$Name)

    return (
        $Name -like '*.backup.*' -or
        $Name -like '*.bak.*' -or
        $Name -like '*.old.*' -or
        $Name -eq '.backup' -or
        $Name -eq '.backups' -or
        $Name -eq 'backup' -or
        $Name -eq 'backups' -or
        $Name -like '.patch-refresh-*' -or
        $Name -like '*~'
    )
}

function Get-FeatureDirectories {
    Get-ChildItem -LiteralPath $script:PatchRoot -Directory |
        Where-Object { -not (Test-IgnoredPatchDirectoryName $_.Name) } |
        Sort-Object FullName
}

function Get-IgnoredPatchDirectories {
    Get-ChildItem -LiteralPath $script:PatchRoot -Directory |
        Where-Object { Test-IgnoredPatchDirectoryName $_.Name } |
        Sort-Object FullName
}

function Test-EnabledValue {
    param([string]$Value)

    switch ($Value) {
        { $_ -in @('1', 'true', 'TRUE', 'yes', 'YES', 'on', 'ON', 'enabled', 'ENABLED') } {
            return $true
        }
        { $_ -in @('0', 'false', 'FALSE', 'no', 'NO', 'off', 'OFF', 'disabled', 'DISABLED') } {
            return $false
        }
        default {
            Fail "ERROR: Invalid ENABLED value: $Value`nUse one of: 1, 0, true, false, yes, no, on, off"
        }
    }
}

function Write-DefaultFeatureConfig {
    param(
        [string]$ConfigFile,
        [string]$FeatureName
    )

    $parent = Split-Path -Parent $ConfigFile
    New-Item -ItemType Directory -Force -Path $parent | Out-Null

    @"
# Auto-generated config for clang-mg feature: $FeatureName

# Whether this feature should be applied.
# Valid values: 1, 0, true, false, yes, no, on, off
ENABLED=1

# Features that must be applied before this feature.
# Example:
#   DEPENDS=(core)
DEPENDS=()

# Features that this feature must be applied before.
# Usually DEPENDS is enough, but this is useful for ordering from the other side.
# Example:
#   BEFORE=(if-constexpr-members)
BEFORE=()
"@ | Set-Content -LiteralPath $ConfigFile -Encoding UTF8
}

function Remove-InlineComment {
    param([string]$Text)

    return ($Text -replace '\s+#.*$', '').Trim()
}

function Normalize-ConfigValue {
    param([string]$Value)

    $value = Remove-InlineComment $Value

    if (($value.StartsWith('"') -and $value.EndsWith('"')) -or
        ($value.StartsWith("'") -and $value.EndsWith("'"))) {
        $value = $value.Substring(1, $value.Length - 2)
    }

    return $value.Trim()
}

function Parse-NameList {
    param([string]$Text)

    $clean = Remove-InlineComment $Text
    if ([string]::IsNullOrWhiteSpace($clean)) {
        return @()
    }

    $items = @()
    $matches = [regex]::Matches($clean, '"([^\"]*)"|''([^'']*)''|([^\s]+)')

    foreach ($match in $matches) {
        if ($match.Groups[1].Success) {
            $item = $match.Groups[1].Value
        }
        elseif ($match.Groups[2].Success) {
            $item = $match.Groups[2].Value
        }
        else {
            $item = $match.Groups[3].Value
        }

        $item = $item.Trim()
        if ($item -ne '') {
            $items += $item
        }
    }

    return $items
}

function Read-FeatureConfig {
    param([string]$ConfigFile)

    $enabled = '1'
    $depends = @()
    $before = @()

    foreach ($line in Get-Content -LiteralPath $ConfigFile) {
        $trimmed = $line.Trim()
        if ($trimmed -eq '' -or $trimmed.StartsWith('#')) {
            continue
        }

        if ($trimmed -match '^ENABLED\s*=\s*(.+?)\s*$') {
            $enabled = Normalize-ConfigValue $Matches[1]
            continue
        }

        if ($trimmed -match '^DEPENDS\s*=\s*\((.*)\)\s*$') {
            $depends = Parse-NameList $Matches[1]
            continue
        }

        if ($trimmed -match '^BEFORE\s*=\s*\((.*)\)\s*$') {
            $before = Parse-NameList $Matches[1]
            continue
        }

        if ($trimmed -match '^DEPENDS\s*=\s*(.+?)\s*$') {
            $depends = Parse-NameList $Matches[1]
            continue
        }

        if ($trimmed -match '^BEFORE\s*=\s*(.+?)\s*$') {
            $before = Parse-NameList $Matches[1]
            continue
        }
    }

    [pscustomobject]@{
        Enabled = $enabled
        Depends = $depends
        Before  = $before
    }
}

function Load-FeatureConfigs {
    $ignoredDirs = @(Get-IgnoredPatchDirectories)

    if ($ignoredDirs.Count -gt 0) {
        Write-Host 'Ignoring backup/temp patch directories:'
        foreach ($dir in $ignoredDirs) {
            Write-Host "  $($dir.FullName)"
        }
        Write-Host
    }

    foreach ($featureDir in Get-FeatureDirectories) {
        $featureName = $featureDir.Name
        $configFile = Join-Path $featureDir.FullName $script:FeatureConfigName

        if ($featureName -match '\s') {
            Fail "ERROR: Feature directory names cannot contain whitespace:`n  $featureName"
        }

        if (-not (Test-Path -LiteralPath $configFile -PathType Leaf)) {
            Write-Host 'Generating missing config:'
            Write-Host "  $configFile"
            Write-DefaultFeatureConfig $configFile $featureName
        }

        [void]$script:Features.Add($featureName)
        $script:FeatureDirs[$featureName] = $featureDir.FullName

        $patchFiles = @(Get-ChildItem -LiteralPath $featureDir.FullName -File -Filter '*.patch' -ErrorAction SilentlyContinue)
        $script:FeatureHasPatches[$featureName] = if ($patchFiles.Count -gt 0) { 1 } else { 0 }

        $config = Read-FeatureConfig $configFile

        if (Test-EnabledValue $config.Enabled) {
            $script:FeatureEnabled[$featureName] = 1
        }
        else {
            $script:FeatureEnabled[$featureName] = 0
        }

        $script:FeatureDeps[$featureName] = @($config.Depends)
        $script:FeatureBefore[$featureName] = @($config.Before)
    }
}

function Sort-Queue {
    if ($script:Queue.Count -eq 0) {
        return
    }

    $sorted = @($script:Queue | Sort-Object)
    $script:Queue = [System.Collections.Generic.List[string]]::new()

    foreach ($item in $sorted) {
        [void]$script:Queue.Add($item)
    }
}

function Add-Edge {
    param(
        [string]$From,
        [string]$To
    )

    if (-not $script:FeatureEdges.ContainsKey($From)) {
        $script:FeatureEdges[$From] = @()
    }

    $script:FeatureEdges[$From] = @($script:FeatureEdges[$From]) + $To
    $script:FeatureInDegree[$To] = [int]$script:FeatureInDegree[$To] + 1
}

function Validate-Dependency {
    param(
        [string]$Feature,
        [string]$Dependency
    )

    if (-not $script:FeatureDirs.ContainsKey($Dependency)) {
        Write-Host "ERROR: Feature '$Feature' depends on unknown feature '$Dependency'."
        Write-Host
        Write-Host 'Known features:'
        foreach ($knownFeature in $script:Features) {
            Write-Host "  $knownFeature"
        }
        exit 1
    }

    if ($script:FeatureHasPatches[$Dependency] -ne 1) {
        Fail "ERROR: Feature '$Feature' depends on '$Dependency', but '$Dependency' has no .patch files."
    }

    if ($script:FeatureEnabled[$Dependency] -ne 1) {
        Write-Host "ERROR: Feature '$Feature' depends on '$Dependency', but '$Dependency' is disabled."
        Write-Host
        Write-Host "Either enable '$Dependency' or disable '$Feature'."
        exit 1
    }
}

function Build-FeatureOrder {
    foreach ($feature in $script:Features) {
        if ($script:FeatureHasPatches[$feature] -ne 1) {
            Write-Host "Skipping feature with no .patch files: $feature"
            continue
        }

        if ($script:FeatureEnabled[$feature] -ne 1) {
            Write-Host "Skipping disabled feature: $feature"
            continue
        }

        [void]$script:EnabledFeatures.Add($feature)
        $script:EnabledFeatureMap[$feature] = 1
        $script:FeatureInDegree[$feature] = 0
        $script:FeatureEdges[$feature] = @()
    }

    foreach ($feature in $script:EnabledFeatures) {
        foreach ($dependency in @($script:FeatureDeps[$feature])) {
            if ([string]::IsNullOrWhiteSpace($dependency)) {
                continue
            }

            Validate-Dependency $feature $dependency
            Add-Edge $dependency $feature
        }

        foreach ($before in @($script:FeatureBefore[$feature])) {
            if ([string]::IsNullOrWhiteSpace($before)) {
                continue
            }

            if (-not $script:FeatureDirs.ContainsKey($before)) {
                Fail "ERROR: Feature '$feature' has BEFORE entry for unknown feature '$before'."
            }

            if (-not $script:EnabledFeatureMap.ContainsKey($before)) {
                Write-Host "NOTE: '$feature' says it should run before '$before', but '$before' is not enabled. Ignoring."
                continue
            }

            Add-Edge $feature $before
        }
    }

    foreach ($feature in $script:EnabledFeatures) {
        if ([int]$script:FeatureInDegree[$feature] -eq 0) {
            [void]$script:Queue.Add($feature)
        }
    }

    Sort-Queue

    while ($script:Queue.Count -gt 0) {
        $feature = $script:Queue[0]
        $script:Queue.RemoveAt(0)

        [void]$script:OrderedFeatures.Add($feature)

        foreach ($next in @($script:FeatureEdges[$feature])) {
            $script:FeatureInDegree[$next] = [int]$script:FeatureInDegree[$next] - 1

            if ([int]$script:FeatureInDegree[$next] -eq 0) {
                [void]$script:Queue.Add($next)
                Sort-Queue
            }
        }
    }

    if ($script:OrderedFeatures.Count -ne $script:EnabledFeatures.Count) {
        Write-Host 'ERROR: Dependency cycle detected between enabled features.'
        Write-Host
        Write-Host 'Features still blocked:'

        $remaining = $false
        foreach ($feature in $script:EnabledFeatures) {
            if ([int]$script:FeatureInDegree[$feature] -gt 0) {
                Write-Host "  $feature"
                $remaining = $true
            }
        }

        if (-not $remaining) {
            Write-Host '  unknown'
        }

        exit 1
    }
}

function Apply-LoosePatches {
    $loosePatches = @(
        Get-ChildItem -LiteralPath $script:PatchRoot -File -Filter '*.patch' -ErrorAction SilentlyContinue |
            Where-Object {
                $_.Name -notlike '*.backup.patch' -and
                $_.Name -notlike '*.bak.patch' -and
                $_.Name -notlike '*.old.patch' -and
                $_.Name -notlike '*~'
            } |
            Sort-Object FullName
    )

    if ($loosePatches.Count -eq 0) {
        Write-Host 'No loose top-level patches found.'
        return
    }

    Write-Host
    Write-Host 'Applying loose top-level patches from:'
    Write-Host $script:PatchRoot

    $patchPaths = @($loosePatches | ForEach-Object { $_.FullName })
    $gitArgs = @('am', '--3way') + $patchPaths
    Invoke-Git -Arguments $gitArgs
}

function Apply-OrderedFeatures {
    Write-Host
    Write-Host 'Feature apply order:'

    if ($script:OrderedFeatures.Count -eq 0) {
        Write-Host '  No enabled feature patch directories found.'
        return
    }

    foreach ($feature in $script:OrderedFeatures) {
        Write-Host "  $feature"
    }

    foreach ($featureName in $script:OrderedFeatures) {
        Write-Host
        Write-Host "Applying feature: $featureName"

        $oldLlvmDir = $env:LLVM_DIR
        $hadLlvmDir = Test-Path Env:LLVM_DIR
        $env:LLVM_DIR = $script:LlvmDir

        try {
            & $script:ApplyFeatureScript $featureName
            if ($LASTEXITCODE -ne 0) {
                throw "apply-feature.ps1 failed for '$featureName' with exit code $LASTEXITCODE."
            }
        }
        finally {
            if ($hadLlvmDir) {
                $env:LLVM_DIR = $oldLlvmDir
            }
            else {
                Remove-Item Env:LLVM_DIR -ErrorAction SilentlyContinue
            }
        }
    }
}

try {
    $scriptDir = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $PSCommandPath }

    if ([string]::IsNullOrWhiteSpace($RootDir)) {
        $RootDir = Join-Path $scriptDir '..'
    }

    $script:RootDir = Get-NormalizedPath $RootDir

    if ([string]::IsNullOrWhiteSpace($LlvmDir)) {
        $script:LlvmDir = Join-Path (Join-Path $script:RootDir 'work') 'llvm-project'
    }
    else {
        $script:LlvmDir = Get-NormalizedPath $LlvmDir
    }

    $script:PatchRoot = Join-Path $script:RootDir 'patches'
    $script:ApplyFeatureScript = Join-Path (Join-Path $script:RootDir 'scripts') 'apply-feature.ps1'
    $script:FeatureConfigName = if ([string]::IsNullOrWhiteSpace($env:FEATURE_CONFIG_NAME)) { 'feature.conf' } else { $env:FEATURE_CONFIG_NAME }

    $script:FeatureDirs = @{}
    $script:FeatureHasPatches = @{}
    $script:FeatureEnabled = @{}
    $script:FeatureDeps = @{}
    $script:FeatureBefore = @{}
    $script:FeatureInDegree = @{}
    $script:FeatureEdges = @{}
    $script:EnabledFeatureMap = @{}

    $script:Features = [System.Collections.Generic.List[string]]::new()
    $script:EnabledFeatures = [System.Collections.Generic.List[string]]::new()
    $script:OrderedFeatures = [System.Collections.Generic.List[string]]::new()
    $script:Queue = [System.Collections.Generic.List[string]]::new()

    Write-Host '=== apply all clang-mg patches ==='
    Write-Host "Root dir:   $script:RootDir"
    Write-Host "LLVM dir:   $script:LlvmDir"
    Write-Host "Patch root: $script:PatchRoot"
    Write-Host

    if (-not (Test-Path -LiteralPath (Join-Path $script:LlvmDir '.git') -PathType Container)) {
        Fail "ERROR: LLVM repo is not cloned:`n$script:LlvmDir"
    }

    if (-not (Test-Path -LiteralPath $script:PatchRoot -PathType Container)) {
        Fail "ERROR: Patch directory does not exist:`n$script:PatchRoot"
    }

    if (-not (Test-Path -LiteralPath $script:ApplyFeatureScript -PathType Leaf)) {
        Write-Host 'ERROR: apply-feature PowerShell script not found:'
        Write-Host $script:ApplyFeatureScript
        Write-Host
        Write-Host 'Expected this file to exist:'
        Write-Host '  scripts/apply-feature.ps1'
        exit 1
    }

    Set-Location -LiteralPath $script:LlvmDir

    $status = @(& git status --porcelain)
    if ($LASTEXITCODE -ne 0) {
        Fail 'ERROR: Could not check LLVM git status.'
    }

    if ($status.Count -gt 0) {
        Write-Host 'ERROR: LLVM has uncommitted changes.'
        Write-Host
        Write-Host 'Save, commit, or reset your changes before applying patches.'
        Write-Host
        Write-Host 'Useful commands:'
        Write-Host '  git status'
        Write-Host '  git diff'
        Write-Host '  git add .'
        Write-Host '  git commit -m "clang-mg: describe current work"'
        Write-Host
        Write-Host 'Apply cancelled.'
        exit 1
    }

    Load-FeatureConfigs
    Build-FeatureOrder

    Apply-LoosePatches
    Apply-OrderedFeatures

    Write-Host
    Write-Host 'All enabled clang-mg patches applied.'
}
catch {
    Write-Host $_.Exception.Message
    exit 1
}
