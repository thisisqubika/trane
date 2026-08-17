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

### Prerequisites (once per maintainer)

- A [rubygems.org](https://rubygems.org/sign_up) account with **MFA enabled**
  (Settings → Multi-factor Authentication → "UI and API"). This is mandatory:
  the gemspec declares `rubygems_mfa_required`.
- An **API key** (password sign-in from the CLI was retired by RubyGems):
  create one at [rubygems.org/profile/api_keys](https://rubygems.org/profile/api_keys)
  with the **Push rubygem** scope — ideally scoped to the `trane` gem — and
  store it locally:

  ```bash
  mkdir -p ~/.gem
  printf -- "---\n:rubygems_api_key: YOUR_KEY\n" > ~/.gem/credentials
  chmod 0600 ~/.gem/credentials
  ```

- Being an owner of the gem (see [Co-owners](#co-owners)).

### Release checklist

1. **Release PR**: bump `lib/trane/version.rb` + turn the `[Unreleased]`
   CHANGELOG section into `[X.Y.Z] - date` (with its tag link at the bottom
   of the file). Merge to `main`.

2. **Build and push from `main`**:

   ```bash
   git checkout main && git pull
   gem build trane.gemspec          # produces trane-X.Y.Z.gem
   gem push trane-X.Y.Z.gem         # uses ~/.gem/credentials; prompts for the MFA OTP code
   ```

   The very first push in the gem's history also claims the `trane` name on
   rubygems.org.

3. **Verify the page** at [rubygems.org/gems/trane](https://rubygems.org/gems/trane):
   the README renders (logo and absolute links are already prepared for
   this), the metadata links work (Source Code, Changelog, Bug Tracker,
   Documentation), and the new version is listed.

4. **Tag and GitHub release** (the CHANGELOG links to this tag):

   ```bash
   git tag vX.Y.Z && git push origin vX.Y.Z
   gh release create vX.Y.Z --title "vX.Y.Z"
   ```

   Paste the corresponding CHANGELOG section as the release notes (via the
   UI or `--notes`).

### Co-owners

The gem must not depend on a single account (bus factor):

```bash
gem owner trane --add gaston.gabadian@qubika.com
```

Each owner needs their own rubygems.org account with MFA. List current
owners with `gem owner trane`.

### Future automation (recommended)

Set up RubyGems [Trusted Publishing](https://guides.rubygems.org/trusted-publishing/):
on the gem's page → Settings → Trusted Publishers, authorize this repo + a
GitHub Actions workflow to publish via OIDC, with no stored API keys. With
the official [`rubygems/release-gem`](https://github.com/rubygems/release-gem)
action, the flow becomes: release PR → merge → `git push origin vX.Y.Z` → it
publishes itself. Steps 2 and 3 of the checklist go away.

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
