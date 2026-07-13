# Amazon::Lambda::Runtime::Builder 1.5.1

**Released:** Mon Jul 13 2026

## Overview

Version 1.5.1 is a focused improvement release addressing developer
experience, error handling robustness, and the policies scaffolding
workflow. The headline change is that the `policies` file installed by
`alr-builder install` is now generated dynamically based on the
selected trigger type and any extra permissions requested, rather than
copied from a static template. Colored log output, improved IAM error
messages, and telemetry for the S3 `make` pipeline round out the
release.

---

## What's New

### Dynamic `policies` File Generation

The `install` command now generates a trigger-type-appropriate `policies`
file on the fly via the new `Amazon::Lambda::Runtime::Builder::Policies`
module, rather than copying a static `share/policies` template.

- The generated file is pre-populated with the managed-policy ARNs
  relevant to the chosen trigger type.
- Additional service permissions can be requested at install time as
  positional arguments in `service:ro|full` format (e.g. `s3:ro`,
  `sns:full`). Invalid service names and access types are validated and
  rejected with a clear error.
- The static `share/policies` file has been removed; `share/policies.json`
  replaces it as the data source consumed by the new module.
- The `policies` entry has been removed from `share/MANIFEST.json` since
  the file is no longer copied from the distribution share directory.

```
# Install with S3 read-only permissions enabled from the start
alr-builder install MyApp eventbridge s3:ro
```

### Colored Log Output

`alr-builder` now emits color-coded log output by default when
`Term::ANSIColor` is available:

| Level | Color |
|---|---|
| `DEBUG` | magenta |
| `INFO` | green |
| `WARN` | yellow |
| `ERROR` | red |
| `FATAL` | bold red |
| `TRACE` | bold white |

Color can be suppressed with `--no-color`. The new `init_logger` override
in `Builder.pm` handles this by clearing the Log4perl configuration when
color is disabled, falling back to the parent class's plain logger.

### Improved IAM Error Handling in `check`

`alr-builder check` now distinguishes between a genuine IAM `403
Forbidden` response (meaning the caller lacks permission to make IAM API
calls at all) and other unexpected failures when running
`SimulatePrincipalPolicy`:

- A `403` response from the IAM API produces a clear
  `"You do not have permissions for IAM API calls!"` message.
- Other errors produce a separate message indicating the permission status
  could not be determined.
- The IAM permission log messages now correctly display the full
  `service:Action` string (e.g. `iam:PassRole`) rather than just the
  service prefix.

### S3 Pipeline Telemetry

All `make` targets in `share/s3.mk` now emit structured telemetry events
via `alr-helper report-step`, consistent with the other trigger pipelines
introduced in 1.5.0. Sentinel files are also made writable before being
updated, preventing permission errors on re-runs.

### `Amazon::S3::Lite` in S3 Handler Template

The scaffolded `S3.pm` event handler template (`share/S3.pm.tmpl`) now
uses `Amazon::S3::Lite` instead of `Amazon::S3`. The `get_obj` method and
`content` response key replace the previous `bucket->get_key` / `value`
pattern. `Amazon::S3::Lite` is a lighter dependency better suited to
Lambda container images.

---

## Bug Fixes and Hardening

### `cmd_install` Error Handling

Several `die` calls in `Role::Install` have been replaced with the
`->error` / `return $FAILURE` pattern, consistent with the rest of the
CLI framework:

- File-existence conflicts that would previously throw an uncaught
  exception now log an error and return a failure code.
- `open` failures for `project.mk` updates and template writes now follow
  the same pattern.
- Copy failures now use `get_logger->warn` instead of bare `warn`.

### Trigger Type Validation in `install`

The hardcoded list of trigger types used to validate the `--trigger-type`
argument and to mark handler registration lines in the generated
`Handler.pm` is now derived from
`Amazon::Lambda::Runtime::Builder::Policies`, ensuring the validation list
stays in sync with the supported types.

### `check-env-file` Formatting

`GETTING-STARTED.md` has been reformatted for improved readability in
terminals and editors with line-length constraints. Content is unchanged.

---

## Documentation

- **`README.md`**: The `OPTIONAL DEPENDENCIES` section has been removed.
  IAM permission checking is now always attempted when the required modules
  are available; the install command now generates the `policies` file
  automatically, so the manual note about optional modules is no longer
  needed.
- **`GETTING-STARTED.md`**: Reformatted throughout for improved
  readability; the note about installing `Amazon::API::IAM`,
  `Amazon::API::STS`, and `Amazon::Credentials` as optional dependencies
  has been removed, and the `check` command description updated to reflect
  that permission checking is built in.

---

## Upgrade Notes

### Existing Projects: `policies` File

The `policies` file installed by previous versions of `alr-builder install`
is a hand-editable static file and is **not overwritten** on upgrade
(manifest policy `overwrite: never`). Existing projects are unaffected.

For new scaffolds, the generated `policies` file replaces the old static
template. Review the generated file after running `install` to confirm the
enabled policies match your requirements.

### `REPO_NAME`, `ROLE_NAME`, `RULE_NAME` Defaults (carried forward from 1.5.0)

As noted in the 1.5.0 release, these three variables now default from
`FUNCTION_NAME` rather than fixed strings. If you are redeploying an
existing project that relies on the old defaults (`perl-lambda`,
`lambda-role`, `lambda-rule`), set the values explicitly in `lambda.yaml`
or `lambda.env` to avoid creating new-named AWS resources alongside the
existing ones.

---

## Files Changed

| File | Change |
|---|---|
| `VERSION` | Bumped to `1.5.1` |
| `lib/Amazon/Lambda/Runtime/Builder.pm.in` | Added `$LOG4PERL_CONF`, `init_logger` override; removed optional-deps note from POD |
| `lib/Amazon/Lambda/Runtime/Builder/Policies.pm.in` | **New** â policy generation module |
| `lib/Amazon/Lambda/Runtime/Builder/Role/CheckDeps.pm.in` | Trap IAM 403; clearer permission log messages |
| `lib/Amazon/Lambda/Runtime/Builder/Role/Install.pm.in` | Dynamic policy generation; extra-permission args; hardened error handling |
| `share/MANIFEST.json` | Removed static `policies` entry |
| `share/policies.json` | Renamed from `share/policies`; serves as data source for `Policies.pm` |
| `share/S3.pm.tmpl` | Switch to `Amazon::S3::Lite` |
| `share/s3.mk` | Add telemetry; make sentinels writable before update |
| `buildspec.yml` | Add `Policies.pm.in` and `share/policies.json` to build |
| `GETTING-STARTED.md` | Reformatted; optional-deps section removed |
| `README.md` | `OPTIONAL DEPENDENCIES` section removed; handler runtime permissions note updated |