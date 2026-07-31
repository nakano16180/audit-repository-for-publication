#!/usr/bin/env bash
set -euo pipefail

script="$(
  cd "$(dirname "${BASH_SOURCE[0]}")/.." &&
    pwd
)/scripts/audit_repository.sh"
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

fail_test() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

assert_contains() {
  [[ "$1" == *"$2"* ]] || fail_test "expected output to contain: $2"
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

clean_output="$("$script" "$clean_repo" --branch main)" ||
  fail_test 'clean ordinary repository should not fail'
assert_contains "$clean_output" 'PASS: no work-record-like path found'
assert_contains "$clean_output" 'PASS: all author and committer emails use GitHub noreply'
assert_contains "$clean_output" 'Prospective push refspec: refs/heads/main:refs/heads/main'

skill_repo="$tmp_dir/skill"
init_repo "$skill_repo"
printf '%s\n' '---' 'name: fixture' 'description: Fixture.' '---' >"$skill_repo/SKILL.md"
git -C "$skill_repo" add README.md LICENSE SKILL.md
git -C "$skill_repo" commit -q -m 'skill fixture'

skill_output="$("$script" "$skill_repo" --branch main)" ||
  fail_test 'skill repository should be accepted without special requirements'
assert_contains "$skill_output" 'PASS: target is a Git repository'

leaky_repo="$tmp_dir/leaky"
init_repo "$leaky_repo"
mkdir -p "$leaky_repo/records/example/sessions"
printf '%s\n' 'CODEX_THREAD_ID=019f1234-secret' \
  >"$leaky_repo/records/example/sessions/session-019f1234.md"
git -C "$leaky_repo" add README.md LICENSE records
git -C "$leaky_repo" commit -q -m 'commit work record'

set +e
leaky_output="$("$script" "$leaky_repo" --branch main 2>&1)"
leaky_status=$?
set -e
((leaky_status != 0)) || fail_test 'sensitive fixture should fail'
assert_contains "$leaky_output" 'WARN: work-record-like paths exist'
assert_contains "$leaky_output" 'FAIL: potential personal, session, or secret data found'

key_repo="$tmp_dir/key"
init_repo "$key_repo"
printf '%s\n' 'not-a-real-key' >"$key_repo/server.key"
git -C "$key_repo" add README.md LICENSE server.key
git -C "$key_repo" commit -q -m 'key filename fixture'

set +e
key_output="$("$script" "$key_repo" --branch main 2>&1)"
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
  "$script" "$pattern_repo" --branch main \
    --sensitive-pattern 'internal-customer-[0-9]+' 2>&1
)"
pattern_status=$?
set -e
((pattern_status != 0)) || fail_test 'custom sensitive pattern should fail'
assert_contains "$pattern_output" 'FAIL: potential personal, session, or secret data found'

printf 'PASS: generic repository publication audit checks\n'
