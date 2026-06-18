# Amazon::Lambda::Runtime::Builder 1.2.5 Release Notes

## Overview

1.2.5 adds the `s3-direct` trigger type (Lambda triggered directly by S3
without SQS), introduces `--config-file` / `LAMBDA_ENV` / `LAMBDA_YAML`
for multi-Lambda projects from a single directory, namespaces the sentinel
cache by `FUNCTION_NAME` to prevent clobbering, hardens `_wait_function_active`
to check `LastUpdateStatus` in addition to `State`, and adds wait calls
around all Lambda mutation operations.

This release was validated end-to-end against three trigger types in a single
project: `s3-sqs` (`orepan2-s3-handler`), `eventbridge`
(`OrePAN2::S3::Monitor`), and `s3-direct` (`orepan2-s3-direct`) - the latter
two sharing the same ECR image.

---

## New Features

### s3-direct trigger type

`lambda-mapping.yml` version `1.3` adds `s3-direct` to `trigger_types`.
Three existing fields gain `s3-direct` in their `applies_to` lists:
`trigger.bucket` (`BUCKET_NAME`, required), `trigger.prefix` (`KEY_PREFIX`,
optional), and `trigger.event` (`S3_EVENT`, default `s3:ObjectCreated:*`).

`s3.mk` is rewritten with full sentinel hardening and a complete pipeline:

- `$(CACHE_DIR)/s3-bucket` - locates or creates the trigger bucket.
  `CREATE_BUCKET ?= false`: if the bucket does not exist and `CREATE_BUCKET`
  is not `true`, fails with a clear actionable error. Explicit bucket creation
  is a conscious act - typos in `BUCKET_NAME` will not silently create
  unwanted buckets.
- `$(CACHE_DIR)/lambda-s3-permission` - grants S3 permission to invoke the
  Lambda function; idempotent.
- `$(CACHE_DIR)/lambda-s3-trigger` - calls `put-bucket-notification` with
  `lambda:$(FUNCTION_NAME)` as the target. `KEY_PREFIX` is optional; if
  unset, no filter is applied and all `S3_EVENT` events trigger the function.
- `lambda-s3-pipeline` - top-level `.PHONY` target provisioning the full
  s3-direct infrastructure.
- `lambda-s3-teardown` / `_lambda-s3-teardown` - deprovisions in order:
  remove bucket notification, remove Lambda permission, delete function,
  detach policies, delete role, delete repo, `clean`.

`lambda-pipeline` and `lambda-teardown` in `Makefile.mk` dispatch to
`lambda-s3-pipeline` / `lambda-s3-teardown` when `TRIGGER_TYPE=s3-direct`.

`builder.mk` gains `lambda-s3-pipeline` and `lambda-s3-teardown` delegations.

### --config-file / LAMBDA_ENV / LAMBDA_YAML

Both `alr-builder` and `alr-helper` now accept `--config-file|-c` to specify
an alternate `.env` or `.yaml` configuration file. Resolution order:

1. `--config-file` CLI option
2. `$LAMBDA_ENV` environment variable
3. `$LAMBDA_YAML` environment variable
4. `lambda.env` (default)

`Role::Config` gains `_env_file` and `_yaml_file` private methods that derive
the paired filename from the configured `config_file` by extension - passing
`s3-direct.env` automatically derives `s3-direct.yaml` as the yaml counterpart
and vice versa. All hardcoded `'lambda.env'` and `'lambda.yaml'` strings in
`_lambda_env_needs_regen`, `_generate_lambda_env`, `cmd_generate_yaml`, and
`_read_lambda_env` are replaced with calls to `_env_file` / `_yaml_file`.

`Helper.pm` gains `default_options => { wait => 60 }` - the wait timeout
defaults to 60 seconds across all `alr-helper` commands.

### CACHE_DIR namespaced by FUNCTION_NAME

```makefile
CACHE_DIR := $(BUILDER_HOME)/.cache/$(FUNCTION_NAME)
```

Sentinel files are now stored under `.cache/$(FUNCTION_NAME)/` rather than
`.cache/`. This allows multiple Lambdas to be provisioned from the same
project directory without clobbering each other's sentinels:

```bash
make lambda-pipeline                           # .cache/orepan2-s3-handler/
make lambda-pipeline LAMBDA_ENV=s3-direct.env  # .cache/orepan2-s3-direct/
make lambda-clean                              # cleans orepan2-s3-handler only
make lambda-clean LAMBDA_ENV=s3-direct.env     # cleans orepan2-s3-direct only
```

`BUILDER_HOME` is the project root, resolved via `$(CURDIR)`.

Existing projects with sentinels at `.cache/` will need to either reprovision
(`make lambda-clean && make lambda-pipeline`) or manually move sentinels to
`.cache/$(FUNCTION_NAME)/`.

### CLEANFILES additions

`$(CACHE_DIR)/lambda-configuration` and `$(CACHE_DIR)/lambda-sqs-response-types`
added to `CLEANFILES` - both were missing from the list and not cleaned by
`make lambda-clean`.

---

## Changes

### _wait_function_active - checks LastUpdateStatus

`_wait_function_active` now checks both `State` and `LastUpdateStatus`:

```perl
last if $state eq 'Active' && $last_update_status ne 'InProgress';
```

Previously only `State eq 'Active'` was checked. A function can be `Active`
while an update is still `InProgress`, causing 409 conflicts on subsequent
`UpdateFunctionConfiguration` calls.

### Role::Lambda - waits surround all mutation calls

`cmd_lambda_update_function_code`, `cmd_lambda_update_function_configuration`,
`cmd_lambda_put_function_concurrency`, and `cmd_lambda_invoke_function` all
now call `_wait_function_active` before and after the mutation. This prevents
409 "update in progress" errors when multiple operations are chained in a
pipeline.

`cmd_lambda_create_function` moves `_wait_function_active` inside the `eval{}`
block so the wait runs before the sentinel is written, guaranteeing the
function is `Active` and `LastUpdateStatus` is not `InProgress` before
`lambda-configuration` can proceed.

### Role::Lambda - _handle_response refactoring

`cmd_lambda_get_function_configuration`, `cmd_lambda_get_function`,
`cmd_lambda_get_policy`, and `cmd_lambda_list_event_source_mappings` all
refactored to delegate error handling to `_handle_response`, removing
duplicated inline error-handling code.

`_lambda_get_function` - `eval{}` wrapper removed; callers handle exceptions.

### Role::S3 - list-buckets accepts optional bucket name

`cmd_s3_list_buckets` now accepts an optional bucket name argument. When
provided, returns just the bucket name if it exists in the account, or
nothing if it does not. Used by the `s3-bucket` sentinel to check existence
without parsing JSON in the Makefile recipe.

`cmd_s3_get_bucket_notification_configuration` refactored to use
`_handle_response`.

### Role::SQS - set-queue-bucket-policy exit code

`cmd_sqs_set_queue_bucket_policy` now delegates to `_handle_response`,
correctly propagating non-zero exit codes on failure.

### sqs.mk - wait-eventsource-mapping-enabled renamed

`wait-event-source-mapping-enabled` renamed to `wait-eventsource-mapping-enabled`
(dropping the hyphen between `event` and `source`) for consistency with the
internal method name `_wait_eventsource_mapping_enabled`. Both `lambda-sqs-trigger`
and `lambda-sqs-response-types` updated.

`lambda-sqs-trigger` - UUID extracted from `create-event-source-mappings`
response and passed directly to `wait-eventsource-mapping-enabled`, avoiding
a redundant `list-event-source-mappings` call.

`lambda-sqs-response-types` - fixed two bugs: (1) missing closing `)` on the
`update-eventsource-mapping` subshell; (2) `rm -f > $@` corrected to
`rm -f $@`; (3) `test -z` inverted to `test -n` (fail when response is empty,
not when non-empty).

---

## Upgrade Notes

After installing 1.2.5, refresh shared files:

    cpanm Amazon::Lambda::Runtime::Builder

**Cache migration required.** Existing `.cache/` sentinels are no longer
read - they live at `.cache/$(FUNCTION_NAME)/` in 1.2.5. Run
`make lambda-clean && make lambda-pipeline` to reprovision, or move files
manually:

    mkdir -p .cache/$(FUNCTION_NAME)
    mv .cache/lambda-* .cache/ecr-* .cache/image* .cache/deploy \
       .cache/policy-document .cache/sqs-* .cache/s3-* \
       .cache/cpanfile .cache/debian-packages \
       .cache/$(FUNCTION_NAME)/

Projects using `wait-event-source-mapping-enabled` in custom recipes must
rename to `wait-eventsource-mapping-enabled`.
