# Amazon::Lambda::Runtime::Builder 1.2.2 Release Notes

## Overview

1.2.2 introduces full teardown support — `lambda-teardown`,
`lambda-sqs-teardown`, and `lambda-eventbridge-teardown` — allowing complete
deprovisioning of Lambda infrastructure from a single `make` target. The
release also adds `TRIGGER_TYPE` to the configuration schema (version `1.2`),
enabling `lambda-teardown` to dispatch automatically to the correct
trigger-type teardown based on `lambda.env`. New `alr-helper` commands
support the teardown recipes across ECR, IAM, SQS, and S3.

---

## New Features

### Teardown targets

Three new teardown targets provide complete infrastructure deprovisioning:

**`lambda-teardown`** (in `Makefile.mk`) — dispatches to the correct
trigger-type teardown based on `$(TRIGGER_TYPE)` from `lambda.env`. Fails
at parse time with a clear error if `TRIGGER_TYPE` is unset or unrecognized:

```
Unknown or unset TRIGGER_TYPE: ''. Set TRIGGER_TYPE in lambda.env to one of: s3-sqs, eventbridge
```

**`lambda-eventbridge-teardown`** (in `eventbridge.mk`) — full EventBridge
stack deprovisioning in dependency order:
1. Disable the EventBridge rule (stop invocations immediately)
2. Remove Lambda targets from the rule
3. Delete the rule
4. Delete the Lambda function
5. Detach all IAM policies from the execution role
6. Delete the execution role
7. Delete the ECR repository
8. `make clean` — remove all sentinels

**`lambda-sqs-teardown`** (in `sqs.mk`) — full s3-sqs stack deprovisioning
in dependency order:
1. Remove S3 bucket notification configuration
2. Delete event source mappings (disconnect SQS from Lambda)
3. Delete SQS queue and DLQ
4. Delete the Lambda function
5. Detach all IAM policies from the execution role
6. Delete the execution role
7. Delete the ECR repository
8. `make clean` — remove all sentinels

All three targets are delegated from `builder.mk` so they work from the
project root via the standard `make` invocation.

### TRIGGER_TYPE in lambda-mapping.yml (version 1.2)

`trigger.type` → `TRIGGER_TYPE` added as a required field with no `applies_to`
filter — universal across all trigger types. This makes `TRIGGER_TYPE`
available in `lambda.env` for Makefile dispatch and for any project-level
tooling that needs to know the trigger type at make-time.

`lambda-mapping.yml` version bumped to `1.2` (from `1.1`).

### New alr-helper commands

**ECR:**
- `delete-repo` — delete an ECR repository
- `delete-repo-policy` — delete a repository policy

**IAM:**
- `delete-role` — delete an IAM role (policies must be detached first)
- `detach-all-policies` — list and detach all policies attached to a role;
  idempotent, safe to call when no policies are attached

**SQS:**
- `delete-queue` — delete an SQS queue by name

**S3:**
- `remove-bucket-notification` — clear all notification configurations from
  an S3 bucket by PUTting an empty `NotificationConfiguration`

---

## Changes

### cmd_sqs_purge_queue renamed

`cmd_purge_queue` renamed to `cmd_sqs_purge_queue` for consistency with the
naming convention used throughout `Role::SQS`.

### Role::IAM — _list_attached_policies refactored

`_list_attached_policies` extracted as a private helper used by both
`cmd_iam_list_attached_policies` and `cmd_iam_detach_all_policies`, removing
duplicated IAM API call logic.

---

## Upgrade Notes

After installing 1.2.2, refresh shared files in the `File::ShareDir` install
location:

    cpanm Amazon::Lambda::Runtime::Builder

Projects using `lambda.yaml` must add `trigger.type` to their `lambda.yaml`
— it is now required. Run `alr-builder check-env-file` to validate. Existing
`lambda.env` files that pre-date `lambda.yaml` adoption are unaffected until
`generate-yaml` is run.

The `lambda-teardown` targets are destructive and irreversible — they delete
AWS resources. Sentinel removal via `make clean` is the final step; after
teardown, `make lambda-function` or `make lambda-sqs-pipeline` /
`make lambda-eventbridge-pipeline` will rebuild from scratch.
