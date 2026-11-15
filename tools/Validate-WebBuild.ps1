param(
    [string]$WebRoot = (Join-Path (Split-Path -Parent $PSScriptRoot) 'build/web'),
    [string]$SourceRoot = (Join-Path (Split-Path -Parent $PSScriptRoot) 'web')
)

$ErrorActionPreference = 'Stop'

function Fail([string]$Message) {
    throw "Web release validation failed: $Message"
}

$required = @(
    'index.html', 'index.js', 'index.pck', 'index.wasm',
    'network-config.js', 'mobile-shell.css', 'viewport-bootstrap.js'
)
foreach ($name in $required) {
    $path = Join-Path $WebRoot $name
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { Fail "missing $name" }
    if ((Get-Item -LiteralPath $path).Length -le 0) { Fail "$name is empty" }
}

$indexPath = Join-Path $WebRoot 'index.html'
$html = [System.IO.File]::ReadAllText($indexPath, [System.Text.Encoding]::UTF8)
$viewportTags = [regex]::Matches($html, '<meta\s+name="viewport"\s+content="[^"]*">', 'IgnoreCase')
if ($viewportTags.Count -ne 1) { Fail "expected exactly one viewport meta tag, found $($viewportTags.Count)" }
if (-not $viewportTags[0].Value.Contains('viewport-fit=cover')) { Fail 'viewport meta is missing viewport-fit=cover' }
if ($html -notmatch '<html\s+lang="vi">') { Fail 'Web shell language must be Vietnamese (lang="vi")' }
if ($html -match '<title>[^<]*(Miá|TÃ¢y|Äáº¡i)[^<]*</title>') { Fail 'Web title contains mojibake instead of UTF-8 Vietnamese' }
foreach ($asset in @('network-config.js', 'mobile-shell.css', 'viewport-bootstrap.js')) {
    if (-not $html.Contains($asset)) { Fail "index.html does not reference $asset" }
    $source = Join-Path $SourceRoot $asset
    $built = Join-Path $WebRoot $asset
    if (-not (Test-Path -LiteralPath $source -PathType Leaf)) { Fail "missing source web/$asset" }
    if ((Get-FileHash -LiteralPath $source).Hash -ne (Get-FileHash -LiteralPath $built).Hash) {
        Fail "build/web/$asset differs from web/$asset"
    }
}

Write-Output "PASS: Web release contains one viewport-fit=cover tag, synchronized shell assets and non-empty Godot payloads."
