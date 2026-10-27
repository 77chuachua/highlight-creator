# Run the test suites from a normal (non-sandboxed) shell: flutter needs to
# spawn its compiler and flutter_tester, which a confined shell blocks, and it
# writes to %APPDATA% and the SDK cache.
#
#   powershell -NoProfile -ExecutionPolicy Bypass -File run_tests.ps1
#
# The agent reads the log this writes; it cannot run the suites itself.

$ErrorActionPreference = 'Continue'
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$log = Join-Path $root 'temp\test_run.log'
$app = Join-Path $root 'app'
New-Item -ItemType Directory -Force -Path (Join-Path $root 'temp') | Out-Null

if (-not (Get-Command flutter -ErrorAction SilentlyContinue)) {
    $env:PATH = "C:\Code\flutter-sdk\flutter\bin;$env:PATH"
}

# drift needs sqlite3.dll, which only exists next to a built desktop runner.
$runner = Join-Path $app 'build\windows\x64\runner\Debug'
if (Test-Path $runner) { $env:PATH = "$runner;$env:PATH" }

Set-Location $app

$steps = @(
    @{ name = 'slotCaption unit tests'; args = @('test/data/video_processing_service_test.dart') },
    @{ name = 'make pipeline e2e';      args = @('test/e2e/make_pipeline_test.dart') },
    @{ name = 'full suite';             args = @() }
)

"" | Set-Content -Path $log -Encoding utf8
foreach ($step in $steps) {
    "==== $($step.name) ====" | Add-Content -Path $log -Encoding utf8
    & flutter test @($step.args) --no-pub *>> $log
}

$text = Get-Content $log -Raw
Write-Host "Log: $log"
if ($text -match 'Some tests failed') {
    Write-Host 'SOME TESTS FAILED'
    exit 1
}
if ($text -match 'All tests passed') {
    Write-Host 'ALL PASSED'
    exit 0
}
Write-Host 'Unknown result - open the log above.'
exit 0
