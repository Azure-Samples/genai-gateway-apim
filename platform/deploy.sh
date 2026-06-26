#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# Deploy (or update) the shared APIM platform stack — run ONCE, ahead of any
# pattern workload. Re-running is idempotent.
#
# Plain `az deployment sub create` rather than azd: the platform has no app
# lifecycle, just infrastructure that every pattern attaches to.
#
# Usage:
#   az login && az account set --subscription <sub-id>
#   ./platform/deploy.sh
#
# Override defaults via env vars:
#   PLATFORM_ENV_NAME=shared-platform \
#   PLATFORM_LOCATION=westeurope \
#   PLATFORM_APIM_LOCATION=westeurope \
#   PLATFORM_APIM_SKU=BasicV2 \
#   ./platform/deploy.sh
# -----------------------------------------------------------------------------
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

ENV_NAME="${PLATFORM_ENV_NAME:-shared-platform}"
LOCATION="${PLATFORM_LOCATION:-westeurope}"
APIM_LOCATION="${PLATFORM_APIM_LOCATION:-westeurope}"
APIM_SKU="${PLATFORM_APIM_SKU:-BasicV2}"
DEPLOYMENT_NAME="platform-${ENV_NAME}"

echo "Deploying shared platform '${ENV_NAME}' (APIM ${APIM_SKU} in ${APIM_LOCATION})..."

az deployment sub create \
  --name "${DEPLOYMENT_NAME}" \
  --location "${LOCATION}" \
  --template-file "${SCRIPT_DIR}/main.bicep" \
  --parameters \
      environmentName="${ENV_NAME}" \
      location="${LOCATION}" \
      apimLocation="${APIM_LOCATION}" \
      apimSku="${APIM_SKU}" \
  --output none

echo "Reading outputs..."
OUTPUTS=$(az deployment sub show --name "${DEPLOYMENT_NAME}" --query properties.outputs -o json)

# ARM camel-cases deployment output keys (SHARED_APIM_NAME -> shareD_APIM_NAME),
# so look up case-insensitively.
get() { echo "${OUTPUTS}" | python3 -c "import sys,json;d={k.lower():v for k,v in json.load(sys.stdin).items()};print(d['$1'.lower()]['value'])"; }

APIM_NAME=$(get SHARED_APIM_NAME)
APIM_RG=$(get SHARED_APIM_RESOURCE_GROUP)
APIM_PRINCIPAL=$(get SHARED_APIM_PRINCIPAL_ID)
APPI_NAME=$(get SHARED_APPLICATION_INSIGHTS_NAME)
ENDPOINT=$(get APIM_ENDPOINT)

cat <<EOF

============================================================================
Shared platform is up.

  APIM endpoint : ${ENDPOINT}
  APIM name     : ${APIM_NAME}
  APIM RG       : ${APIM_RG}

Wire each pattern workload to it — from that pattern's repo root, run:

  azd env set SHARED_APIM_NAME ${APIM_NAME}
  azd env set SHARED_APIM_RESOURCE_GROUP ${APIM_RG}
  azd env set SHARED_APIM_PRINCIPAL_ID ${APIM_PRINCIPAL}
  azd env set SHARED_APPLICATION_INSIGHTS_NAME ${APPI_NAME}
  azd env set PATTERN_SUFFIX a        # a / b / d — must be unique per pattern

Then \`azd up\` the pattern as usual.
============================================================================
EOF
