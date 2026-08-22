# Validate the relay compose file without a live VPS.
# Requires: Docker Compose v2, Python 3.
$ErrorActionPreference = "Stop"
$RelayRoot = Split-Path -Parent $PSScriptRoot
Set-Location $RelayRoot

Write-Host "== render templates from .env.example (temp dir; do not clobber generated/) =="
$RenderOut = Join-Path $env:TEMP "keryx-relay-validate"
python "$RelayRoot\scripts\render_config.py" --env "$RelayRoot\.env.example" --out $RenderOut
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

Write-Host "== docker compose --env-file .env.example config =="
docker compose --env-file "$RelayRoot\.env.example" config
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

Write-Host "== unit checks =="
python "$RelayRoot\tests\test_relay_config.py"
exit $LASTEXITCODE
