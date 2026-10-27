# Ecosystem Profile: .NET Library Published to NuGet

Load this when the repository's deliverable is a .NET library packed with `dotnet pack` and published to nuget.org. It supplies the project-level and registry-level checks that sit on top of the generic audit.

> **Property names and workflow shapes are from memory and web summaries, not yet checked against `learn.microsoft.com`.** Run `source-driven-development` against the current .NET SDK and NuGet docs before writing any of them into a repo, and resolve GitHub Action versions to full commit SHAs with `gh api` at the time of writing.

## Project skeleton checks

| File | What it should do |
|---|---|
| `global.json` | Pins the SDK (feature band) with an explicit `rollForward`; needed when several SDKs are installed. |
| `Directory.Build.props` | Repo-wide: `Nullable`, `TreatWarningsAsErrors`, analyzer level, `EnforceCodeStyleInBuild`; `ContinuousIntegrationBuild` set only when `GITHUB_ACTIONS` is `true`; SourceLink properties (`PublishRepositoryUrl`, `EmbedUntrackedSources`); NuGet audit enabled. |
| `Directory.Packages.props` | Central Package Management; lock files with locked-mode restore in CI. |
| `nuget.config` | Only the intended sources, with package source mapping. |
| `.editorconfig`, `.gitattributes` | See the line-endings section of [apply-playbook.md](apply-playbook.md). |
| Library `.csproj` | Package metadata: ID, authors, description, SPDX license expression, readme, project and repository URLs, tags, icon; symbol package (`snupkg`). After the first release: package validation against the previous version, so accidental breaking changes fail the build. |
| Versioning | Tag-driven versioning (for example MinVer or Nerdbank.GitVersioning) so the tag is the single source of truth. **Ask the user**; do not pick silently. |

## CI shape (once a skeleton project exists)

- Restore in locked mode, build `Release`, test, and `dotnet pack` as a smoke test on every PR.
- Formatting and line-ending gates: `dotnet format --verify-no-changes` and the renormalize check.
- **One aggregate job** with a stable, deliberately chosen name; that name is what the ruleset requires. Renaming it later breaks merges.
- Pin every action to a full SHA; set `permissions` to the minimum per job; use `concurrency` to cancel superseded runs.
- Wire shared quality gates through `constraint-driven-development` and `ci-cd-and-automation`; do not restate them here.

## Release shape

Tag `vX.Y.Z` triggers: build, test, pack, **attest build provenance**, create a **draft** GitHub release with `.nupkg` and `.snupkg` attached, push to nuget.org with **trusted publishing**, then publish the release. The draft-then-publish order is required once immutable releases are on.

The publish job runs in a dedicated environment, requests `id-token: write` only there, and exchanges the OIDC token for a short-lived key with the NuGet login action. No stored API key.

## nuget.org steps (manual; the user's account)

1. Two-factor authentication on, with a phishing-resistant method.
2. Check the package ID is free; consider reserving an ID prefix.
3. Add a trusted-publishing policy whose repository owner, repository, **workflow file name** and environment match the repo exactly. A renamed workflow silently invalidates it.
4. First publish: use a prerelease version. Published versions can be unlisted but never deleted.

## Deferrable items

Record, do not decide: package ID, target frameworks, versioning tool, release trigger, test stack, API-compat baseline. Each affects the files above; list what is blocked until it is chosen.
