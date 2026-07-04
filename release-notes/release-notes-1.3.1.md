# Release Notes — v1.3.1

**Date:** 2026-07-04
**Author:** Rob Lauer <rclauer@gmail.com>

---

## Overview

Version 1.3.1 is a maintenance and tooling update to the
`CPAN::Maker::Bootstrapper`-driven build infrastructure. This release
modernises the build toolchain, improves resilience when optional
tools are absent, adds Docker module-reinstall support, and fixes
several minor bugs in the `Makefile` and helper scripts.

---

## What's New

### Docker: Module Reinstall Support (`share/Dockerfile`, `share/Makefile.mk`)

A new Docker build stage has been added that allows specific Perl
modules to be reinstalled after the main distribution is
installed. This is useful when dependent modules are also under active
development.

- A new `requires.reinstall` file can be placed in the project
  root. If present, it will be copied into the Docker build context
  and used to reinstall the listed modules via `cpm install
  --reinstall`.
- A new `CACHE_BUST` build argument has been added to
  `share/Dockerfile` and passed through `share/Makefile.mk`, allowing
  the reinstall layer to be invalidated on demand.

**Usage:** Create a `requires.reinstall` file containing one module
per line, then trigger a rebuild.

---

## Changes to Build Infrastructure

### `Makefile` — Robustness and Tool Detection

- **`make-cpan-dist.pl` replaced by `cpan-maker`:** The
  `MAKE_CPAN_DIST` variable and its associated command have been
  replaced with `CPAN_MAKER` (`cpan-maker`). The `cpanfile` generation
  target now calls `$(CPAN_MAKER) create-cpanfile`.
- **`PODEXTRACT` removed from `perl.mk`:** The variable is now only
  referenced conditionally; an explicit error message is emitted if
  `podextract` is not installed when POD extraction is attempted.
- **Hard error if `CPAN::Maker::Bootstrapper` is absent:** The
  `Makefile` now emits a fatal `$(error ...)` if `bootstrapper` is not
  found on `PATH`.
- **Warning if `Markdown::Render` is absent:** A non-fatal `$(warning
  ...)` is emitted when `md-utils.pl` is not found, rather than
  silently failing.
- **`SCAN` defaulting improved:** `SCAN` is now automatically set to
  `OFF` when `scandeps-static.pl` is not installed, and defaults to
  `ON` otherwise.
- **`git config` calls are now silent on error** (`2>/dev/null`) to
  avoid noise in environments without a global Git identity
  configured.
- **`MODULE_NAME` shell quoting fix:** The `$(pwd)` call in the
  `MODULE_NAME` derivation was corrected to `$$(pwd)` for proper shell
  expansion.
- **`DEPS` list moved** above `.DEFAULT_GOAL` for clarity;
  `.DEFAULT_GOAL` is now set to `$(TARBALL)` directly.
- **`README.md` generation is now graceful:** Both the `README.md.in`
  and POD-based paths now check for the presence of `MD_UTILS` and
  `POD2MARKDOWN` before invoking them, emitting a warning and falling
  back to a plain copy rather than failing the build.
- **`buildspec.yml` template:** Removed the unused `@EXTRA_FILES@`
  substitution.
- **`$(MODULE_PATH).in`:** Changed from an order-only prerequisite (`|
  module.pm.tmpl`) to a regular dependency on `module.pm.tmpl`, and
  the template file is now removed after use.
- **`module.pm.tmpl`:** Now attempts to locate the template via
  `File::ShareDir` and pre-sets permissions before touching the file.

### `.includes/perl.mk` — Conditional Tool Checks

- `tidy_on` and `critic_on` are now only evaluated when `perltidy` and
  `perlcritic` are present on `PATH` respectively, preventing spurious
  errors in environments where those tools are not installed.
- **`check_syntax_pl`:** Removed the `-M"$$module"` flag from the
  `perl -wc` invocation for `.pl` files (it was incorrect for
  scripts).
- **Tidiness diff fix:** Removed a duplicate `2>/dev/null` redirect
  (`2>/dev/null 2>&1` → `2>/dev/null`) in the `.pl.tdy` sentinel rule.
- `PODEXTRACT` variable declaration removed; error handling for missing `podextract` is now deferred to the `run_podextract` macro at runtime.

### `.includes/git.mk` — Unconditional Initial Commit

- The `git commit -m 'BigBang'` step is no longer conditional on
  `$$NOCOMMIT`. The commit is now always performed after `git add
  ChangeLog`.

### `.includes/release-notes.mk` — Delegated to Bootstrapper

- The `release-notes` target has been simplified. It now delegates
  entirely to `bootstrapper release-notes` rather than implementing
  release artifact generation inline. This removes the dependency on
  local `git diff` and `tar` invocations and produces
  `release-notes/release-notes-{version}.md` via the bootstrapper.

---

## Changes to `builder` (CI Script)

- **Default installer updated:** Changed from `cpm install -g
  --resolver 02packages,https://cpan.openbedrock.net/orepan2` to `cpm
  install -g --show-build-log-on-failure --verbose`.
- **`EXTRA_DEPS` updated:** Now lists `CPAN::Maker` and
  `CPAN::Maker::Bootstrapper` without pinned versions (previously
  pinned to `CPAN::Maker@1.9.1` and `Markdown::Render@2.0.4`).
- **Removed `sed -i` blank-line stripping** of `build-requires` and
  `test-requires` before concatenating them (the stripping was
  unnecessary and potentially destructive).
- **`apt-get` packages:** Removed `sed`, `libxml2-dev` from the
  installed package list.
- **`git clone` guard:** The `git clone` step is now skipped if the
  target directory already exists (`test -d $dir || git clone $REPO`),
  making re-runs of the builder script idempotent.

---

## Bug Fixes

| Location | Fix |
|---|---|
| `Makefile` | `$(pwd)` → `$$(pwd)` in `MODULE_NAME` derivation |
| `.includes/perl.mk` | Duplicate stderr redirect `2>/dev/null 2>&1` → `2>/dev/null` |
| `.includes/perl.mk` | Removed incorrect `-M"$$module"` from `perl -wc` for `.pl` files |
| `builder` | `git clone` is now idempotent |

---

## Upgrade Notes

- The `make-cpan-dist.pl` script is no longer used by the
  `Makefile`. Ensure `cpan-maker` is installed (`cpanm CPAN::Maker`).
- The `bootstrapper` binary is now **required**; the build will abort
  with an error if it is not present. Install with `cpanm
  CPAN::Maker::Bootstrapper`.
- If you use `release-notes`, the output location has changed from
  `release-{version}.diffs` / `.lst` / `.tar.gz` to
  `release-notes/release-notes-{version}.md`.
- Projects that relied on the `NOCOMMIT` environment variable to
  suppress the initial `git commit` in `make git` will need to update
  their workflows; the commit is now unconditional.
