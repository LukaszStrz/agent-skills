# Audit Checklist

How to read each line of `scripts/audit.sh` output, plus the checks the script cannot make. An **unknown** result is valid; never report "OK" for a check that failed in a way you do not understand.

> Verify every "good" value against current official docs (`source-driven-development`) before presenting it as a recommendation. GitHub settings and API fields change; this file records what was true when it was written (2026-10).

## Reading failures

| Result | Usually means |
|---|---|
| `404` on a toggle endpoint (`legacy_branch_protection`, `dependabot_alerts`) | The feature is **not enabled / not configured**. GitHub documents this as a "disabled" signal. Confirm against `repo.security_and_analysis` where possible. |
| `403` | Token lacks a scope or the plan lacks the feature. Read the message; report **unknown** or **disabled** accordingly and name the scope to request. |
| `200` with `{"enabled": false}` | Explicitly disabled (`private_vulnerability_reporting`, `immutable_releases`, `dependabot_security_updates`). |
| `http: 0` | Network or `gh` failure. Re-run before drawing conclusions. |
| Admin-only data missing (`collaborators`, `actions_secrets`) | The token is not an admin/push token. Report as unknown. |

## Checks

Severity: **High** = default branch or supply chain can be altered without review or detection. **Medium** = weakens defences or hygiene. **Low** = polish.

### Governance

| Check id | Good | If not | Sev |
|---|---|---|---|
| `rulesets`, `effective_rules_default_branch`, `legacy_branch_protection` | The default branch has, via a ruleset (preferred) or legacy protection: pull request required, at least one real required status check, block force-push (`non_fast_forward`), block deletion. Linear history when squash/rebase-only. | Direct pushes and force-pushes possible | High |
| `rulesets` (tag target) | Release tags (`v*`) cannot be updated or deleted | Tags can be moved after release | Medium (High for published libraries) |
| Ruleset `bypass_actors` | Empty, or the narrowest actor, in `pull_request` mode | Standing admin bypass makes the rules advisory | Medium |
| `repo`: merge settings | Only intended strategies enabled; `delete_branch_on_merge: true`; `allow_auto_merge: true`; `allow_update_branch: true`; squash title `PR_TITLE`, message `PR_BODY` when PR titles follow the commit convention | Mixed history, stale branches | Low |
| `repo.web_commit_signoff_required`, required signatures | Matches a **recorded decision** (the user may decline signed commits; record it, do not push it) | Undecided | Low |

### Actions

| Check id | Good | If not | Sev |
|---|---|---|---|
| `actions_workflow_permissions` | `default_workflow_permissions: read`, `can_approve_pull_request_reviews: false` | Compromised workflow can write | High |
| `actions_permissions` | `allowed_actions` is `selected` (GitHub-owned + verified + allow-list) or deliberately `all`; `sha_pinning_required: true` once workflows are pinned | Mutable action tags can be hijacked | Medium |
| `actions_fork_pr_approval` | Public repo: `all_external_contributors` | Outside PRs run workflows after one merged PR | Medium |
| `workflows` | CI exists and its aggregate job name is known **before** required checks are configured | Required check that never reports blocks every merge | High (ordering) |
| `environments` | A release environment exists for publish jobs when publishing to a registry | Publish job ungated | Medium |

### Security features

| Check id | Good | If not | Sev |
|---|---|---|---|
| `repo.security_and_analysis` | Secret scanning and push protection enabled; non-provider patterns and validity checks enabled where offered | Leaked credentials unnoticed | High |
| `dependabot_alerts`, `dependabot_security_updates` | Enabled | Known-vulnerable dependencies unnoticed | High |
| `tree.has_dependabot_config` | `.github/dependabot.yml` covers each package ecosystem **and** `github-actions` | Dependencies and actions go stale | Medium |
| `code_scanning_default_setup` or a code-scanning workflow in `tree.workflow_files` | Enabled for the repo's languages | No SAST | Medium |
| `private_vulnerability_reporting`, `tree.has_security_md` | Both present, and `SECURITY.md` says how to report and what to expect | Reporters go public or give up | Medium |

### Releases

| Check id | Good | If not | Sev |
|---|---|---|---|
| `immutable_releases` | Enabled **before the first release** | Published assets and tags can be replaced | High for libraries |
| `tags`, `releases` | Match the release process; a release workflow exists and publishes with short-lived credentials (OIDC / trusted publishing), not stored API keys | Long-lived registry secret | High |

### Community and metadata

| Check id | Good | If not | Sev |
|---|---|---|---|
| `community_profile` | README, LICENSE, CONTRIBUTING, CODE_OF_CONDUCT, issue forms, PR template all present | Low health score, unclear contribution path | Low |
| `tree.has_codeowners` | Present when more than one maintainer or when code-owner review is required | Solo repo: optional | Low |
| `repo`: description, homepage, topics, license | Description and topics set; SPDX license detected | Poor discoverability | Low |
| `repo.has_wiki`, `has_projects` | Off unless used | Unmoderated surface | Low |
| `labels` | Taxonomy that matches issue forms and release-note categories | Default labels only | Low |
| `tree.has_gitattributes`, `tree.has_editorconfig` | Both present and agree on line endings | Noisy diffs, CRLF/LF churn, failing Linux CI | Medium |

### Hygiene

| Check id | Good | If not | Sev |
|---|---|---|---|
| `open_pull_requests` | None stale | Review debt | Low |
| `collaborators` | Least privilege, only people who need access | Over-broad access | Medium |

## Checks the script cannot make (ask or inspect locally)

- **Account:** two-factor authentication with a phishing-resistant method; registry accounts (for example nuget.org) also secured. Ask the user; do not assume.
- **Registry:** package ID availability and prefix reservation; trusted-publishing policy matches the repo, release workflow filename, and environment exactly.
- **Local repo:**
  - Line endings: `git ls-files --eol` (look for `i/crlf` or `i/mixed`), and `git config core.autocrlf`.
  - Stale branches: `git branch -vv` and `git branch -r --merged origin/<default>`.
  - Stale local config files that point at third-party services the user no longer uses.
- **Ecosystem files:** see the matching profile, for example [ecosystem-dotnet-nuget.md](ecosystem-dotnet-nuget.md).

## Report format

Findings table, most severe first:

| Area | Finding | Evidence (check id + value) | Sev | Proposed fix | Approval tier |
|---|---|---|---|---|---|

Follow it with: items marked **unknown** and why, items the user **deferred** (with what is blocked by each), and the dependency-ordered plan.
