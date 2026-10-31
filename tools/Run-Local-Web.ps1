param([Parameter(Mandatory=$true)][string]$Godot)
$ErrorActionPreference = 'Stop'
$projectPath = Split-Path -Parent $PSScriptRoot
if (-not (Test-Path -LiteralPath (Join-Path $projectPath 'build/web/index.html'))) {
    throw 'Web build missing. Run tools/Export-Web.ps1 first.'
}
$serverLog = Join-Path $projectPath 'tests/web/local-server.log'
$serverErr = Join-Path $projectPath 'tests/web/local-server.err'
$webLog = Join-Path $projectPath 'tests/web/local-http.log'
$webErr = Join-Path $projectPath 'tests/web/local-http.err'
$gameProcess = Start-Process -FilePath $Godot -ArgumentList @('--headless','--path', ('"' + $projectPath + '"'),'--log-file',('"' + $serverLog + '"'),'server/DedicatedServer.tscn','--','--development') -WindowStyle Hidden -PassThru -RedirectStandardOutput (Join-Path $projectPath 'tests/web/local-server-stdout.log') -RedirectStandardError $serverErr
$webProcess = Start-Process -FilePath 'node' -ArgumentList @('tools/serve-web.cjs') -WorkingDirectory $projectPath -WindowStyle Hidden -PassThru -RedirectStandardOutput $webLog -RedirectStandardError $webErr
Write-Output "Local game: http://127.0.0.1:8080"
Write-Output "Game server PID: $($gameProcess.Id); Web server PID: $($webProcess.Id)"
Write-Output 'Stop these two PIDs with Stop-Process after testing. Both bind only to 127.0.0.1.'
