[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $true

$repositoryRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
Push-Location $repositoryRoot

function Get-AzdValue {
    param([Parameter(Mandatory)][string]$Name)
    $value = [Environment]::GetEnvironmentVariable($Name)
    if ([string]::IsNullOrWhiteSpace($value)) {
        $value = (& azd env get-value $Name).Trim()
    }
    if ([string]::IsNullOrWhiteSpace($value)) {
        throw "Required azd environment value '$Name' is missing."
    }
    return $value
}

function Invoke-WithRetry {
    param([Parameter(Mandatory)][scriptblock]$Operation)
    for ($attempt = 1; $attempt -le 6; $attempt++) {
        try {
            return & $Operation
        } catch {
            if ($attempt -eq 6) { throw }
            Start-Sleep -Seconds 10
        }
    }
}

$parameterPath = $null
$buildContext = $null
$publishRoot = $null
$helperRoot = $null
$registryPassword = $null

try {
    $dotnet = (Get-Command dotnet -ErrorAction Stop).Source
    if (-not (@(& $dotnet --list-sdks) | Where-Object { $_ -match '^1[0-9]\.' })) {
        throw '.NET 10 SDK or later is required.'
    }

    $subscriptionId = Get-AzdValue 'AZURE_SUBSCRIPTION_ID'
    $environmentName = Get-AzdValue 'AZURE_ENV_NAME'
    $resourceGroup = Get-AzdValue 'AZURE_RESOURCE_GROUP'
    $registryName = Get-AzdValue 'AZURE_CONTAINER_REGISTRY_NAME'
    $registryEndpoint = Get-AzdValue 'AZURE_CONTAINER_REGISTRY_ENDPOINT'
    $imageRepository = Get-AzdValue 'AZURE_IMAGE_REPOSITORY'
    $tokenName = Get-AzdValue 'AZURE_ACR_TOKEN_NAME'
    $functionAppName = Get-AzdValue 'AZURE_DOCUMENT_FUNCTION_NAME'
    $functionLocation = Get-AzdValue 'AZURE_FUNCTION_LOCATION'
    $planId = Get-AzdValue 'AZURE_DOCUMENT_PLAN_ID'
    $storageName = Get-AzdValue 'AZURE_STORAGE_ACCOUNT_NAME'
    $busNamespace = Get-AzdValue 'AZURE_SERVICE_BUS_NAMESPACE'
    $queueName = Get-AzdValue 'AZURE_SHIPMENT_QUEUE'
    $insights = Get-AzdValue 'AZURE_APPLICATION_INSIGHTS_CONNECTION_STRING'
    $identityId = Get-AzdValue 'AZURE_USER_ASSIGNED_IDENTITY_ID'
    $identityClientId = Get-AzdValue 'AZURE_USER_ASSIGNED_IDENTITY_CLIENT_ID'

    & az account set --subscription $subscriptionId

    $buildContext = Join-Path ([IO.Path]::GetTempPath()) "ship-doc-context-$([guid]::NewGuid().ToString('N'))"
    $publishRoot = Join-Path ([IO.Path]::GetTempPath()) "ship-doc-publish-$([guid]::NewGuid().ToString('N'))"
    $helperRoot = Join-Path ([IO.Path]::GetTempPath()) "ship-doc-helper-$([guid]::NewGuid().ToString('N'))"
    New-Item -ItemType Directory -Path $buildContext, $publishRoot, $helperRoot | Out-Null

    & $dotnet publish .\infra\scripts\DeployHelper\DeployHelper.csproj `
        --configuration Release --output $helperRoot --nologo -p:NuGetAudit=false | Out-Null
    $helper = Join-Path $helperRoot 'DeployHelper.dll'

    & $dotnet restore .\tests\ShippingDocumentWorker.Tests\ShippingDocumentWorker.Tests.csproj `
        --nologo -p:NuGetAudit=false
    & $dotnet test .\tests\ShippingDocumentWorker.Tests\ShippingDocumentWorker.Tests.csproj `
        --configuration Release --no-restore --nologo `
        -p:TreatWarningsAsErrors=true -p:NuGetAudit=false
    & $dotnet restore .\ShippingDocumentWorker.csproj `
        --nologo -p:NuGetAudit=false
    & $dotnet publish .\ShippingDocumentWorker.csproj `
        --configuration Release --self-contained false --no-restore `
        --output (Join-Path $publishRoot 'app') --nologo `
        -p:TreatWarningsAsErrors=true `
        -p:DebugType=None -p:DebugSymbols=false -p:NuGetAudit=false
    & $dotnet restore .\tests\RenderCheck\RenderCheck.csproj `
        --nologo -p:NuGetAudit=false
    & $dotnet publish .\tests\RenderCheck\RenderCheck.csproj `
        --configuration Release --self-contained false --no-restore `
        --output (Join-Path $publishRoot 'rendercheck') --nologo `
        -p:TreatWarningsAsErrors=true -p:DebugType=None `
        -p:DebugSymbols=false -p:NuGetAudit=false

    Remove-Item (Join-Path $publishRoot 'app\worker.config.json') -Force -ErrorAction SilentlyContinue
    Remove-Item (Join-Path $publishRoot 'app\functions.metadata') -Force -ErrorAction SilentlyContinue

    $contextHash = (& $dotnet $helper stage-context $buildContext $publishRoot).Trim()
    if ($contextHash -notmatch '^[0-9a-f]{64}$') {
        throw "Invalid image-context hash: '$contextHash'."
    }
    $imageTag = "azd-$contextHash"
    $taggedImage = "$imageRepository`:$imageTag"

    $tagExists = $false
    $repositories = @(& az acr repository list --name $registryName --output tsv --only-show-errors)
    if ($repositories -contains $imageRepository) {
        $tags = @(& az acr repository show-tags --name $registryName --repository $imageRepository --output tsv --only-show-errors)
        $tagExists = $tags -contains $imageTag
    }

    if ($tagExists) {
        $buildAction = 'reused'
        Write-Host "Reusing $registryEndpoint/$taggedImage"
    } else {
        $buildAction = 'built'
        $run = (& az acr build --registry $registryName `
            --resource-group $resourceGroup --platform linux/amd64 `
            --file dotnet10.Dockerfile --image $taggedImage `
            --timeout 1800 --no-logs --only-show-errors --output json `
            $buildContext) | ConvertFrom-Json
        if ($run.status -ne 'Succeeded') {
            throw "ACR build '$($run.runId)' ended in '$($run.status)'."
        }
    }

    $digest = Invoke-WithRetry {
        $value = (& az acr manifest show-metadata --registry $registryName `
            --name $taggedImage --query digest --output tsv --only-show-errors).Trim()
        if ($value -notmatch '^sha256:[0-9a-f]{64}$') {
            throw 'Image digest is not available yet.'
        }
        $value
    }
    $registryImage = "$registryEndpoint/$taggedImage@$digest"

    & az acr repository update --name $registryName --image $taggedImage `
        --write-enabled false --delete-enabled false --only-show-errors | Out-Null
    $registryPassword = Invoke-WithRetry {
        $value = (& az acr token credential generate --registry $registryName `
            --resource-group $resourceGroup --name $tokenName `
            --password1 --expiration-in-days 7 `
            --query "passwords[?name=='password1'].value | [0]" `
            --output tsv --only-show-errors).Trim()
        if ([string]::IsNullOrWhiteSpace($value)) {
            throw 'ACR token password generation returned no value.'
        }
        $value
    }

    $parameterPath = Join-Path ([IO.Path]::GetTempPath()) "ship-doc-$([guid]::NewGuid().ToString('N')).parameters.json"
    $parameterEnvironment = @{
        AZURE_ENV_NAME = $environmentName
        AZURE_DOCUMENT_FUNCTION_NAME = $functionAppName
        AZURE_FUNCTION_LOCATION = $functionLocation
        AZURE_DOCUMENT_PLAN_ID = $planId
        AZURE_APPLICATION_INSIGHTS_CONNECTION_STRING = $insights
        AZURE_STORAGE_ACCOUNT_NAME = $storageName
        AZURE_SERVICE_BUS_NAMESPACE_FQDN = "$busNamespace.servicebus.windows.net"
        AZURE_SHIPMENT_QUEUE = $queueName
        AZURE_USER_ASSIGNED_IDENTITY_ID = $identityId
        AZURE_USER_ASSIGNED_IDENTITY_CLIENT_ID = $identityClientId
        REGISTRY_IMAGE = $registryImage
        AZURE_ACR_TOKEN_NAME = $tokenName
        REGISTRY_PASSWORD = $registryPassword
    }
    foreach ($entry in $parameterEnvironment.GetEnumerator()) {
        [Environment]::SetEnvironmentVariable($entry.Key, $entry.Value)
    }
    & $dotnet $helper write-parameters $parameterPath

    $state = (& az deployment group create --resource-group $resourceGroup `
        --name "document-worker-$([DateTime]::UtcNow.ToString('yyyyMMddHHmmss'))" `
        --template-file .\infra\document-worker.bicep `
        --parameters "@$parameterPath" `
        --query properties.provisioningState --output tsv `
        --only-show-errors).Trim()
    if ($state -ne 'Succeeded') {
        throw "Document worker deployment ended in '$state'."
    }

    & azd env set AZURE_IMAGE_CONTEXT_HASH $contextHash --no-prompt | Out-Null
    & azd env set AZURE_IMAGE_BUILD_ACTION $buildAction --no-prompt | Out-Null
    & azd env set AZURE_IMAGE_DIGEST $digest --no-prompt | Out-Null
    & azd env set AZURE_REGISTRY_IMAGE $registryImage --no-prompt | Out-Null
    Write-Host "Document worker image: $registryImage"
} finally {
    foreach ($name in @(
        'AZURE_ENV_NAME', 'AZURE_DOCUMENT_FUNCTION_NAME',
        'AZURE_FUNCTION_LOCATION', 'AZURE_DOCUMENT_PLAN_ID',
        'AZURE_APPLICATION_INSIGHTS_CONNECTION_STRING',
        'AZURE_STORAGE_ACCOUNT_NAME', 'AZURE_SERVICE_BUS_NAMESPACE_FQDN',
        'AZURE_SHIPMENT_QUEUE', 'AZURE_USER_ASSIGNED_IDENTITY_ID',
        'AZURE_USER_ASSIGNED_IDENTITY_CLIENT_ID', 'REGISTRY_IMAGE',
        'AZURE_ACR_TOKEN_NAME', 'REGISTRY_PASSWORD'
    )) {
        [Environment]::SetEnvironmentVariable($name, $null)
    }
    foreach ($path in @($parameterPath, $buildContext, $publishRoot, $helperRoot)) {
        if ($path -and (Test-Path -LiteralPath $path)) {
            Remove-Item -LiteralPath $path -Recurse -Force
        }
    }
    $registryPassword = $null
    Pop-Location
}
