#!/bin/sh
set -e

# Parse arguments
FILE_PATH=""
CLIENT_ID=""
CLIENT_SECRET=""
TENANT_ENDPOINT=""
TOKEN_ENDPOINT="https://auth.us.kusari.cloud/oauth2/token"
ALIAS=""
DOCUMENT_TYPE=""
OPEN_VEX="false"
TAG=""
SOFTWARE_ID=""
SBOM_SUBJECT=""
COMPONENT_NAME=""
CHECK_BLOCKED_PACKAGES="false"
SBOM_SUBJECT_NAME_OVERRIDE=""
SBOM_SUBJECT_VERSION_OVERRIDE=""

while [ $# -gt 0 ]; do
  case "$1" in
    --file-path=*)
      FILE_PATH="${1#*=}"
      ;;
    --client-id=*)
      CLIENT_ID="${1#*=}"
      ;;
    --client-secret=*)
      CLIENT_SECRET="${1#*=}"
      ;;
    --tenant-endpoint=*)
      TENANT_ENDPOINT="${1#*=}"
      ;;
    --token-endpoint=*)
      TOKEN_ENDPOINT="${1#*=}"
      ;;
    --alias=*)
      ALIAS="${1#*=}"
      ;;
    --document-type=*)
      DOCUMENT_TYPE="${1#*=}"
      ;;
    --open-vex=*)
      OPEN_VEX="${1#*=}"
      ;;
    --tag=*)
      TAG="${1#*=}"
      ;;
    --software-id=*)
      SOFTWARE_ID="${1#*=}"
      ;;
    --sbom-subject=*)
      SBOM_SUBJECT="${1#*=}"
      ;;
    --component-name=*)
      COMPONENT_NAME="${1#*=}"
      ;;
    --check-blocked-packages=*)
      CHECK_BLOCKED_PACKAGES="${1#*=}"
      ;;
    --sbom-subject-name-override=*)
      SBOM_SUBJECT_NAME_OVERRIDE="${1#*=}"
      ;;
    --sbom-subject-version-override=*)
      SBOM_SUBJECT_VERSION_OVERRIDE="${1#*=}"
      ;;
  esac
  shift
done

# Set auth endpoint - use token-endpoint if provided, otherwise use default
if [ -n "${TOKEN_ENDPOINT}" ] && [ "${TOKEN_ENDPOINT}" != "https://auth.us.kusari.cloud/oauth2/token" ]; then
  # Extract base domain from token endpoint for custom auth endpoints
  AUTH_ENDPOINT=$(echo "${TOKEN_ENDPOINT}" | sed 's|/oauth2/token||')
else
  # Use default auth endpoint
  AUTH_ENDPOINT="https://auth.us.kusari.cloud/"
fi

# Create a temporary directory for kusari config
export HOME=$(mktemp -d)

# Login to kusari using client credentials
echo "Kusari CLI Version:"
kusari --version
echo "Logging in to Kusari..."
kusari auth login \
  --client-id="${CLIENT_ID}" \
  --client-secret="${CLIENT_SECRET}" \
  --auth-endpoint="${AUTH_ENDPOINT}"

# Execute upload command
echo "Uploading to Kusari Platform..."

# Build arguments array for upload command
set -- kusari platform upload \
  --file-path="${FILE_PATH}" \
  --tenant-endpoint="${TENANT_ENDPOINT}"

# Add optional parameters
if [ -n "${ALIAS}" ]; then
  set -- "$@" --alias="${ALIAS}"
fi

if [ -n "${DOCUMENT_TYPE}" ]; then
  set -- "$@" --document-type="${DOCUMENT_TYPE}"
fi

if [ "${OPEN_VEX}" = "true" ]; then
  set -- "$@" --openvex
fi

if [ -n "${TAG}" ]; then
  set -- "$@" --tag="${TAG}"
fi

if [ -n "${SOFTWARE_ID}" ]; then
  set -- "$@" --software-id="${SOFTWARE_ID}"
fi

if [ -n "${SBOM_SUBJECT}" ]; then
  set -- "$@" --sbom-subject="${SBOM_SUBJECT}"
fi

if [ -n "${COMPONENT_NAME}" ]; then
  set -- "$@" --component-name="${COMPONENT_NAME}"
fi

if [ "${CHECK_BLOCKED_PACKAGES}" = "true" ]; then
  set -- "$@" --check-blocked-packages
fi

if [ -n "${SBOM_SUBJECT_NAME_OVERRIDE}" ]; then
  set -- "$@" --sbom-subject-name-override="${SBOM_SUBJECT_NAME_OVERRIDE}"
fi

if [ -n "${SBOM_SUBJECT_VERSION_OVERRIDE}" ]; then
  set -- "$@" --sbom-subject-version-override="${SBOM_SUBJECT_VERSION_OVERRIDE}"
fi

# Execute the command
"$@"
