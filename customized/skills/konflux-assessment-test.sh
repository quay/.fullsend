#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
AGENT="${ROOT}/agents/review.md"
HARNESS="${ROOT}/harness/review.yaml"
SKILL="${ROOT}/skills/konflux-assessment/SKILL.md"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

[[ -f "${AGENT}" ]] || fail "missing customized review agent"
[[ -f "${HARNESS}" ]] || fail "missing customized review harness"
[[ -f "${SKILL}" ]] || fail "missing Konflux Assessment skill"

grep -q "konflux-assessment" "${AGENT}" || fail "review agent must list konflux-assessment skill"
grep -q "skills/konflux-assessment" "${HARNESS}" || fail "review harness must include konflux-assessment skill"
grep -q "timeout_minutes: 120" "${HARNESS}" || fail "review harness must allow the 90 minute Konflux wait"
grep -q "quay/quay-konflux-components" "${AGENT}" || fail "review agent must scope behavior to quay/quay-konflux-components"
grep -q 'action.*"comment"' "${AGENT}" || fail "review agent must use comment for non-success Konflux without code findings"
grep -q 'action.*"failure"' "${AGENT}" || fail "review agent must fail closed when Konflux context is unavailable"

grep -q "Do not push code" "${SKILL}" || fail "skill must prohibit mutation"
grep -q "single best hypothesis" "${SKILL}" || fail "skill must require one best hypothesis"
grep -q "GitHub check-run" "${SKILL}" || fail "skill must use GitHub check-run data"
grep -q "kubectl" "${SKILL}" && fail "skill must not depend on kubectl"
grep -q "NotebookLM" "${SKILL}" && fail "skill must not depend on NotebookLM"

echo "konflux-assessment-test.sh: PASS"
