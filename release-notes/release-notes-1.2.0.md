# Amazon::Lambda::Runtime::Builder 1.2.0 Release Notes

## Overview

1.2.0 introduces `lambda.yaml` as an optional, minimal source of truth for
Lambda configuration. This is a continuation of the ALRB roadmap
toward a version that no longer relies on `make`.

Existing projects that hand-manage `lambda.env` are fully supported
and unaffected; the new workflow is opt-in via `alr-builder
generate-yaml`. Two new CLI commands, a canonical configuration schema
(`lambda-mapping.yml`), a new `Role::Config` module, IAM profile-based
policy attachment, and `sqs.mk` infrastructure targets round out the
release.

---

## New Features

### lambda.yaml / lambda-mapping.yml configuration workflow

`lambda-mapping.yml` (installed as a shared file) is now the canonical schema
for all Lambda configuration fields. It defines, for each field: the
corresponding `lambda.env` variable name, an optional default, whether the
field is required, whether it should be omitted when false, and which trigger
types it applies to. Version 1 covers 19 fields for the `s3-sqs` trigger type.

`lambda.yaml` is an optional, minimal project-level file containing only the
values that differ from `lambda-mapping.yml` defaults (plus any required field
with no default). When `lambda.yaml` is present, `alr-builder` regenerates
`lambda.env` automatically on `init()` - whenever `lambda.yaml` is newer than
`lambda.env`, or when the mapping schema version has advanced since the last
generation. A generated `lambda.env` begins with a header noting it is
generated; hand edits are overwritten on the next regeneration.

Projects without `lambda.yaml` continue to use `lambda.env` directly, with
`alr-builder check-env-file` available for validation.

**Note:** `YAML::Tiny` does not parse flow-style arrays (`[s3-sqs]`). All
`applies_to:` entries in `lambda-mapping.yml` use YAML block style.

### alr-builder check-env-file

Validates the project's configuration against `lambda-mapping.yml`
requirements. Reads `lambda.env` if present (an absent `lambda.env` is treated
as "nothing configured yet"). Reports three groups:

- **MISSING (required)** - required fields with no default that are not set.
  `image.handler` (`HANDLER_CLASS`) is required for every trigger type;
  `trigger.bucket` (`BUCKET_NAME`) is additionally required for `s3-sqs`.
- **Customized** - values present in `lambda.env` that differ from their
  `lambda-mapping.yml` default, or have no default at all.
- **Using defaults** - values not set in `lambda.env` and the default that
  applies in their place.

Exits non-zero if any required values are missing.

### alr-builder generate-yaml

Migrates an existing hand-written `lambda.env` to `lambda.yaml`. Requires
`lambda.env` to exist and `lambda.yaml` to not yet exist - this is a one-time
migration step. Runs the same validation as `check-env-file` first; if any
required values are missing, no `lambda.yaml` is written. Otherwise writes a
minimal `lambda.yaml` containing only values that differ from their defaults
(plus required fields with no default such as `trigger.bucket`).

### Role::Config (new module)

Implements the configuration machinery shared by `check-env-file`,
`generate-yaml`, and `init()`:

- `_load_mapping` - loads and caches `lambda-mapping.yml` via `File::ShareDir`
- `_yaml_get` / `_yaml_set` - dotted-path accessors for nested YAML structures
- `_walk_mapping` - iterates the mapping filtered by trigger type, driving both
  validation and generation
- `_read_lambda_env` - parses `lambda.env` into a hash
- `_generate_lambda_env` - writes `lambda.env` from `lambda.yaml` + mapping defaults
- `_lambda_env_needs_regen` - compares `lambda.yaml` mtime and mapping version
  against the generation header in `lambda.env`
- `cmd_check` - registered as `check-env-file`
- `cmd_generate_yaml` - registered as `generate-yaml`

`init()` calls `_generate_lambda_env` wrapped in `eval{}` and never dies on
`lambda.yaml` problems.

### Role::IAM - attach-policies-from-profile

`cmd_attach_policies_from_profile` reads `profiles.yml` (installed as a shared
file) and attaches the named profile's policies to the Lambda execution role.
Operation is additive and idempotent. Registered as `attach-policies-from-profile`
in `Helper.pm`.

### Makefile.mk - ROLE_PROFILE-conditional policy attachment

`lambda-policies` and `update-policies` now branch on `ROLE_PROFILE`:

- If `ROLE_PROFILE` is set: uses `alr-helper attach-policies-from-profile`
  with `lambda.env` as the prerequisite.
- If unset: uses `alr-helper attach-policy` with the `policies` file as
  before.

`update-policies` description updated to reflect both modes.

### Makefile.mk - DIST_NAME resolution fix

`DIST_NAME` is now resolved via `$(notdir $(CURDIR))` (defaulting to the
project directory name) rather than by extracting the `name` field from
`META.json` inside the tarball. `DIST_TARBALL` is subsequently resolved as
`$(DIST_NAME)-*.tar.gz`, eliminating the prior silent failure when `META.json`
was absent. `DIST_NAME` remains overridable via environment or command line.

### sqs.mk - lambda-configuration target

New `lambda-configuration` target (with sentinel) calls
`alr-helper update-function-configuration` to apply `MEMORY` and `TIMEOUT`
from `lambda.env`. Default: `MEMORY ?= 128`. Added as a prerequisite of
`lambda-sqs-pipeline`.

### sqs.mk - lambda-sqs-response-types target

New `lambda-sqs-response-types` target (with sentinel) manages the SQS event
source mapping's `FunctionResponseTypes`. Controlled by
`PARTIAL_BATCH_RESPONSE ?= false`; when `true`, sets
`response-types:@ReportBatchItemFailures`, otherwise clears the list. Added as
a prerequisite of `lambda-sqs-pipeline`.

### sqs.mk - lambda-sqs-pipeline prereqs expanded

`lambda-sqs-pipeline` now requires `lambda-configuration` and
`lambda-sqs-response-types` in addition to the existing `lambda-sqs-trigger`,
`lambda-concurrency`, and `lambda-s3-sqs-trigger`. A single
`make lambda-sqs-pipeline` now reconciles the full s3-sqs infrastructure
including memory, timeout, and partial batch response settings.

---

## Changes

- `Role::CheckDeps`: removed redundant `local $ENV{AWS_PROFILE}` (now set
  once in `init()`).
- `Builder.pm.in`: `init()` sets `$ENV{AWS_PROFILE}` from `--profile` before
  any AWS calls; `check-dependencies` command renamed to `check`; `check-env-file`
  and `generate-yaml` registered; POD updated throughout (new CONFIGURATION
  section, COMMANDS updated, WORKFLOW updated, MAKEFILE TARGETS updated).
- `buildspec.yml`: `lambda-mapping.yml` added to shared file list.

---

## Upgrade Notes

After installing 1.2.0, the shared files (`share/Makefile.mk`, `share/sqs.mk`,
`share/lambda-mapping.yml`, `share/profiles.yml`) must be refreshed in the
`File::ShareDir` install location. A stale install will silently continue
running 1.1.1 behavior, including the unfixed `DIST_TARBALL` resolution. Run:

    cpanm Amazon::Lambda::Runtime::Builder

and verify the installed path contains the new files before testing any 1.2.0
behavior.

Existing projects using hand-written `lambda.env` require no changes. To adopt
the `lambda.yaml` workflow, run `alr-builder generate-yaml` once from the
project root.
