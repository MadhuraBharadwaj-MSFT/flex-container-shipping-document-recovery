$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $true

python ./scripts/seed_schema.py
& ./infra/scripts/deployimage.ps1
