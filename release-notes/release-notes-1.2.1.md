# Amazon::Lambda::Runtime::Builder 1.2.1 Release Notes

## Overview

1.2.1 adds EventBridge as the second supported trigger type, validated
end-to-end against a real scheduled Lambda (`OrePAN2::S3::Monitor`). It
also consolidates `lambda-function` and `update-function` into a single
idempotent create-or-update target, adds `wait-function-active` to eliminate
race conditions during function updates, hardens `alr-helper` exit code
propagation, and refactors `Role::ECR` error handling through
`_handle_response`.

---

## New Features

### EventBridge trigger type

`lambda-mapping.yml` version `1.1` adds `eventbridge` to `trigger_types`
and two new mapping entries:

- `trigger.schedule` → `SCHEDULE_EXPRESSION`, default `rate(1 day)`
- `trigger.rule_name` → `RULE_NAME`, default `lambda-handler-rule`

`eventbridge.mk` gains `lambda-eventbridge-pipeline` as a top-level
`.PHONY` target (prerequisite of `lambda-configuration` and
`lambda-eventbridge-trigger`), completing the parallel to
`lambda-sqs-pipeline`. `RULE_STATE` variable added (default `ENABLED`);
pass `RULE_STATE=DISABLED` on the first deploy to wire up the rule without
activating it:

```bash
make lambda-eventbridge-pipeline RULE_STATE=DISABLED
```

The `put-rule-expression` call now quotes `$(SCHEDULE_EXPRESSION)` with
single quotes to correctly handle schedule expressions containing spaces
(e.g. `rate(5 minutes)`).

### builder.mk delegations

New targets delegating to `Makefile.builder`:

- `lambda-function` - prime the full sentinel chain; create or update the
  Lambda function
- `lambda-eventbridge-pipeline` - full EventBridge infrastructure
- `enable-eventbridge-rule` - enable a disabled rule
- `disable-eventbridge-rule` - disable an active rule
- `delete-eventbridge-rule` - remove targets and delete the rule

---

## Changes

### lambda-function / update-function consolidation

`$(CACHE_DIR)/update-function` sentinel and target are removed. The new
`$(CACHE_DIR)/lambda-function` sentinel covers both create and update
with a unified recipe:

1. `alr-helper get-function $(FUNCTION_NAME)` - check if the function exists
2. If absent: `alr-helper create-function` using role ARN from
   `$(CACHE_DIR)/lambda-role`
3. If present: `alr-helper update-function` with current digest and URI
4. If `get-function` returns an unexpected response: hard error

Prerequisites expanded to include `$(CACHE_DIR)/lambda-role` and
`$(CACHE_DIR)/lambda-policies`, ensuring the IAM role and policy attachment
are complete before any Lambda API call. `update-function` is now a simple
alias for `lambda-function`.

`update-function` removed from `CLEANFILES` and `.PHONY` list.

### ROLE_PROFILE / policies guard

When `ROLE_PROFILE` is unset and the `policies` file does not exist, make
now fails at parse time with an actionable error message rather than the
generic "no rule to make target 'policies'" error:

```
No policies file 'policies' found and ROLE_PROFILE is not set.
Either create a policies file or set ROLE_PROFILE in lambda.env
```

### wait-function-active

New `_wait_function_active` internal method in `Role::Lambda` polls until
the function's `LastUpdateStatus` is no longer `InProgress`, with a
`SIGALRM`-based timeout. Called automatically before and after
`UpdateFunctionCode` to prevent 409 conflicts when `lambda-configuration`
runs immediately after a function update. Also exposed as
`alr-helper wait-function-active` for use in custom Makefile recipes.

### alr-helper exit code propagation

`caller or __PACKAGE__->main()` changed to
`caller or exit __PACKAGE__->main()`. Previously the return value of
`main()` was discarded by the modulino idiom and the process always exited 0
regardless of command success or failure, silently masking errors in
Makefile recipes. The exit code now correctly reflects `$SUCCESS` (0) or
`$FAILURE` (1) from `_handle_response`.

### _handle_response fix

`_handle_response` previously checked `!$rsp && $EVAL_ERROR` - requiring
both an empty response and an eval error to trigger failure. Changed to
check `$EVAL_ERROR` alone, correctly returning `$FAILURE` whenever the
`eval{}` in the caller caught an exception regardless of what `$rsp`
contains.

### Role::ECR refactored

`cmd_ecr_create_repository`, `cmd_ecr_describe_repositories`,
`cmd_ecr_get_lifecycle_policy`, and `cmd_ecr_put_lifecycle_policy` all
previously had inline `if (!$rsp)` error handling with duplicated
`print/return` logic. All four now delegate to `_handle_response`.
`use JSON` added to `Role::ECR` (previously relied on implicit import).

### Role::Lambda - create-function role ARN fix

`cmd_lambda_create_function` was extracting the role ARN as
`$role->{Arn}`. The correct path in the IAM `GetRole` response is
`$role->{Role}{Arn}`. Fixed.

### YAML::Tiny dependency

`YAML::Tiny 1.76` added to `requires` and `cpanfile`. Required by
`Role::Config` for `lambda.yaml` parsing (was a transitive dependency
in 1.2.0, now declared explicitly).

---

## Upgrade Notes

After installing 1.2.1 the shared files (`share/Makefile.mk`,
`share/builder.mk`, `share/eventbridge.mk`, `share/lambda-mapping.yml`)
must be refreshed in the `File::ShareDir` install location. Run:

    cpanm Amazon::Lambda::Runtime::Builder

Projects using `update-function` directly continue to work - it is now
an alias for `lambda-function`. Projects that reference
`$(CACHE_DIR)/update-function` in custom rules should update to
`$(CACHE_DIR)/lambda-function`.
