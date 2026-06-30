#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'EOF'
Usage:
  konflux-checks.sh json --repo owner/repo --pr number
  konflux-checks.sh wait --repo owner/repo --pr number [--timeout-seconds n] [--interval-seconds n]
EOF
}

die() {
  echo "konflux-checks: $*" >&2
  exit 1
}

command="${1:-}"
if [[ -z "${command}" ]]; then
  usage
  exit 2
fi
shift

repo=""
pr=""
timeout_seconds=5400
interval_seconds=60

while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --repo)
      repo="${2:-}"
      shift 2
      ;;
    --pr)
      pr="${2:-}"
      shift 2
      ;;
    --timeout-seconds)
      timeout_seconds="${2:-}"
      shift 2
      ;;
    --interval-seconds)
      interval_seconds="${2:-}"
      shift 2
      ;;
    *)
      usage
      exit 2
      ;;
  esac
done

[[ "${repo}" =~ ^[a-zA-Z0-9._-]+/[a-zA-Z0-9._-]+$ ]] || die "--repo must be owner/repo, got '${repo}'"
[[ "${pr}" =~ ^[1-9][0-9]*$ ]] || die "--pr must be a positive integer, got '${pr}'"
[[ "${timeout_seconds}" =~ ^[0-9]+$ ]] || die "--timeout-seconds must be a non-negative integer"
[[ "${interval_seconds}" =~ ^[0-9]+$ ]] || die "--interval-seconds must be a non-negative integer"

head_sha() {
  gh api "repos/${repo}/pulls/${pr}" | jq -r '.head.sha'
}

check_runs_for_sha() {
  local sha="$1"
  gh api "repos/${repo}/commits/${sha}/check-runs?per_page=100"
}

normalize_checks() {
  local sha="$1"
  jq --arg repo "${repo}" --argjson pr "${pr}" --arg sha "${sha}" '
    def text_blob:
      ([.details_url, .output.summary, .output.text] | map(select(. != null)) | join(" "));

    def first_pipelinerun_url:
      try (text_blob | match("https://[^\"'\''<> )]+/ns/[^\"'\''<> )]+/pipelinerun/[^\"'\''<> )]+").string) catch "";

    def namespace_from($url):
      if $url == "" then ""
      else (try ($url | capture("/ns/(?<namespace>[^/]+)/pipelinerun/").namespace) catch "")
      end;

    def pipelinerun_from($url):
      if $url == "" then ""
      else (try ($url | capture("/pipelinerun/(?<pipelinerun>[^/?#)\"'\''<> ]+)").pipelinerun) catch "")
      end;

    def failed_task_from_text:
      (.output.text // "") as $text
      | (
          (try ($text | capture("task <b>(?<task>[^<]+)</b> has the status").task) catch "")
          // (try ($text | capture("\\[(?<task>[^\\]]+)\\]\\(https://[^)]*/logs/[^)]+\\)").task) catch "")
          // ""
        );

    def failure_snippet_from_text:
      (.output.text // "") as $text
      | (
          (try ($text | capture("<h4>Failure snippet:</h4>(?<snippet>.*)").snippet) catch "")
          // ""
        )
      | gsub("<[^>]+>"; "")
      | gsub("&quot;"; "\"")
      | gsub("&lt;"; "<")
      | gsub("&gt;"; ">")
      | gsub("&amp;"; "&")
      | gsub("[[:space:]]+"; " ")
      | .[0:1000];

    def priority:
      if .status != "completed" then "pending"
      elif (.conclusion // "") as $c | ["failure", "cancelled", "timed_out", "action_required"] | index($c) then "failure"
      elif .conclusion == "neutral" then "warning"
      elif .conclusion == "success" then "success"
      else "other"
      end;

    [
      .check_runs[]
      | select(.app.slug == "red-hat-konflux")
      | first_pipelinerun_url as $url
      | {
          name,
          status,
          conclusion,
          app_slug: .app.slug,
          details_url,
          summary: (.output.summary // ""),
          pipeline_run_url: $url,
          namespace: namespace_from($url),
          pipeline_run: pipelinerun_from($url),
          failed_task: failed_task_from_text,
          failure_snippet: failure_snippet_from_text,
          assessment_priority: priority,
          non_success: (.status != "completed" or .conclusion != "success")
        }
    ] as $checks
    | {
        repo: $repo,
        pr: $pr,
        head_sha: $sha,
        state: (
          if ($checks | length) == 0 then "none"
          elif any($checks[]; .non_success) then "non-success"
          else "success"
          end
        ),
        counts: {
          total: ($checks | length),
          non_success: ([ $checks[] | select(.non_success) ] | length)
        },
        checks: $checks
      }
  '
}

json_command() {
  local sha
  sha="$(head_sha)"
  [[ -n "${sha}" && "${sha}" != "null" ]] || die "could not resolve PR head SHA"
  check_runs_for_sha "${sha}" | normalize_checks "${sha}"
}

all_terminal() {
  jq -e '
    (.counts.total > 0) and ([.checks[] | select(.status != "completed")] | length == 0)
  ' >/dev/null
}

all_success() {
  jq -e '.state == "success"' >/dev/null
}

wait_command() {
  local start now elapsed output
  start="$(date +%s)"

  while true; do
    output="$(json_command)"

    if all_terminal <<<"${output}"; then
      if all_success <<<"${output}"; then
        echo "All Red Hat Konflux checks completed successfully for ${repo}#${pr}"
      else
        non_success="$(jq -r '.counts.non_success' <<<"${output}")"
        echo "Red Hat Konflux checks reached terminal state with ${non_success} non-success check(s) for ${repo}#${pr}"
      fi
      return 0
    fi

    now="$(date +%s)"
    elapsed=$((now - start))
    if (( elapsed >= timeout_seconds )); then
      pending="$(jq -r '[.checks[] | select(.status != "completed") | .name] | join(", ")' <<<"${output}")"
      echo "Timed out waiting for Red Hat Konflux checks for ${repo}#${pr}: ${pending}" >&2
      return 2
    fi

    sleep "${interval_seconds}"
  done
}

case "${command}" in
  json) json_command ;;
  wait) wait_command ;;
  *)
    usage
    exit 2
    ;;
esac
