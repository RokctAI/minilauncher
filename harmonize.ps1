param (
    [Parameter(Mandatory = $false)] [string]$PackageName = "",
    [Parameter(Mandatory = $false)] [switch]$NormalizeOnly,
    [Parameter(Mandatory = $false)] [switch]$normalize,
    [Parameter(Mandatory = $false)] [switch]$Deduplicate
)

# Support --normalize as alias
if ($normalize) { $NormalizeOnly = $true }

# ============================================================
# 1. Detect target package name — pubspec is source of truth
# ============================================================
$targetPackage = $PackageName
if (-not $targetPackage) {
    if (Test-Path "pubspec.yaml") {
        $pubContent = Get-Content "pubspec.yaml" -Raw
        if ($pubContent -match "(?m)^name:\s*([a-zA-Z0-9_]+)") {
            $targetPackage = $Matches[1]
        }
    }
}
if (-not $targetPackage) {
    Write-Host "ERROR: Could not determine package name. Ensure pubspec.yaml exists with a 'name:' field, or pass -PackageName explicitly." -ForegroundColor Red
    exit 1
}

Write-Host "Package: $targetPackage" -ForegroundColor Cyan
if ($NormalizeOnly) {
    Write-Host "Mode: NORMALIZE ONLY (Pass 1)" -ForegroundColor Magenta
}
else {
    Write-Host "Mode: FULL (Pass 1 + Pass 2 + Pass 3 + Pass 4)" -ForegroundColor Magenta
}

$libPath = (Resolve-Path "lib").Path
$logFile = (Join-Path (Get-Location) "harmonize.log")
$normalizedCount = 0
$fixedCount = 0
$skippedCount = 0
$brokenCount = 0

"--- HARMONIZER REPORT (Created: $(Get-Date)) ---`n" | Out-File -FilePath $logFile -Encoding utf8

# ============================================================
# 2. Build filename -> [package paths] lookup map
# ============================================================
$dartFileMap = @{}
Get-ChildItem -Path "lib" -Recurse -Filter *.dart | ForEach-Object {
    $relativeToLib = $_.FullName.Substring($libPath.Length).TrimStart([System.IO.Path]::DirectorySeparatorChar).Replace('\', '/')
    $packagePath = "package:$targetPackage/$relativeToLib"
    $fileName = $_.Name

    if (-not $dartFileMap.ContainsKey($fileName)) {
        $dartFileMap[$fileName] = [System.Collections.Generic.List[string]]::new()
    }
    $dartFileMap[$fileName].Add($packagePath)
}

# ============================================================
# 3. Helpers
# ============================================================
function Get-AbsPathFromPackagePath {
    param([string]$packagePath)
    $inner = $packagePath.Replace("package:$targetPackage/", "").Replace('/', [System.IO.Path]::DirectorySeparatorChar)
    return Join-Path $libPath $inner
}

function Resolve-DartPath {
    param([string]$rawPath, [string]$currentDir)
    if ($rawPath.StartsWith("package:$targetPackage/")) {
        $inner = $rawPath.Replace("package:$targetPackage/", "").Replace('/', [System.IO.Path]::DirectorySeparatorChar)
        return Join-Path $libPath $inner
    }
    if ($rawPath.StartsWith("package:") -or $rawPath.StartsWith("dart:")) { return $null }
    try {
        return [System.IO.Path]::GetFullPath([System.IO.Path]::Combine($currentDir, $rawPath))
    }
    catch { return $null }
}

function Get-DirectiveSuffix {
    param([string]$line)
    if ($line -match "\.dart['""](.+);") { return $Matches[1].Trim() }
    return ""
}

function Get-ExportedIdentifiers {
    param([string]$filePath)
    $identifiers = [System.Collections.Generic.HashSet[string]]::new()
    if (-not (Test-Path $filePath)) { return $identifiers }
    $lines = [System.IO.File]::ReadAllLines($filePath)
    foreach ($line in $lines) {
        $trimmed = $line.Trim()
        if ($trimmed.StartsWith("//") -or
            $trimmed.StartsWith("import") -or
            $trimmed.StartsWith("export") -or
            $trimmed.StartsWith("part")) { continue }
        $patterns = @(
            '^(?:abstract\s+|final\s+|sealed\s+|base\s+|interface\s+)?class\s+([A-Z][a-zA-Z0-9_]*)',
            '^enum\s+([A-Z][a-zA-Z0-9_]*)',
            '^mixin\s+([A-Z][a-zA-Z0-9_]*)',
            '^extension\s+([A-Za-z][a-zA-Z0-9_]*)\s+on',
            '^typedef\s+([A-Z][a-zA-Z0-9_]*)',
            '^const\s+(?:[A-Za-z_][a-zA-Z0-9_<>, ]*\s+)?([a-zA-Z_][a-zA-Z0-9_]*)\s*=',
            '^final\s+(?:[A-Za-z_][a-zA-Z0-9_<>, ]*\s+)?([a-zA-Z_][a-zA-Z0-9_]*)\s*=',
            '^(?:[A-Za-z_][a-zA-Z0-9_<>?, ]*)\s+([a-z_][a-zA-Z0-9_]*)\s*\('
        )
        foreach ($pattern in $patterns) {
            if ($trimmed -match $pattern) {
                $null = $identifiers.Add($Matches[1])
                break
            }
        }
    }
    return $identifiers
}

function Get-UsedIdentifiers {
    param([string]$filePath)
    $identifiers = [System.Collections.Generic.HashSet[string]]::new()
    if (-not (Test-Path $filePath)) { return $identifiers }
    $lines = [System.IO.File]::ReadAllLines($filePath)
    foreach ($line in $lines) {
        $trimmed = $line.Trim()
        if ($trimmed.StartsWith("//") -or
            $trimmed.StartsWith("import") -or
            $trimmed.StartsWith("export")) { continue }
        $ms = [regex]::Matches($trimmed, '\b([A-Z][a-zA-Z0-9_]*)\b')
        foreach ($m in $ms) { $null = $identifiers.Add($m.Groups[1].Value) }
    }
    return $identifiers
}

function Test-HasExportableContent {
    param([string]$candidateAbsPath)
    $exported = Get-ExportedIdentifiers -filePath $candidateAbsPath
    if ($exported.Count -gt 0) { return $true }
    $lines = [System.IO.File]::ReadAllLines($candidateAbsPath)
    foreach ($line in $lines) {
        if ($line.Trim().StartsWith("export")) { return $true }
    }
    return $false
}

function Test-ImportCompatibility {
    param([string]$importerFile, [string]$candidateAbsPath)
    $exported = Get-ExportedIdentifiers -filePath $candidateAbsPath
    if ($exported.Count -eq 0) { return $null }
    $used = Get-UsedIdentifiers -filePath $importerFile
    foreach ($id in $exported) {
        if ($used.Contains($id)) { return $true }
    }
    return $false
}

function Test-ExportCompatibility {
    param([string]$candidateAbsPath)
    $hasContent = Test-HasExportableContent -candidateAbsPath $candidateAbsPath
    if ($hasContent) { return $true }
    return $null
}

# ============================================================
# 4. Dart analyze helper — returns error count for a file
# ============================================================
function Get-AnalyzeErrorCount {
    param([string]$filePath)
    try {
        $result = & dart analyze $filePath 2>&1
        $errors = $result | Where-Object { $_ -match "^\s*error\s*\|" }
        return $errors.Count
    }
    catch {
        return 999
    }
}

# Temporarily swap a line in a file, analyze, restore
function Get-CandidateErrorDelta {
    param(
        [string]$filePath,
        [string]$originalLine,
        [string]$candidateLine,
        [int]$lineIndex,
        [int]$baselineErrors
    )
    $content = [System.IO.File]::ReadAllLines($filePath)
    $content[$lineIndex] = $candidateLine
    [System.IO.File]::WriteAllLines($filePath, $content)

    $errorCount = Get-AnalyzeErrorCount -filePath $filePath

    # Restore original
    $content[$lineIndex] = $originalLine
    [System.IO.File]::WriteAllLines($filePath, $content)

    return ($errorCount - $baselineErrors)
}

# ============================================================
# 5. Resolve broken path — identifier filter + analyze tiebreaker
# ============================================================
function Resolve-BrokenPath {
    param(
        [string]$rawPath,
        [string]$currentFile,
        [string]$lineRef,
        [string]$directiveType,
        [string]$originalLine,
        [int]$lineIndex
    )

    $brokenFileName = [System.IO.Path]::GetFileName($rawPath)

    if (-not $dartFileMap.ContainsKey($brokenFileName)) {
        $script:brokenCount++
        "$lineRef [MISSING] Not found anywhere in lib/: $rawPath" | Add-Content -Path $logFile
        Write-Host "    [MISSING]  '$brokenFileName' not found in lib/" -ForegroundColor Red
        return $null
    }

    $candidates = $dartFileMap[$brokenFileName]
    $compatible = @()
    $unknown = @()
    $incompatible = @()

    foreach ($candidate in $candidates) {
        $candidateAbs = Get-AbsPathFromPackagePath -packagePath $candidate
        if ($directiveType -eq "import") {
            $result = Test-ImportCompatibility -importerFile $currentFile -candidateAbsPath $candidateAbs
        }
        else {
            $result = Test-ExportCompatibility -candidateAbsPath $candidateAbs
        }
        if ($result -eq $true) { $compatible += $candidate }
        elseif ($result -eq $null) { $unknown += $candidate }
        else { $incompatible += $candidate }
    }

    # Single unambiguous compatible match
    if ($compatible.Count -eq 1 -and $unknown.Count -eq 0) {
        $script:fixedCount++
        "$lineRef [FIXED] Verified: '$rawPath' -> '$($compatible[0])'" | Add-Content -Path $logFile
        Write-Host "    [FIXED]    '$rawPath'" -ForegroundColor Green
        Write-Host "               -> $($compatible[0])" -ForegroundColor Green
        return $compatible[0]
    }

    # One compatible plus unknowns
    if ($compatible.Count -eq 1 -and $unknown.Count -ge 1) {
        $script:fixedCount++
        "$lineRef [FIXED~] 1 compatible, $($unknown.Count) unverified ignored: '$rawPath' -> '$($compatible[0])'" | Add-Content -Path $logFile
        Write-Host "    [FIXED~]   '$rawPath'" -ForegroundColor DarkGreen
        Write-Host "               -> $($compatible[0]) ($($unknown.Count) unverified ignored)" -ForegroundColor DarkGreen
        return $compatible[0]
    }

    # No compatible, one unknown
    if ($compatible.Count -eq 0 -and $unknown.Count -eq 1) {
        $script:fixedCount++
        "$lineRef [FIXED?] Unverified: '$rawPath' -> '$($unknown[0])'" | Add-Content -Path $logFile
        Write-Host "    [FIXED?]   '$rawPath' -> $($unknown[0]) (unverified)" -ForegroundColor DarkYellow
        return $unknown[0]
    }

    # Multiple candidates remain — use dart analyze as tiebreaker
    $analyzePool = @()
    if ($compatible.Count -ge 2) { $analyzePool = $compatible }
    elseif ($compatible.Count -eq 0 -and $unknown.Count -ge 2) { $analyzePool = $unknown }
    elseif ($compatible.Count -ge 1 -and $unknown.Count -ge 1) { $analyzePool = $compatible + $unknown }

    if ($analyzePool.Count -ge 2) {
        Write-Host "    [ANALYZE]  Running dart analyze tiebreaker for '$brokenFileName'..." -ForegroundColor DarkCyan

        $baselineErrors = Get-AnalyzeErrorCount -filePath $currentFile
        $results = @{}

        foreach ($candidate in $analyzePool) {
            $suffix = Get-DirectiveSuffix -line $originalLine
            $candidateLine = if ($suffix) { "$directiveType '$candidate' $suffix;" } else { "$directiveType '$candidate';" }
            $delta = Get-CandidateErrorDelta `
                -filePath $currentFile `
                -originalLine $originalLine `
                -candidateLine $candidateLine `
                -lineIndex $lineIndex `
                -baselineErrors $baselineErrors
            $results[$candidate] = $delta
            Write-Host "      delta=$delta  $candidate" -ForegroundColor DarkGray
            "$lineRef [ANALYZE] delta=$delta for '$candidate'" | Add-Content -Path $logFile
        }

        $minDelta = ($results.Values | Measure-Object -Minimum).Minimum
        $winners = $results.Keys | Where-Object { $results[$_] -eq $minDelta }

        if ($winners.Count -eq 1) {
            $winner = $winners[0]
            $script:fixedCount++
            "$lineRef [FIXED-ANALYZE] delta=${minDelta}: '$rawPath' -> '$winner'" | Add-Content -Path $logFile
            Write-Host "    [FIXED-A]  '$rawPath'" -ForegroundColor Green
            Write-Host "               -> $winner (analyze delta=$minDelta)" -ForegroundColor Green
            return $winner
        }
        else {
            # Still tied after analyze
            $script:skippedCount++
            $entry = "$lineRef [AMBIGUOUS] Tied after analyze (delta=$minDelta): '$rawPath'`n"
            foreach ($w in $winners) { $entry += "    [TIED] $w`n" }
            $entry | Add-Content -Path $logFile
            Write-Host "    [AMBIGUOUS] '$rawPath' still tied after analyze - manual fix needed" -ForegroundColor Yellow
            foreach ($w in $winners) { Write-Host "               tied: $w" -ForegroundColor Yellow }
            return $null
        }
    }

    # No candidates compatible and none to analyze
    $script:brokenCount++
    $entry = "$lineRef [NO MATCH] No compatible candidate for '$rawPath'`n"
    foreach ($c in $incompatible) { $entry += "    [INCOMPATIBLE] $c`n" }
    $entry | Add-Content -Path $logFile
    Write-Host "    [NO MATCH] '$rawPath' - no compatible candidate found" -ForegroundColor Red
    return $null
}

# ============================================================
# 6. PASS 1 — Normalize
# ============================================================
Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " PASS 1 - Normalizing relative paths to full package paths" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
"" | Add-Content -Path $logFile
"=== PASS 1 - NORMALIZE ===" | Add-Content -Path $logFile

Get-ChildItem -Path "lib" -Recurse -Filter *.dart | ForEach-Object {
    $file = $_
    $content = [System.IO.File]::ReadAllLines($file.FullName)
    $modified = $false
    $newLines = @()
    $currentDir = Split-Path $file.FullName -Parent
    $fileHeader = $false

    for ($i = 0; $i -lt $content.Count; $i++) {
        $line = $content[$i]
        $newLine = $line

        if ($newLine.Trim().StartsWith("//")) { $newLines += $newLine; continue }
        if ($newLine.Trim() -match "^part\s") { $newLines += $newLine; continue }

        if ($newLine -match '\bStyle\.') {
            $newLine = [regex]::Replace($newLine, '\bStyle\.', 'AppStyle.')
        }

        $directiveType = $null
        if ($newLine.Trim().StartsWith("import")) { $directiveType = "import" }
        elseif ($newLine.Trim().StartsWith("export")) { $directiveType = "export" }

        if ($directiveType -and ($newLine -match "(?:import|export)\s+['""]([^'""]+\.dart)['""]")) {
            $rawPath = $Matches[1]
            if ($rawPath.StartsWith("package:") -and -not $rawPath.StartsWith("package:$targetPackage/")) {
                $newLines += $newLine; continue
            }
            if ($rawPath.StartsWith("dart:")) { $newLines += $newLine; continue }

            $targetAbsPath = Resolve-DartPath -rawPath $rawPath -currentDir $currentDir
            $isPackageImport = $rawPath.StartsWith("package:$targetPackage/")

            if ($null -ne $targetAbsPath -and (Test-Path $targetAbsPath)) {
                if (-not $isPackageImport -and $targetAbsPath.ToLower().StartsWith($libPath.ToLower())) {
                    $relativeToLib = $targetAbsPath.Substring($libPath.Length).TrimStart([System.IO.Path]::DirectorySeparatorChar).Replace('\', '/')
                    $newPath = "package:$targetPackage/$relativeToLib"
                    $suffix = Get-DirectiveSuffix -line $newLine
                    $newLine = if ($suffix) { "$directiveType '$newPath' $suffix;" } else { "$directiveType '$newPath';" }
                    $script:normalizedCount++
                    if (-not $fileHeader) {
                        $relativePath = $file.FullName.Replace($libPath, "lib")
                        Write-Host "  $relativePath" -ForegroundColor Gray
                        $fileHeader = $true
                    }
                    Write-Host "    [NORM] $rawPath" -ForegroundColor DarkCyan
                    "[$($file.FullName):$($i+1)] [NORM] '$rawPath' -> '$newPath'" | Add-Content -Path $logFile
                }
            }
        }

        if ($newLine -ne $line) { $modified = $true }
        $newLines += $newLine
    }

    if ($modified) { [System.IO.File]::WriteAllLines($file.FullName, $newLines) }
}

Write-Host ""
Write-Host "  Pass 1 complete. Normalized: $normalizedCount paths." -ForegroundColor Cyan

if ($NormalizeOnly) {
    Write-Host ""
    Write-Host "Skipping Pass 2/3/4 (NormalizeOnly mode)." -ForegroundColor Magenta
    Write-Host "Run without -NormalizeOnly / --normalize to continue." -ForegroundColor Magenta
    exit 0
}

# ============================================================
# 7. PASS 2 — Fix broken imports/exports with analyze tiebreaker
# ============================================================
Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " PASS 2 - Resolving broken imports and exports" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
"" | Add-Content -Path $logFile
"=== PASS 2 - FIX BROKEN ===" | Add-Content -Path $logFile

Get-ChildItem -Path "lib" -Recurse -Filter *.dart | ForEach-Object {
    $file = $_
    $content = [System.IO.File]::ReadAllLines($file.FullName)
    $modified = $false
    $newLines = @()
    $currentDir = Split-Path $file.FullName -Parent
    $fileHeader = $false

    for ($i = 0; $i -lt $content.Count; $i++) {
        $line = $content[$i]
        $newLine = $line
        $lineRef = "[$($file.FullName):$($i+1)]"

        if ($newLine.Trim().StartsWith("//")) { $newLines += $newLine; continue }
        if ($newLine.Trim() -match "^part\s") { $newLines += $newLine; continue }

        $directiveType = $null
        if ($newLine.Trim().StartsWith("import")) { $directiveType = "import" }
        elseif ($newLine.Trim().StartsWith("export")) { $directiveType = "export" }

        if ($directiveType -and ($newLine -match "(?:import|export)\s+['""]([^'""]+\.dart)['""]")) {
            $rawPath = $Matches[1]
            if ($rawPath.StartsWith("package:") -and -not $rawPath.StartsWith("package:$targetPackage/")) {
                $newLines += $newLine; continue
            }
            if ($rawPath.StartsWith("dart:")) { $newLines += $newLine; continue }

            $targetAbsPath = Resolve-DartPath -rawPath $rawPath -currentDir $currentDir

            if ($null -ne $targetAbsPath -and -not (Test-Path $targetAbsPath)) {
                if (-not $fileHeader) {
                    $relativePath = $file.FullName.Replace($libPath, "lib")
                    Write-Host "  $relativePath" -ForegroundColor Gray
                    $fileHeader = $true
                }
                $resolved = Resolve-BrokenPath `
                    -rawPath $rawPath `
                    -currentFile $file.FullName `
                    -lineRef $lineRef `
                    -directiveType $directiveType `
                    -originalLine $line `
                    -lineIndex $i

                if ($null -ne $resolved) {
                    $suffix = Get-DirectiveSuffix -line $newLine
                    $newLine = if ($suffix) { "$directiveType '$resolved' $suffix;" } else { "$directiveType '$resolved';" }
                }
            }
        }

        if ($newLine -ne $line) { $modified = $true }
        $newLines += $newLine
    }

    if ($modified) { [System.IO.File]::WriteAllLines($file.FullName, $newLines) }
}

Write-Host ""
Write-Host "  Pass 2 complete." -ForegroundColor Cyan

# ============================================================
# 8. PASS 3 — Auto Router verification
# ============================================================
Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " PASS 3 - Auto Router verification" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
"" | Add-Content -Path $logFile
"=== PASS 3 - AUTO ROUTER ===" | Add-Content -Path $logFile

# FIX 1: Initialize $routerIssues before the conditional block so the
#         summary section can always reference it, even if no router is found.
$routerIssues = 0

# Find router config
$routerFile = $null
$knownRouterPath = Join-Path $libPath "presentation\routes\app_router.dart"
if (Test-Path $knownRouterPath) {
    $routerFile = $knownRouterPath
}
else {
    Write-Host "  app_router.dart not at default location, searching..." -ForegroundColor DarkYellow
    $found = Get-ChildItem -Path "lib" -Recurse -Filter "app_router.dart" | Select-Object -First 1
    if ($found) {
        $routerFile = $found.FullName
        Write-Host "  Found router at: $routerFile" -ForegroundColor DarkYellow
    }
}

if (-not $routerFile) {
    Write-Host "  WARNING: app_router.dart not found anywhere. Skipping Auto Router pass." -ForegroundColor Yellow
    "PASS 3 SKIPPED: app_router.dart not found" | Add-Content -Path $logFile
}
else {
    $routerContent = [System.IO.File]::ReadAllText($routerFile)

    # Collect all routes registered in the router
    $registeredRoutes = [System.Collections.Generic.HashSet[string]]::new()
    $routeMatches = [regex]::Matches($routerContent, '\b([A-Z][a-zA-Z0-9_]*)Route\b')
    foreach ($m in $routeMatches) {
        $null = $registeredRoutes.Add($m.Groups[1].Value + "Route")
    }

    # Collect all active @RoutePage annotations and their derived route names
    $activeRoutePages = @{}   # className -> routeName
    $commentedOutPages = @{}  # className -> routeName

    Get-ChildItem -Path "lib" -Recurse -Filter *.dart | ForEach-Object {
        $f = $_
        $lines = [System.IO.File]::ReadAllLines($f.FullName)

        for ($i = 0; $i -lt $lines.Count; $i++) {
            $trimmed = $lines[$i].Trim()

            # Detect commented out @RoutePage
            if ($trimmed -match "^//\s*@RoutePage") {
                for ($j = $i + 1; $j -lt [Math]::Min($i + 5, $lines.Count); $j++) {
                    $nextLine = $lines[$j].Trim()
                    if ($nextLine.StartsWith("//") -or $nextLine -eq "") { continue }
                    if ($nextLine -match "class\s+([A-Z][a-zA-Z0-9_]*)") {
                        $className = $Matches[1]
                        $routeName = $null
                        if ($trimmed -match "name:\s*'([^']+)'") {
                            $routeName = $Matches[1]
                        }
                        else {
                            $routeName = $className -replace "Page$", "Route" -replace "Screen$", "Route" -replace "View$", "Route"
                            if ($routeName -eq $className) { $routeName = $className + "Route" }
                        }
                        $commentedOutPages[$className] = @{
                            RouteName = $routeName
                            File      = $f.FullName
                            Line      = $i + 1
                        }
                        break
                    }
                }
            }

            # Detect active @RoutePage
            if ($trimmed -match "^@RoutePage") {
                $customName = $null
                if ($trimmed -match "name:\s*'([^']+)'") { $customName = $Matches[1] }

                for ($j = $i + 1; $j -lt [Math]::Min($i + 5, $lines.Count); $j++) {
                    $nextLine = $lines[$j].Trim()
                    if ($nextLine.StartsWith("//") -or $nextLine -eq "") { continue }
                    if ($nextLine -match "class\s+([A-Z][a-zA-Z0-9_]*)") {
                        $className = $Matches[1]
                        $routeName = if ($customName) {
                            $customName
                        }
                        else {
                            $rn = $className -replace "Page$", "Route" -replace "Screen$", "Route" -replace "View$", "Route"
                            if ($rn -eq $className) { $rn = $className + "Route" } else { $rn }
                        }
                        $activeRoutePages[$className] = @{
                            RouteName = $routeName
                            File      = $f.FullName
                            Line      = $i + 1
                        }
                        break
                    }
                }
            }
        }
    }

    # Check for duplicate route names among active pages
    $routeNameUsage = @{}
    foreach ($className in $activeRoutePages.Keys) {
        $info = $activeRoutePages[$className]
        $rn = $info.RouteName
        if (-not $routeNameUsage.ContainsKey($rn)) { $routeNameUsage[$rn] = @() }
        $routeNameUsage[$rn] += $className
    }

    # Report active pages
    foreach ($className in $activeRoutePages.Keys) {
        $info = $activeRoutePages[$className]
        $routeName = $info.RouteName
        $shortFile = $info.File.Replace($libPath, "lib")

        if (-not $registeredRoutes.Contains($routeName)) {
            $routerIssues++
            $msg = "[ROUTER] MISSING REGISTRATION: '$className' has @RoutePage (-> $routeName) but is NOT registered in app_router.dart  [${shortFile}:$($info.Line)]"
            Write-Host "  [MISSING REG]  $className -> $routeName  ($shortFile)" -ForegroundColor Red
            $msg | Add-Content -Path $logFile
        }

        if ($routeNameUsage[$routeName].Count -gt 1) {
            $routerIssues++
            $others = ($routeNameUsage[$routeName] | Where-Object { $_ -ne $className }) -join ", "
            $msg = "[ROUTER] DUPLICATE ROUTE NAME: '$routeName' used by '$className' AND '$others'  [${shortFile}:$($info.Line)]"
            Write-Host "  [DUPE ROUTE]   $routeName used by: $($routeNameUsage[$routeName] -join ', ')  ($shortFile)" -ForegroundColor Red
            $msg | Add-Content -Path $logFile
        }
    }

    # Report commented out pages
    foreach ($className in $commentedOutPages.Keys) {
        $info = $commentedOutPages[$className]
        $routeName = $info.RouteName
        $shortFile = $info.File.Replace($libPath, "lib")

        $stillRegistered = $registeredRoutes.Contains($routeName)
        $wouldDuplicate = $routeNameUsage.ContainsKey($routeName) -and $routeNameUsage[$routeName].Count -gt 0

        if ($stillRegistered -and $wouldDuplicate) {
            $routerIssues++
            $existing = $routeNameUsage[$routeName] -join ", "
            $msg = "[ROUTER] COMMENTED @RoutePage CONFLICT: '$className' is still registered as '$routeName' but restoring would duplicate with '$existing'  [${shortFile}:$($info.Line)]"
            Write-Host "  [CONFLICT]     $className - still registered, restoring would duplicate with: $existing  ($shortFile)" -ForegroundColor Red
            $msg | Add-Content -Path $logFile
        }
        elseif ($stillRegistered -and -not $wouldDuplicate) {
            $routerIssues++
            $msg = "[ROUTER] COMMENTED @RoutePage NEEDED: '$className' is still registered as '$routeName' - restore the annotation  [${shortFile}:$($info.Line)]"
            Write-Host "  [RESTORE]      $className - still registered as '$routeName', annotation should be restored  ($shortFile)" -ForegroundColor Yellow
            $msg | Add-Content -Path $logFile
        }
        elseif (-not $stillRegistered -and $wouldDuplicate) {
            $msg = "[ROUTER] COMMENTED @RoutePage SAFE (not registered, but would duplicate if restored): '$className' -> '$routeName'  [${shortFile}:$($info.Line)]"
            Write-Host "  [SAFE/WARN]    $className - not registered, safe to leave commented, but would duplicate if restored  ($shortFile)" -ForegroundColor DarkYellow
            $msg | Add-Content -Path $logFile
        }
        else {
            $msg = "[ROUTER] COMMENTED @RoutePage SAFE: '$className' -> '$routeName' not registered anywhere  [${shortFile}:$($info.Line)]"
            Write-Host "  [SAFE]         $className - not registered, safe to leave commented out  ($shortFile)" -ForegroundColor Green
            $msg | Add-Content -Path $logFile
        }
    }

    if ($routerIssues -eq 0 -and $commentedOutPages.Count -eq 0) {
        Write-Host "  All @RoutePage annotations look good." -ForegroundColor Green
    }

    Write-Host ""
    Write-Host "  Pass 3 complete. Issues found: $routerIssues" -ForegroundColor Cyan
}

# ============================================================
# 9. PASS 4 — Duplicate import/export reporter + fixer
# ============================================================
Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " PASS 4 - Duplicate import/export reporter" -ForegroundColor Cyan
if ($Deduplicate) {
    Write-Host " (AUTO-FIX ENABLED)" -ForegroundColor Green
}
Write-Host "============================================================" -ForegroundColor Cyan

"" | Add-Content -Path $logFile
"=== PASS 4 - DUPLICATES ===" | Add-Content -Path $logFile

function Parse-ImportDetails {
    param([string]$line)

    $alias = $null
    $hasHideShow = $false

    if ($line -match '\sas\s+([a-zA-Z0-9_]+)') {
        $alias = $Matches[1]
    }

    if ($line -match '\s(hide|show)\s+') {
        $hasHideShow = $true
    }

    return @{
        Alias       = $alias
        HasHideShow = $hasHideShow
    }
}

function Test-AliasUsed {
    param([string]$alias, [string[]]$fileLines)

    foreach ($l in $fileLines) {
        if ($l -match "\b$alias\.") {
            return $true
        }
    }
    return $false
}

$totalDuplicateFiles = 0
$totalRemoved = 0

Get-ChildItem -Path "lib" -Recurse -Filter *.dart | ForEach-Object {

    $file = $_
    $content = [System.IO.File]::ReadAllLines($file.FullName)
    $currentDir = Split-Path $file.FullName -Parent

    $seen = @{}

    # Join continuation lines before scanning so that multi-line directives like:
    #   import 'pkg/foo.dart'
    #       as cust_foo;
    # or
    #   import 'pkg/foo.dart'
    #       hide FooClass;
    # are parsed as a single logical unit. Without this, the alias/hide keyword
    # lives on line N+1 and Parse-ImportDetails never sees it.
    $i = 0
    while ($i -lt $content.Count) {

        $line = $content[$i]
        $trimmed = $line.Trim()

        if ($trimmed.StartsWith("//") -or $trimmed -match "^part\s") { $i++; continue }

        $directiveType = $null
        if ($trimmed.StartsWith("import")) { $directiveType = "import" }
        elseif ($trimmed.StartsWith("export")) { $directiveType = "export" }

        if ($directiveType -and ($trimmed -match "(?:import|export)\s+['""]([^'""]+\.dart)['""]")) {

            # Gather all physical lines that belong to this directive
            $spanLines = [System.Collections.Generic.List[int]]::new()
            $spanLines.Add($i)
            $joined = $trimmed

            # Keep pulling in the next line while the directive isn't terminated
            while ($joined -notmatch ";\s*$" -and ($i + 1) -lt $content.Count) {
                $i++
                $spanLines.Add($i)
                $joined = $joined + " " + $content[$i].Trim()
            }

            # Re-extract rawPath from the now-complete logical line
            if ($joined -match "(?:import|export)\s+['""]([^'""]+\.dart)['""]") {
                $rawPath = $Matches[1]

                if ($rawPath.StartsWith("dart:") -or
                    ($rawPath.StartsWith("package:") -and -not $rawPath.StartsWith("package:$targetPackage/"))) {
                    $absPath = $rawPath
                }
                else {
                    $resolved = Resolve-DartPath -rawPath $rawPath -currentDir $currentDir
                    $absPath = if ($resolved) { $resolved.ToLower() } else { $rawPath.ToLower() }
                }

                # Parse-ImportDetails now receives the full joined line, so it
                # correctly detects "as alias" and "hide/show" on continuation lines
                $details = Parse-ImportDetails -line $joined

                if (-not $seen.ContainsKey($absPath)) {
                    $seen[$absPath] = @()
                }

                $seen[$absPath] += @{
                    Line        = $spanLines[0]           # first physical line (display / key)
                    SpanLines   = $spanLines.ToArray()    # ALL lines to remove
                    Raw         = $content[$spanLines[0]]
                    Type        = $directiveType
                    Alias       = $details.Alias
                    HasHideShow = $details.HasHideShow
                }
            }
        }

        $i++
    }

    $fileModified = $false

    # FIX 2: Collect ALL line indices to remove across every duplicate group
    #         first, then do a single removal pass. This avoids stale line
    #         numbers caused by mutating $content mid-loop when a file has
    #         more than one set of duplicates.
    $allLinesToRemove = [System.Collections.Generic.HashSet[int]]::new()

    foreach ($absPath in $seen.Keys) {

        $entries = $seen[$absPath]

        if ($entries.Count -lt 2) { continue }

        $relativePath = $file.FullName.Replace($libPath, "lib")

        if (-not $fileModified) {
            Write-Host ""
            Write-Host "  FILE: $relativePath" -ForegroundColor Gray
            Write-Host "  ----------------------------------------" -ForegroundColor DarkGray
            $fileModified = $true
            $totalDuplicateFiles++
        }

        Write-Host "    [DUPLICATE] x$($entries.Count): $absPath" -ForegroundColor Yellow

        foreach ($e in $entries) {
            $spanDisplay = ($e.SpanLines | ForEach-Object { $_ + 1 }) -join "-"
            Write-Host "      line ${spanDisplay}: $($e.Raw.Trim())" -ForegroundColor DarkGray
        }

        if (-not $Deduplicate) { continue }

        if ($entries | Where-Object { $_.HasHideShow }) {
            Write-Host "      [SKIP] contains hide/show" -ForegroundColor DarkYellow
            continue
        }

        $toRemove = @()

        $plain = $entries | Where-Object { -not $_.Alias }
        $aliased = $entries | Where-Object { $_.Alias }

        # Alias handling FIRST: keep used aliases, drop unused ones.
        # We need to know how many aliases are kept before deciding what
        # to do with the plain import — if all aliases are unused and get
        # removed, the plain must be kept so the import is not lost entirely.
        $keptAliasCount = 0
        foreach ($entry in $aliased) {
            $used = Test-AliasUsed -alias $entry.Alias -fileLines $content

            if (-not $used) {
                Write-Host "      [REMOVE] unused alias '$($entry.Alias)'" -ForegroundColor Green
                $toRemove += $entry
            }
            else {
                Write-Host "      [KEEP] alias '$($entry.Alias)' is used" -ForegroundColor Cyan
                $keptAliasCount++
            }
        }

        # Plain import handling:
        # - Multiple plain copies: keep the first, remove the rest.
        # - One plain + at least one alias being kept: alias supersedes plain, remove plain.
        # - One plain + all aliases removed: keep the plain to avoid losing the import.
        if ($plain.Count -gt 1) {
            $toRemove += $plain | Select-Object -Skip 1
        }
        elseif ($plain.Count -eq 1 -and $keptAliasCount -ge 1) {
            $toRemove += $plain
        }

        # FIX 4: Use a HashSet<int> so line numbers are deduplicated by value,
        #         not by hashtable object reference. The old
        #         `Sort-Object -Unique` on hashtable arrays compared references
        #         and could produce duplicate indices, causing removal errors.
        foreach ($entry in $toRemove) {
            foreach ($ln in $entry.SpanLines) {
                $null = $allLinesToRemove.Add($ln)
            }
        }
    }

    # Single write per file after all groups are processed
    if ($Deduplicate -and $allLinesToRemove.Count -gt 0) {
        $newContent = @()

        for ($j = 0; $j -lt $content.Count; $j++) {
            if ($allLinesToRemove.Contains($j)) {
                $totalRemoved++
            }
            else {
                $newContent += $content[$j]
            }
        }

        [System.IO.File]::WriteAllLines($file.FullName, $newContent)
    }
}

if ($totalDuplicateFiles -eq 0) {
    Write-Host "  No duplicate imports found." -ForegroundColor Green
}

Write-Host ""
Write-Host "  Pass 4 complete. Files with duplicates: $totalDuplicateFiles" -ForegroundColor Cyan

if ($Deduplicate) {
    Write-Host "  Removed duplicate imports: $totalRemoved" -ForegroundColor Green
}

# ============================================================
# 10. Summary
# ============================================================
Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " SUMMARY" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "  [PASS 1] Normalized  : $normalizedCount  (relative -> full package path)" -ForegroundColor DarkCyan
Write-Host "  [PASS 2] Fixed       : $fixedCount  (broken paths resolved)" -ForegroundColor Green
Write-Host "  [PASS 2] Skipped     : $skippedCount  (ambiguous - manual review needed)" -ForegroundColor Yellow
Write-Host "  [PASS 2] Broken      : $brokenCount  (no compatible match found)" -ForegroundColor Red
Write-Host "  [PASS 3] Router issues : $routerIssues" -ForegroundColor Gray
Write-Host "  [PASS 4] Files with duplicate imports/exports: $totalDuplicateFiles" -ForegroundColor Gray
Write-Host ""

if ($brokenCount -eq 0 -and $skippedCount -eq 0) {
    if (Test-Path $logFile) { Remove-Item $logFile }
    Write-Host "Harmonization complete for '$targetPackage'. No unresolved issues." -ForegroundColor Green
}
else {
    Write-Host "See harmonize.log for full details." -ForegroundColor Yellow
}