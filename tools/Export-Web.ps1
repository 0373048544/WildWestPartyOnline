param([Parameter(Mandatory=$true)][string]$Godot, [switch]$Release)
$ErrorActionPreference = 'Stop'
$projectPath = Split-Path -Parent $PSScriptRoot
New-Item -ItemType Directory -Force -Path (Join-Path $projectPath 'build/web') | Out-Null
$mode = if ($Release) { '--export-release' } else { '--export-debug' }
& $Godot --headless --path $projectPath $mode Web (Join-Path $projectPath 'build/web/index.html')
if ($LASTEXITCODE -ne 0) { throw 'Godot Web export failed.' }
Copy-Item -LiteralPath (Join-Path $projectPath 'web/network-config.js') -Destination (Join-Path $projectPath 'build/web/network-config.js') -Force
Copy-Item -LiteralPath (Join-Path $projectPath 'web/mobile-shell.css') -Destination (Join-Path $projectPath 'build/web/mobile-shell.css') -Force
Copy-Item -LiteralPath (Join-Path $projectPath 'web/viewport-bootstrap.js') -Destination (Join-Path $projectPath 'build/web/viewport-bootstrap.js') -Force
$indexPath = Join-Path $projectPath 'build/web/index.html'
$html = [System.IO.File]::ReadAllText($indexPath, [System.Text.Encoding]::UTF8)
# Godot's stock shell owns the single viewport tag. Normalize it after every
# export so iPhone safe-area support persists without injecting a duplicate.
$html = [regex]::Replace(
    $html,
    '<meta\s+name="viewport"\s+content="[^"]*">',
    '<meta name="viewport" content="width=device-width, initial-scale=1.0, user-scalable=no, viewport-fit=cover">'
)
$projectText = [System.IO.File]::ReadAllText((Join-Path $projectPath 'project.godot'), [System.Text.Encoding]::UTF8)
$projectNameMatch = [regex]::Match($projectText, '(?m)^config/name="([^"]+)"')
if (-not $projectNameMatch.Success) { throw 'Could not read config/name from project.godot.' }
$projectTitle = $projectNameMatch.Groups[1].Value.Replace('&', '&amp;').Replace('<', '&lt;').Replace('>', '&gt;')
$html = [regex]::Replace($html, '<title>[^<]*</title>', '<title>' + $projectTitle + '</title>')
$html = [regex]::Replace($html, '<html\s+lang="[^"]*">', '<html lang="vi">')
$viewportTags = [regex]::Matches($html, '<meta\s+name="viewport"').Count
if ($viewportTags -ne 1) { throw "Expected exactly one viewport meta tag, found $viewportTags." }
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText($indexPath, $html, $utf8NoBom)
& (Join-Path $PSScriptRoot 'Validate-WebBuild.ps1') -WebRoot (Join-Path $projectPath 'build/web') -SourceRoot (Join-Path $projectPath 'web')
if ($LASTEXITCODE -ne 0) { throw 'Godot Web release validation failed.' }
