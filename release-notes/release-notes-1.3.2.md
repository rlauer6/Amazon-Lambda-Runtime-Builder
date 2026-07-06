# Release Notes — Amazon::Lambda::Runtime::Builder 1.3.2

**Released:** Mon Jul 6 2026  
**Author:** Rob Lauer \<rclauer@gmail.com\>

---

## Overview

Version 1.3.2 broadens trigger-type support, hardens the `install`
scaffold, adds per-trigger-type sample payloads, ships comprehensive
`alr-helper` documentation, and applies a collection of naming and
default-value fixes across the Makefiles.

---

## New Features

### Five trigger types now fully documented and supported

`TRIGGER_TYPE` now selects from five event-source patterns, each with
its own `lambda-pipeline` / `lambda-teardown` dispatch path:

| Type | Event source |
|------|-------------|
| `s3-sqs` | S3 object events via SQS queue + DLQ |
| `s3-direct` | S3 bucket notifications direct to Lambda |
| `eventbridge` | EventBridge scheduled rule |
| `sns` | SNS topic subscription |
| `alb` | Application Load Balancer listener rule |

Both `TRIGGER_TYPE` and `HANDLER_CLASS` are now explicitly documented
as **required** for every deployment.

### Per-trigger-type sample payloads

New sample payload files are shipped in `share/` and picked up
automatically by `make invoke`:

- `share/payload-alb.json`
- `share/payload-eventbridge.json`
- `share/payload-s3-direct.json`
- `share/payload-s3-sqs.json`

`PAYLOAD` is now resolved at build time via:

```makefile
PAYLOAD ?= $(firstword $(wildcard payload-$(TRIGGER_TYPE).json) \
                       $(wildcard $(FRAMEWORK_DIR)/payload-$(TRIGGER_TYPE).json) \
                       payload.json)
```

The correct payload for the configured trigger type is used
automatically with no manual setting required.

### `EXTRA_RUNTIME_PACKAGES` in the final image layer

The Dockerfile's runtime stage now accepts `EXTRA_RUNTIME_PACKAGES` as
a build argument. This allows XS modules that require shared libraries
at run time (e.g. `libssl3`) to be installed in the final layer
without bloating the builder stage. The `RUN` directive is a no-op
when the argument is unset.

### `alr-helper` fully documented

`Amazon::Lambda::Runtime::Builder::Helper` now ships complete POD
documentation covering every command grouped by AWS service:

- CloudFront, CloudWatch Logs, ECR, ELB, EventBridge, IAM, Lambda,
  Miscellaneous (`check`, `create-cpanfile`, `get-meta`), S3, STS,
  SQS, SNS

Each command is tagged **[read]**, **[write]**, or **[local]** to
indicate its safety profile. All options (`--dryrun`, `--region`,
`--tarball`, `--timeout`, `--wait`, etc.) are documented.

### New `GETTING-STARTED.md`

A new top-level `GETTING-STARTED.md` provides a concise on-ramp for
new users.

### `check-env-file` is now trigger-aware

`check-env-file` (and `generate-yaml`) scope their validation to the
active `TRIGGER_TYPE` via `lambda-mapping.yml`'s `applies_to`
field. Only the values relevant to the configured trigger type are
reported as missing, customized, or defaulted.

Required values by trigger type:

| Trigger type | Required values |
|---|---|
| All | `HANDLER_CLASS`, `TRIGGER_TYPE` |
| `s3-sqs`, `s3-direct` | `BUCKET_NAME` |
| `sns` | `TOPIC_NAME` |
| `alb` | `LISTENER_ARN` |

### Additional IAM permissions documented

A new **"Additional permissions (not verified by check)"** section
documents the permissions needed for features that
`SimulatePrincipalPolicy` does not yet cover:

- CloudWatch Logs (`logs:CreateLogGroup`, `logs:PutRetentionPolicy`, etc.)
- ALB triggers (`elasticloadbalancing:*`)
- Inline custom policies (`iam:PutRolePolicy`, `iam:DeleteRolePolicy`)
- Reserved concurrency (`lambda:PutFunctionConcurrency`)
- Full teardown (`sqs:*`, `sns:*`, `s3:*` deletion operations)

---

## Changes and Improvements

### `install` scaffold overhaul

The `install` command and its documentation have been updated to reflect the current scaffold:

- `LambdaHandler.pm` (renamed from `LambdaHandler.pm.in`) — `overwrite: never`
- `policies` — `overwrite: never`
- `Makefile.builder` — `overwrite: always` (safe to regenerate and commit)
- `project.mk` — appends ALRB integration block between marker comments; writes `project.mk.bak` backup; leaves an already-integrated file unchanged

The Dockerfile, trigger Makefiles, and platform/overlay/log-group
fragments are **not** copied into the project; they are read from the
distribution's `share/` directory at build time.

The new `--force` / `-f` option overrides the manifest `overwrite:
never` policy for any file.

### New CLI options documented

Three options previously accepted but undocumented are now listed in
the `OPTIONS` section:

- `--config-file|-c FILE` — configuration file (defaults to `lambda.env`, then `$LAMBDA_ENV`/`$LAMBDA_YAML`)
- `--profile|-p NAME` — sets `AWS_PROFILE` for `check`
- `--force|-f` — overwrite scaffold files regardless of manifest policy

### `lambda.yaml` structure expanded

The `lambda.yaml` reference now documents fields common to all trigger
types (including `log_retention`, `platform_image`, `overlay`) plus
the full set of trigger-specific `trigger:` keys for all five trigger
types.

### IAM method naming aligned

Two IAM role methods have been renamed for consistency with the
`cmd_iam_*` convention:

| Old name | New name |
|---|---|
| `cmd_attach_policies_from_profile` | `cmd_iam_attach_policies_from_profile` |
| `cmd_create_assume_policy` | `cmd_iam_create_assume_policy` |

The corresponding `alr-helper` command names
(`attach-policies-from-profile`, `create-assume-policy`) are
unchanged.

### EventBridge defaults aligned with `lambda.env`

`share/eventbridge.mk` defaults updated:

| Variable | Old default | New default |
|---|---|---|
| `SCHEDULE_EXPRESSION` | `rate(1 minute)` | `rate(1 day)` |
| `RULE_NAME` | `lambda-handler-test` | `lambda-handler-rule` |

### Removed unused `REBUILD` variable

The `REBUILD` / `REBUILD_ARG` build argument and its associated
`ifdef` block have been removed from `share/Makefile.mk`. Use
`CACHE_BUST` (which has been available since 1.3.1) to invalidate the
`requires.reinstall` layer.

### `share/MANIFEST.json` cleaned up

qThe `payload*.json` entries have been removed from `MANIFEST.json`
(they are no longer copied into the project on `install`). The files
themselves are retained in `share/` and referenced at build time via
the `PAYLOAD` resolution logic above.

### Module description updated

The one-line module description has been updated from:

> *Project scaffolding and environment checker for Perl Lambda container images*

to:

> *scaffolding, environment checker, and deployment toolchain for Perl Lambda container images*

---

## Files Changed

| File | Change |
|------|--------|
| `VERSION` | Bumped to `1.3.2` |
| `lib/Amazon/Lambda/Runtime/Builder.pm.in` | Updated POD |
| `lib/Amazon/Lambda/Runtime/Builder/Helper.pm.in` | Full POD for all `alr-helper` commands |
| `lib/Amazon/Lambda/Runtime/Builder/Role/IAM.pm.in` | Method naming alignment |
| `share/Dockerfile` | Added `EXTRA_RUNTIME_PACKAGES` to runtime stage |
| `share/Makefile.mk` | Auto-resolve `PAYLOAD` from trigger type; remove `REBUILD` variable |
| `share/eventbridge.mk` | Updated default `SCHEDULE_EXPRESSION` and `RULE_NAME` |
| `share/MANIFEST.json` | Remove `payload*.json` entries |
| `share/payload-alb.json` | **New** |
| `share/payload-eventbridge.json` | **New** |
| `share/payload-s3-direct.json` | **New** |
| `share/payload-s3-sqs.json` | **New** |
| `GETTING-STARTED.md` | **New** |
| `README.md` | Regenerated |
| `buildspec.yml` | Added new payload files to build |
| `ChangeLog` | Updated |

---

## Upgrade Notes

- If you call `cmd_attach_policies_from_profile` or
  `cmd_create_assume_policy` directly in Perl code, update the call
  sites to `cmd_iam_attach_policies_from_profile` and
  `cmd_iam_create_assume_policy` respectively. The `alr-helper` CLI
  command names are unchanged.
- The `REBUILD` Makefile variable is no longer recognised. Switch to
  `CACHE_BUST=<value>` to force reinstallation of `requires.reinstall`
  modules.
- `PAYLOAD` no longer needs to be set manually for standard trigger
  types. Remove any explicit `PAYLOAD = payload.json` override in
  `lambda.env` if you want automatic resolution to take effect.
