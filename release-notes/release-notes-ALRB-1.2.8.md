# Amazon::Lambda::Runtime::Builder 1.2.8 Release Notes

## Summary

Adds ALB (Application Load Balancer) as a supported Lambda trigger
type, introduces overlay image support for multi-layer Lambda
deployments, adds a `filter=` response extraction feature to
`alr-helper` commands, and fixes several robustness issues in the
Lambda create/configure pipeline.

---

## Changes

### ALB trigger type (new)

**`share/alb.mk`** — new makefile implementing the full ALB trigger
pipeline:

- `$(CACHE_DIR)/alb-lambda-permission` — grants
  `elasticloadbalancing.amazonaws.com` permission to invoke the
  function
- `$(CACHE_DIR)/alb-target-group` — creates a Lambda target group,
  idempotent (uses existing group if found)
- `$(CACHE_DIR)/alb-target-group-registration` — registers the Lambda
  function ARN with the target group
- `$(CACHE_DIR)/alb-listener-rule` — creates a path-based forwarding
  rule on the listener, idempotent
- `lambda-alb-pipeline` — chains all of the above plus
  `lambda-configuration`
- `lambda-alb-teardown` / `_lambda-alb-teardown` — full deprovision

**`lib/Amazon/Lambda/Runtime/Builder/Role/ELBv2.pm.in`** — new role
providing `alr-helper` commands for ELBv2:

- `describe-load-balancers`, `describe-listeners`
- `get-alb-target-group`, `create-alb-target-group`,
  `delete-alb-target-group`
- `register-alb-target`, `deregister-alb-target`
- `get-alb-listener-rule`, `create-alb-listener-rule`,
  `delete-alb-listener-rule`

`Role::ELBv2` is composed into `Helper` via `with`.

**`Role::Config` — `_validate_constraints`**

Refactored from a single `s3-sqs` check to a dispatch table keyed by
`TRIGGER_TYPE`. ALB constraint added: `LISTENER_ARN` must match
`arn:aws:elasticloadbalancing:`.

**`share/Makefile.mk`**

- `alb` branch added to `lambda-pipeline` and `lambda-teardown`
  dispatch
- `include $(FRAMEWORK_DIR)/alb.mk` added
- `$(CACHE_DIR)/alb-*` sentinels added to `CLEANFILES`

**`share/builder.mk`**

- `lambda-alb-pipeline`, `lambda-alb-teardown`, and `overlay` targets
  added, delegating to the `ALR_BUILDER` makefile

**`share/lambda-mapping.yml`**

- `alb` added to `trigger_types`
- `OVERLAY` mapping added (no `applies_to` filter)
- `LISTENER_ARN` (required), `ALB_PATH` (default `/build`), and
  `RULE_PRIORITY` (default `10`) added with `applies_to: [alb]`

---

### Overlay image support (new)

**`share/Makefile.mk`**

- `$(CACHE_DIR)/overlay` — new cached target that builds the overlay
  image from a `Dockerfile` in the project root, pushes it to its own
  ECR repo, and calls `update-function` with the overlay digest.
  Depends on `$(CACHE_DIR)/image` and `$(wildcard Dockerfile)` — stale
  when either changes.
- `overlay` — `.PHONY` target depending on `$(CACHE_DIR)/overlay`
- `update-function` — now chains to `overlay` when `OVERLAY` is set
- `lambda-pipeline` — now runs `overlay` as a final step when `OVERLAY`
  is set
- `$(CACHE_DIR)/lambda-configuration` — now also depends on
  `$(wildcard lambda-handler.env)` so touching that file invalidates
  the configuration sentinel

---

### `filter=` response extraction (new)

**`Helper._handle_response`**

Accepts an optional `$filter` argument. When present, uses
`Data::NestedKey` to extract a nested value from the response before
printing, eliminating `perl -MJSON -0ne` one-liners from make recipes.

**`Role::ECR`**

- `cmd_ecr_create_repository` — `filter=` support
- `cmd_ecr_describe_repositories` — `filter=` support; returns blank
  on `RepositoryNotFoundException` rather than printing an error
- `cmd_ecr_describe_images` — `filter=` support; refactored to sort by
  push time and return the most recent image details

**`share/ecr-create-repo.mk`**

`perl -MJSON` one-liners replaced with `filter=repositories[0].repositoryUri`
and `filter=repository.repositoryUri`.

**`share/Makefile.mk`**

`image-digest` target replaced with `filter=imageDigest`.

---

### `Role::Lambda` fixes

**`_add_environment`** — new helper reads `lambda-handler.env` from
cwd and injects `Environment.Variables` into a configuration hashref.
Called from both `cmd_lambda_create_function` and
`cmd_lambda_update_function_configuration`.

**`cmd_lambda_create_function`**

- Retries up to 10 times (2s sleep) when `CreateFunction` fails with
  `cannot be assumed` — handles IAM propagation delay without a blind
  `sleep`
- `_wait_function_active` now conditional on `$self->get_wait`

**`cmd_lambda_update_function_configuration`**

- `@params` no longer required — can be called with function name only
  (environment-only update)
- Both pre- and post-update `_wait_function_active` calls are now
  conditional on `$self->get_wait`

**`cmd_lambda_invoke_function`**

- `_wait_function_active` conditional on `$self->get_wait`

---

### `Role::IAM` — `_wait_create_role`

New `_wait_create_role` method polls `GetRole` until the role exists,
called from `cmd_iam_create_role` when `--wait` is set. In practice
the IAM propagation delay affects `sts:AssumeRole` rather than
`GetRole`, so the retry loop in `cmd_lambda_create_function` is the
definitive fix.

---

### `Helper._parse_params`

`pascal` option added (default `$TRUE`). When `$FALSE`, key names are
not converted to PascalCase — used by `Role::ECR` and `Role::ELBv2`
commands that pass raw filter keys.

---

### Dependencies

- `Amazon::API::ELBv2 2015.12.01` added to `requires` and `cpanfile`
- `Data::NestedKey 1.1.0` added to `requires` and `cpanfile`
