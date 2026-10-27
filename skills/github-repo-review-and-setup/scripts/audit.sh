#!/bin/bash
# Read-only audit of a GitHub repository's live configuration.
#
# Usage: skills/github-repo-review-and-setup/scripts/audit.sh OWNER/REPO
#
# Output: one JSON object per line on stdout (JSON Lines):
#   {"check":"<id>","http":200,"data":<json>}   request succeeded
#   {"check":"<id>","http":404,"error":"..."}   request failed (see references/audit-checklist.md
#                                               for what each failure means - 404 often means "disabled")
# Status messages go to stderr. Only GET requests are made; nothing is modified.
# Requires: gh (authenticated). The jq filters run inside gh, so a separate jq is not needed.
set -e

REPO="${1:?usage: audit.sh OWNER/REPO}"
ERR_FILE="$(mktemp)"
trap 'rm -f "$ERR_FILE"' EXIT

# check <id> <api-path-relative-to-repo> <jq-filter>  (filter must yield one JSON value)
check() {
  local id="$1" path="$2" filter="$3" out http msg
  if out="$(gh api "repos/${REPO}${path:+/}${path}" --jq "$filter" 2>"$ERR_FILE")"; then
    printf '{"check":"%s","http":200,"data":%s}\n' "$id" "${out:-null}"
  else
    http="$(sed -n 's/.*(HTTP \([0-9][0-9]*\)).*/\1/p' "$ERR_FILE" | head -1)"
    msg="$(tr -d '"\\\r\n' <"$ERR_FILE" | cut -c1-200)"
    printf '{"check":"%s","http":%s,"error":"%s"}\n' "$id" "${http:-0}" "$msg"
  fi
}

echo "Auditing ${REPO} (read-only)..." >&2

DEFAULT_BRANCH="$(gh api "repos/${REPO}" --jq '.default_branch')"

check repo "" '{visibility, owner_type: .owner.type, default_branch, archived, is_template,
  description, homepage, topics, license: .license.spdx_id,
  has_issues, has_wiki, has_projects, has_discussions,
  allow_squash_merge, allow_merge_commit, allow_rebase_merge, allow_auto_merge, allow_update_branch,
  delete_branch_on_merge, squash_merge_commit_title, squash_merge_commit_message,
  web_commit_signoff_required, security_and_analysis, viewer_permissions: .permissions}'

# Governance
check rulesets "rulesets" 'map({id, name, target, enforcement})'
check effective_rules_default_branch "rules/branches/${DEFAULT_BRANCH}" 'map(.type)'
check legacy_branch_protection "branches/${DEFAULT_BRANCH}/protection" '{enforce_admins: .enforce_admins.enabled, required_signatures: .required_signatures.enabled, reviews: .required_pull_request_reviews, checks: .required_status_checks}'

# Actions
check actions_permissions "actions/permissions" '.'
check actions_workflow_permissions "actions/permissions/workflow" '.'
check actions_fork_pr_approval "actions/permissions/fork-pr-contributor-approval" '.'
check workflows "actions/workflows" '{total_count, names: [.workflows[].path]}'
check environments "environments" '{total_count, names: [.environments[].name]}'
check actions_secrets "actions/secrets" '{total_count}'

# Security features (404 on the toggles below generally means "not enabled")
check dependabot_alerts "vulnerability-alerts" '.'
check dependabot_security_updates "automated-security-fixes" '.'
check private_vulnerability_reporting "private-vulnerability-reporting" '.'
check code_scanning_default_setup "code-scanning/default-setup" '{state, languages, query_suite}'
check secret_scanning_alerts_open "secret-scanning/alerts?state=open" 'length'

# Releases
check immutable_releases "immutable-releases" '.'
check tags "tags" 'length'
check releases "releases" 'length'

# Community and content
check community_profile "community/profile" '{health_percentage, files: (.files | with_entries(.value |= (. != null)))}'
check labels "labels?per_page=100" 'map(.name)'
check open_pull_requests "pulls?state=open" 'map({number, title, draft})'
check collaborators "collaborators" 'map({login, role_name})'
check tree "git/trees/${DEFAULT_BRANCH}?recursive=1" '. as $t | $t.tree | map(.path) as $p | {
  truncated: $t.truncated,
  has_gitattributes: ($p | index(".gitattributes") != null),
  has_editorconfig: ($p | index(".editorconfig") != null),
  has_security_md: (($p | index("SECURITY.md") != null) or ($p | index(".github/SECURITY.md") != null)),
  has_contributing: (($p | index("CONTRIBUTING.md") != null) or ($p | index(".github/CONTRIBUTING.md") != null)),
  has_code_of_conduct: (($p | index("CODE_OF_CONDUCT.md") != null) or ($p | index(".github/CODE_OF_CONDUCT.md") != null)),
  has_codeowners: (($p | index("CODEOWNERS") != null) or ($p | index(".github/CODEOWNERS") != null) or ($p | index("docs/CODEOWNERS") != null)),
  has_pr_template: (($p | index(".github/pull_request_template.md") != null) or ($p | index("pull_request_template.md") != null)),
  has_issue_templates: ($p | map(select(startswith(".github/ISSUE_TEMPLATE/"))) | length > 0),
  has_dependabot_config: (($p | index(".github/dependabot.yml") != null) or ($p | index(".github/dependabot.yaml") != null)),
  has_global_json: ($p | index("global.json") != null),
  has_nuget_config: ($p | index("nuget.config") != null or index("NuGet.config") != null),
  has_directory_build_props: ($p | index("Directory.Build.props") != null),
  workflow_files: ($p | map(select(startswith(".github/workflows/")))) }'

echo "Done. Interpret results with references/audit-checklist.md." >&2
