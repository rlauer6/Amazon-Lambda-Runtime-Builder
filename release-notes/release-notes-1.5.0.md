# Amazon::Lambda::Runtime::Builder 1.5.0

**Released:** 2026-07-10

## Overview

Version 1.5.0 introduces two major improvements: high-level CLI
commands that replace direct `make` invocations for build and
teardown, and a live structured progress display that replaces raw
`docker`/`aws` output scrolling past during pipeline runs. This
release also adds a telemetry system that pipes step-level status from
`make` back to the CLI for rendering, fixes a version regex in
configuration regeneration, and changes several resource name defaults
to derive from `FUNCTION_NAME` rather than fixed strings.

---

## New Features

### `alr-builder build-lambda` and `alr-builder teardown-lambda`

Two new top-level commands replace `make lambda-pipeline` and `make
lambda-teardown` as the primary interface for deploying and
deprovisioning a Lambda function:

```
alr-builder build-lambda
alr-builder teardown-lambda
```

Both commands fork a child process that runs `make` against
`Makefile.builder`, redirect all `docker`/`aws` output to a
timestamped log file under `.cache/<function-name>/build-<stamp>.log`,
and expose a `build.log` symlink pointing to the most recent log. If
the pipeline fails, the last 40 lines of the log are printed to stderr
automatically.

The full `make` pipeline and its sentinel-based idempotency are
unchanged — the new commands are a rendered front-end to the same
machinery.

### Structured progress display

Instead of raw tool output, `build-lambda` and `teardown-lambda` now
print a live, hierarchical progress stream as each pipeline step
starts and completes:

```
• image...
    • docker-build...
    ✓ docker-build (11.4s)
    ✓ docker-inspect
✓ image (12.2s)
• lambda-function...
    ✓ create (1.1s)
✓ lambda-function (1.1s)
• eventbridge-trigger...
    ✓ rule (0.6s)
✓ eventbridge-trigger (0.6s)
build-lambda complete in 14.7s
```

- Each pipeline stage and sub-step is timed individually and shown with elapsed time.
- Status symbols adapt to UTF-8 terminal capability (`✓`/`✗`/`–` vs `[ok]`/`[XX]`/`[--]`).
- Color output is on by default and can be toggled with `--color`/`--no-color`.

### `--color`/`--no-color` option

The `alr-builder` CLI now accepts `--color` (default) and `--no-color` to control ANSI color output during `build-lambda` and `teardown-lambda`. Color is applied per status: green for success, red for failure, yellow for not-found, bold white for in-progress. Requires `Term::ANSIColor` (gracefully degraded when unavailable).

### Step telemetry (`report-step` command)

A new internal telemetry system allows `make` recipes to report step
status back to the parent `alr-builder` process via a pipe file
descriptor (`ALR_STATUS_FD`). This is implemented as:

- **`alr-builder report-step <target> <step> <status>`** — writes a status event to the pipe (or stdout when run outside `alr-builder`).
- **`alr-helper report-step <target> <step> <status>`** — same command available in `alr-helper` for use within `make` recipes via `--report-step <target>`.
- **`--report-step|-R`** option added to `alr-helper` — passes the make target through to `_handle_return`, so individual AWS API calls report their own status (including distinguishing `not-found` from `fail`) back through the telemetry channel.

All `Makefile.mk` and `eventbridge.mk` recipes have been updated to
emit start/done events for every step.

### `_handle_return` in `alr-helper`

A new `_handle_return` method in
`Amazon::Lambda::Runtime::Builder::Helper` routes every API response
through the telemetry channel when `--report-step` is set. It maps API
error codes and response types to telemetry statuses:

- HTTP 404 → `not-found`
- `NoSuchEntity` IAM errors → `not-found`
- `__type` containing `notfound` → `not-found`
- Bless exception objects → inspected for error code
- All other failures → `fail`
- Success → `ok`

`_handle_response` now routes through `_handle_return` so all existing
AWS API wrappers gain telemetry automatically.

### Build log rotation

Build logs under `.cache/<function-name>/` are automatically pruned
after 7 days. Pruning runs at the start of each `build-lambda` or
`teardown-lambda` invocation.

### `config.mk` documented

`config.mk` — an optional `make` fragment loaded via `-include
config.mk` before `lambda.env` — is now documented in both the POD and
`GETTING-STARTED.md`. It is the intended location for machine-local or
shell-local overrides (`AWS_PROFILE`, `AWS_ACCOUNT`, `RESOLVER`, etc.)
that should not live in `lambda.env`. `alr-builder install` does not
create one; `CPAN::Maker::Bootstrapper` does.

---

## Changes

### `alr-builder install` now accepts an app name and generates structured scaffolding

`install` now takes a required application name argument and generates
a namespace-correct handler hierarchy:

```
alr-builder install HelloLambda --install-dir hello-lambda
```

Generated files follow the `App::Name::Lambda::Handler` module naming
convention with per-trigger event modules under
`lib/<App>/Lambda/Event/`. The `lambda.yaml` is pre-populated with
`image.handler` and `trigger.type`. The default trigger type is
`eventbridge` when none is specified.

### Default resource names now derive from `FUNCTION_NAME`

**Breaking change for existing projects without explicit overrides.**
As of 1.5.0:

| Variable | Old default | New default |
|---|---|---|
| `REPO_NAME` | `perl-lambda` | `$(FUNCTION_NAME)` |
| `ROLE_NAME` | `lambda-role` | `$(FUNCTION_NAME)-role` |
| `RULE_NAME` | `lambda-handler-rule` | `$(FUNCTION_NAME)-rule` |

Existing projects that rely on the old fixed defaults and do not set
these variables explicitly will have the pipeline attempt to create
new-named resources rather than update existing ones on next
deploy. Set the variables explicitly in `lambda.env` or `lambda.yaml`
to preserve existing resource names.

### `NOCACHE` renamed to `NO_CACHE`

The `make` variable for bypassing Docker's layer cache has been
renamed from `NOCACHE` to `NO_CACHE` for consistency. Update any
scripts or CI configuration that set `NOCACHE=--no-cache` to use
`NO_CACHE=--no-cache`.

### ECR login moved to `alr-helper`

`share/ecr-login.mk` has been removed. ECR authentication is now
handled directly by `alr-helper get-login-password` within the
`deploy` recipe in `Makefile.mk`. This eliminates the inline Perl
one-liner that called `Amazon::API::ECR` directly and routes login
through the same telemetry channel as other steps.

### `_check_response` renamed to `_handle_response` in `Role::Events`

All `cmd_eventbridge_*` methods in
`Amazon::Lambda::Runtime::Builder::Role::Events` that previously
called `_check_response` now call `_handle_response`. The old name is
retained as an alias via `goto`. `cmd_eventbridge_disable_rule` and
`cmd_eventbridge_enable_rule` now route early-exit failures through
`_handle_return` for telemetry.

### Version regex fix in `_lambda_env_needs_regen`

The regex matching the mapping version in the `lambda.env` header was
broadened from `/mapping \s v(\S+)/` to `/mapping \s v([0-9.]+)/` to
avoid matching non-version trailing content. A diagnostic message is
now printed to stderr when no version line is found.

### `Makefile.mk` recipe hardening

All sentinel-producing recipes in `Makefile.mk` and `eventbridge.mk`
now emit `report-step` start/done events. Additional fixes:

- Docker `build` stderr is now redirected to stdout (`2>&1`) within
  the recipe so build output is captured in the log file.
- The `lambda-function` recipe no longer lacks its leading `$(NO_ECHO)` on the first line.
- The `ATTACH_POLICIES_CMD` now passes `--report-step $@` for telemetry.

---

## Bug Fixes

- `_lambda_env_needs_regen`: fixed regex to match only numeric version
  strings, preventing spurious regeneration when the header contained
  unexpected characters after the version token.
- `eventbridge.mk`: fixed unbalanced parenthesis in
  `lambda-eventbridge-permission` recipe (`SOURCE_ARN` assignment was
  missing closing `)` on the `dnk get RuleArn` call).
- `eventbridge.mk` `_lambda-eventbridge-teardown`: `alr-helper
  report-step $@ done ok` was placed after the recipe's last line
  without a tab, causing it to be treated as a new target rather than
  a recipe line. Now correctly placed within the recipe.

---

## Documentation

- `GETTING-STARTED.md` has been substantially revised to reflect the
  new `alr-builder build-lambda` / `teardown-lambda` commands
  throughout the walkthrough (Parts I and II).
- Section 4 (Your first Lambda) updated with new scaffold layout,
  handler file paths, and `lambda.yaml` pre-population behaviour.
- Section 5 (What just happened) updated to describe log capture and
  the structured progress display.
- Section 7 (Configuration) adds `config.mk` documentation.
- Section 14 (Reference) footnote added for the `REPO_NAME`/`ROLE_NAME`/`RULE_NAME` default change.
- Appendix B updated: `CPAN::Maker::Bootstrapper` invocation example
  corrected to `bootstrapper -I . -i . MyApp`.
- POD for `Makefile.builder` updated to clarify the two ways to invoke it (direct or as your project `Makefile`) and the relationship between `Makefile.builder` and `project.mk`.
- Workflow section (POD) updated to reflect that `install` generates
  the handler skeleton and pre-populates `lambda.yaml`, reducing
  manual configuration steps.

---

## Upgrade Notes

1. **Resource name defaults changed.** If you have deployed functions
   with `REPO_NAME=perl-lambda`, `ROLE_NAME=lambda-role`, or
   `RULE_NAME=lambda-handler-rule` (the old defaults) and do not set
   those variables explicitly, the next `build-lambda` will target
   differently-named AWS resources. Add explicit values to
   `lambda.env` or `lambda.yaml` before upgrading if you need to
   manage existing resources.

2. **`NOCACHE` → `NO_CACHE`.** Any Makefile, script, or CI step that
   sets `NOCACHE` must be updated to `NO_CACHE`.

3. **`ecr-login.mk` removed.** If your project's `Makefile.builder` or
   any custom makefiles explicitly include `ecr-login.mk`, remove
   those includes. The file no longer exists in the distribution.

4. **`build.log` symlink.** `alr-builder build-lambda` and
   `teardown-lambda` create or replace a `build.log` symlink in the
   project directory pointing to the current run's log file. Ensure
   your `.gitignore` excludes `build.log` and `.cache/`.
