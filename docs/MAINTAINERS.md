# Maintainers guide

Internal documentation for gem maintainers. Everything a *user* of the gem
needs lives in the [README](../README.md) and the [wiki](wiki/Home.md); this
file covers the internals: developing, reviewing, versioning, and publishing.

## Development environment

```bash
bundle install
bundle exec rspec       # full suite (unit + integration against the dummy app)
bundle exec rubocop     # lint
bundle exec rake        # both — same checks CI runs
```

Test groups: `spec/trane/` (unit, no Rails), `spec/integration/` (real Rails
dummy app), `spec/trane/docs/` (generated documentation).

The CI matrix crosses Rails 7.2/8.0/8.1 × Ruby 3.2–4.0. Per-Rails Gemfiles
live in `gemfiles/` — the procedure for adding a new Rails or Ruby version to
the matrix is documented in [gemfiles/README.md](../gemfiles/README.md).

## Change flow

1. Short-lived branch per change, cut from `main`.
2. PR to `main`. CI must be green (full matrix + RuboCop + the security
   workflow the organization requires).
3. Merge with **"Squash and merge"** — one clean commit per PR on `main`.
4. If the change is visible to gem users, the PR adds a line to the
   `[Unreleased]` section of the [CHANGELOG](../CHANGELOG.md) and updates the
   corresponding wiki page.

**Watch the squash commit message**: GitHub pre-fills it with the
`Co-authored-by:` trailers of *every* commit in the PR. Review the message
before confirming and keep only trailers for real human authors — no
tool/AI attributions.

**Direct pushes to `main` are blocked** by an organization ruleset
("Repository security code scan"): every change goes through a PR.

## Versioning

[SemVer](https://semver.org/), with the pre-1.0 convention:

- **Patch** (`0.1.x`): bug fixes with no documented behavior change.
- **Minor** (`0.x.0`): new features — and, while on `0.x`, breaking changes
  too, always documented in the CHANGELOG with a migration note.
- **`1.0.0`**: once the public API is considered stable; from then on,
  breaking = major.

The version lives in exactly one place: `lib/trane/version.rb`.

## Publishing a release

Releases are published automatically via RubyGems
[Trusted Publishing](https://guides.rubygems.org/trusted-publishing/): the
`Release` workflow (`.github/workflows/release.yml`) builds and pushes the
gem through OIDC whenever a `v*` tag is pushed. No API keys are stored
anywhere — rubygems.org trusts this repository + workflow directly (gem page
→ Settings → Trusted publishers).

### Release checklist

1. **Release PR**: bump `lib/trane/version.rb` + turn the `[Unreleased]`
   CHANGELOG section into `[X.Y.Z] - date` (with its tag link at the bottom
   of the file). Merge to `main`.

2. **Tag** (must match `lib/trane/version.rb` — the gem is built from the
   tagged tree):

   ```bash
   git checkout main && git pull
   git tag vX.Y.Z && git push origin vX.Y.Z
   ```

   The tag push triggers the `Release` workflow, which builds and publishes
   to rubygems.org.

3. **GitHub release** (the CHANGELOG links to this tag):

   ```bash
   gh release create vX.Y.Z --title "vX.Y.Z"
   ```

   Paste the corresponding CHANGELOG section as the release notes (via the
   UI or `--notes`).

4. **Verify the page** at [rubygems.org/gems/trane](https://rubygems.org/gems/trane):
   the new version is listed and the metadata links work (Source Code,
   Changelog, Bug Tracker, Documentation).

### Manual publishing (fallback)

If the workflow is unavailable, an owner can publish by hand: create an API
key at [rubygems.org/profile/api_keys](https://rubygems.org/profile/api_keys)
(scope **Push rubygem**, ideally restricted to `trane`; password sign-in from
the CLI was retired by RubyGems), store it in `~/.gem/credentials` (mode
0600), then `gem build trane.gemspec && gem push trane-X.Y.Z.gem` from
`main` — it prompts for the MFA OTP code, mandatory because the gemspec
declares `rubygems_mfa_required`.

### Co-owners

The gem must not depend on a single account (bus factor):

```bash
gem owner trane --add gaston.gabadian@qubika.com
```

Each owner needs their own rubygems.org account with MFA. List current
owners with `gem owner trane`.

## Issues and contributions

### Reporting a bug

Open an issue on [GitHub Issues](https://github.com/thisisqubika/trane/issues)
with:

- Gem, Rails, and Ruby versions.
- Expected vs observed behavior.
- A minimal reproduction: ideally the contract definition + the
  `render contract:` call that triggers it (no sensitive data — Trane's own
  error messages only carry contract metadata; issues should meet the same
  standard).

For **security vulnerabilities**, do not open a public issue: report through
GitHub Security Advisories ("Report a vulnerability" under the Security tab)
or to the maintainer emails in the gemspec.

### Proposing a change

1. Open an issue first to discuss the design if the change affects behavior
   or public API — it avoids large rejected PRs.
2. Fork (external contributors) or branch (maintainers) → PR to `main`.
3. Merge requirements: tests covering the change (the suite treats TDD as
   the norm — failing test first), full suite green, RuboCop clean, a line
   in the CHANGELOG's `[Unreleased]` section if user-visible, and the wiki
   updated if documented behavior changes.

### Design principles to preserve in review

These decisions are deliberate — a PR eroding them needs a very good
justification:

- **Fail-closed by default**: under ambiguity the gem raises instead of
  serving unfiltered data (`on_missing_operation :raise`, configuration
  setters that validate their values, exact-FQDN error matching).
- **Immutable request path**: frozen snapshot, lock-free reads, no shared
  mutable state per request. Derived caches are invalidated on every path
  that replaces the snapshot (`clear_derived_caches`).
- **Never user data in logs**: the gem's log lines carry metadata only
  (field paths, class names) — never values. A memory regression spec
  (`spec/trane/memory_regression_spec.rb`) guards the hot paths.
- **Verbose exception messages only in local environments**
  (`Rails.env.local?`) — staging/uat/production get the generic envelope.

## Repository language

Everything in this repository is written in **English**: code, comments,
documentation, commit messages, PRs, and issues.
