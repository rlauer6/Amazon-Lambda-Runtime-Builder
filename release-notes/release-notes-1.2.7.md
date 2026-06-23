# Amazon::Lambda::Runtime::Builder 1.2.7 Release Notes

## Overview

1.2.7 adds CloudFront cache invalidation support, a custom inline IAM policy
mechanism (`custom-policies.json`), and fixes to the Dockerfile's dependency
installation pipeline. No new Lambda trigger types are introduced; this release
is focused on operational tooling and IAM policy management.

---

## New Features

### CloudFront cache invalidation (`alr-helper create-invalidation`)

A new `Role::CloudFront` provides `alr-helper create-invalidation`, allowing
a CloudFront distribution's cache to be invalidated directly from the builder
toolchain:

```bash
alr-helper create-invalidation <distribution-id> /path/one /path/two ...
```

`Amazon::API::CloudFront` is now a declared dependency (2.2.6 or later).
`Data::UUID` is also added as a dependency, used to generate the required
`CallerReference` for each invalidation request.

### Custom inline IAM policies (`custom-policies.json`)

The IAM policy pipeline now supports project-specific inline policies that
cannot be expressed as AWS managed policy ARNs. Place a `custom-policies.json`
file alongside `lambda.yaml`:

```json
[
  {
    "PolicyName": "cloudfront-invalidation",
    "PolicyDocument": {
      "Version": "2012-10-17",
      "Statement": [{
        "Effect": "Allow",
        "Action": "cloudfront:CreateInvalidation",
        "Resource": "arn:aws:cloudfront::123456789:distribution/ABCDEF"
      }]
    }
  }
]
```

The policy pipeline now has two independent sentinels and targets:

- **`lambda-managed-policies`** - attaches AWS managed policies from the
  `policies` file (replaces the old `lambda-policies` target internally)
- **`lambda-inline-policies`** - applies inline policies from
  `custom-policies.json`; a no-op if the file is absent
- **`lambda-policies`** - aggregator target that depends on both; unchanged
  as the prerequisite for `lambda-function` and the rest of the pipeline

New `alr-helper` commands: `put-role-policies` (applies all policies in a
`custom-policies.json`), `get-role-policy` (used internally for verification).

New `make` targets: `update-managed-policies`, `update-inline-policies`
(force-rebuild their respective sentinels independently);
`update-policies` now depends on both.

`lambda-inline-policies` uses `$(wildcard $(CUSTOM_POLICIES_FILE))` as a
prerequisite, so the sentinel is only rebuilt when `custom-policies.json`
actually changes - normal `make lambda-pipeline` runs are timestamp-aware.

### `_parse_params` - `file://` passthrough for colon-form parameters

When a `key:value` parameter's value is a `file://` path (e.g.
`policy-document:file://custom-policies.json`), `_parse_params` now returns
the `file://` string intact rather than attempting to split on the embedded
`://`. The caller resolves the file reference explicitly.

---

## Bug Fixes

- **`policy-document` sentinel** - `$(CACHE_DIR)/policy-document` recipe now
  marks the sentinel writable before writing, preventing `make` errors on
  re-runs when the sentinel is read-only
- **`lambda-concurrency` sentinel** - same read-only sentinel fix applied to
  `sqs.mk`'s `lambda-concurrency` target
- **`lambda-sqs-trigger` sentinel** - likewise

---

## Dockerfile

The dependency installation step now correctly sets `PERL5LIB` and uses
`--use-install-command` to ensure `cpm` runs `make install` (rather than
blib-copy) for distributions that have `ExtUtils::MakeMaker` postambles.
This fixes `XML::SAX`'s `ParserDetails.ini` not being written to the
container's local lib:

```dockerfile
PERL5LIB=/cache/local-debian/lib/perl5 \
  cpm install --show-build-log-on-failure --use-install-command \
  -L /cache/local-debian ${RESOLVER}
```

The separate `ARG DARKPAN_REBUILD / RUN cpm install` layer (used to force
a rebuild when the DarkPAN changes) has been removed - cache invalidation
is now handled by the `cpanfile` dependency declarations directly.

---

## Upgrade Notes

Projects that use `update-policies` should be aware that it now depends on
both `update-managed-policies` and `update-inline-policies`. If no
`custom-policies.json` is present, `update-inline-policies` is a no-op.

`Amazon::API::CloudFront` 2.2.6 or later is required. Ensure it is available
in your CPAN mirror before building Lambda images from this version.
