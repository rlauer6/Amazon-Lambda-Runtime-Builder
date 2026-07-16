# Release Notes — Amazon::Lambda::Runtime::Builder 1.5.2

**Released:** Thu Jul 16 2026

---

## Overview

Version 1.5.2 removes the `ROLE_PROFILE` / `profiles.yml` mechanism in
favour of the simpler `policies` file workflow, extends ALB
listener-rule matching to support host-header conditions alongside
path conditions, and adds `alr-helper` telemetry instrumentation
across all build Makefiles.

---

## Breaking Changes

### `ROLE_PROFILE` and `profiles.yml` removed

The `ROLE_PROFILE` environment variable and the `profiles.yml` bundled
policy-profile lookup have been removed. Managed policies must now be
listed explicitly in the `policies` file (`POLICIES_FILE`).

**Migration:** If you were using `ROLE_PROFILE`, copy the
corresponding policy ARNs from `profiles.yml` into your project's
`policies` file and remove the `ROLE_PROFILE` setting from
`lambda.env` / `lambda.yaml`.

The `role.profile` key has also been removed from
`lambda-mapping.yml`; any `lambda.yaml` that sets `role.profile`
should be updated.

---

## New Features

### ALB host-header matching (`ALB_HOST`)

ALB listener rules can now match on a `Host` header in addition to (or
instead of) a path pattern. The two conditions are combined with AND
when both are set.

```makefile
# Match requests to sandbox.example.com on any path
make ALB_HOST=sandbox.example.com lambda-alb-pipeline

# Match a specific path on a specific host
make ALB_HOST=sandbox.example.com ALB_PATH='^/api' lambda-alb-pipeline
```

- New variable: `ALB_HOST` (default: empty — host condition omitted)
- `ALB_CONDITIONS` is now derived from whichever of `ALB_PATH` and
  `ALB_HOST` are set, and is passed uniformly to
  `get-alb-listener-rule`, `create-alb-listener-rule`, and
  `modify-alb-listener-rule`.
- The listener-rule value stamp (`alb-listener-rule.value`) now tracks
  both conditions, so the rule is invalidated and rebuilt whenever
  either changes.

### `cmd_elbv2_get_alb_listener_rule` — host and regex matching

`get-alb-listener-rule` now accepts `path:REGEX` and `host:HOSTNAME`
key-value arguments (replacing the positional `path` argument) and
matches against `PathPatternConfig.RegexValues` and
`HostHeaderConfig.Values` respectively.

```
alr-helper get-alb-listener-rule <listener-arn> path:^/api host:example.com
```

### `cmd_elbv2_create_alb_listener_rule` — optional host condition

`create-alb-listener-rule` and `modify-alb-listener-rule` now accept
an optional `host:HOSTNAME` argument. When supplied, a `host-header`
condition is added to the listener rule alongside the path-pattern
condition.

---

## Improvements

### Telemetry via `alr-helper --report-step` — all Makefiles

Every significant make step across `alb.mk`, `ecr-create-repo.mk`,
`log-group.mk`, `overlay.mk`, `platform.mk`, `sns.mk`, `sqs.mk`, and
`streaming.mk` now emits structured start/done telemetry through
`alr-helper report-step`. This feeds the live progress display
rendered by `alr-builder build-lambda` / `teardown-lambda`.

Previously only a subset of steps were instrumented; this release
achieves consistent coverage across all trigger types and image-layer
pipelines.

### Documentation updates

- **`GETTING-STARTED.md`** — All references to `ROLE_PROFILE` and
  profiles have been removed. Section 3 (*Before you begin*) now
  documents the requirement for standard Unix shell tools (`bash`,
  `sed`, `chmod`, `cp`, `rm`) and clarifies that Windows is not
  supported (WSL works). The managed-policies section (§11.3) now
  describes only the `policies` file. References to `alr-builder
  build-lambda` / `teardown` have been added alongside raw `make`
  invocations in the day-two operations section.
- **`README.md`** / **`Builder.pm`** POD — Policy documentation
  updated to describe only the `policies` file workflow; profiles
  removed. An example `custom-policies.json` document has been
  added. Formatting and line-wrapping improvements throughout.

---

## Bug Fixes

- `_lambda-alb-teardown`: added a guard so that reading
  `alb-listener-rule` is skipped when the sentinel file does not
  exist, preventing a spurious error on first teardown.
- `overlay.mk`: added Makefile mode comment; `NOCACHE` variable
  reference corrected (`NOCACHE` rather than `NO_CACHE`) to match the
  rest of the build system.
- `sns.mk` (`_lambda-sns-teardown`): stray `alr-helper
  delete-function` / `delete-role` / `delete-repo` lines that
  duplicated teardown logic already handled by the per-trigger
  teardown have been removed.

---

## Files Changed

| File | Change |
|---|---|
| `VERSION` | Bumped to `1.5.2` |
| `buildspec.yml` | Removed `profiles.yml` from extra-files |
| `share/lambda-mapping.yml` | Removed `role.profile` / `ROLE_PROFILE` mapping entry |
| `share/Makefile.mk` | Removed `ROLE_PROFILE` conditional; `ATTACH_POLICIES_CMD` now always uses `policies` file |
| `share/alb.mk` | Added `ALB_HOST`, `ALB_CONDITIONS`; full telemetry instrumentation |
| `share/ecr-create-repo.mk` | Full telemetry instrumentation |
| `share/log-group.mk` | Full telemetry instrumentation |
| `share/overlay.mk` | Full telemetry instrumentation; mode comment added |
| `share/platform.mk` | Full telemetry instrumentation |
| `share/sns.mk` | Full telemetry instrumentation; teardown cleanup |
| `share/sqs.mk` | Full telemetry instrumentation |
| `share/streaming.mk` | Full telemetry instrumentation |
| `lib/…/Builder.pm.in` | POD: profiles removed; custom-policies example added |
| `lib/…/Role/ELBv2.pm.in` | Host-header matching in `get` and `create`/`modify` listener-rule commands |
| `GETTING-STARTED.md` | Profiles removed; tooling prereqs expanded; formatting |
| `README.md` | Regenerated |
