#!/bin/sh
set -e
# Disable pathname (glob) expansion. The script word-splits a few
# user-supplied strings (notably ${MIKEBOM_ARGS}) by intentionally
# leaving them unquoted; without -f those expansions would also be
# globbed against the workspace, which would silently mutate the
# user's flags based on what files happen to exist in cwd.
set -f

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
CHECK_BLOCKED_PACKAGES="false"
SBOM_SUBJECT_NAME_OVERRIDE=""
SBOM_SUBJECT_VERSION_OVERRIDE=""
WAIT="true"
COMMIT_SHA=""
GENERATE="false"
SOURCE_PATH=""
IMAGE=""
OUTPUT_PATH="project.cdx.json"
MIKEBOM_ARGS=""
ROOT_NAME=""
ROOT_VERSION=""

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
    --check-blocked-packages=*)
      CHECK_BLOCKED_PACKAGES="${1#*=}"
      ;;
    --sbom-subject-name-override=*)
      SBOM_SUBJECT_NAME_OVERRIDE="${1#*=}"
      ;;
    --sbom-subject-version-override=*)
      SBOM_SUBJECT_VERSION_OVERRIDE="${1#*=}"
      ;;
    --wait=*)
      WAIT="${1#*=}"
      ;;
    --commit-sha=*)
      COMMIT_SHA="${1#*=}"
      ;;
    --generate=*)
      GENERATE="${1#*=}"
      ;;
    --source-path=*)
      SOURCE_PATH="${1#*=}"
      ;;
    --image=*)
      IMAGE="${1#*=}"
      ;;
    --output-path=*)
      OUTPUT_PATH="${1#*=}"
      ;;
    --mikebom-args=*)
      MIKEBOM_ARGS="${1#*=}"
      ;;
    --root-name=*)
      ROOT_NAME="${1#*=}"
      ;;
    --root-version=*)
      ROOT_VERSION="${1#*=}"
      ;;
  esac
  shift
done

# In upload mode, file-path is required. In generate mode it is unused.
if [ "${GENERATE}" != "true" ] && [ -z "${FILE_PATH}" ]; then
  echo "file-path is required when generate is not enabled"
  exit 1
fi

# In generate mode, exactly one scan target must be supplied. Setting both
# would silently let one win; setting neither would hand an empty --path to
# mikebom. Reject both cases up front. Also reject a stray file-path — the
# action uploads the generated SBOM, so any file-path the caller set would
# be silently dropped.
if [ "${GENERATE}" = "true" ]; then
  if [ -n "${FILE_PATH}" ]; then
    echo "file-path must not be set when generate is true; the action uploads the generated SBOM"
    exit 1
  fi
  if [ -z "${IMAGE}" ] && [ -z "${SOURCE_PATH}" ]; then
    echo "one of image or source-path must be set when generate is true"
    exit 1
  fi
  if [ -n "${IMAGE}" ] && [ -n "${SOURCE_PATH}" ]; then
    echo "image and source-path are mutually exclusive; set only one when generate is true"
    exit 1
  fi
fi

# Users sometimes try to set mikebom's --output via mikebom-args; that
# silently desyncs from the file the upload step expects. Refuse the
# override and point them at the output-path input. Iterate the same way
# the actual invocation does (unquoted word-splitting) so we catch the
# flag regardless of which whitespace (spaces, tabs, newlines from a
# multiline YAML scalar) separates the tokens.
# shellcheck disable=SC2086
for token in ${MIKEBOM_ARGS}; do
  case "$token" in
    --output|--output=*)
      echo "mikebom-args must not contain --output; use the output-path input instead"
      exit 1
      ;;
    --root-name|--root-name=*)
      echo "mikebom-args must not contain --root-name; use the root-name input instead"
      exit 1
      ;;
    --root-version|--root-version=*)
      echo "mikebom-args must not contain --root-version; use the root-version input instead"
      exit 1
      ;;
  esac
done

# Fail if CLIENT_ID or CLIENT_SECRET is still empty
if [ -z "${CLIENT_ID}" ] || [ -z ${CLIENT_SECRET} ]; then
  echo "CLIENT_ID or CLIENT_SECRET not provided"
  exit 1
fi

# Auto-detect repository traceability metadata from GitHub environment variables
# GITHUB_SERVER_URL: https://github.com or https://github.enterprise.com
# GITHUB_REPOSITORY_OWNER: organization or user name
# GITHUB_REPOSITORY: owner/repo format

# Extract forge hostname from GITHUB_SERVER_URL (e.g., https://github.com -> github.com)
FORGE=""
if [ -n "${GITHUB_SERVER_URL}" ]; then
  FORGE=$(echo "${GITHUB_SERVER_URL}" | sed -E 's|^https?://||' | sed -E 's|/.*$||')
fi

# Use GITHUB_REPOSITORY_OWNER for org
ORG="${GITHUB_REPOSITORY_OWNER:-}"

# Extract just the repo name from GITHUB_REPOSITORY (format: owner/repo -> repo)
REPO=""
if [ -n "${GITHUB_REPOSITORY}" ]; then
  REPO="${GITHUB_REPOSITORY#*/}"
fi

# Auto-derive subrepo path. In generate mode it tracks source-path (unless
# we're scanning an image, in which case there is no meaningful subrepo);
# otherwise it tracks file-path.
SUBREPO_PATH=""
if [ "${GENERATE}" = "true" ]; then
  if [ -z "${IMAGE}" ]; then
    SUBREPO_PATH="${SOURCE_PATH}"
  fi
elif [ -n "${FILE_PATH}" ]; then
  if [ -d "${FILE_PATH}" ]; then
    # FILE_PATH is a directory, use it as subrepo path
    SUBREPO_PATH="${FILE_PATH}"
  else
    # FILE_PATH is a file, extract the directory portion
    SUBREPO_PATH=$(dirname "${FILE_PATH}")
  fi
fi

if [ -n "${SUBREPO_PATH}" ]; then
  # Normalize: remove leading ./ and trailing /
  SUBREPO_PATH=$(echo "${SUBREPO_PATH}" | sed -E 's|^\./||' | sed -E 's|/$||')
  # If empty or just ".", set to "."
  if [ -z "${SUBREPO_PATH}" ] || [ "${SUBREPO_PATH}" = "." ]; then
    SUBREPO_PATH="."
  fi
fi

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

# In generate mode, produce the SBOM with mikebom first, then upload the
# resulting file via the normal upload codepath below. mikebom requires
# exactly one of --image or --path as the scan target.
if [ "${GENERATE}" = "true" ]; then
  if [ -n "${IMAGE}" ]; then
    echo "Generating SBOM for image ${IMAGE} with kusari platform generate..."
    SCAN_TARGET_FLAG="--image"
    SCAN_TARGET_VALUE="${IMAGE}"
  else
    echo "Generating SBOM for source path ${SOURCE_PATH} with kusari platform generate..."
    SCAN_TARGET_FLAG="--path"
    SCAN_TARGET_VALUE="${SOURCE_PATH}"
  fi
  set -- kusari platform generate -- \
    --output "${OUTPUT_PATH}" \
    "${SCAN_TARGET_FLAG}" "${SCAN_TARGET_VALUE}"
  if [ -n "${ROOT_NAME}" ]; then
    set -- "$@" --root-name "${ROOT_NAME}"
  fi
  if [ -n "${ROOT_VERSION}" ]; then
    set -- "$@" --root-version "${ROOT_VERSION}"
  fi
  # shellcheck disable=SC2086
  "$@" ${MIKEBOM_ARGS}
  FILE_PATH="${OUTPUT_PATH}"
fi

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

if [ "${CHECK_BLOCKED_PACKAGES}" = "true" ]; then
  set -- "$@" --check-blocked-packages
fi

if [ -n "${SBOM_SUBJECT_NAME_OVERRIDE}" ]; then
  set -- "$@" --sbom-subject-name-override="${SBOM_SUBJECT_NAME_OVERRIDE}"
fi

if [ -n "${SBOM_SUBJECT_VERSION_OVERRIDE}" ]; then
  set -- "$@" --sbom-subject-version-override="${SBOM_SUBJECT_VERSION_OVERRIDE}"
fi

if [ -n "${COMMIT_SHA}" ]; then
  set -- "$@" --commit-sha="${COMMIT_SHA}"
fi

if [ "${WAIT}" = "false" ]; then
  set -- "$@" --wait=false
else
  set -- "$@" --wait
fi

if [ -n "${FORGE}" ]; then
  set -- "$@" --forge="${FORGE}"
fi

if [ -n "${ORG}" ]; then
  set -- "$@" --org="${ORG}"
fi

if [ -n "${REPO}" ]; then
  set -- "$@" --repo="${REPO}"
fi

if [ -n "${SUBREPO_PATH}" ]; then
  set -- "$@" --subrepo-path="${SUBREPO_PATH}"
fi

# Execute the command
"$@"
