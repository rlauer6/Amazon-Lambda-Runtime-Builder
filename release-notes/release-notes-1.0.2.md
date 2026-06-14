# Amazon::Lambda::Runtime::Builder 1.0.2

Released: Saturday, June 13, 2026

## Summary

This release fixes a parameter-parsing bug that affected several
`alr-helper` commands, adds support for resetting list-valued event
source mapping attributes (such as `FunctionResponseTypes`), abbreviates
ECR repository references in `update-function`, adds a `purge-queue`
command, and continues hardening `share/Makefile` toward a fully
immutable, project-agnostic build recipe.

## Highlights

### Fixed: `toPascalCase` scalar-context bug in `_parse_params`

`_parse_params` is the shared `key:value` argument parser used by most
`alr-helper` commands (`update-event-source-mapping`,
`create-event-source-mappings`, `update-function-configuration`, etc.).

`toPascalCase()` returns different shapes depending on calling context:
in list context it returns the transformed string; in scalar context it
returns a `{ original => transformed }` hashref (useful for bulk
key-renaming elsewhere). `_parse_params` was calling it in scalar
context and assigning the result directly to the parameter key,
producing hash keys like `HASH(0x...)` instead of `Uuid`, `BatchSize`,
etc. Any `key:value` pair processed by `_parse_params` was affected.

Fixed by forcing list context: `($k) = toPascalCase($k)`.

### New: `_scalar_or_array` - array-valued parameters via `@`

Some Lambda API fields take arrays (`FunctionResponseTypes`,
`Architectures`, etc.). `_parse_params` now recognizes a leading `@` on
a value as a comma-separated array:

```
alr-helper update-event-source-mapping \
  uuid:2fd1ff8e-7c6f-448d-8ab6-52d7b7a026eb \
  response-types:@ReportBatchItemFailures
```

`response-types:@` (just `@`, nothing after) produces an empty array
`[]` - this is how to reset `FunctionResponseTypes` and return to
all-or-nothing batch semantics. Values not starting with `@` are passed
through unchanged.

### Fixed: `update-event-source-mapping` UUID handling and parameter parsing

- The UUID is now passed as `uuid:<uuid>` like every other parameter,
  rather than as a required leading positional argument. This makes the
  command consistent with `create-event-source-mappings`.
- `_parse_params` produces a `Uuid` key (via `toPascalCase`), but the
  Lambda API expects `UUID`. `cmd_lambda_update_event_source_mapping`
  now copies `Uuid` to `UUID` before calling `UpdateEventSourceMapping`,
  and dies with `"uuid is a required parameter"` if it's missing.

```
alr-helper update-event-source-mapping \
  uuid:2fd1ff8e-7c6f-448d-8ab6-52d7b7a026eb \
  batch-size:1 \
  response-types:@ReportBatchItemFailures
```

### Improved: `update-function` accepts abbreviated repo names

`cmd_lambda_update_function_code` now accepts either a bare ECR
repository name or a fully-qualified registry URI for the `repo-name`
argument. If `repo-name` doesn't already look like
`*.dkr.ecr.us-east-1.amazonaws.com/*`, it's expanded to
`<account>.dkr.ecr.<region>.amazonaws.com/<repo-name>` using the
caller's account ID (`_sts_get_account`) and configured region.

```
# both of these now work
alr-helper update-function lambda-handler perl-lambda sha256:abc123...
alr-helper update-function lambda-handler 311974035819.dkr.ecr.us-east-1.amazonaws.com/perl-lambda sha256:abc123...
```

A digest sanity check was also added (`die ... if $digest !~
/^sha256:/`), but the `die` call uses `sprintf`-style `%s`
interpolation, which `die` does not perform - the literal text
`ERROR: sprintf %s does not look like a digest` will be shown, with the
actual digest value appended on the following line by `die`'s normal
list-concatenation behavior. The check itself works correctly (rejects
non-`sha256:` digests); only the error message text is malformed. The
hardcoded `us-east-1` in the repo-name detection regex will also need
revisiting for multi-region use.

### New: `get-meta` command

`alr-helper --tarball <dist>.tar.gz get-meta <field>` extracts a single
field (e.g. `name`, `version`, `abstract`) from the distribution's
`META.json`. `_fetch_meta` now falls back to `$self->get_tar` if no
`Archive::Tar` object is passed explicitly, so `cmd_get_meta` can call
it with no arguments.

Note: `cmd_get_meta` prints the result to **STDERR**
(`print {*STDERR} ...`), not STDOUT. If this command is intended for use
in `$(shell ...)` substitutions in Makefiles (which capture STDOUT),
this will need to be changed to `*STDOUT` in a follow-up.

### New: `purge-queue` command

`alr-helper purge-queue <queue-name>` calls SQS `PurgeQueue` for the
named queue, with no confirmation prompt. A new internal `_queue_url`
helper centralizes queue URL construction
(`https://sqs.<region>.amazonaws.com/<account>/<queue-name>`), and
`_sqs_set_queue_attributes` has been refactored to use it as well.
`PurgeQueue` is destructive, irreversible, and rate-limited by SQS to
once per 60 seconds per queue - callers should be aware no `--force` or
confirmation step exists at this layer.

### `share/Makefile`: continued hardening toward immutability

- Removed the unused `VERSION` variable and its `../VERSION` file
  dependency - version information is no longer required by the build
  recipe.
- `HANDLER_CLASS` is now a hard requirement (`$(error You must specify
  the HANDLER_CLASS)`); the previous silent default of `LambdaHandler.pm`
  has been removed.
- `DIST_TARBALL` is no longer required for targets that don't need it
  (e.g. `clean`), avoiding spurious errors when running housekeeping
  targets without a tarball present.
- Fixed a shell syntax error in the `deploy` target where a trailing
  line continuation (`\`) incorrectly merged the `chmod` step with the
  `$(call ecr_login,...)` macro invocation, causing the macro's own
  `$(NO_ECHO)`/`@` prefix to land mid-command (`/bin/bash: ... @URI=...:
  No such file or directory`). The `chmod` step is now its own recipe
  line.
- Fixed a typo in the `lambda-function` target (`if [[ "$$function" =
  "" }]]` -> `if [[ "$$function" = "" ]]`) that caused a shell
  conditional-expression syntax error.

### Dependency versions relaxed

`cpanfile` and `requires` now specify `0` (any version) for the
`Amazon::API::*`, `Amazon::Credentials`, `Amazon::S3::Lite`, and
`CLI::Simple*` family of dependencies, and add
`Amazon::API::CloudWatchLogs` as a new dependency (used by
`describe-log-streams`). Pinned minimum versions for these distributions
were removed during active co-development; version constraints will be
reintroduced once the dependent distributions stabilize.

### Minor

- `Role::Install`: whitespace/import-ordering cleanup, no functional
  change.

## Upgrading

No configuration changes are required for existing projects. If you were
relying on the previous default `HANDLER_CLASS ?= LambdaHandler.pm`, you
must now set `HANDLER_CLASS` explicitly (via `lambda.env`, `project.mk`,
or the `make` command line) or the build will fail with `You must
specify the HANDLER_CLASS`.

If any `update-event-source-mapping` invocations previously passed the
UUID as a bare positional argument, update them to `uuid:<uuid>` syntax.
