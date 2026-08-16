# Audit Repository for Publication

`audit-repository-for-publication` is a Codex skill for reviewing a Git
repository before making it public on GitHub. It checks the publication branch,
reachable history, author metadata, documentation, licensing, and common traces
of work records or personal data. It does not publish or modify the target
repository.

This skill supersedes `audit-skill-for-publication`; Codex skill and plugin
repositories are handled through automatic repository-type detection.

## Requirements

- Codex
- Bash 4 or later
- Git
- ripgrep
- GitHub CLI when GitHub visibility and default-branch checks are requested
- Python 3 and the Codex skill validator when auditing a Codex skill
- Python 3 and the Codex plugin validator when auditing a Codex plugin

The bundled scripts target Linux and WSL. Other Unix-like environments may work
but are not currently tested.

## Installation

Install the repository as `audit-repository-for-publication` in a Codex skills
directory, or ask Codex to install it with `$skill-installer`.

## Usage

Invoke the skill and identify the repository to audit:

```text
$audit-repository-for-publication audit this repository before I make it public
```

The bundled read-only audit can also be run directly:

```bash
scripts/audit_repository.sh /path/to/repository --branch main
```

Add `--github` to read repository visibility and default-branch information
through GitHub CLI. Add project-specific committed-content checks with repeated
`--sensitive-pattern ERE` options.

The report distinguishes blocking failures, material warnings, and verified
checks. A branch-only push publishes commits reachable from that branch; local
reflogs, unreachable objects, other branches, and tags have different Git
boundaries and are reported separately.

The script detects a root `SKILL.md` as a single Codex skill and a root
`.codex-plugin/plugin.json` as a Codex plugin. It automatically runs the
applicable installed validator; plugin detection takes precedence.

## Privacy and security

The audit reads the target repository's current tree, Git metadata, and full
history reachable from the selected branch. With `--github`, it also queries
GitHub for repository metadata using the current `gh` authentication.

The scanner reports locations and categories instead of intentionally printing
secret values. Pattern matching is best-effort and cannot prove that a history
is free of secrets or personal data. Review every match and inspect examples,
fixtures, generated output, and third-party assets before publication.

The skill does not push, change visibility, rewrite history, or delete Git
objects. Those operations require a separate explicit request.

## Compatibility and limitations

The audit assumes a Git repository and a publication branch resolvable as a
local commit. GitHub checks require a configured remote understood by GitHub CLI.
Automated checks cannot establish documentation accuracy, ownership, license
compatibility, or whether a real user journey succeeds; the bundled checklist
requires these human-judgment checks separately.

## Development and testing

Run the syntax check and integration test:

```bash
bash -n scripts/audit_repository.sh tests/test_audit_repository.sh
bash tests/test_audit_repository.sh
```

The integration test creates temporary Git repositories and exercises clean and
leaky publication histories without changing an existing repository.

## License

[MIT](LICENSE)
