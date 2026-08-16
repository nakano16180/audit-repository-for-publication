#!/usr/bin/env bash
set -euo pipefail

script="$(
  cd "$(dirname "${BASH_SOURCE[0]}")/.." &&
    pwd
)/scripts/audit_repository.sh"
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

skill_validator="$tmp_dir/validate_skill.py"
plugin_validator="$tmp_dir/validate_plugin.py"
printf '%s\n' 'import sys' 'print("skill fixture valid")' >"$skill_validator"
printf '%s\n' 'import sys' 'print("plugin fixture valid")' >"$plugin_validator"
export AUDIT_SKILL_VALIDATOR="$skill_validator"
export AUDIT_PLUGIN_VALIDATOR="$plugin_validator"

fail_test() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

assert_contains() {
  [[ "$1" == *"$2"* ]] || fail_test "expected output to contain: $2"
}

assert_not_contains() {
  [[ "$1" != *"$2"* ]] || fail_test "expected output not to contain: $2"
}

run_audit() {
  bash "$script" "$@"
}

init_repo() {
  local path="$1"
  mkdir -p "$path"
  git -C "$path" init -q -b main
  git -C "$path" config user.name tester
  git -C "$path" config user.email 123+tester@users.noreply.github.com
  printf '%s\n' \
    '# Fixture' \
    '## Requirements' \
    '## Installation' \
    '## Usage' \
    '## License' >"$path/README.md"
  printf '%s\n' 'MIT License' >"$path/LICENSE"
}

clean_repo="$tmp_dir/clean"
init_repo "$clean_repo"
printf '%s\n' 'hello' >"$clean_repo/app.txt"
git -C "$clean_repo" add README.md LICENSE app.txt
git -C "$clean_repo" commit -q -m 'initial fixture'

clean_output="$(run_audit "$clean_repo" --branch main)" ||
  fail_test 'clean ordinary repository should not fail'
assert_contains "$clean_output" 'PASS: no work-record-like path found'
assert_contains "$clean_output" 'PASS: all author and committer emails use GitHub noreply'
assert_contains "$clean_output" 'Prospective push refspec: refs/heads/main:refs/heads/main'

remote_repo="$tmp_dir/remote"
init_repo "$remote_repo"
printf '%s\n' 'hello' >"$remote_repo/app.txt"
git -C "$remote_repo" add README.md LICENSE app.txt
git -C "$remote_repo" commit -q -m 'remote fixture'
git -C "$remote_repo" remote add origin \
  'https://fake-user:fake-token@example.test/owner/repository.git'

remote_output="$(run_audit "$remote_repo" --branch main)" ||
  fail_test 'credential-bearing remote fixture should complete safely'
assert_contains "$remote_output" \
  'https://example.test/owner/repository.git'
assert_not_contains "$remote_output" 'fake-user'
assert_not_contains "$remote_output" 'fake-token'

skill_repo="$tmp_dir/skill"
init_repo "$skill_repo"
printf '%s\n' '---' 'name: fixture' 'description: Fixture.' '---' >"$skill_repo/SKILL.md"
git -C "$skill_repo" add README.md LICENSE SKILL.md
git -C "$skill_repo" commit -q -m 'skill fixture'

skill_output="$(run_audit "$skill_repo" --branch main)" ||
  fail_test 'skill repository should pass its applicable validator'
assert_contains "$skill_output" 'PASS: repository type detected: Codex skill'
assert_contains "$skill_output" 'PASS: Codex skill validator passed'

plugin_repo="$tmp_dir/plugin"
init_repo "$plugin_repo"
mkdir -p "$plugin_repo/.codex-plugin"
printf '%s\n' '{}' >"$plugin_repo/.codex-plugin/plugin.json"
git -C "$plugin_repo" add README.md LICENSE .codex-plugin/plugin.json
git -C "$plugin_repo" commit -q -m 'plugin fixture'

plugin_output="$(run_audit "$plugin_repo" --branch main)" ||
  fail_test 'plugin repository should pass its applicable validator'
assert_contains "$plugin_output" 'PASS: repository type detected: Codex plugin'
assert_contains "$plugin_output" \
  'PASS: Codex plugin validator (including bundled skill manifests) passed'

leaky_repo="$tmp_dir/leaky"
init_repo "$leaky_repo"
mkdir -p "$leaky_repo/records/example/sessions"
printf '%s\n' 'CODEX_THREAD_ID=019f1234-secret' \
  >"$leaky_repo/records/example/sessions/session-019f1234.md"
git -C "$leaky_repo" add README.md LICENSE records
git -C "$leaky_repo" commit -q -m 'commit work record'

set +e
leaky_output="$(run_audit "$leaky_repo" --branch main 2>&1)"
leaky_status=$?
set -e
((leaky_status != 0)) || fail_test 'sensitive fixture should fail'
assert_contains "$leaky_output" 'WARN: work-record-like paths exist'
assert_contains "$leaky_output" 'FAIL: potential personal, session, or secret data found'
assert_contains "$leaky_output" \
  ':records/example/sessions/session-019f1234.md:1:session-identifier'
assert_not_contains "$leaky_output" '019f1234-secret'

key_repo="$tmp_dir/key"
init_repo "$key_repo"
printf '%s\n' 'not-a-real-key' >"$key_repo/server.key"
git -C "$key_repo" add README.md LICENSE server.key
git -C "$key_repo" commit -q -m 'key filename fixture'

set +e
key_output="$(run_audit "$key_repo" --branch main 2>&1)"
key_status=$?
set -e
((key_status != 0)) || fail_test 'secret-like filename should fail'
assert_contains "$key_output" 'FAIL: high-risk secret-like filenames exist'

pattern_repo="$tmp_dir/pattern"
init_repo "$pattern_repo"
printf '%s\n' 'internal-customer-42' >"$pattern_repo/example.txt"
git -C "$pattern_repo" add README.md LICENSE example.txt
git -C "$pattern_repo" commit -q -m 'custom pattern fixture'

set +e
pattern_output="$(
  run_audit "$pattern_repo" --branch main \
    --sensitive-pattern 'internal-customer-[0-9]+' 2>&1
)"
pattern_status=$?
set -e
((pattern_status != 0)) || fail_test 'custom sensitive pattern should fail'
assert_contains "$pattern_output" 'FAIL: potential personal, session, or secret data found'
assert_contains "$pattern_output" ':example.txt:1:custom-pattern'
assert_not_contains "$pattern_output" 'internal-customer-42'

printf 'PASS: generic repository publication audit checks\n'
