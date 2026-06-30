#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="${SCRIPT_DIR}/pre-review.sh"
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
mode="${KONFLUX_CHECKS_TEST_MODE:-success}"
args="$*"

if [[ "${args}" == pr\ view* ]]; then
  printf 'OPEN\n'
  exit 0
fi

if [[ "${args}" == issue\ comment* ]]; then
  cat >/dev/null
  exit 0
fi

if [[ "${args}" == *"/pulls/2343"* ]]; then
  cat "${fixture_dir}/pr.json"
  exit 0
fi

if [[ "${args}" == *"/commits/abc123/check-runs"* ]]; then
  case "${mode}" in
    success) cat "${fixture_dir}/check-runs-success.json" ;;
    pending) cat "${fixture_dir}/check-runs-pending.json" ;;
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
  "$@"
}

run_pre_review() {
  local repo="$1"
  local mode="$2"
  REVIEW_TOKEN=test-token \
  GH_TOKEN=test-token \
  PR_NUMBER=2343 \
  REPO_FULL_NAME="${repo}" \
  GITHUB_PR_URL="https://github.com/${repo}/pull/2343" \
  KONFLUX_WAIT_TIMEOUT_SECONDS=0 \
  KONFLUX_WAIT_INTERVAL_SECONDS=0 \
  with_gh_stub "${mode}" bash "${SCRIPT}"
}

test_non_target_repo_skips_konflux_wait() {
  local output
  output="$(run_pre_review quay/ai-helpers success)"

  [[ "${output}" == *"Skipping Konflux Assessment wait for quay/ai-helpers"* ]] || fail "expected non-target skip message"
  [[ "${output}" != *"Red Hat Konflux"* ]] || fail "did not expect Konflux wait output"
}

test_target_repo_wait_timeout_does_not_abort_review() {
  local output
  output="$(run_pre_review quay/quay-konflux-components pending 2>&1)"

  [[ "${output}" == *"Timed out waiting for Red Hat Konflux checks"* ]] || fail "expected wait timeout message"
  [[ "${output}" == *"proceeding to review agent"* ]] || fail "expected review to proceed after timeout"
}

test_target_repo_successful_wait_proceeds() {
  local output
  output="$(run_pre_review quay/quay-konflux-components success)"

  [[ "${output}" == *"All Red Hat Konflux checks completed successfully"* ]] || fail "expected successful wait message"
  [[ "${output}" == *"proceeding to review agent"* ]] || fail "expected review to proceed"
}

test_non_target_repo_skips_konflux_wait
test_target_repo_wait_timeout_does_not_abort_review
test_target_repo_successful_wait_proceeds

echo "pre-review-test.sh: PASS"
