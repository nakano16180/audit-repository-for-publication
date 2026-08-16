#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: audit_repository.sh [PATH] [--branch BRANCH] [--github]
                           [--sensitive-pattern ERE]

Run a read-only pre-publication audit of any Git repository.

Options:
  --branch BRANCH          Branch whose reachable history would be published.
                           Default: current branch.
  --github                 Query GitHub visibility and default branch.
                           Requires gh authentication and network access.
  --sensitive-pattern ERE  Add an extended regular expression to the committed
                           content scan. May be repeated.
  --help                   Show this help.
USAGE
}

target=""
branch=""
check_github="false"
sensitive_patterns=()

while (($#)); do
  case "$1" in
    --branch)
      shift || true
      [[ $# -gt 0 ]] || { printf 'error: --branch requires a value\n' >&2; exit 2; }
      branch="$1"
      ;;
    --github)
      check_github="true"
      ;;
    --sensitive-pattern)
      shift || true
      [[ $# -gt 0 ]] || { printf 'error: --sensitive-pattern requires a value\n' >&2; exit 2; }
      sensitive_patterns+=("$1")
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    -*)
      printf 'error: unknown option: %s\n' "$1" >&2
      exit 2
      ;;
    *)
      [[ -z "$target" ]] || { printf 'error: multiple target paths supplied\n' >&2; exit 2; }
      target="$1"
      ;;
  esac
  shift
done

target="${target:-.}"
[[ -d "$target" ]] || { printf 'error: directory not found: %s\n' "$target" >&2; exit 2; }
target="$(cd "$target" && pwd -P)"

for required_command in git rg; do
  command -v "$required_command" >/dev/null 2>&1 || {
    printf 'error: required command not found: %s\n' "$required_command" >&2
    exit 2
  }
done

pass_count=0
warn_count=0
fail_count=0

pass() {
  pass_count=$((pass_count + 1))
  printf 'PASS: %s\n' "$*"
}

run_validator() {
  local label="$1"
  local validator="$2"
  local output
  local status

  if [[ -z "$validator" || ! -f "$validator" ]]; then
    warn "$label was not found; run it in the target environment"
    return
  fi

  set +e
  output="$(python3 "$validator" "$target" 2>&1)"
  status=$?
  set -e
  if ((status == 0)); then
    pass "$label passed"
  elif [[ "$output" == *"ModuleNotFoundError"* || "$output" == *"No module named"* ]]; then
    warn "$label could not run because a Python dependency is unavailable"
    printf '%s\n' "$output" | sed 's/^/  /' | sed -n '1,5p'
  else
    fail "$label failed"
    printf '%s\n' "$output" | sed 's/^/  /' | sed -n '1,20p'
  fi
}

warn() {
  warn_count=$((warn_count + 1))
  printf 'WARN: %s\n' "$*"
}

fail() {
  fail_count=$((fail_count + 1))
  printf 'FAIL: %s\n' "$*"
}

record_sensitive_matches() {
  local revision="$1"
  local category="$2"
  local pattern="$3"
  local matched_location
  local matched_revision
  local matched_path
  local matched_line
  local ignored_content

  while IFS= read -r -d '' matched_location &&
    IFS= read -r -d '' matched_line &&
    IFS= read -r ignored_content; do
    matched_revision="${matched_location%%:*}"
    matched_path="${matched_location#*:}"
    printf '%s:%s:%s:%s\n' \
      "$matched_revision" "$matched_path" "$matched_line" "$category" \
      >>"$scan_file"
  done < <(
    git -C "$target" grep -n -I -z -E "$pattern" "$revision" -- . 2>/dev/null || true
  )
}

redact_remote_url() {
  printf '%s\n' "$1" | sed -E 's#([a-zA-Z][a-zA-Z0-9+.-]*://)[^/@]+@#\1#'
}

printf 'Audit target: %s\n' "$target"

if [[ -s "$target/README.md" ]]; then
  pass 'README.md exists and is non-empty'
  for heading in 'install|setup|getting started' 'usage|example' 'require|prerequisite|compatib' 'licen'; do
    if ! rg -qi "^#{1,6}[[:space:]]+.*($heading)" "$target/README.md" 2>/dev/null; then
      warn "README.md has no heading matching: $heading"
    fi
  done
else
  fail 'README.md is missing or empty'
fi

license_found="false"
for candidate in LICENSE LICENSE.md LICENSE.txt COPYING; do
  if [[ -s "$target/$candidate" ]]; then
    license_found="true"
    pass "license file exists: $candidate"
    break
  fi
done
[[ "$license_found" == "true" ]] || fail 'no non-empty license file found'

if [[ -d "$target/.github/workflows" ]] &&
  find "$target/.github/workflows" -type f -print -quit | rg -q .; then
  pass 'GitHub workflow files are present'
else
  warn 'no GitHub workflow files found; confirm whether automated checks are needed'
fi

if ! git -C "$target" rev-parse --git-dir >/dev/null 2>&1; then
  fail 'target is not a Git repository'
  printf 'SUMMARY: PASS=%d WARN=%d FAIL=%d\n' "$pass_count" "$warn_count" "$fail_count"
  exit 1
fi
pass 'target is a Git repository'

repository_type="repository"
if [[ -f "$target/.codex-plugin/plugin.json" ]]; then
  repository_type="plugin"
  pass 'repository type detected: Codex plugin'
elif [[ -f "$target/SKILL.md" ]]; then
  repository_type="skill"
  pass 'repository type detected: Codex skill'
else
  pass 'repository type detected: generic repository'
fi

if [[ -z "$branch" ]]; then
  branch="$(git -C "$target" branch --show-current)"
fi
if [[ -z "$branch" ]]; then
  fail 'publication branch is not specified and HEAD is detached'
elif git -C "$target" rev-parse --verify --quiet "$branch^{commit}" >/dev/null; then
  pass "publication branch resolves: $branch"
  printf 'Prospective push refspec: refs/heads/%s:refs/heads/%s\n' "$branch" "$branch"
else
  fail "publication branch does not resolve: $branch"
fi

status_output="$(git -C "$target" status --short)"
if [[ -z "$status_output" ]]; then
  pass 'working tree is clean'
else
  warn 'working tree has uncommitted changes'
  printf '%s\n' "$status_output" | sed 's/^/  /'
fi

if [[ -n "$branch" ]] &&
  git -C "$target" rev-parse --verify --quiet "$branch^{commit}" >/dev/null; then
  record_paths="$(
    git -C "$target" log "$branch" --name-only --format= |
      sed '/^$/d' |
      sort -u |
      rg '(^|/)(records?|sessions?|plans?)(/|$)|(^|/)session-[0-9a-fA-F]{8}[^/]*\.md$' || true
  )"
  if [[ -z "$record_paths" ]]; then
    pass 'no work-record-like path found in branch-reachable history'
  else
    warn 'work-record-like paths exist in branch-reachable history; review intent'
    printf '%s\n' "$record_paths" | sed 's/^/  /'
  fi

  risky_paths="$(
    git -C "$target" log "$branch" --name-only --format= |
      sed '/^$/d' |
      sort -u |
      rg '(^|/)\.env($|\.)|(^|/)(id_rsa|id_ed25519)(\.pub)?$|\.pem$|\.p12$|\.pfx$|\.key$' || true
  )"
  if [[ -z "$risky_paths" ]]; then
    pass 'no high-risk secret filename found in branch-reachable history'
  else
    fail 'high-risk secret-like filenames exist in branch-reachable history'
    printf '%s\n' "$risky_paths" | sed 's/^/  /'
  fi

  scan_file="$(mktemp)"
  trap 'rm -f "$scan_file"' EXIT
  while IFS= read -r revision; do
    record_sensitive_matches \
      "$revision" 'personal-path' '(/home/|/Users/)[A-Za-z0-9._-]+/'
    record_sensitive_matches \
      "$revision" 'session-identifier' \
      'CODEX_THREAD_ID[=:][[:space:]]*[0-9a-fA-F]{8}|ATUIN_SESSION[=:][[:space:]]*[0-9a-fA-F]{8}|WT_SESSION[=:][[:space:]]*[0-9a-fA-F-]{8}'
    record_sensitive_matches \
      "$revision" 'private-key-marker' \
      '-----BEGIN ([A-Z0-9 ]+ )?PRIVATE KEY-----'
    for pattern in "${sensitive_patterns[@]}"; do
      record_sensitive_matches "$revision" 'custom-pattern' "$pattern"
    done
  done < <(git -C "$target" rev-list "$branch")
  if [[ -s "$scan_file" ]]; then
    fail 'potential personal, session, or secret data found; review locations'
    sort -u "$scan_file" | sed 's/^/  /' | sed -n '1,40p'
  else
    pass 'no default or user-supplied sensitive pattern matched committed content'
  fi

  email_output="$(
    git -C "$target" log "$branch" --format='%ae%n%ce' |
      sed '/^$/d' |
      sort -u
  )"
  non_noreply_emails="$(printf '%s\n' "$email_output" | rg -v '@users\.noreply\.github\.com$' || true)"
  if [[ -z "$non_noreply_emails" ]]; then
    pass 'all author and committer emails use GitHub noreply addresses'
  else
    warn 'public author or committer emails are present'
    printf '%s\n' "$non_noreply_emails" | sed 's/^/  /'
  fi
fi

remote_name="$(git -C "$target" remote | head -1 || true)"
if [[ -z "$remote_name" ]]; then
  warn 'no Git remote is configured'
else
  remote_url="$(git -C "$target" remote get-url "$remote_name")"
  pass "Git remote is configured: $remote_name"
  printf '  %s\n' "$(redact_remote_url "$remote_url")"
fi

if [[ -n "$branch" ]] &&
  git -C "$target" rev-parse --abbrev-ref "$branch@{upstream}" >/dev/null 2>&1; then
  upstream="$(git -C "$target" rev-parse --abbrev-ref "$branch@{upstream}")"
  pass "publication branch has upstream: $upstream"
else
  warn 'publication branch has no upstream'
fi

unreachable_output="$(
  git -C "$target" fsck --no-reflogs --unreachable --no-progress 2>/dev/null || true
)"
if [[ -z "$unreachable_output" ]]; then
  pass 'no unreachable Git objects reported'
else
  unreachable_count="$(printf '%s\n' "$unreachable_output" | sed '/^$/d' | wc -l)"
  warn "$unreachable_count unreachable Git objects exist locally; they are not normally sent by a branch-only push"
fi

if [[ "$repository_type" == "skill" ]]; then
  skill_validator="${AUDIT_SKILL_VALIDATOR:-}"
  if [[ -z "$skill_validator" ]]; then
    for candidate in \
      "${CODEX_HOME:-$HOME/.codex}/skills/.system/skill-creator/scripts/quick_validate.py" \
      "$HOME/.codex/skills/.system/skill-creator/scripts/quick_validate.py"; do
      if [[ -f "$candidate" ]]; then
        skill_validator="$candidate"
        break
      fi
    done
  fi
  run_validator 'Codex skill validator' "$skill_validator"
elif [[ "$repository_type" == "plugin" ]]; then
  plugin_validator="${AUDIT_PLUGIN_VALIDATOR:-}"
  if [[ -z "$plugin_validator" ]]; then
    for candidate in \
      "${CODEX_HOME:-$HOME/.codex}/skills/.system/plugin-creator/scripts/validate_plugin.py" \
      "$HOME/.codex/skills/.system/plugin-creator/scripts/validate_plugin.py"; do
      if [[ -f "$candidate" ]]; then
        plugin_validator="$candidate"
        break
      fi
    done
  fi
  run_validator 'Codex plugin validator (including bundled skill manifests)' "$plugin_validator"
fi

if [[ "$check_github" == "true" ]]; then
  if ! command -v gh >/dev/null 2>&1; then
    fail '--github requested but gh is not installed'
  elif [[ -z "$remote_name" ]]; then
    fail '--github requested but no remote is configured'
  else
    github_json="$(
      cd "$target" &&
        gh repo view --json nameWithOwner,visibility,defaultBranchRef,url 2>/dev/null || true
    )"
    if [[ -z "$github_json" ]]; then
      fail 'GitHub repository state could not be read'
    else
      pass 'GitHub repository state was read'
      printf '  %s\n' "$github_json"
    fi
  fi
else
  warn 'GitHub visibility and default branch were not checked; rerun with --github when needed'
fi

printf 'SUMMARY: PASS=%d WARN=%d FAIL=%d\n' "$pass_count" "$warn_count" "$fail_count"
((fail_count == 0))
