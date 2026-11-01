param(
    [string]$Godot = 'godot',
    [switch]$SkipRenderer
)

$ErrorActionPreference = 'Stop'
$testRoot = Split-Path -Parent $PSScriptRoot
$artifactRoot = Join-Path $testRoot 'tests/artifacts'
New-Item -ItemType Directory -Force -Path $artifactRoot | Out-Null
$results = [Collections.Generic.List[object]]::new()

function Start-TestProcess([string]$suite, [string]$tag, [string[]]$extra, [bool]$headless) {
    $stdout = Join-Path $artifactRoot "$tag.stdout"
    $stderr = Join-Path $artifactRoot "$tag.stderr"
    $engineLog = Join-Path $artifactRoot "$tag.log"
    $arguments = @('--path', $testRoot, '--log-file', $engineLog)
    if ($headless) { $arguments += '--headless' }
    $arguments += "tests/$suite.tscn"
    if ($extra.Count) { $arguments += '--'; $arguments += $extra }
    $process = Start-Process -FilePath $Godot -ArgumentList $arguments -WorkingDirectory $testRoot -WindowStyle Hidden -PassThru -RedirectStandardOutput $stdout -RedirectStandardError $stderr
    # Retain the process handle even if a short test exits before collection.
    $null = $process.Handle
    return @{ Process = $process; Tag = $tag; Out = $stdout; Err = $stderr }
}

function Complete-TestProcess($job, [int]$timeoutSeconds = 90) {
    $finished = $job.Process.WaitForExit($timeoutSeconds * 1000)
    if (-not $finished) { $job.Process.Kill(); $job.Process.WaitForExit() }
    $output = (Get-Content -LiteralPath $job.Out -Raw -Encoding UTF8) + (Get-Content -LiteralPath $job.Err -Raw -Encoding UTF8)
    $exitCode = $job.Process.ExitCode
    $passed = $finished -and ($null -eq $exitCode -or $exitCode -eq 0) -and $output.Contains('PASS:') -and $output -notmatch 'SCRIPT ERROR|Parse Error|FAILED:'
    $results.Add([pscustomobject]@{ Suite = $job.Tag; Passed = $passed; ExitCode = $exitCode; TimedOut = -not $finished })
    Write-Output "$(if ($passed) { 'PASS' } else { 'FAIL' }): $($job.Tag)"
    if (-not $passed) { Write-Output $output }
}

# Multiplayer test scenes require real peers, not a single unconfigured process.
foreach ($testScene in (Get-ChildItem (Join-Path $testRoot 'tests') -Filter '*Test.tscn' | Sort-Object Name)) {
    if ($testScene.BaseName -in @('NetworkTest', 'LobbyTest', 'TableProfileTest')) { continue }
    $job = Start-TestProcess $testScene.BaseName "all-$($testScene.BaseName)" @() $true
    Complete-TestProcess $job
}

$lobbyJobs = @()
$lobbyJobs += Start-TestProcess 'LobbyTest' 'all-Lobby-host' @('--host') $true
Start-Sleep -Milliseconds 500
$lobbyJobs += Start-TestProcess 'LobbyTest' 'all-Lobby-client' @() $true
foreach ($job in $lobbyJobs) { Complete-TestProcess $job 40 }

$networkJobs = @()
$networkJobs += Start-TestProcess 'NetworkTest' 'all-Network-host' @('--host', '--players=4') $true
Start-Sleep -Milliseconds 500
for ($index = 1; $index -le 3; $index++) {
    $networkJobs += Start-TestProcess 'NetworkTest' "all-Network-client$index" @('--players=4') $true
}
foreach ($job in $networkJobs) { Complete-TestProcess $job 50 }

if (-not $SkipRenderer) {
    Complete-TestProcess (Start-TestProcess 'TableProfileTest' 'all-TableProfileTest' @() $false)
    Complete-TestProcess (Start-TestProcess 'ResponsiveLayoutTest' 'all-ResponsiveCapture' @('--capture') $false)
}

$results | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $artifactRoot 'all-tests-summary.json') -Encoding UTF8
$failed = @($results | Where-Object { -not $_.Passed })
Write-Output "Total: $($results.Count); passed: $($results.Count - $failed.Count); failed: $($failed.Count)"
if ($failed.Count) { exit 1 }
