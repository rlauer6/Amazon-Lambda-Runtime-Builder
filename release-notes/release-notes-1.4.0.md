# Amazon::Lambda::Runtime::Builder 1.4.0

**Released:** Wed Jul 8 2026

## Overview

This release introduces a significantly improved `install` command
with full template-based project scaffolding, smarter configuration
defaults derived from `FUNCTION_NAME`, a new EventBridge
`list-targets-by-rule` command, robustness improvements across
EventBridge API calls, and a broad replacement of inline Perl/JSON
parsing in Makefiles with the `dnk` utility.

---

## New Features

### Template-Based Project Scaffolding (`install` command)

The `install` command has been substantially reworked. It now accepts
an `app-name` and an optional `trigger-type` argument, generating a
complete project skeleton from templates rather than copying a single
flat handler file.

```
alr-builder install MyApp::Handler eventbridge
```

**What gets installed:**

- `Handler.pm` — main Lambda handler stub with inactive trigger-type handlers commented out
- Trigger-specific event modules under `lib/<AppPath>/Lambda/Event/`:
  - `ALB.pm`
  - `EventBridge.pm`
  - `S3.pm`
  - `SNS.pm`
  - `SQS.pm`
- Trigger-type YAML configuration files:
  - `lambda-alb.yaml`
  - `lambda-eventbridge.yaml`
  - `lambda-s3-direct.yaml`
  - `lambda-s3-sqs.yaml`
  - `lambda-sns.yaml`
- The appropriate `lambda-<trigger-type>.yaml` is copied to
  `lambda.yaml` automatically
- A `tree`-style display of installed assets is shown on completion

The `app-name` is normalized to `PascalCase` (e.g. `my-app` →
`MyApp`), and each namespace segment is validated as a legal Perl
identifier. Defaults to the `eventbridge` trigger type if none is
specified.

### New `list-targets-by-rule` Command (`alr-helper`)

A new helper command lists the targets registered for a named
EventBridge rule:

```bash
alr-helper list-targets-by-rule my-rule-name
```

---

## Improvements

### Configuration: `FUNCTION_NAME`-Derived Defaults

The `lambda-mapping.yml` and the configuration subsystem now use
template tokens so that `REPO_NAME`, `ROLE_NAME`, and `RULE_NAME`
default to values derived from `FUNCTION_NAME` rather than hardcoded
strings:

| Variable | Previous Default | New Default |
|---|---|---|
| `REPO_NAME` | `perl-lambda` | `<FUNCTION_NAME>` |
| `ROLE_NAME` | `lambda-role` | `<FUNCTION_NAME>-role` |
| `RULE_NAME` | `lambda-handler-rule` | `<FUNCTION_NAME>-rule` |

Token substitution (`@FIELD@`) is performed on the raw YAML text
before parsing, so YAML never encounters bare `@` characters and
downstream tools see concrete values immediately.

### `lambda.env` Generation: Defaults Now Written Out

Previously, mapping entries with no value in `lambda.yaml` were
silently skipped during `lambda.env` generation. They now fall back to
their (already-interpolated) mapping defaults, making `lambda.env`
self-contained. Resources such as `REPO_NAME`, `ROLE_NAME`, and
`RULE_NAME` are written with correct values rather than relying on
Makefile fallback logic.

### `_walk_mapping`: Seeded with `FUNCTION_NAME`

`_walk_mapping` now passes `FUNCTION_NAME` from the current
`lambda.env` into `_load_mapping` so that reported defaults in
`check-env-file` output match what the writer would actually produce.

### `_validate_constraints`: Stubs for All Trigger Types

Constraint validation no longer raises an error for trigger types that
have no defined constraints. Stubs are now present for `eventbridge`,
`sns`, and `s3-direct`.

### EventBridge API Robustness

All EventBridge API calls that could raise exceptions are now wrapped in `eval {}`:

- `cmd_eventbridge_put_rule_expression`
- `cmd_eventbridge_put_rule_pattern`
- `cmd_eventbridge_disable_rule`
- `cmd_eventbridge_remove_targets` — also fixes a bug where `Name` was incorrectly passed instead of `Rule`

`_eventbridge_put_rule` no longer calls `_check_response` internally
(which was producing duplicate output); callers handle the response
themselves.

### Makefile Improvements (`Makefile.mk`)

- Optionally includes a local `config.mk` (`-include config.mk`) for
  per-project overrides
- `REPO_NAME` and `ROLE_NAME` now default from `FUNCTION_NAME`
  (aligning with mapping defaults)
- `DIST_NAME` now derives from `MODULE_NAME` (`$(subst
  ::,-,$(MODULE_NAME))`) rather than the project directory name
- Improved error message when the distribution tarball is missing

### `dnk` Replaces Inline Perl/JSON Parsing in Makefiles

All occurrences of `perl -MJSON -0ne '...'` patterns in the
distributed Makefiles have been replaced with the `dnk` command-line
tool for extracting values from JSON:

- `alb.mk` — `TargetGroupArn`, `RuleArn`
- `eventbridge.mk` — `RuleArn`, default `RULE_NAME`
- `sns.mk` — `TopicArn`, `SubscriptionArn`
- `sqs.mk` — `RedrivePolicy`, `QueueUrls`, `EventSourceMappings[0].UUID`, `UUID`
- `streaming.mk` — `FunctionURL`

---

## Bug Fixes

- **`cmd_eventbridge_remove_targets`**: Fixed incorrect use of `Name`
  key (should be `Rule`) in the `RemoveTargets` API call.
- **`Helper.pm` command table**: Corrected two IAM command references
  (`attach-policies-from-profile` →
  `cmd_iam_attach_policies_from_profile`, `create-assume-policy` →
  `cmd_iam_create_assume_policy`).
- **`_wait_create_role`**: Removed a stray `Dumper` debug log
  statement that was emitting noise on every role creation poll.

---

## Dependency Changes

| Dependency | Previous | New |
|---|---|---|
| `Data::NestedKey` | 1.2.0 | 1.2.1 |

---

## New Shared Files

The following template and configuration files are now distributed
with the module and installed by `alr-builder install`:

- `share/Handler.pm.tmpl`
- `share/ALB.pm.tmpl`
- `share/EventBridge.pm.tmpl`
- `share/S3.pm.tmpl`
- `share/SNS.pm.tmpl`
- `share/SQS.pm.tmpl`
- `share/lambda-alb.yaml.tmpl`
- `share/lambda-eventbridge.yaml.tmpl`
- `share/lambda-s3-direct.yaml.tmpl`
- `share/lambda-s3-sqs.yaml.tmpl`
- `share/lambda-sns.yaml.tmpl`

The previously distributed `share/LambdaHandler.pm` has been removed
and replaced by the above templates.

---

## Upgrade Notes

- Projects that previously relied on the hardcoded defaults
  `perl-lambda` (repo), `lambda-role` (role), or `lambda-handler-rule`
  (EventBridge rule) should verify that the new
  `FUNCTION_NAME`-derived defaults are acceptable, or explicitly set
  these variables in `lambda.env` or `config.mk`.
- The `install` command now **requires** an `app-name`
  argument. Existing projects are unaffected; the command is only used
  to scaffold new projects.
- `DIST_NAME` is now derived from `MODULE_NAME` rather than `$(notdir
  $(CURDIR))`. Projects that relied on the directory name for tarball
  discovery should set `MODULE_NAME` in their `lambda.env` or
  `config.mk`.
