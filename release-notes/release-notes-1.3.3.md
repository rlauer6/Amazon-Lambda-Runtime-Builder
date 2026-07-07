# Release Notes — Amazon::Lambda::Runtime::Builder v1.3.3

**Released:** 2026-07-07

---

## Overview

Version 1.3.3 adds in-place modification of ALB listener rules (so
that changing a path or priority no longer requires tearing down and
recreating the rule), upgrades the `Data::NestedKey` dependency, and
promotes the Getting Started guide out of draft status. Several
documentation improvements and internal refactors accompany these
changes.

---

## What's New

### ALB Listener Rule: Create-or-Modify Lifecycle

Previously, the ALB pipeline only created a listener rule on first
deploy and left it unchanged on subsequent runs. The rule is now
managed throughout its lifetime:

- **On first deploy** — the rule is looked up by path; if absent, it
  is created as before.
- **On subsequent deploys where `ALB_PATH` or `RULE_PRIORITY` have
  changed** — the existing rule is modified in place via the new
  `ModifyRule` API call, avoiding the need to delete and recreate it.
- A new `alb-listener-rule.value` stamp file tracks the current
  `ALB_PATH` and `RULE_PRIORITY` values so that `make` can detect when
  a rebuild is needed.

### New `modify-alb-listener-rule` Helper Command

A new `alr-helper` subcommand has been added:

```
alr-helper modify-alb-listener-rule <rule-arn> <target-group-arn> [key=value ...]
```

This modifies an existing listener rule by ARN — updating its path
condition and/or forward target — without recreating the
rule. Internally, `create-alb-listener-rule` and
`modify-alb-listener-rule` share a single refactored implementation
(`cmd_elbv2_create_alb_listener_rule`) that dispatches to `CreateRule`
or `ModifyRule` based on the command name.

### Path Values Are Now Regular Expressions

The `path` field for ALB listener rules is now treated as a regular
expression, populating the rule condition's `RegexValues` field rather
than `Values`. Validation is applied at rule creation/modification
time:

- The path is compiled as a Perl regex; an invalid expression is
  rejected with a clear error.
- A warning is emitted if the path is not anchored (does not begin
  with `^`).

### Default `RULE_PRIORITY` Changed to 999

`RULE_PRIORITY` now defaults to `999` (previously `10`). This ensures
that a path-only rule is evaluated after more-specific host- or
path-based rules already present on a shared ALB. Documentation notes
that on a shared load balancer, adding a host condition is preferable
to relying on priority ordering alone.

---

## Dependency Update

| Dependency | Previous | New |
|---|---|---|
| `Data::NestedKey` | 1.1.0 | 1.2.0 |

The `alb-listener-rule` Makefile target now uses the `dnk` CLI
(provided by `Data::NestedKey`) to extract `TargetGroupArn` and
`RuleArn` from cached JSON files, replacing inline `perl -MJSON`
one-liners.

---

## IAM Permissions

The ALB trigger now requires `elasticloadbalancing:ModifyRule` in
addition to the previously documented ELBv2 permissions. The full
updated set for ALB triggers is:

> `CreateTargetGroup`, `RegisterTargets`, `CreateRule`,
> **`ModifyRule`**, `DescribeTargetGroups`, `DescribeRules`, and their
> `Delete`/`Deregister` counterparts.

---

## Documentation

- **Getting Started guide** (`GETTING-STARTED.md`) — the draft notice
  has been removed; the guide is now considered complete and is
  published without qualification.
- **ALB trigger documentation** — updated to clarify that `path` is a
  regular expression, that `priority` defaults to `999`, and that
  `ModifyRule` is used on subsequent deploys. Guidance added on using
  a host condition on shared load balancers.
- **`alr-helper` POD** — updated entries for
  `create-alb-listener-rule` and the new `modify-alb-listener-rule`
  command.

---

## Internal Changes

- `cmd_elbv2_create_alb_listener_rule` refactored to serve both
  `create-alb-listener-rule` and `modify-alb-listener-rule`,
  dispatching on command name.
- Helper command dispatch table reformatted for consistent alignment.
- `register-alb-target` entry moved to alphabetical position in the dispatch table.

---

## Upgrade Notes

- If you have a deployed ALB listener rule, the rule will be
  **modified in place** on the next `make lambda-pipeline` run if
  `ALB_PATH` or `RULE_PRIORITY` differ from their cached values. No
  teardown is required.
- If your `path` value is not a valid Perl regular expression, the
  deploy will fail with a descriptive error. Plain path strings
  (e.g. `/build`) remain valid regex and are unaffected.
- The default `RULE_PRIORITY` has changed from `10` to `999`. Projects
  that rely on the old default should set `RULE_PRIORITY = 10`
  explicitly in `lambda.yaml` or `lambda.env` to preserve existing
  behaviour.
