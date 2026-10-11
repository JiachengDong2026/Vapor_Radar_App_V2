param(
    [Parameter(Mandatory=$true)][string]$OutputRoot,
    [Parameter(Mandatory=$true)][string]$CyUsbDll,
    [string]$QtRoot='C:\Qt\6.11.2\mingw_64',
    [string]$MingwRoot='C:\Qt\Tools\mingw1310_64',
    [string]$CMakeExe='C:\Qt\Tools\CMake_64\bin\cmake.exe',
    [string]$NinjaRoot='C:\Qt\Tools\Ninja',
    [string]$CscExe='C:\Windows\Microsoft.NET\Framework64\v4.0.30319\csc.exe',
    [switch]$SkipDeploy
)
$ErrorActionPreference='Stop'
$projectDir=$PSScriptRoot
$repositoryRoot=[IO.Path]::GetFullPath((Join-Path $projectDir '..\..')).TrimEnd('\','/')
$outputPath=[IO.Path]::GetFullPath($OutputRoot).TrimEnd('\','/')
if ($outputPath.Equals($repositoryRoot,[StringComparison]::OrdinalIgnoreCase) -or
    $outputPath.StartsWith($repositoryRoot+'\',[StringComparison]::OrdinalIgnoreCase)) {
    throw 'OutputRoot must be outside the formal repository (use Vapor_Lc_App_Test).'
}
$cyusbSource=(Resolve-Path -LiteralPath $CyUsbDll).Path
foreach ($dependency in @($CMakeExe,$CscExe,"$QtRoot\bin\windeployqt.exe","$MingwRoot\bin\g++.exe","$NinjaRoot\ninja.exe")) {
    if (!(Test-Path -LiteralPath $dependency -PathType Leaf)) { throw "Missing dependency: $dependency" }
}
$buildDir=Join-Path $outputPath 'build'
$distDir=Join-Path $outputPath 'dist'
New-Item -ItemType Directory -Path $outputPath,$distDir -Force | Out-Null
$originalPath=$env:PATH
$env:PATH="$QtRoot\bin;$MingwRoot\bin;$NinjaRoot;$env:PATH"
Push-Location $outputPath
try {
    & $CMakeExe -S $projectDir -B $buildDir -G Ninja "-DCMAKE_PREFIX_PATH=$QtRoot" "-DCMAKE_CXX_COMPILER=$MingwRoot\bin\g++.exe" -DCMAKE_BUILD_TYPE=Release
    if ($LASTEXITCODE -ne 0) { throw 'CMake configuration failed' }
    & $CMakeExe --build $buildDir --parallel 4
    if ($LASTEXITCODE -ne 0) { throw 'C++ build failed' }
    Copy-Item -LiteralPath $cyusbSource -Destination "$distDir\CyUSB.dll"
    & $CscExe /nologo /optimize+ /target:exe /platform:x64 "/reference:$distDir\CyUSB.dll" "/out:$distDir\VaporUsbBridge.exe" "$projectDir\bridge\VaporUsbBridge.cs"
    if ($LASTEXITCODE -ne 0) { throw 'USB bridge build failed' }
    Copy-Item -LiteralPath "$buildDir\VaporMonitor.exe" -Destination "$distDir\VaporMonitor.exe"
    if (!$SkipDeploy) {
        & "$QtRoot\bin\windeployqt.exe" --release --no-translations --no-system-d3d-compiler --no-opengl-sw "$distDir\VaporMonitor.exe"
        if ($LASTEXITCODE -ne 0) { throw 'Qt deployment failed' }
        Copy-Item -LiteralPath "$QtRoot\plugins\platforms\qoffscreen.dll" -Destination "$distDir\platforms\qoffscreen.dll"
    }
    Write-Host "Ready: $distDir\VaporMonitor.exe"
} finally {
    Pop-Location
    $env:PATH=$originalPath
}
