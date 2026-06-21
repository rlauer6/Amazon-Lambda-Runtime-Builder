# Amazon::Lambda::Runtime::Builder 1.2.6 Release Notes

## Overview

1.2.6 adds the **`sns` trigger type**, allowing a Lambda function to be
provisioned, subscribed to an SNS topic, and torn down through the same
declarative pipeline already used for the `s3-sqs`, `s3-direct`, and
`eventbridge` trigger types. A new `Role::SNS` provides the underlying
`alr-helper` commands (topic creation, subscription, publishing), and the
`sns.mk` pipeline wires them into idempotent `make` targets.

This release was validated end-to-end against live AWS: provision =>publish
a message with attributes => deliver to the Lambda => handler decode =>
teardown.

> **Dependency note:** the `sns` trigger type publishes messages with
> `MessageAttributes`, which exercises SNS's query-protocol map
> serialization. This requires **`Amazon::API` 2.2.6 or later**, which fixes
> a bug that corrupted map-typed parameters on query/ec2-protocol services.
> Earlier versions of `Amazon::API` will fail when publishing messages with
> attributes.

---

## New Features

### `sns` trigger type

A new trigger type provisions an SNS topic, grants SNS permission to invoke
the Lambda, and subscribes the function to the topic:

```
make TOPIC_NAME=my-topic FUNCTION_NAME=my-fn lambda-sns-pipeline
make lambda-sns-teardown
```

The pipeline (`sns.mk`) provides idempotent sentinel-driven targets:

- `sns-topic` - creates the topic (`CreateTopic` is naturally idempotent,
  so no existence guard is needed)
- `lambda-sns-permission` - grants `sns.amazonaws.com` permission to invoke
  the function, scoped to the topic ARN
- `lambda-sns-trigger` - subscribes the function, with a dedup check
  (`get-subscription`) so re-running the pipeline does not create duplicate
  subscriptions
- `lambda-sns-pipeline` / `lambda-sns-teardown` - top-level provision and
  deprovision targets

Lambda-protocol same-account subscriptions are auto-confirmed by AWS, so no
subscription-confirmation wait step is required. Topic deletion is
deliberately omitted from teardown by default, since topics may be shared
across multiple subscribers; unsubscribe is always performed.

### `Role::SNS` commands

New `alr-helper` commands backing the trigger type and available
standalone:

- `create-topic`, `delete-topic`, `list-topics`, `get-topic`
- `subscribe`, `unsubscribe`, `list-subscriptions`, `get-subscription`,
  `confirm-subscription`
- `publish`

`publish` accepts a message plus optional message attributes
(`attr:Name:Value`) and a topic identifier; `get-subscription` looks up an
existing subscription by topic and endpoint ARN, returning empty on no
match for clean use in pipeline dedup logic.

### `get-function-arn`

A new `Role::Lambda` command that returns a function's ARN by name
(returning empty on a 404 rather than dying), used by the SNS trigger to
resolve the subscription endpoint.

---

## Configuration

`lambda-mapping.yml` is bumped to version 1.4:

- `sns` added to the recognized `trigger_types`
- new `trigger.topic_name` => `TOPIC_NAME` mapping, required for `sns`-typed
  projects

`Makefile.mk` and `builder.mk` dispatch `lambda-pipeline` / `lambda-teardown`
to the SNS targets when `TRIGGER_TYPE=sns`.

---

## Bug Fixes

- **`_parse_params`** now validates its input, dying with a clear message on
  malformed parameters rather than emitting a cascade of uninitialized-value
  warnings, and supports a spec-driven form declaring `required` and `valid`
  parameter keys.
- **`Config.pm`** trigger-type resolution: `_generate_lambda_env` and
  `_walk_mapping` now use the project's actual configured `trigger.type`
  rather than always assuming the first entry in `trigger_types`. Previously,
  any non-`s3-sqs` project incorrectly had `s3-sqs`'s required fields (e.g.
  `BUCKET_NAME`) enforced and its defaults reported.
- **`_lambda_env_needs_regen`** version comparison now treats the mapping
  version as a string, so non-integer versions (e.g. `1.4`) are compared and
  displayed correctly rather than being truncated to an integer.
- **`Makefile.mk`** now requires `lambda.env` to exist (with an actionable
  message pointing at `alr-builder check-env-file`), exempting `clean`.
- **Pipeline recipes** that create AWS resources now fail the `make` target
  when the underlying `alr-helper` call fails, instead of silently removing
  the sentinel and reporting success.
- **`lambda-function`** correctly treats a 404 "Function not found" as
  "needs creating" rather than a hard error.

---

## Upgrade Notes

`sns`-typed projects must declare `trigger.topic_name` in `lambda.yaml`
(there is no default). Ensure `Amazon::API` is at 2.2.6 or later before
publishing messages with attributes.
