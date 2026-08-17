1. Trane Remote
2. Create a devcontainer environment for local development
3. main has no branch protection (the API returns 404 = no rules): anyone with write access can push directly, without a PR or CI. For a published gem, main should require a PR + green checks and forbid force-pushes.
4. CI runs duplicated on PRs: the trigger is on: push: (all branches) + pull_request: — that is why every check showed up twice on PR #1 (26 jobs instead of 13). One-line fix: push: branches: [main].
5. No Dependabot: worth adding for bundler (dev deps) and github-actions (action versions).
6. The GitHub Wiki tab is enabled but empty — since we decided the docs live in docs/wiki/, disable the tab so there aren't two places.
7. No topics — once public, ruby, rails, api, contracts, openapi-alternative, etc. help discoverability.
