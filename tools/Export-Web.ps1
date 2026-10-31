param([Parameter(Mandatory=$true)][string]$Godot, [switch]$Release)
$ErrorActionPreference = 'Stop'
$projectPath = Split-Path -Parent $PSScriptRoot
New-Item -ItemType Directory -Force -Path (Join-Path $projectPath 'build/web') | Out-Null
$mode = if ($Release) { '--export-release' } else { '--export-debug' }
& $Godot --headless --path $projectPath $mode Web (Join-Path $projectPath 'build/web/index.html')
if ($LASTEXITCODE -ne 0) { throw 'Godot Web export failed.' }
Copy-Item -LiteralPath (Join-Path $projectPath 'web/network-config.js') -Destination (Join-Path $projectPath 'build/web/network-config.js') -Force
