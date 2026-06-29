# Amazon::Lambda::Runtime::Builder 1.3.0

## Three-Layer Image Architecture

The `Dockerfile` distributed by ALRB has been refactored to support a
three-layer image model:

```
perl-lambda-base          (runtime + all ALR dependencies)
  └── platform image      (stable, infrequently-changing artifacts)
        └── handler image (application handler distribution)
```

The runtime stage now builds `FROM ${PLATFORM_IMAGE}` rather than
`FROM debian:trixie-slim`, eliminating the redundant reinstallation of
Perl, system packages, and ALR dependencies on every handler build.
`PLATFORM_IMAGE` defaults to `perl-lambda-base:latest`, preserving
backward compatibility for projects that do not need an intermediate
layer.

### `platform.mk` (new)

Manages the optional platform image layer. Builds from
`Dockerfile.platform` in the project root, pushes to ECR, and
invalidates handler image sentinels so the next `make lambda-pipeline`
picks up the change automatically.

```make
make platform           # build and push platform image
make platform-teardown  # clear sentinels (ECR repo must be deleted manually)
```

`PLATFORM_IMAGE` and `LOG_RETENTION` are now recognised keys in
`lambda-mapping.yml` and `lambda.env`.

### `lambda-pipeline` guard

If `PLATFORM_IMAGE` is set and `Dockerfile.platform` exists in the
project root, `lambda-pipeline` now runs `make platform` automatically
before the trigger-type pipeline.

## CloudWatch Log Group Management

### `log-group.mk` (new)

Provisions the Lambda function's CloudWatch log group before the
function is configured, ensuring retention policy is applied even when
Lambda would otherwise auto-create the group on first invocation.

```make
make log-group           # create log group and set retention policy
make log-group-teardown  # delete log group
```

`LOG_RETENTION` (default: `1` day) controls the retention period.
`lambda-configuration` now depends on `$(CACHE_DIR)/log-group`.
`lambda-teardown` calls `log-group-teardown` unconditionally.

### `alr-helper` commands added

- `create-log-group`
- `delete-log-group`
- `describe-log-groups`
- `put-retention-policy`
- `delete-retention-policy`

Implemented in `Role::Logs` (`cmd_logs_create_log_group`,
`cmd_logs_delete_log_group`, `cmd_logs_describe_log_groups`,
`cmd_logs_put_retention_policy`, `cmd_logs_delete_retention_policy`).

`put-retention-policy` validates the `days` argument against the
CloudWatch Logs accepted set and delegates to `delete-retention-policy`
when `days` is `0`.

## Overlay Extraction

The overlay build recipe has been extracted from `Makefile.mk` into a
dedicated `overlay.mk`. An `overlay-teardown` target is now available
and is called by `lambda-teardown` when `OVERLAY` is set. `builder.mk`
exposes `overlay-teardown`, `platform`, `platform-teardown`,
`log-group`, and `log-group-teardown` as delegating targets.

## Bug Fixes

### `Role::Lambda` — IAM propagation delay (`cmd_lambda_create_function`)

The retry loop that handles IAM role propagation now also catches
`InvalidArnException` in addition to the existing `cannot be assumed`
pattern. Both errors occur transiently while IAM propagates a newly
created role to the Lambda service.

### `alb.mk` — sentinel chmod guards

`alb-lambda-permission` and `alb-target-group` recipes now open the
sentinel for writing (`chmod -f 644`) before executing, matching the
pattern used by other recipes in the framework and preventing stale
read-only sentinels from blocking re-runs.
