#!/usr/bin/env sh
set -eu

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
cd "$repo_root"

azd_value() {
  value=$(printenv "$1" 2>/dev/null || true)
  if [ -z "$value" ]; then value=$(azd env get-value "$1"); fi
  if [ -z "$value" ]; then echo "Missing azd value: $1" >&2; exit 1; fi
  printf '%s' "$value"
}

command -v dotnet >/dev/null 2>&1 || { echo ".NET 10 SDK is required." >&2; exit 1; }
dotnet --list-sdks | grep -Eq '^1[0-9]\.' || { echo ".NET 10 SDK is required." >&2; exit 1; }

subscription_id=$(azd_value AZURE_SUBSCRIPTION_ID)
environment_name=$(azd_value AZURE_ENV_NAME)
resource_group=$(azd_value AZURE_RESOURCE_GROUP)
registry_name=$(azd_value AZURE_CONTAINER_REGISTRY_NAME)
registry_endpoint=$(azd_value AZURE_CONTAINER_REGISTRY_ENDPOINT)
image_repository=$(azd_value AZURE_IMAGE_REPOSITORY)
token_name=$(azd_value AZURE_ACR_TOKEN_NAME)
function_name=$(azd_value AZURE_DOCUMENT_FUNCTION_NAME)
function_location=$(azd_value AZURE_FUNCTION_LOCATION)
plan_id=$(azd_value AZURE_DOCUMENT_PLAN_ID)
storage_name=$(azd_value AZURE_STORAGE_ACCOUNT_NAME)
bus_namespace=$(azd_value AZURE_SERVICE_BUS_NAMESPACE)
queue_name=$(azd_value AZURE_SHIPMENT_QUEUE)
insights=$(azd_value AZURE_APPLICATION_INSIGHTS_CONNECTION_STRING)
identity_id=$(azd_value AZURE_USER_ASSIGNED_IDENTITY_ID)
identity_client_id=$(azd_value AZURE_USER_ASSIGNED_IDENTITY_CLIENT_ID)

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT INT TERM
context="$work/context"
publish="$work/publish"
helper_root="$work/helper"
mkdir -p "$context" "$publish" "$helper_root"

dotnet publish ./infra/scripts/DeployHelper/DeployHelper.csproj \
  --configuration Release --output "$helper_root" --nologo -p:NuGetAudit=false >/dev/null
helper="$helper_root/DeployHelper.dll"

dotnet restore ./tests/ShippingDocumentWorker.Tests/ShippingDocumentWorker.Tests.csproj --nologo -p:NuGetAudit=false
dotnet test ./tests/ShippingDocumentWorker.Tests/ShippingDocumentWorker.Tests.csproj \
  --configuration Release --no-restore --nologo \
  -p:TreatWarningsAsErrors=true -p:NuGetAudit=false
dotnet restore ./ShippingDocumentWorker.csproj --nologo -p:NuGetAudit=false
dotnet publish ./ShippingDocumentWorker.csproj --configuration Release \
  --self-contained false --no-restore \
  --output "$publish/app" --nologo -p:TreatWarningsAsErrors=true \
  -p:DebugType=None -p:DebugSymbols=false -p:NuGetAudit=false
dotnet restore ./tests/RenderCheck/RenderCheck.csproj --nologo -p:NuGetAudit=false
dotnet publish ./tests/RenderCheck/RenderCheck.csproj --configuration Release \
  --self-contained false --no-restore \
  --output "$publish/rendercheck" --nologo -p:TreatWarningsAsErrors=true \
  -p:DebugType=None -p:DebugSymbols=false -p:NuGetAudit=false
rm -f "$publish/app/worker.config.json" "$publish/app/functions.metadata"

context_hash=$(dotnet "$helper" stage-context "$context" "$publish")
image_tag="azd-$context_hash"
tagged_image="$image_repository:$image_tag"

az account set --subscription "$subscription_id"
if az acr repository show-tags --name "$registry_name" --repository "$image_repository" \
  --output tsv --only-show-errors 2>/dev/null | grep -Fxq "$image_tag"; then
  build_action=reused
else
  build_action=built
  az acr build --registry "$registry_name" --resource-group "$resource_group" \
    --platform linux/amd64 --file dotnet10.Dockerfile --image "$tagged_image" \
    --timeout 1800 --no-logs --only-show-errors "$context" >/dev/null
fi

digest=
attempt=0
while [ -z "$digest" ] && [ "$attempt" -lt 6 ]; do
  digest=$(az acr manifest show-metadata --registry "$registry_name" \
    --name "$tagged_image" --query digest --output tsv --only-show-errors 2>/dev/null || true)
  attempt=$((attempt + 1))
  [ -n "$digest" ] || sleep 10
done
echo "$digest" | grep -Eq '^sha256:[0-9a-f]{64}$' || { echo "Image digest unavailable." >&2; exit 1; }
registry_image="$registry_endpoint/$tagged_image@$digest"

az acr repository update --name "$registry_name" --image "$tagged_image" \
  --write-enabled false --delete-enabled false --only-show-errors >/dev/null
registry_password=$(az acr token credential generate --registry "$registry_name" \
  --resource-group "$resource_group" --name "$token_name" --password1 \
  --expiration-in-days 7 --query "passwords[?name=='password1'].value | [0]" \
  --output tsv --only-show-errors)
[ -n "$registry_password" ] || { echo "ACR token generation failed." >&2; exit 1; }

parameter_path="$work/document-worker.parameters.json"
export AZURE_ENV_NAME="$environment_name"
export AZURE_DOCUMENT_FUNCTION_NAME="$function_name"
export AZURE_FUNCTION_LOCATION="$function_location"
export AZURE_DOCUMENT_PLAN_ID="$plan_id"
export AZURE_APPLICATION_INSIGHTS_CONNECTION_STRING="$insights"
export AZURE_STORAGE_ACCOUNT_NAME="$storage_name"
export AZURE_SERVICE_BUS_NAMESPACE_FQDN="$bus_namespace.servicebus.windows.net"
export AZURE_SHIPMENT_QUEUE="$queue_name"
export AZURE_USER_ASSIGNED_IDENTITY_ID="$identity_id"
export AZURE_USER_ASSIGNED_IDENTITY_CLIENT_ID="$identity_client_id"
export REGISTRY_IMAGE="$registry_image"
export AZURE_ACR_TOKEN_NAME="$token_name"
export REGISTRY_PASSWORD="$registry_password"
dotnet "$helper" write-parameters "$parameter_path"

state=$(az deployment group create --resource-group "$resource_group" \
  --name "document-worker-$(date -u +%Y%m%d%H%M%S)" \
  --template-file ./infra/document-worker.bicep \
  --parameters "@$parameter_path" \
  --query properties.provisioningState --output tsv --only-show-errors)
[ "$state" = "Succeeded" ] || { echo "Document worker deployment failed: $state" >&2; exit 1; }

azd env set AZURE_IMAGE_CONTEXT_HASH "$context_hash" --no-prompt >/dev/null
azd env set AZURE_IMAGE_BUILD_ACTION "$build_action" --no-prompt >/dev/null
azd env set AZURE_IMAGE_DIGEST "$digest" --no-prompt >/dev/null
azd env set AZURE_REGISTRY_IMAGE "$registry_image" --no-prompt >/dev/null
echo "Document worker image: $registry_image"
