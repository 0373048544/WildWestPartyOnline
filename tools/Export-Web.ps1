param([Parameter(Mandatory=$true)][string]$Godot, [switch]$Release)
$ErrorActionPreference = 'Stop'
$projectPath = Split-Path -Parent $PSScriptRoot
New-Item -ItemType Directory -Force -Path (Join-Path $projectPath 'build/web') | Out-Null
$mode = if ($Release) { '--export-release' } else { '--export-debug' }
& $Godot --headless --path $projectPath $mode Web (Join-Path $projectPath 'build/web/index.html')
if ($LASTEXITCODE -ne 0) { throw 'Godot Web export failed.' }
Copy-Item -LiteralPath (Join-Path $projectPath 'web/network-config.js') -Destination (Join-Path $projectPath 'build/web/network-config.js') -Force
Copy-Item -LiteralPath (Join-Path $projectPath 'web/mobile-shell.css') -Destination (Join-Path $projectPath 'build/web/mobile-shell.css') -Force
$indexPath = Join-Path $projectPath 'build/web/index.html'
$html = Get-Content -LiteralPath $indexPath -Raw
# Godot's stock shell owns the single viewport tag. Normalize it after every
# export so iPhone safe-area support persists without injecting a duplicate.
$html = [regex]::Replace(
    $html,
    '<meta\s+name="viewport"\s+content="[^"]*">',
    '<meta name="viewport" content="width=device-width, initial-scale=1.0, user-scalable=no, viewport-fit=cover">'
)
$viewportTags = [regex]::Matches($html, '<meta\s+name="viewport"').Count
if ($viewportTags -ne 1) { throw "Expected exactly one viewport meta tag, found $viewportTags." }
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText($indexPath, $html, $utf8NoBom)
