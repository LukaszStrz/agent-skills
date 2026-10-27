# Apply Playbook

Concrete mutations for the fixes found by the audit. Use only after the user has approved the specific items (see the approval tiers in `SKILL.md`).

> **Field names and payloads below are starting points, last checked 2026-10.** Re-verify each against current official docs (`source-driven-development`) before the first call, and prefer `gh repo edit` / `gh label` / `gh ruleset`-style subcommands where `gh` offers them. `REPO` below is `OWNER/REPO`, always explicit.

## Ground rules

1. **Snapshot first.** Save `scripts/audit.sh` output, plus `gh api repos/$REPO/rulesets/<id>` for any ruleset you will modify, to a file **outside** the repo. That file is your rollback reference.
2. **One change per call, then re-audit.** Never batch unrelated settings; a failed call in the middle of a batch leaves an unknown state.
3. **Send JSON bodies from a file or stdin** (`--input file.json`), not inline strings; quoting differs across shells.
4. **Record what changed** (setting, old value, new value) for the final report and any ADR.

## Tier B: reversible settings

| Goal | Command | Rollback |
|---|---|---|
| Merge settings | `gh api -X PATCH repos/$REPO -F allow_auto_merge=true -F allow_update_branch=true -F delete_branch_on_merge=true -f squash_merge_commit_title=PR_TITLE -f squash_merge_commit_message=PR_BODY` | Same call with old values |
| Turn off unused surfaces | `gh api -X PATCH repos/$REPO -F has_wiki=false -F has_projects=false` | Same, `true` |
| Description, topics | `gh repo edit $REPO --description "..." --add-topic <t>` | `--remove-topic` |
| Dependabot alerts / security updates | `gh api -X PUT repos/$REPO/vulnerability-alerts`; `gh api -X PUT repos/$REPO/automated-security-fixes` | `-X DELETE` on the same paths |
| Secret-scanning extras | `gh api -X PATCH repos/$REPO -f 'security_and_analysis[secret_scanning_non_provider_patterns][status]=enabled' -f 'security_and_analysis[secret_scanning_validity_checks][status]=enabled'` | `status=disabled` |
| Private vulnerability reporting | `gh api -X PUT repos/$REPO/private-vulnerability-reporting` | `-X DELETE` |
| Fork PR approval (public repos) | `gh api -X PUT repos/$REPO/actions/permissions/fork-pr-contributor-approval -f approval_policy=all_external_contributors` | Previous `approval_policy` |
| Restrict allowed actions | `gh api -X PUT repos/$REPO/actions/permissions -F enabled=true -f allowed_actions=selected`, then `PUT .../actions/permissions/selected-actions` with `github_owned_allowed`, `verified_allowed`, `patterns_allowed[]` | `allowed_actions=all` |
| Require SHA-pinned actions | `gh api -X PUT repos/$REPO/actions/permissions -F enabled=true -f allowed_actions=<current> -F sha_pinning_required=true` | `sha_pinning_required=false` |
| Labels | `gh label create/edit/delete -R $REPO` | Re-create |
| Release environment | `gh api -X PUT repos/$REPO/environments/<name>`; restrict to release tags with a deployment tag policy (`POST .../deployment-branch-policies -f name='v*' -f type=tag`) | `-X DELETE` |

**Ordering traps**

- Do not enable `sha_pinning_required` until every workflow (including ones from templates and AI-review tools) uses full commit SHAs, or those workflows fail.
- Do not change a ruleset's required checks and the workflow's job names in the same step.

## Tier C: rulesets and irreversible changes

Run `doubt-driven-development` on the plan first. Each item needs explicit per-item approval.

### Default-branch ruleset (solo-maintainer variant)

A solo maintainer cannot approve their own PR, so require a PR with **zero** approvals and let required status checks do the gating. Save as `ruleset-default-branch.json`:

```json
{
  "name": "default-branch",
  "target": "branch",
  "enforcement": "evaluate",
  "conditions": { "ref_name": { "include": ["~DEFAULT_BRANCH"], "exclude": [] } },
  "bypass_actors": [],
  "rules": [
    { "type": "deletion" },
    { "type": "non_fast_forward" },
    { "type": "required_linear_history" },
    { "type": "pull_request", "parameters": {
        "required_approving_review_count": 0,
        "dismiss_stale_reviews_on_push": false,
        "require_code_owner_review": false,
        "require_last_push_approval": false,
        "required_review_thread_resolution": true } },
    { "type": "required_status_checks", "parameters": {
        "strict_required_status_checks_policy": true,
        "required_status_checks": [ { "context": "<exact name of the CI aggregate job>" } ] } }
  ]
}
```

Apply: `gh api -X POST repos/$REPO/rulesets --input ruleset-default-branch.json`.

- **Evaluate mode.** `evaluate` may not be offered on every plan. If the API rejects it (HTTP 422), create the ruleset as `disabled`, review it, then switch to `active` with a tested way back (below). Otherwise run in `evaluate`, inspect rule insights, then promote: `gh api -X PUT repos/$REPO/rulesets/<id> -f enforcement=active`.
- **Do not add `required_status_checks` until the check exists** (the workflow has run and reported that exact name). A required check that never reports blocks every merge, and with no bypass actor that includes yours.
- **Signed commits.** Add `{ "type": "required_signatures" }` **only** if the user has decided on it. If they declined, do not add it and do not re-suggest it.
- **Escape hatch.** Admins can always edit rulesets: `gh api -X PUT repos/$REPO/rulesets/<id> -f enforcement=disabled`. Write this command in the report before activating.
- **Verify the effect** without pushing anything: `gh api repos/$REPO/rules/branches/<default-branch>` lists the rules that apply to the branch.

### Release-tag ruleset

```json
{
  "name": "release-tags",
  "target": "tag",
  "enforcement": "evaluate",
  "conditions": { "ref_name": { "include": ["refs/tags/v*"], "exclude": [] } },
  "bypass_actors": [],
  "rules": [ { "type": "update" }, { "type": "deletion" }, { "type": "non_fast_forward" } ]
}
```

Creation stays allowed so the release process can tag. Tighten with a `creation` rule only if the user wants releases to come from a specific actor.

### Immutable releases

`gh api -X PUT repos/$REPO/immutable-releases` (state: `GET` the same path).

- **Hard to undo.** Releases published while this is on keep their lock; assets cannot be edited or deleted, and their tags cannot be reused. Confirm the user has read the current docs for this feature.
- **Shapes the release workflow.** Create the release as a **draft**, attach every asset, **then** publish. Anything uploaded after publish is rejected.
- Enable it **before the first release**, not after.

### Never without being asked

Changing visibility, renaming or deleting the default branch, deleting tags/releases/branches the user did not name, transferring or archiving the repo, creating or rotating secrets, publishing to a package registry.

## Repository files (Tier A: always through a pull request)

### Line endings (cross-platform)

Git is authoritative; the editor follows.

`.gitattributes`
```gitattributes
* text=auto eol=lf
*.sln  text eol=crlf
*.cmd  text eol=crlf
*.bat  text eol=crlf
*.{png,jpg,jpeg,gif,ico,pfx,snk,nupkg,dll,exe} binary
```

`.editorconfig` (fragment)
```ini
root = true
[*]
end_of_line = lf
insert_final_newline = true
charset = utf-8
trim_trailing_whitespace = true
[*.{cmd,bat,sln}]
end_of_line = crlf
```

Rollout on an existing repo, in this order, as **separate commits**:

1. Add `.gitattributes` and `.editorconfig`.
2. Renormalize: `git add --renormalize .`, inspect `git diff --cached --stat`, commit as `chore: normalize line endings`.
3. Add that commit's SHA to `.git-blame-ignore-revs` (GitHub's blame view honors this file) and tell contributors to run `git config blame.ignoreRevsFile .git-blame-ignore-revs`.

Do not rely on `core.autocrlf`; it is per-machine. Enforce in CI: `git add --renormalize . && git diff --cached --exit-code`.

### Community and policy files

| File | Notes |
|---|---|
| `SECURITY.md` | Supported versions, how to report (link to private vulnerability reporting), response expectations. Keep it short and true. |
| `CODE_OF_CONDUCT.md` | Use the official Contributor Covenant text verbatim, with a real contact method. Do not paraphrase. |
| `CONTRIBUTING.md` | How to build and test, branch and commit convention, PR expectations. |
| `.github/ISSUE_TEMPLATE/*.yml` + `config.yml` | Issue **forms**; `blank_issues_enabled: false` with `contact_links` for questions and security reports. |
| `.github/pull_request_template.md` | Checklist mirrors the Definition of Done. |
| `.github/dependabot.yml` | One entry per ecosystem **plus** `github-actions`; weekly; grouped. |
| `.github/release.yml` | Release-note categories matching the label taxonomy. |
| `CODEOWNERS` | Only if it will be used (multiple maintainers, or code-owner review). |

Minimal `dependabot.yml` for the Actions ecosystem (add the project's own ecosystem alongside):

```yaml
version: 2
updates:
  - package-ecosystem: github-actions
    directory: /
    schedule:
      interval: weekly
    groups:
      actions:
        patterns: ["*"]
```
