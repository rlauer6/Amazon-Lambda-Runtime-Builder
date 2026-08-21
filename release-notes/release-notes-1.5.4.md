# Release Notes — Amazon-Lambda-Runtime-Builder 1.5.4

**Released:** Fri Aug 21 2026  
**Author:** Rob Lauer

---

## Overview

This release delivers a new `ecr-login` helper command that
consolidates Docker ECR authentication into a single, telemetry-aware
call, eliminating the three-step `get-login-password` / `docker login`
/ `report-step` pattern previously scattered across the deployment
Makefiles. It also brings a significant upgrade of the build
infrastructure to the latest `CPAN::Maker::Bootstrapper`, introducing
dependency-tier separation (`requires` / `recommends` / `suggests`), a
cleaner templating pipeline, and several usability improvements.

---

## New Features

### `ecr-login` Helper Command

A new `alr-helper ecr-login <registry-uri>` command replaces the
manual three-step ECR login sequence in `Makefile.mk`, `overlay.mk`,
and `platform.mk`.

- Fetches an ECR authorization token via `_ecr_login_password`
  (refactored from the former `cmd_ecr_get_login_password`
  implementation).
- Pipes the password directly to `docker login --username AWS
  --password-stdin`.
- Emits `start` / `ok` / `fail` telemetry via `--report-step`
  automatically, so the status dashboard updates correctly.
- One login covers all repositories in the same account and region.

**Before:**
```makefile
PASSWORD="$(alr-helper --report-step $@ get-login-password)";
echo "$$PASSWORD" | docker login --username AWS --password-stdin $$URI;
alr-helper report-step $@ docker-login ok;
```

**After:**
```makefile
alr-helper --report-step $@ ecr-login $$URI;
```

### `recommends` and `suggests` Dependency Tiers

The build system now produces and tracks three separate dependency
tiers alongside the existing `requires` file:

| File | Purpose |
|------|---------|
| `requires` | Runtime hard dependencies |
| `recommends` | Soft, non-`eval`-wrapped optional dependencies |
| `suggests` | `eval`-wrapped, optional dependencies |

All three tiers are produced in a single grouped scan via the new
`scandeps-static` `--raw` / `--requires-file` / `--recommends-file` /
`--suggests-file` interface. The `cpanfile` is now assembled from
three intermediate targets (`cpanfile.requires`,
`cpanfile.recommends`, `cpanfile.suggests`), each created by
`cpan-maker create-cpanfile --dependency-type`.

### `make repo` Target

A new `repo` target in `git.mk` creates a GitHub repository via
`gha-aws`:

```sh
make repo REPO=my-repo [PUBLIC=1] [REPO_DESCRIPTION="..."]
```

### `make install` Target

`project.mk` gains a convenience `install` target:

```sh
make install   # installs the built tarball to ~/
```

---

## Changes and Improvements

### ECR Role Refactor (`Role::ECR`)

- `cmd_ecr_get_login_password` is refactored: the token-fetch logic
  moves to a new private `_ecr_login_password` method, keeping the
  public command as a thin wrapper.
- New private `_report_login($status)` helper centralises telemetry
  emission for login operations.
- New `cmd_ecr_login` implements the full Docker login flow (see
  above).

### Build Infrastructure Updates (`CPAN::Maker::Bootstrapper` upgrade)

All managed `.includes/` files have been updated:

- **`perl.mk`** — Templating and syntax-checking are merged back into
  the `%.pm` / `%.pl` pattern rules. The intermediate `%.pm.checked` /
  `%.pl.checked` sentinel phase is removed; `deps.mk` now depends on
  `.pm.in` / `.pl.in` source files directly, eliminating the
  chicken-and-egg problem that previously required the two-phase
  approach. `PERL5LIB=` is now cleared before syntax checks to avoid
  false passes from system-installed modules. `perlcritic` output is
  captured with `tee` and configurable via `PERLCRITIC_SEVERITY`
  (default `5`) and `PERLCRITIC_THEME` (default `pbp`). `PERLINCLUDE`
  now includes `local/lib/perl5` for `cpm`-installed dependencies.
- **`help.mk`** — Help output is now buffered to a temp file and paged
  through `$PAGER` / `less` / `more` / `cat`.
- **`version.mk`** — `release`, `minor`, and `major` targets now run
  `clean` first.
- **`release-notes.mk`** — Updated to invoke `cmb release-notes`
  (replacing `bootstrapper release-notes`).
- **`update.mk`** — New managed files `bash-completion.mk`,
  `modulino.mk`, and `local.mk` are now tracked. `post-update` merges
  new `.gitignore` entries from the bootstrapper distribution. The
  Makefile update step now runs _after_ `.includes/` updates (ordering
  fix).
- **`git.mk`** — New `repo` target (see above).

### Makefile Changes

- `BOOTSTRAPPER` now resolves to `cmb` (previously `bootstrapper`).
- `SCANDEPS` now resolves to `scandeps-static` (previously
  `scandeps-static.pl`).
- `MD_UTILS` now resolves to `markdown-render` (previously `md-utils.pl`).
- `DOCKER_CPAN_INSTALLER` replaces `INSTALLER` for the `build-ci`
  target variable name.
- `GIT_SHA` and `GIT_DIRTY` are now captured at build time and exposed
  as template variables.
- `find-files` macro now excludes editor backup and lock files (`#*`,
  `.#*`, `*~`, `*.bak`).
- `deps.mk` rebuild rule now depends on `SOURCE_FILES_IN` (`.pm.in` /
  `.pl.in`) rather than built `.pm` targets — `make clean` can no
  longer trigger a spurious rebuild.
- New `extra-files.mk` is generated from `buildspec.yml` to wire
  non-source share files into the tarball dependency graph.
- New `package` target runs a full lint + scan build.
- `config.mk` gets a no-op rule (`: ;`) so a missing `config.mk` no
  longer triggers a warning.
- `-include` of `deps.mk` is now unconditional (the
  `clean`/`distclean` guard is removed, as `deps.mk` no longer depends
  on built artifacts).
- `modulino.mk` and `bash-completion.mk` are included via `-include`.
- `CPAN_INSTALLER` is detected from `cpm` or `carton` and warned about
  if absent.

### Builder Script (`builder`)

- Function renamed from `install_deps` to `install_build_deps`.
- Build dependencies slimmed to `CPAN::Maker::Bootstrapper` only
  (removes `CPAN::Maker`, `File::ShareDir`, `File::ShareDir::Install`,
  `Pod::Markdown`, `Markdown::Render` from the bootstrapped set; these
  are pulled in transitively or are no longer required at build time).
- `build-requires` validation: warns and auto-creates the file if
  missing; warns and resets to `CPAN::Maker::Bootstrapper` if the
  module is absent from the file.
- Separate `cpanfile.build` file used for build-phase installs (does
  not clobber the distribution `cpanfile`).
- `INSTALLER` default adds `--no-prebuilt`.
- `git clone` guard prevents re-cloning when the directory already exists.
- `git checkout` is skipped when no `.git` directory is present
  (e.g. when the source is bind-mounted).
- `PERL5LIB` is set to `$(pwd)/local/lib/perl5` before the final `make` invocation.
- `make` invoked as `make CMB_VERSION_DRIFT=ignore NO_ECHO=` for verbose CI output.
- `build-ci` target now bind-mounts the project directory into the
  container and passes `REPO` from `git remote get-url origin`.

### Documentation Fixes

- `README.md` / `Builder.pm.in`: Fixed typo "Th `policies` file" →
  "The `policies` file".
- `README.md` / `Builder.pm.in`: `custom-policies.js` example now
  shows the outer `{` `}` braces that were previously missing.

---

## `.gitignore` Additions

```
**/*.raw
buildspec.yml.current
extra-files.mk
local/**
```

---

## Bug Fixes

- Syntax-check macros (`check_syntax_pm`, `check_syntax_pl`) now
  reference `$@` (the build target) instead of `$<` (the source
  prerequisite) when removing bad output files and reporting errors —
  previously a failed check could remove the wrong file.
- `README.md` generation now uses `|| true` to prevent a
  `pod2markdown` / `markdown-render` failure from aborting the entire
  build.

---

## Upgrade Notes

Run `make update` after installing this release to propagate all
`.includes/` changes to your project. The update will also merge any
new entries from the bootstrapper's `gitignore` template into your
project's `.gitignore`.

If your project uses `scandeps-static.pl` or `bootstrapper` on `PATH`,
rename / alias them to `scandeps-static` and `cmb` respectively, or
update your `PATH` — the Makefile now looks for the new names.
