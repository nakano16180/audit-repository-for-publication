---
name: audit-repository-for-publication
description: Audit any Git repository before making it public on GitHub. Use when Codex needs to assess public-release readiness, inspect README and license coverage, scan branch-reachable history for work records, secrets, personal paths or session data, review author and committer identity, verify branch and remote scope, distinguish unreachable local objects from pushable history, or evaluate a private trial before changing repository visibility.
---

# Audit Repository for Publication

Audit first. Do not publish, push, rewrite history, delete objects, or change
repository visibility unless the user separately authorizes that action.

## Workflow

1. Resolve the repository and intended publication branch. Ask only when local
   context cannot determine them safely.
2. Run the bundled read-only audit from this skill directory:

   ```bash
   scripts/audit_repository.sh /path/to/repository --branch main
   ```

   Add project-specific patterns with repeated `--sensitive-pattern ERE`.
3. Read `references/publication-checklist.md`. Inspect the human-judgment items
   the script cannot prove, especially documentation accuracy, privacy claims,
   compatibility, third-party assets, generated artifacts, and the shortest
   real user journey.
4. Inspect the repository's documented toolchain before running tests. Run the
   central tests and release/build checks without installing missing tools or
   executing unfamiliar scripts outside the user's authorization.
5. If GitHub state matters, explain the external read and rerun:

   ```bash
   scripts/audit_repository.sh /path/to/repository --branch main --github
   ```

6. For a Codex skill repository only, also run the applicable skill validator.
   Do not require `SKILL.md` or skill metadata from ordinary repositories.
7. Report evidence in priority order:
   - `FAIL`: blocks public release or requires explicit review.
   - `WARN`: material limitation or incomplete evidence.
   - `PASS`: verified evidence.

## Git Boundaries

- A branch-only push sends commits and objects reachable from that branch.
- Other branches and tags are not included unless separately pushed.
- Reflog-only and unreachable objects normally are not sent by
  `git push <remote> <branch>`.
- Never use `.gitignore` as proof that a file was never committed.
- Inspect both author and committer metadata in the full reachable history.
- Treat history rewriting and object deletion as destructive actions requiring
  explicit authorization.

## Guardrails

- Keep the audit read-only by default.
- Never print secret values; report commit, path, line, and category only.
- Treat automated secret and personal-data scans as incomplete.
- Before any later commit or push, run `git status --short` and confirm records,
  plans, fixtures, build output, and investigation notes are intentionally
  included or excluded.
- Treat a successful private trial as evidence, not proof of public readiness.

## Decision

Conclude with exactly one readiness result:

- `READY`: no blocking findings and required real checks passed.
- `READY FOR PRIVATE TRIAL`: safe to test privately, with named public gaps.
- `NOT READY`: one or more blocking findings remain.

Include the audited branch, exact prospective push refspec, remote and
visibility when verified, checks actually run, blockers, warnings, and any
action that still requires authorization.

