---
name: github-repo-review-and-setup
description: Audits a GitHub repository's live configuration against current open-source best practices and applies the fixes in a safe order, covering rulesets and branch protection, security features, workflow permissions, merge settings, community-health files, line endings, immutable releases, and package-publishing setup. Use when setting up a new repository or repo template, reviewing or hardening an existing repo's GitHub settings, checking what is actually enabled on GitHub, or preparing an open-source library repo for releases. Applies even when the user only asks what is configured, wants a settings checklist, or is the sole maintainer of their own repo.
---

# GitHub Repo Review and Setup

## Overview

Repository setup fails in two ways: settings are assumed from the files in the repo instead of read from GitHub, and protections are applied in an order that locks the maintainer out. This skill audits the **live** configuration, reports findings with evidence, plans the fixes in dependency order, applies them only with approval, and verifies the result.

It adds the GitHub-specific knowledge that the rest of the pack lacks and delegates everything else. Do not restate other skills here; invoke them at the points named below.

## When to Use

- Setting up a new repo, or building a repo template, for open-source work
- "What is configured on this repo?", "review my repo settings", "harden this repo", "what best practices am I missing?"
- Preparing a library repo for its first release (rulesets, security features, release and publishing setup)
- Re-auditing a repo after a long gap, since GitHub settings and APIs change

**When NOT to use:**

- Day-to-day commits, branches and PRs: `git-workflow-and-versioning`
- Writing or debugging a specific workflow for an application: `ci-cd-and-automation`
- Finding vulnerabilities in the code itself: `security-and-hardening`
- Reviewing a code change: `code-review-and-quality`

## How This Skill Composes the Others

| Phase | Invoke | This skill adds |
|---|---|---|
| Scope and decisions | `interview-me` (only for open decisions that change the outcome) | The list of GitHub-specific decisions worth asking about, and the rule that a deferral is a valid answer |
| Quality bar | `constraint-driven-development` | Mapping each constraint to the mechanism that enforces it (ruleset, required check, Dependabot, scanning) |
| Research | `source-driven-development` | Which settings and API fields to verify, and the rule that web summaries are leads, not authority |
| Audit | none | `scripts/audit.sh` and [references/audit-checklist.md](references/audit-checklist.md) |
| Plan | `planning-and-task-breakdown` | The dependency-ordering rules below |
| Apply | `incremental-implementation`, `git-workflow-and-versioning`, `ci-cd-and-automation`, `security-and-hardening` (supply chain) | [references/apply-playbook.md](references/apply-playbook.md): exact mutations, approval tiers, rollback |
| High-risk steps | `doubt-driven-development` | Which steps count as high-risk |
| Verify and hand over | `code-review-and-quality`, `shipping-and-launch`, `documentation-and-adrs` | Re-audit diff, and ADRs for non-obvious settings |

## Process

### 1. Scope the repository

Establish, from the repo itself where possible and from the user otherwise:

- `OWNER/REPO`, personal account or organization, public or private (plan limits differ)
- Number of maintainers. A **sole maintainer** cannot approve their own PRs; see the solo section
- Deliverable and ecosystem. For a .NET library published to NuGet, also load [references/ecosystem-dotnet-nuget.md](references/ecosystem-dotnet-nuget.md)
- Decisions already made, **including declined ones** (for example "no signed commits"). Record them and never re-propose them

If decisions are open, ask only those that change the outcome, and accept "defer". For each deferral, note what it blocks and move on to everything it does not block.

### 2. Research what is current

Settings, API fields, plan limits and action versions change. Before recommending anything not already verified in this session, check it against official documentation (`source-driven-development`) and note the date. Treat search summaries as leads: cross-check any that disagree with each other, and say so in the report rather than picking one.

### 3. Audit (read-only)

```bash
skills/github-repo-review-and-setup/scripts/audit.sh OWNER/REPO > audit.jsonl
```

The script only issues GET requests and prints one JSON object per check. Interpret it with [references/audit-checklist.md](references/audit-checklist.md). Add the local checks the script cannot make (line endings, stale branches, account-level questions).

- A failed check is **unknown** until you understand why. `404` on a toggle usually means "disabled"; `403` usually means a missing scope. Name the scope.
- Never "fix" an unknown by assuming.

### 4. Report and plan

Produce the findings table from the checklist, then an ordered plan. Order by these rules, because violating them causes lockouts or broken pipelines:

1. **Files and workflows first, enforcement last.** CI must exist and have reported a check before that check is required.
2. **Line endings before anything that diffs or formats.** Normalize in its own commit before adding formatters or CI gates that compare files.
3. **Immutable releases before the first release**, and the release workflow built as draft, attach assets, publish.
4. **SHA-pinning enforcement only after every workflow is pinned.**
5. **Registry trust setup (OIDC policy) only once the workflow file name is final.**
6. Deferred items stay on the plan as "blocked by decision X".

Put each step in an approval tier from [references/apply-playbook.md](references/apply-playbook.md):

| Tier | Examples | Approval |
|---|---|---|
| A. Repo files | `.gitattributes`, workflows, community files | Open as a PR; the user merges |
| B. Reversible settings | merge options, Dependabot, topics, labels | User approves the specific list, then apply one by one |
| C. Hard to undo or lockout risk | rulesets, immutable releases, visibility, deleting refs, secrets, registry publishing | `doubt-driven-development` review, then explicit per-item approval |

### 5. Apply

- Work in thin slices (`incremental-implementation`): one PR per phase for Tier A, one approved batch per Tier B group, one item at a time for Tier C.
- Snapshot before changing anything and keep the rollback command next to each change.
- Always pass the repository explicitly to `gh`. Never push to the default branch to make a change land.
- Stop at the first unexpected response. Do not retry blindly or work around a permission error; report what scope or plan feature is missing.

### 6. Verify and hand over

- Re-run the audit and diff it against the pre-change snapshot. Every intended change appears; nothing else moved.
- Confirm enforcement without breaking anything: list the rules that apply to the branch with `gh api repos/OWNER/REPO/rules/branches/<branch>`; do not test by attempting a forbidden push.
- Record non-obvious decisions as ADRs (`documentation-and-adrs`), for example "zero required approvals because sole maintainer", "signed commits declined".
- Final report: what changed (old and new values), what is deferred and what blocks it, what remains unknown, and the escape-hatch command for each ruleset.

## Sole Maintainer Notes

- A PR rule that requires approvals can never be satisfied by the only maintainer. Require a PR with **zero** approvals and make required status checks the gate.
- Do not add a standing admin bypass. If a break-glass path is wanted, scope it to `pull_request` mode, or rely on the fact that admins can disable a ruleset.
- AI reviewers and similar integrations are advisory: never required checks, and added only once the user has chosen a provider.
- CODEOWNERS and required reviewers add nothing for one person; skip them until there is a second maintainer.

## Common Rationalizations

| Rationalization | Reality |
|---|---|
| "The workflow files show what's enabled" | Files show intent. Settings, rulesets and security toggles live on GitHub; only the API shows them. |
| "I'll turn on the required check first, then add CI" | A required check that never reports blocks every merge, including yours. CI first. |
| "It's my own repo, I'll push straight to main to apply this" | Use a PR. The point of the setup is that nothing reaches the default branch unreviewed. |
| "The search summary said this setting exists" | Summaries conflict and go stale. Verify against official docs and state the date. |
| "403 means it's fine" | 403 means you do not know. Report unknown and name the missing scope. |
| "The user didn't say no to signed commits" | If they declined, it is a recorded decision. Do not re-propose or re-add it. |
| "Immutable releases are just another toggle" | They cannot be undone for releases already published and shape the release workflow. Tier C. |
| "Let me apply all the settings in one script" | One failure midway leaves an unknown state. One change, then re-audit. |

## Red Flags

- Settings changed without a saved snapshot or a rollback command
- A ruleset activated with a required check that has never reported
- A `GET` result of `404` or `403` reported as "OK"
- Changes pushed directly to the default branch
- The same declined decision raised again
- Recommendations with no source or date, or that cite only a search summary
- Any Tier C action taken on a batch approval instead of per-item approval

## Verification

- [ ] The audit ran against the live repo, and every check is marked OK, finding, or unknown with a reason
- [ ] Findings table has evidence (check id and value) and severity for each row
- [ ] Open decisions are recorded as decided, declined, or deferred, with what each deferral blocks
- [ ] Plan follows the ordering rules and each step has an approval tier
- [ ] Every applied change had approval at its tier, a snapshot, and a rollback command
- [ ] Post-change audit diff shows exactly the intended changes
- [ ] Rules in force were confirmed through the rules API, not by attempting a forbidden action
- [ ] Final report lists changes, deferrals, unknowns, and escape hatches
