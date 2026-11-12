#!/usr/bin/env bash
# Runs `kusari platform sboms tag-deployment` for tag-deployment/action.yaml.
# Inputs arrive as INPUT_* environment variables. A failed tag warns unless
# INPUT_FAIL_ON_ERROR is "true"; a failed commit time lookup only ever warns.

# Escapes a value for a workflow command, so a multi-line message stays in one annotation.
escape() {
  local s="$1"
  s="${s//'%'/%25}"
  s="${s//$'\r'/%0D}"
  s="${s//$'\n'/%0A}"
  printf '%s' "$s"
}

tag_failed() {
  if [ "${INPUT_FAIL_ON_ERROR}" = "true" ]; then
    echo "::error title=Deployment tag failed::$(escape "$1")"
    exit 1
  fi
  echo "::warning title=Deployment tag failed::$(escape "$1")"
  exit 0
}

# The message of the last "Error: " line cobra printed, or a fallback naming the exit status.
cli_error() {
  local msg
  msg="$(grep '^Error: ' "$1" | tail -1 | sed 's/^Error: //')"
  printf '%s' "${msg:-$2 exited with status $3}"
}

if [ -z "${INPUT_SBOM_ID}" ] || [ -z "${INPUT_SBOM_VERSION_ID}" ]; then
  tag_failed "sbom-id and sbom-version-id are required. The root kusari-ingest action sets them only when results-file or map-components is set."
fi

commit_time="${INPUT_COMMIT_TIME}"
if [ -z "${commit_time}" ]; then
  body="$(mktemp)"
  http_status="$(curl -sS --max-time 30 -o "${body}" -w '%{http_code}' \
    -H "Authorization: Bearer ${INPUT_GITHUB_TOKEN}" \
    -H "Accept: application/vnd.github+json" \
    "${GITHUB_API_URL}/repos/${GITHUB_REPOSITORY}/git/commits/${GITHUB_SHA}")"
  if [ "${http_status}" = "200" ]; then
    commit_time="$(jq -r '.committer.date // empty' "${body}")"
  fi
  if [ -z "${commit_time}" ]; then
    echo "::warning title=Commit time not found::Could not read the committer date of ${GITHUB_SHA} in ${GITHUB_REPOSITORY} (HTTP ${http_status}). Tagging without --commit-time. Give the token contents: read, or pass commit-time."
  fi
fi

# Same auth endpoint derivation as the root action's entrypoint.sh: the CLI
# appends "oauth2/token", so the endpoint keeps its trailing slash.
if [ -n "${INPUT_TOKEN_ENDPOINT}" ] && [ "${INPUT_TOKEN_ENDPOINT}" != "https://auth.us.kusari.cloud/oauth2/token" ]; then
  auth_endpoint="${INPUT_TOKEN_ENDPOINT%oauth2/token}"
  case "${auth_endpoint}" in
    */) ;;
    *) auth_endpoint="${auth_endpoint}/" ;;
  esac
else
  auth_endpoint="https://auth.us.kusari.cloud/"
fi

HOME="$(mktemp -d)"
export HOME
stderr_file="$(mktemp)"
stdout_file="$(mktemp)"

login=(kusari auth login --client-id="${INPUT_CLIENT_ID}" --client-secret="${INPUT_CLIENT_SECRET}" --auth-endpoint="${auth_endpoint}")
[ -n "${INPUT_CONSOLE_URL}" ] && login+=(--console-url="${INPUT_CONSOLE_URL}")
[ -n "${INPUT_PLATFORM_URL}" ] && login+=(--platform-url="${INPUT_PLATFORM_URL}")
"${login[@]}" 2>"${stderr_file}"
status=$?
cat "${stderr_file}" >&2
if [ "${status}" -ne 0 ]; then
  tag_failed "$(cli_error "${stderr_file}" "kusari auth login" "${status}")"
fi

tag=(kusari platform sboms tag-deployment "${INPUT_SBOM_ID}" "${INPUT_SBOM_VERSION_ID}" "${INPUT_VALUE}"
  --label="${INPUT_LABEL}" --tenant-endpoint="${INPUT_TENANT_ENDPOINT}")
[ -n "${commit_time}" ] && tag+=(--commit-time="${commit_time}")
"${tag[@]}" >"${stdout_file}" 2>"${stderr_file}"
status=$?
cat "${stderr_file}" >&2
cat "${stdout_file}"

# Random heredoc delimiter, as in the root action: the JSON holds SBOM names.
delim="KUSARI_$(od -An -tx8 -N16 /dev/urandom | tr -d ' \n')"
{
  echo "result<<${delim}"
  cat "${stdout_file}"
  echo "${delim}"
} >> "${GITHUB_OUTPUT}"

not_tagged="$(jq -r 'select(.source.result? == "not_tagged")
  | "Source SBOM \(.source.sbom_id) (\(.source.name)) was not tagged \(.label)=\(.value): \(.source.message)."' \
  "${stdout_file}")"
if [ -n "${not_tagged}" ]; then
  echo "::warning title=Source SBOM not tagged::$(escape "${not_tagged}")"
  echo "${not_tagged}" >> "${GITHUB_STEP_SUMMARY}"
fi

if [ "${status}" -ne 0 ]; then
  tag_failed "$(cli_error "${stderr_file}" "kusari platform sboms tag-deployment" "${status}")"
fi
