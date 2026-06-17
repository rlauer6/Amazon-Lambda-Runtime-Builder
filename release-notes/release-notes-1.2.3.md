# Amazon::Lambda::Runtime::Builder 1.2.3 Release Notes

## Overview

1.2.3 is a hardening and convenience release. It introduces `lambda-pipeline`
as the canonical single-target provisioning command (dispatching on
`TRIGGER_TYPE`), adds `update-lambda-configuration` for pushing configuration
changes without a full rebuild, moves `lambda-configuration` to `Makefile.mk`
so it is available to all trigger types, adds `wait-event-source-mapping-enabled`
to eliminate a race condition in `lambda-sqs-pipeline`, adds cross-field
configuration validation to `check-env-file`, and fixes several bugs in
teardown recipes, `put-lifecycle-policy`, and `cmd_iam_detach_all_policies`.

---

## New Features

### lambda-pipeline

`lambda-pipeline` in `Makefile.mk` dispatches to the correct pipeline target
based on `$(TRIGGER_TYPE)` from `lambda.env`:

```makefile
make lambda-pipeline    # provisions full infrastructure for s3-sqs or eventbridge
```

Fails at parse time with a clear error if `TRIGGER_TYPE` is unset or
unrecognized. Delegated from `builder.mk`. This is now the recommended
first-deploy target - `lambda-function` remains available as a lower-level
primitive.

### update-lambda-configuration

`update-lambda-configuration` removes the `lambda-configuration` sentinel and
rebuilds it, forcing `UpdateFunctionConfiguration` to run against the current
`lambda.env` values without triggering a full image rebuild or pipeline
re-run. Delegated from `builder.mk`.

```makefile
make update-lambda-configuration
```

### lambda-configuration moved to Makefile.mk

`$(CACHE_DIR)/lambda-configuration` and the `lambda-configuration` phony
target moved from `sqs.mk` to `Makefile.mk`. This makes configuration updates
available to all trigger types - previously only `s3-sqs` deployments had
access to `make lambda-configuration`.

### wait-event-source-mapping-enabled

New `alr-helper wait-event-source-mapping-enabled <uuid>` command polls until
the event source mapping transitions out of `Creating` state to `Enabled`.
Eliminates the 400 "Cannot update the event source mapping because it is in
use" error that occurred when `lambda-sqs-response-types` ran immediately
after `create-event-source-mappings`. Implemented via
`_lambda_wait_eventsource_mapping_enabled` in `Role::Lambda`.

### _validate_constraints in Role::Config

New `_validate_constraints` method called from `cmd_check` after
`_walk_mapping`. Currently enforces one cross-field constraint for `s3-sqs`:

- `VISIBILITY_TIMEOUT` must be at least 6× `TIMEOUT` - AWS enforces
  `VISIBILITY_TIMEOUT >= TIMEOUT` at the API level, and the recommended
  minimum is 6× to allow retries within the visibility window.

Returns a list of warning strings printed by `cmd_check`. Designed for easy
extension with additional constraints in future releases.

---

## Bug Fixes

### put-lifecycle-policy - rules not rule

`cmd_ecr_put_lifecycle_policy` constructed the lifecycle policy JSON with
`rule => [...]` - AWS requires `rules => [...]` (plural). This caused a 400
`InvalidParameterException` on every first deploy. Fixed.

### cmd_iam_detach_all_policies - wrong private method name

`cmd_iam_detach_all_policies` called `$self->_detach_policy(...)` which does
not exist. Corrected to `$self->_detach_role_policy(...)`.

### lambda-sqs-teardown - resilient recipe and UUID lookup

`_lambda-sqs-teardown` now:
- Looks up the event source mapping UUID via `list-event-source-mappings`
  before calling `delete-event-source-mappings` (which requires a UUID, not
  a function name)
- Removes the spurious `$(QUEUE_NAME)` argument from `remove-bucket-notification`
- Adds `|| true` to every `alr-helper` call so teardown continues past
  individual failures
- Separates the `$(MAKE) clean` step as a target dependency rather than an
  inline shell call, fixing incorrect execution under `make -n`

### lambda-eventbridge-teardown - resilient recipe

Same `|| true` hardening and `$(MAKE) clean` separation applied to
`_lambda-eventbridge-teardown`. `delete-eventbridge-rule` also hardened with
`|| true`.

### Makefile.mk - strip trailing whitespace from key variables

`REPO_NAME`, `FUNCTION_NAME`, `ROLE_NAME`, and `TRIGGER_TYPE` are now passed
through `$(strip ...)` after `-include lambda.env`. Trailing whitespace in
`lambda.env` values caused subtle failures - Docker image tag splits, empty
function names, and incorrect `TRIGGER_TYPE` dispatch.

### Role::S3 - remove_bucket_notification error handling

`cmd_s3_remove_bucket_notification_configuration` now wraps the S3 call in
`eval{}` and delegates to `_handle_response` for consistent error handling and
exit code propagation.

### Role::SQS - _sqs_get_queue_attributes eval removed

`_sqs_get_queue_attributes` no longer wraps the SQS call in `eval{}`.
Callers that need error isolation are responsible for their own `eval{}`,
preventing double-wrapping that masked errors.

---

## Upgrade Notes

After installing 1.2.3, refresh shared files in the `File::ShareDir` install
location:

    cpanm Amazon::Lambda::Runtime::Builder

The `lambda-configuration` sentinel has moved from `sqs.mk` to `Makefile.mk`.
If you have an existing `.cache/lambda-configuration` sentinel from a previous
`s3-sqs` deployment it remains valid - no action required. Projects using
other trigger types can now use `make lambda-configuration` and
`make update-lambda-configuration` for the first time.
