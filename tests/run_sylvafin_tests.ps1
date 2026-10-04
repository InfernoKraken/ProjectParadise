param([switch]$RegressionOnly)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path $PSScriptRoot -Parent
$logPath = Join-Path $projectRoot 'sylvafin_suite.log'
$arguments = @('--headless', '--rendering-driver', 'opengl3', '--path', $projectRoot, '--log-file', $logPath, '--script', 'tests/sylvafin_habitat_test.gd')
if ($RegressionOnly) { $arguments += @('--', '--regression-only') }
& godot @arguments | Out-Null
# Some Windows launchers do not propagate Godot's exit status. Require the summary.
$output = Get-Content -LiteralPath $logPath -Raw
$output -split "`n" | Where-Object { $_ -match '^(PASS:|FAIL:|SYLVAFIN_HABITAT:)|SCRIPT ERROR:' } | Write-Output
if ($output -notmatch 'SYLVAFIN_HABITAT: \d+ checks, 0 failures' -or $output -match 'SCRIPT ERROR:') { exit 1 }
exit 0
