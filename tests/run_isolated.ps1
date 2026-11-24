param(
    [Parameter(Mandatory)] [string] $Godot,
    [switch] $Windowed,
    [string] $Script = '',
    [string] $Scene = '',
    [ValidateRange(0, 1000000)] [int] $QuitAfter = 0,
    [string[]] $UserArguments = @()
)

$ErrorActionPreference = 'Stop'
if ($Script -and $Scene) { throw 'Choose either a script or a scene.' }
$engine = (Resolve-Path -LiteralPath $Godot).Path
$project = Split-Path -Parent $PSScriptRoot
$sandbox = Join-Path $project ('.godot\isolated-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $sandbox | Out-Null
$log = Join-Path $sandbox 'run.log'
$previousAppData = $env:APPDATA
$previousIsolation = $env:CUBDOKU_TEST_USER_DIR
$env:APPDATA = $sandbox
$env:CUBDOKU_TEST_USER_DIR = Join-Path $sandbox 'Godot\app_userdata\Cubdoku'

$arguments = @('--path', ('"{0}"' -f $project), '--log-file', ('"{0}"' -f $log))
if (-not $Windowed) { $arguments += '--headless' }
if ($Script) { $arguments += @('--script', $Script) }
if ($Scene) { $arguments += $Scene }
if ($QuitAfter) { $arguments += @('--quit-after', $QuitAfter) }
if ($UserArguments.Count) { $arguments += '--'; $arguments += $UserArguments }
try {
    Write-Output "Isolated Godot user directory: $env:CUBDOKU_TEST_USER_DIR"
    $process = Start-Process -FilePath $engine -ArgumentList $arguments -WindowStyle $(if ($Windowed) {'Normal'} else {'Hidden'}) -Wait -PassThru
    if (-not (Test-Path -LiteralPath $log)) { throw "Godot did not create $log" }
    if ($process.ExitCode -ne 0 -or (Select-String -LiteralPath $log -Pattern 'SCRIPT ERROR' -Quiet)) {
        Get-Content -LiteralPath $log -TotalCount 30
        throw "Godot failed. See $log"
    }
    Get-Content -LiteralPath $log
} finally {
    $env:APPDATA = $previousAppData
    $env:CUBDOKU_TEST_USER_DIR = $previousIsolation
}
