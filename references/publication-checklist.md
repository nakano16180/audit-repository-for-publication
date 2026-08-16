# Repository Publication Checklist

Use this checklist after the bundled script. Mark an item verified only from
repository evidence, executed checks, or the relevant external system.

## Distribution surface

- The repository's purpose and intended audience are clear.
- README covers purpose, requirements, setup, usage, limitations, and support
  expectations appropriate to the project.
- LICENSE states the intended reuse terms and copyright holder.
- Package metadata, repository description, links, and examples use the final
  public name.
- Generated artifacts, caches, local databases, recordings, and large binaries
  are intentionally included or excluded.

## Safety, privacy, and ownership

- The current tree and branch-reachable history contain no secrets, private
  keys, real tokens, customer data, private conversations, session IDs, or
  unintended personal paths.
- Examples, fixtures, screenshots, logs, error output, and debug output receive
  the same privacy review as source files.
- Third-party code, fonts, images, datasets, model weights, and copied examples
  have compatible licenses and attribution.
- Security-sensitive behavior, network access, telemetry, destructive actions,
  and data retention are documented.
- Automated scanning is described as best-effort unless completeness is proven.

## Compatibility and verification

- Supported operating systems, runtimes, versions, and external services are
  stated or deliberately left version-agnostic with evidence.
- Installation or setup works from a clean environment.
- Tests cover the central user journey, important failures, and safety
  boundaries.
- The release build, package, or generated artifact is verified when relevant.
- The shortest real-environment journey is tested separately from mocks when an
  external runtime is involved.
- Known API, schema, platform, or vendor coupling is documented.

## Codex distribution types

- A single-skill repository has a valid root `SKILL.md`, matching
  `agents/openai.yaml` when present, and passes the skill validator.
- A plugin repository has a valid root `.codex-plugin/plugin.json`, passes the
  plugin validator, and its bundled skill manifests match their directories.
- Plugin roots are not required to contain `SKILL.md`; do not apply the
  single-skill validator to the plugin root.
- Skill and plugin privacy claims cover every local or remote data read, write,
  debug output, fixture, and external action.
- The clean install or discovery journey is verified in the actual Codex
  environment, separately from metadata and fixture tests.

## Git and GitHub

- The intended publication branch and exact push refspec are known.
- `git status --short` contains only intended changes before commit or push.
- Work records, plans, temporary fixtures, and investigation notes in reachable
  history have been reviewed rather than merely ignored.
- Author and committer names/emails are suitable for public display.
- Other refs, reflogs, and unreachable objects are distinguished from history
  sent by a branch-only push.
- Remote owner, repository name, visibility, topics, and default branch are
  verified.
- Branch protection, Actions permissions, secrets, Pages, Discussions, Issues,
  and security settings are reviewed when relevant.
- A private trial and clean clone/install are completed before visibility
  changes when practical.

## Decision

Use `READY` only when public documentation, licensing, reachable-history
privacy, ownership, and the central real journey are verified. Use
`READY FOR PRIVATE TRIAL` when private upload is safe but public evidence is
incomplete. Use `NOT READY` for sensitive reachable history, missing reuse
terms, failing central checks, unclear ownership, or a safety defect.
