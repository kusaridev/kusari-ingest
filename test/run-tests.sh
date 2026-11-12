#!/usr/bin/env bash
# Tests for entrypoint.sh, using the mock kusari CLI in test/mock. No network,
# no real tenant. The component-mapping logic itself lives in kusari-cli
# (--map-components) and is tested there; these tests cover the action's
# argument plumbing and validation.
#
#   bash test/run-tests.sh
set -uo pipefail

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
MOCK_DIR="$REPO_DIR/test/mock"
ENTRYPOINT="$REPO_DIR/entrypoint.sh"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

PASS=0
FAIL=0

fail() {
  echo "FAIL: $1"
  FAIL=$((FAIL + 1))
}

pass() {
  echo "ok:   $1"
  PASS=$((PASS + 1))
}

assert_eq() {
  local test_name="$1" expected="$2" actual="$3"
  if [ "$expected" = "$actual" ]; then
    pass "$test_name"
  else
    fail "$test_name (expected: $expected, actual: $actual)"
  fi
}

assert_contains() {
  local test_name="$1" needle="$2" haystack="$3"
  if grep -qF -- "$needle" <<<"$haystack"; then
    pass "$test_name"
  else
    fail "$test_name (output missing: $needle)"
  fi
}

assert_not_contains() {
  local test_name="$1" needle="$2" haystack="$3"
  if grep -qF -- "$needle" <<<"$haystack"; then
    fail "$test_name (output unexpectedly contains: $needle)"
  else
    pass "$test_name"
  fi
}

# bash, not sh: match how action.yaml invokes entrypoint.sh
run_entrypoint() {
  bash "$ENTRYPOINT" "$@" 2>&1
}

echo "=== entrypoint.sh validation ==="

out=$(run_entrypoint --file-path=x.json --client-id=a --client-secret=b --tenant-endpoint=t --results-file=r.json --wait=false)
assert_eq "results-file + wait=false rejected" "1" "$?"
assert_contains "results-file + wait=false message" "results-file requires wait" "$out"

out=$(run_entrypoint --file-path=x.json --client-id=a --client-secret=b --tenant-endpoint=t --map-components=true --wait=false)
assert_eq "map-components + wait=false rejected" "1" "$?"
assert_contains "map-components + wait=false message" "map-components requires wait" "$out"

out=$(run_entrypoint --file-path=x.json --client-id=a --client-secret=b --tenant-endpoint=t --waybill-args="--output foo")
assert_eq "waybill-args --output rejected" "1" "$?"
assert_contains "waybill-args --output message" "waybill-args must not contain --output" "$out"

out=$(run_entrypoint --file-path=x.json --client-id=a --client-secret=b --tenant-endpoint=t --mikebom-args="--output foo")
assert_eq "deprecated mikebom-args --output rejected" "1" "$?"
assert_contains "mikebom-args --output message names deprecated input" "mikebom-args must not contain --output" "$out"
assert_contains "mikebom-args deprecation warning" "'mikebom-args' input is deprecated" "$out"

echo "=== entrypoint.sh flag plumbing (mock CLI) ==="

cat > "$WORK/upload-results.json" <<'EOF'
{"sboms": [{"sbom_id": 9, "sbom_subject": "e2eapp", "software_id": 90, "software_name": "e2eapp", "component_id": null, "component_name": null}]}
EOF
cat > "$WORK/mapped-results.json" <<'EOF'
{"sboms": [{"sbom_id": 9, "sbom_subject": "e2eapp", "software_id": 90, "software_name": "e2eapp", "component_id": 200, "component_name": "e2eapp"}]}
EOF
echo '{"bomFormat": "CycloneDX"}' > "$WORK/e2e-sbom.json"

run_e2e() {
  (cd "$WORK" && PATH="$MOCK_DIR:$PATH" \
    MOCK_UPLOAD_RESULTS="$WORK/upload-results.json" MOCK_MAPPED_RESULTS="$WORK/mapped-results.json" \
    GITHUB_SERVER_URL=https://github.com GITHUB_REPOSITORY_OWNER=kusaridev GITHUB_REPOSITORY=kusaridev/e2e \
    bash "$ENTRYPOINT" \
      --file-path=e2e-sbom.json --client-id=a --client-secret=b \
      --tenant-endpoint=https://demo.api.us.kusari.cloud \
      "$@" 2>&1)
}

# --- without map-components: flag absent, ingestion-time results ---
out=$(run_e2e --results-file="$WORK/plain-results.json")
assert_eq "plain run exits 0" "0" "$?"
assert_contains "results-file passed to upload" "--results-file=$WORK/plain-results.json" "$out"
assert_not_contains "map-components flag absent by default" "--map-components" "$out"
assert_eq "plain results reflect ingestion state" "null" \
  "$(jq -r '.sboms[0].component_id' "$WORK/plain-results.json")"

# --- with map-components: flag passed through, results reflect mapping ---
out=$(run_e2e --results-file="$WORK/mapped-run-results.json" --map-components=true)
assert_eq "map-components run exits 0" "0" "$?"
assert_contains "map-components passed to upload" "--map-components" "$out"
assert_eq "results reflect post-mapping state" "200" \
  "$(jq -r '.sboms[0].component_id' "$WORK/mapped-run-results.json")"

# --- generate mode: waybill-args / deprecated mikebom-args passthrough ---
run_gen() {
  (cd "$WORK" && PATH="$MOCK_DIR:$PATH" \
    GITHUB_SERVER_URL=https://github.com GITHUB_REPOSITORY_OWNER=kusaridev GITHUB_REPOSITORY=kusaridev/e2e \
    bash "$ENTRYPOINT" \
      --generate=true --source-path=. --client-id=a --client-secret=b \
      --tenant-endpoint=https://demo.api.us.kusari.cloud \
      "$@" 2>&1)
}

out=$(run_gen --waybill-args="--quiet --verbose")
assert_eq "generate with waybill-args exits 0" "0" "$?"
assert_contains "waybill-args passed to generate" "--quiet --verbose" "$out"

out=$(run_gen --mikebom-args="--quiet")
assert_eq "generate with deprecated mikebom-args exits 0" "0" "$?"
assert_contains "mikebom-args passed to generate" "--quiet" "$out"
assert_contains "mikebom-args generate deprecation warning" "'mikebom-args' input is deprecated" "$out"

out=$(run_gen --waybill-args="--waybill-wins" --mikebom-args="--mikebom-loses")
assert_eq "both args inputs exits 0" "0" "$?"
assert_contains "waybill-args wins when both set" "--waybill-wins" "$out"
assert_not_contains "mikebom-args ignored when both set" "--mikebom-loses" "$out"
assert_contains "both-set warning printed" "using waybill-args and ignoring mikebom-args" "$out"

echo "=== tag-deployment/entrypoint.sh (mock CLI and curl) ==="

cat > "$WORK/tagged.json" <<'EOF'
{"label": "environment", "value": "prod",
 "image": {"sbom_id": 42, "version_id": 99, "result": "created", "ended_version_ids": [98]},
 "source": {"sbom_id": 7, "name": "app-src", "version_id": 70, "version_found_by": "commit", "result": "created", "ended_version_ids": []}}
EOF
cat > "$WORK/not-tagged.json" <<'EOF'
{"label": "environment", "value": "prod",
 "image": {"sbom_id": 42, "version_id": 99, "result": "created", "ended_version_ids": []},
 "source": {"sbom_id": 7, "name": "app-src", "result": "not_tagged", "ended_version_ids": [], "message": "no version before the commit time"}}
EOF
echo '{"commit": {"committer": {"date": "2026-10-01T12:00:00Z"}}}' > "$WORK/commit.json"

# Runs the tagging script as its action.yaml step does. Extra VAR=value
# arguments override the inputs below.
run_tag() {
  : > "$WORK/tag-output" ; : > "$WORK/tag-summary"
  (cd "$WORK" && env PATH="$MOCK_DIR:$PATH" \
    GITHUB_OUTPUT="$WORK/tag-output" GITHUB_STEP_SUMMARY="$WORK/tag-summary" \
    GITHUB_API_URL=https://api.github.com GITHUB_REPOSITORY=kusaridev/e2e GITHUB_SHA=abc123 \
    MOCK_TAG_OUTPUT="$WORK/tagged.json" MOCK_CURL_BODY="$WORK/commit.json" \
    INPUT_SBOM_ID=42 INPUT_SBOM_VERSION_ID=99 INPUT_VALUE=prod INPUT_LABEL=environment \
    INPUT_COMMIT_TIME= INPUT_GITHUB_TOKEN=gh-token \
    INPUT_TENANT_ENDPOINT=https://demo.api.us.kusari.cloud INPUT_CLIENT_ID=a INPUT_CLIENT_SECRET=b \
    INPUT_TOKEN_ENDPOINT=https://auth.us.kusari.cloud/oauth2/token INPUT_CONSOLE_URL= INPUT_PLATFORM_URL= \
    INPUT_FAIL_ON_ERROR=false \
    "$@" bash "$REPO_DIR/tag-deployment/entrypoint.sh" 2>&1)
}

# --- happy path: commit time looked up, tagged, result output set ---
out=$(run_tag)
assert_eq "tag happy path exits 0" "0" "$?"
assert_contains "commit lookup hits the commits API for github.sha" \
  "https://api.github.com/repos/kusaridev/e2e/commits/abc123" "$out"
assert_contains "tag-deployment gets IDs, label, tenant and looked-up commit time" \
  "tag-deployment 42 99 prod --label=environment --tenant-endpoint=https://demo.api.us.kusari.cloud --commit-time=2026-10-01T12:00:00Z" "$out"
assert_eq "result output holds the CLI's JSON" "created" \
  "$(sed '1d;$d' "$WORK/tag-output" | jq -r '.source.result')"
assert_not_contains "no warnings on success" "::warning" "$out"

# --- CLI fails, fail-on-error at its default: warning, step passes (wrong code: failing the deploy) ---
out=$(run_tag MOCK_TAG_ERROR="failed to move tag environment=prod on SBOM #42: 401 Unauthorized" \
  INPUT_COMMIT_TIME=2026-09-30T08:00:00Z)
assert_eq "failed tag passes by default" "0" "$?"
assert_contains "failed tag warns with the CLI's error" \
  "::warning title=Deployment tag failed::failed to move tag environment=prod on SBOM #42: 401 Unauthorized" "$out"
assert_contains "commit-time input passed as is" "--commit-time=2026-09-30T08:00:00Z" "$out"
assert_not_contains "commit-time input skips the API lookup" "mock curl" "$out"

# --- same with fail-on-error: true (wrong code: ignoring fail-on-error) ---
out=$(run_tag MOCK_TAG_ERROR="boom" INPUT_FAIL_ON_ERROR=true)
assert_eq "failed tag fails with fail-on-error" "1" "$?"

# --- source not tagged: warning and summary line in the CLI's wording (wrong code: missing it on exit 0) ---
out=$(run_tag MOCK_TAG_OUTPUT="$WORK/not-tagged.json")
assert_eq "not tagged source passes" "0" "$?"
assert_contains "not tagged source warns" \
  "::warning title=Source SBOM not tagged::Source SBOM 7 (app-src) was not tagged environment=prod: no version before the commit time." "$out"
assert_eq "not tagged source in step summary" \
  "Source SBOM 7 (app-src) was not tagged environment=prod: no version before the commit time." "$(cat "$WORK/tag-summary")"

# --- commit lookup 403: warning, tags without --commit-time (wrong code: passing an empty --commit-time, which the CLI rejects) ---
out=$(run_tag MOCK_CURL_STATUS=403)
assert_eq "commit lookup failure passes" "0" "$?"
assert_contains "commit lookup failure warns with status" "::warning title=Commit time not found::" "$out"
assert_contains "commit lookup warning names HTTP status" "(HTTP 403)" "$out"
assert_not_contains "no --commit-time after failed lookup" "--commit-time" "$(grep 'mock tag-deployment' <<<"$out")"

echo
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
