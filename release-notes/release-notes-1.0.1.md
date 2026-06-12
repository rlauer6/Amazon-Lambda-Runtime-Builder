## Amazon::Lambda::Runtime::Builder 1.0.1 Release Notes

**Major Expansion of `alr-helper` CLI**

New service clients with shared/cached accessors (`_ecr`, `_iam`,
`_lambda`, `_logs`, `_s3`, `_sqs`, `_sts`, `_events`) replacing
repeated `require`/`->new` calls throughout all role modules.

**New commands**: `delete-function`, `delete-event-source-mappings`,
`update-event-source-mapping`, `update-function-configuration`,
`get-function-configuration`, `get-function-concurrency`,
`put-function-concurrency`, `remove-permission`, `detach-role-policy`,
`list-attached-policies`, `describe-log-streams`, `get-queue-arn`,
`get-queue-attributes`, `get-queue-policy`, `set-queue-bucket-policy`,
`set-queue-redrive-policy`.

New `Amazon::Lambda::Runtime::Builder::Role::Logs` role wrapping
`Amazon::API::CloudWatchLogs`.

**Renamed/refactored**
- `event-bridge` → `eventbridge` naming convention across commands
  (`cmd_event_bridge_*` → `cmd_eventbridge_*`).
- `_check_response` → `_handle_response` (new shared response
  handler).
- `_init_s3` → `_s3` (cached accessor), and S3 client now respects `--region`/`--localstack`.
- ECR `describe-repositories` now passes `repositoryNames` as an
  array.
- `put-lifecycle-policy` accepts count number/unit arguments.
- `cmd_lambda_create_function` now derives role ARN directly from
  `GetRole` response instead of constructing it manually.
- `cmd_lambda_create_event_source_mappings`/`list-event-source-mappings`
  now resolve queue names to ARNs via
  `_resolve_arn`/`_sqs_get_queue_arn`, and accept key:value parameter
  lists.
- `cmd_s3_put_bucket_notification_configuration` reworked to support
  both `lambda:` and `sqs:` notification targets.
- `cmd_iam_get_role` now URL-decodes and JSON-decodes `AssumeRolePolicyDocument`.
- `cmd_iam_attach_role_policy` now returns the list of attached policies.

**New features**
- New `_parse_params`/`_handle_response` helpers for
  key:value/JSON-file argument parsing and consistent response output.
- `--region`, `--input`, `--output`, `--dryrun`, `--log-level` CLI
  options added; abbreviations enabled for commands.
- New `cmd_lambda_add_permission` auto-adds `SourceAccount` for S3
  principals; `cmd_lambda_remove_permission` resolves statement IDs
  from the function policy by source/type.
- New `profiles.yml` defining IAM policy bundles (basic, s3-read,
  s3-sqs, s3, eventbridge).
- Added `URI::Escape` dependency.

**Makefile/share updates**
- `share/Makefile.build` renamed to `share/Makefile`; includes new
  `help.mk`-based dynamic help across all `.mk` includes.
- New SQS pipeline targets: `sqs-dlq`, `sqs-queue` (with
  redrive policy), `sqs-queue-redrive`, `sqs-queue-policy`,
  `lambda-concurrency`, `lambda-sqs-permission`,
  `lambda-s3-sqs-trigger`, and aggregate `lambda-sqs-pipeline` target.
- `s3-bucket`/`s3.mk` fixed to correctly parse `list-buckets` JSON and
  route notifications through SQS.
- Various `.PHONY`/dependency declaration fixes across
  `ecr-create-repo.mk`, `eventbridge.mk`, `sns.mk`, `streaming.mk`.
- Dockerfile simplified: removed `REINSTALL_PACKAGES` and forced
  reinstall of `Amazon::Lambda::Runtime`.

