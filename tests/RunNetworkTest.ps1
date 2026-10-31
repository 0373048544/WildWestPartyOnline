param(
    [Parameter(Mandatory=$true)][string]$Godot,
    [string]$TestScene = 'tests/NetworkTest.tscn',
    [ValidateRange(2, 8)][int]$ProcessCount = 4
)
$ErrorActionPreference = 'Stop'
$projectPath = Split-Path -Parent $PSScriptRoot
$testProcesses = @()
try {
    for ($index = 0; $index -lt $ProcessCount; $index++) {
        $mode = if ($index -eq 0) { '--host' } else { '--client' }
        if ($ProcessCount -eq 8 -and $index -eq 7) {
            Start-Sleep -Milliseconds 700
            $mode = '--overflow'
        }
        $logPath = Join-Path $PSScriptRoot "network-$index.log"
        $errorPath = Join-Path $PSScriptRoot "network-$index.err"
        $playerCount = if ($ProcessCount -eq 8) { 7 } else { $ProcessCount }
        $testProcesses += Start-Process -FilePath $Godot -ArgumentList @('--headless', '--path', $projectPath, $TestScene, '--', $mode, "--players=$playerCount") -WindowStyle Hidden -PassThru -RedirectStandardOutput $logPath -RedirectStandardError $errorPath
        $null = $testProcesses[-1].Handle
        if ($index -eq 0) { Start-Sleep -Milliseconds 700 }
    }
    foreach ($testProcess in $testProcesses) {
        if (-not $testProcess.WaitForExit(45000)) { throw 'Network test timed out.' }
    }
    for ($index = 0; $index -lt $ProcessCount; $index++) {
        Get-Content -LiteralPath (Join-Path $PSScriptRoot "network-$index.log")
        $errors = Get-Content -LiteralPath (Join-Path $PSScriptRoot "network-$index.err") -Raw
        if ($errors) { throw $errors }
        if ($testProcesses[$index].ExitCode -ne 0) { throw "Peer $index failed." }
    }
} finally {
    foreach ($testProcess in $testProcesses) {
        if (-not $testProcess.HasExited) { Stop-Process -Id $testProcess.Id }
    }
}
