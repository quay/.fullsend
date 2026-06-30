#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="${SCRIPT_DIR}/konflux-checks.sh"
FIXTURE_DIR="${SCRIPT_DIR}/testdata"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

with_gh_stub() {
  local mode="$1"
  shift
  local tmp
  tmp="$(mktemp -d)"
  cat > "${tmp}/gh" <<'STUB'
#!/usr/bin/env bash
set -euo pipefail

fixture_dir="${KONFLUX_CHECKS_FIXTURE_DIR:?}"
mode="${KONFLUX_CHECKS_TEST_MODE:?}"
state_file="${KONFLUX_CHECKS_STATE_FILE:-}"
args="$*"

if [[ "${args}" == *"/pulls/2343"* ]]; then
  cat "${fixture_dir}/pr.json"
  exit 0
fi

if [[ "${args}" == *"/commits/abc123/check-runs"* ]]; then
  case "${mode}" in
    mixed) cat "${fixture_dir}/check-runs-mixed.json" ;;
    success) cat "${fixture_dir}/check-runs-success.json" ;;
    pending) cat "${fixture_dir}/check-runs-pending.json" ;;
    none) cat "${fixture_dir}/check-runs-none.json" ;;
    pending-then-success)
      count=0
      if [[ -n "${state_file}" && -f "${state_file}" ]]; then
        count="$(cat "${state_file}")"
      fi
      count=$((count + 1))
      if [[ -n "${state_file}" ]]; then
        printf '%s' "${count}" > "${state_file}"
      fi
      if [[ "${count}" -lt 2 ]]; then
        cat "${fixture_dir}/check-runs-pending.json"
      else
        cat "${fixture_dir}/check-runs-success.json"
      fi
      ;;
    *) echo "unknown mode: ${mode}" >&2; exit 2 ;;
  esac
  exit 0
fi

echo "unexpected gh args: ${args}" >&2
exit 2
STUB
  chmod +x "${tmp}/gh"

  PATH="${tmp}:${PATH}" \
  KONFLUX_CHECKS_FIXTURE_DIR="${FIXTURE_DIR}" \
  KONFLUX_CHECKS_TEST_MODE="${mode}" \
  KONFLUX_CHECKS_STATE_FILE="${tmp}/state" \
  "$@"
}

test_json_extracts_non_success_konflux_checks() {
  local output
  output="$(with_gh_stub mixed bash "${SCRIPT}" json --repo quay/quay-konflux-components --pr 2343)"

  [[ "$(jq -r '.state' <<<"${output}")" == "non-success" ]] || fail "expected non-success state"
  [[ "$(jq '.checks | length' <<<"${output}")" == "2" ]] || fail "expected two Konflux checks"
  [[ "$(jq '[.checks[] | select(.app_slug != "red-hat-konflux")] | length' <<<"${output}")" == "0" ]] || fail "expected only Red Hat Konflux checks"
  [[ "$(jq -r '.checks[] | select(.conclusion == "cancelled") | .pipeline_run' <<<"${output}")" == "quay-quay-v3-17-on-pull-request-t9kp8" ]] || fail "expected PipelineRun name"
  [[ "$(jq -r '.checks[] | select(.conclusion == "cancelled") | .namespace' <<<"${output}")" == "quay-eng-tenant" ]] || fail "expected namespace"
  [[ "$(jq -r '.checks[] | select(.conclusion == "cancelled") | .failed_task' <<<"${output}")" == "build-images" ]] || fail "expected failed task"
  [[ "$(jq -r '.checks[] | select(.conclusion == "cancelled") | .assessment_priority' <<<"${output}")" == "failure" ]] || fail "expected failure priority"
}

test_json_reports_success_when_all_konflux_checks_succeed() {
  local output
  output="$(with_gh_stub success bash "${SCRIPT}" json --repo quay/quay-konflux-components --pr 2343)"

  [[ "$(jq -r '.state' <<<"${output}")" == "success" ]] || fail "expected success state"
  [[ "$(jq '[.checks[] | select(.non_success == true)] | length' <<<"${output}")" == "0" ]] || fail "expected no non-success checks"
}

test_wait_times_out_when_checks_do_not_finish() {
  local output status
  status=0
  output="$(with_gh_stub pending bash "${SCRIPT}" wait --repo quay/quay-konflux-components --pr 2343 --timeout-seconds 0 --interval-seconds 0 2>&1)" || status=$?

  [[ "${status}" == "2" ]] || fail "expected timeout exit 2, got ${status}: ${output}"
  [[ "${output}" == *"Timed out waiting for Red Hat Konflux checks"* ]] || fail "expected timeout message"
}

test_wait_times_out_when_no_konflux_checks_appear() {
  local output status
  status=0
  output="$(with_gh_stub none bash "${SCRIPT}" wait --repo quay/quay-konflux-components --pr 2343 --timeout-seconds 0 --interval-seconds 0 2>&1)" || status=$?

  [[ "${status}" == "2" ]] || fail "expected timeout exit 2 for missing checks, got ${status}: ${output}"
  [[ "${output}" == *"Timed out waiting for Red Hat Konflux checks"* ]] || fail "expected timeout message for missing checks"
}

test_wait_succeeds_after_pending_checks_finish() {
  local output
  output="$(with_gh_stub pending-then-success bash "${SCRIPT}" wait --repo quay/quay-konflux-components --pr 2343 --timeout-seconds 5 --interval-seconds 0 2>&1)"

  [[ "${output}" == *"All Red Hat Konflux checks completed successfully"* ]] || fail "expected success wait message"
}

test_json_extracts_non_success_konflux_checks
test_json_reports_success_when_all_konflux_checks_succeed
test_wait_times_out_when_checks_do_not_finish
test_wait_times_out_when_no_konflux_checks_appear
test_wait_succeeds_after_pending_checks_finish

echo "konflux-checks-test.sh: PASS"
