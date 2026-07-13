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

run_entrypoint() {
  sh "$ENTRYPOINT" "$@" 2>&1
}

echo "=== entrypoint.sh validation ==="

out=$(run_entrypoint --file-path=x.json --client-id=a --client-secret=b --tenant-endpoint=t --results-file=r.json --wait=false)
assert_eq "results-file + wait=false rejected" "1" "$?"
assert_contains "results-file + wait=false message" "results-file requires wait" "$out"

out=$(run_entrypoint --file-path=x.json --client-id=a --client-secret=b --tenant-endpoint=t --map-components=true --wait=false)
assert_eq "map-components + wait=false rejected" "1" "$?"
assert_contains "map-components + wait=false message" "map-components requires wait" "$out"

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
    sh "$ENTRYPOINT" \
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

echo
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
