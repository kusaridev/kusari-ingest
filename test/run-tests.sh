#!/usr/bin/env bash
# Unit tests for map-components.sh and entrypoint.sh validation, using the
# mock kusari CLI in test/mock. No network, no real tenant.
#
#   bash test/run-tests.sh
set -uo pipefail

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
MOCK_DIR="$REPO_DIR/test/mock"
MAPPER="$REPO_DIR/map-components.sh"
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

# Reset mock state: component "webapp" (id 100) exists and already has a
# source software, so assigning to it triggers the conflict fallback.
reset_state() {
  STATE="$WORK/state"
  rm -rf "$STATE"
  mkdir -p "$STATE"
  echo 101 > "$STATE/next-id"
  echo "webapp" > "$STATE/existing-names"
  echo "webapp 100" > "$STATE/name-to-id"
  echo "100" > "$STATE/components-with-source"
  : > "$STATE/sw-to-comp"
}

# Run map-components.sh with the mock CLI. Args: results-file, hash-file.
run_mapper() {
  PATH="$MOCK_DIR:$PATH" MOCK_STATE="$STATE" \
    RESULTS_FILE="$1" TENANT_ENDPOINT="https://demo.api.us.kusari.cloud" HASH_FILE="$2" \
    bash "$MAPPER" 2>&1
}

echo "=== map-components.sh ==="

# --- covers: skip mapped, skip error entry, clean map, conflict fallback ---
reset_state
cat > "$WORK/results.json" <<'EOF'
{"sboms": [
  {"sbom_id": 1, "sbom_subject": "already-mapped", "software_id": 10, "software_name": "already-mapped", "component_id": 55, "component_name": "already-mapped"},
  {"sbom_id": 2, "sbom_subject": "broken", "software_id": null, "software_name": "broken", "component_id": null, "error": "lookup timed out"},
  {"sbom_id": 3, "sbom_subject": "cleanapp", "software_id": 30, "software_name": "cleanapp", "component_id": null, "component_name": null},
  {"sbom_id": 4, "sbom_subject": "webapp", "software_id": 40, "software_name": "webapp", "component_id": null, "component_name": null}
]}
EOF
echo '{"fake": "sbom"}' > "$WORK/sbom.json"
expected_suffix="$(shasum -a 256 "$WORK/sbom.json" 2>/dev/null | cut -c1-7 || sha256sum "$WORK/sbom.json" | cut -c1-7)"

out=$(run_mapper "$WORK/results.json" "$WORK/sbom.json")
assert_eq "mapper exits 0" "0" "$?"
assert_contains "already-mapped entry skipped" "already mapped to component 55 - nothing to do" "$out"
assert_contains "error entry skipped with warning" "::warning::skipping SBOM with lookup error: lookup timed out" "$out"
assert_contains "clean software mapped" "verified: software 30 (cleanapp) mapped to component 101" "$out"
assert_contains "source conflict falls back to hash-suffixed name" "creating fallback component webapp-$expected_suffix" "$out"
assert_contains "fallback component mapped" "verified: software 40 (webapp) mapped to component 102" "$out"

# --- covers: results file write-back ---
assert_eq "write-back: clean software component_id" "101" \
  "$(jq -r '.sboms[] | select(.software_id == 30) | .component_id' "$WORK/results.json")"
assert_eq "write-back: fallback component_name" "webapp-$expected_suffix" \
  "$(jq -r '.sboms[] | select(.software_id == 40) | .component_name' "$WORK/results.json")"
assert_eq "write-back: error entry untouched" "null" \
  "$(jq -r '.sboms[] | select(.software_name == "broken") | .component_id' "$WORK/results.json")"

# --- covers: sbom_id suffix when the SBOM file cannot be attributed ---
reset_state
cat > "$WORK/results.json" <<'EOF'
{"sboms": [{"sbom_id": 777, "sbom_subject": "webapp", "software_id": 40, "software_name": "webapp", "component_id": null}]}
EOF
out=$(run_mapper "$WORK/results.json" "")
assert_eq "mapper exits 0 without hash file" "0" "$?"
assert_contains "falls back to sbom_id suffix" "creating fallback component webapp-777" "$out"

# --- covers: hard API failure aborts nonzero ---
reset_state
cat > "$WORK/results.json" <<'EOF'
{"sboms": [{"sbom_id": 1, "sbom_subject": "app", "software_id": 5, "software_name": "app", "component_id": null}]}
EOF
out=$(MOCK_FAIL_ALL=1 run_mapper "$WORK/results.json" "")
assert_eq "hard failure exits nonzero" "1" "$?"
assert_contains "hard failure reported" "component create failed" "$out"

echo "=== entrypoint.sh validation ==="

run_entrypoint() {
  sh "$ENTRYPOINT" "$@" 2>&1
}

out=$(run_entrypoint --file-path=x.json --client-id=a --client-secret=b --tenant-endpoint=t --results-file=r.json --wait=false)
assert_eq "results-file + wait=false rejected" "1" "$?"
assert_contains "results-file + wait=false message" "results-file requires wait" "$out"

out=$(run_entrypoint --file-path=x.json --client-id=a --client-secret=b --tenant-endpoint=t --results-file=r.json --map-components=true --wait=false)
assert_eq "map-components + wait=false rejected" "1" "$?"
assert_contains "map-components + wait=false message" "map-components requires wait" "$out"

out=$(run_entrypoint --file-path=x.json --client-id=a --client-secret=b --tenant-endpoint=t --map-components=true)
assert_eq "map-components without results-file rejected" "1" "$?"
assert_contains "map-components without results-file message" "map-components requires results-file" "$out"

echo "=== entrypoint.sh end-to-end (mock CLI) ==="

# Full flow: login -> upload (mock writes results fixture) -> map -> write-back.
reset_state
cat > "$WORK/upload-results.json" <<'EOF'
{"sboms": [{"sbom_id": 9, "sbom_subject": "e2eapp", "software_id": 90, "software_name": "e2eapp", "component_id": null}]}
EOF
echo '{"bomFormat": "CycloneDX"}' > "$WORK/e2e-sbom.json"
out=$(cd "$WORK" && PATH="$MOCK_DIR:$PATH" MOCK_STATE="$STATE" MOCK_UPLOAD_RESULTS="$WORK/upload-results.json" \
  GITHUB_SERVER_URL=https://github.com GITHUB_REPOSITORY_OWNER=kusaridev GITHUB_REPOSITORY=kusaridev/e2e \
  sh "$ENTRYPOINT" \
    --file-path=e2e-sbom.json --client-id=a --client-secret=b \
    --tenant-endpoint=https://demo.api.us.kusari.cloud \
    --results-file="$WORK/e2e-results.json" --map-components=true 2>&1)
assert_eq "e2e exits 0" "0" "$?"
assert_contains "e2e upload passes results-file to CLI" "--results-file=$WORK/e2e-results.json" "$out"
assert_contains "e2e mapping runs after upload" "Mapping ingested software to components..." "$out"
assert_eq "e2e write-back: component assigned" "101" \
  "$(jq -r '.sboms[0].component_id' "$WORK/e2e-results.json")"

echo
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
