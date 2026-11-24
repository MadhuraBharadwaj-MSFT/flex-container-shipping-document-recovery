$ErrorActionPreference = 'Stop'
$url = (& azd env get-value DEMO_URL).Trim()
Write-Host "Demo UI: $url"
Write-Host "Sign in with the configured demo-owner Microsoft account."
