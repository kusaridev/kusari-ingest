#!/usr/bin/env bash
# Ensure every ingested software in the results file is mapped to a Kusari
# component. Invoked by entrypoint.sh after a successful upload when the
# map-components input is true.
#
# For each SBOM entry in the results file that has a software_id but no
# component_id:
#   1. Create a component named after the software; if the name is taken,
#      reuse the existing component's ID.
#   2. Assign the software to that component. If the platform rejects the
#      assignment because the component already has a source software, mint a
#      fresh component named "<software-name>-<suffix>" and assign to that
#      instead. The suffix is a short sha256 of the ingested SBOM file
#      (HASH_FILE); when the file can't be attributed (directory uploads),
#      the sbom_id is used.
#   3. Verify the mapping via `kusari platform software get`.
#   4. Write the new component_id/component_name back into the results file,
#      so the file (and the action's `results` output, which is read after
#      this script runs) reflects the final post-mapping state rather than
#      the state at ingestion time.
#
# Environment contract (set by entrypoint.sh):
#   RESULTS_FILE     - path to the --results-file JSON written by the upload
#   TENANT_ENDPOINT  - Kusari tenant endpoint URL, passed as --tenant-endpoint
#   HASH_FILE        - optional path to the ingested SBOM file for the suffix
# Assumes `kusari auth login` already ran under the current HOME.
set -euo pipefail

: "${RESULTS_FILE:?RESULTS_FILE is required}"
: "${TENANT_ENDPOINT:?TENANT_ENDPOINT is required}"
HASH_FILE="${HASH_FILE:-}"

# 7-hex-char sha256 prefix of a file. GitHub's Linux runners ship sha256sum,
# macOS runners ship shasum; support both.
short_hash() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | cut -c1-7
  else
    shasum -a 256 "$1" | cut -c1-7
  fi
}

# Create a component and print its ID. If the name is taken (the platform
# returns 'component with name "X" already exists'), look up the existing
# component's ID instead.
create_or_get_component() {
  local name="$1" out id
  if out=$(kusari platform components create "$name" --tenant-endpoint="${TENANT_ENDPOINT}" 2>&1); then
    jq -r '.id' <<<"$out"
    return 0
  fi
  if grep -q "already exists" <<<"$out"; then
    id=$(kusari platform components list --search "$name" --tenant-endpoint="${TENANT_ENDPOINT}" |
      jq -r --arg n "$name" '.components[] | select(.name == $n) | .id' |
      head -n1)
    if [ -n "$id" ]; then
      echo "$id"
      return 0
    fi
    echo "component \"$name\" reported as existing but not found via list" >&2
    return 1
  fi
  echo "component create failed: $out" >&2
  return 1
}

# Assign software to a component. Returns 42 specifically when the platform
# rejects with 'component already has a source software'.
assign_software() {
  local comp_id="$1" sw_id="$2" out
  if out=$(kusari platform components assign-software "$comp_id" "$sw_id" --tenant-endpoint="${TENANT_ENDPOINT}" 2>&1); then
    return 0
  fi
  if grep -q "already has a source software" <<<"$out"; then
    echo "component $comp_id already has a source software" >&2
    return 42
  fi
  echo "assign failed: $out" >&2
  return 1
}

# Process substitution (not a pipe) so the loop runs in this shell and
# failures inside it abort the script under set -e.
while IFS= read -r sbom; do
  error=$(jq -r '.error // empty' <<<"$sbom")
  if [ -n "$error" ]; then
    echo "::warning::skipping SBOM with lookup error: $error"
    continue
  fi

  sw_id=$(jq -r '.software_id // empty' <<<"$sbom")
  name=$(jq -r '.software_name' <<<"$sbom")
  comp_id=$(jq -r '.component_id // empty' <<<"$sbom")

  if [ -z "$sw_id" ]; then
    echo "::warning::skipping SBOM \"$name\" with no software_id"
    continue
  fi

  if [ -n "$comp_id" ]; then
    echo "$name (software $sw_id) already mapped to component $comp_id - nothing to do"
    continue
  fi

  echo "$name (software $sw_id) is unmapped - creating/locating component"
  comp_name="$name"
  comp_id=$(create_or_get_component "$comp_name")

  # Try the assignment; on a source-software conflict, mint a new component
  # with a suffix.
  rc=0
  assign_software "$comp_id" "$sw_id" || rc=$?
  if [ "$rc" -eq 42 ]; then
    if [ -n "$HASH_FILE" ]; then
      suffix=$(short_hash "$HASH_FILE")
    else
      suffix=$(jq -r '.sbom_id' <<<"$sbom")
    fi
    comp_name="$name-$suffix"
    echo "creating fallback component $comp_name"
    comp_id=$(create_or_get_component "$comp_name")
    assign_software "$comp_id" "$sw_id"
  elif [ "$rc" -ne 0 ]; then
    exit "$rc"
  fi

  # Verify: fetch the software and confirm component_id matches.
  actual=$(kusari platform software get "$sw_id" --tenant-endpoint="${TENANT_ENDPOINT}" | jq -r '.component_id')
  if [ "$actual" != "$comp_id" ]; then
    echo "::error::verification failed: software $sw_id has component_id=$actual, expected $comp_id"
    exit 1
  fi
  echo "verified: software $sw_id ($name) mapped to component $comp_id"

  # Update the results file so it reflects the mapping just made.
  tmp_results=$(mktemp)
  jq --argjson sw "$sw_id" --argjson comp "$comp_id" --arg cname "$comp_name" \
    '(.sboms[] | select(.software_id == $sw)) |= (.component_id = $comp | .component_name = $cname)' \
    "$RESULTS_FILE" > "$tmp_results"
  mv "$tmp_results" "$RESULTS_FILE"
done < <(jq -c '.sboms[]' "$RESULTS_FILE")
