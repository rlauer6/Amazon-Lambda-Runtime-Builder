# Table of Contents

* [NAME](#name)
* [SYNOPSIS](#synopsis)
* [DESCRIPTION](#description)
* [COMMANDS](#commands)
  * [install](#install)
  * [check](#check)
  * [check-env-file](#check-env-file)
  * [generate-yaml](#generate-yaml)
* [OPTIONS](#options)
* [CONFIGURATION](#configuration)
  * [Trigger types](#trigger-types)
  * [lambda.yaml structure](#lambdayaml-structure)
* [WORKFLOW](#workflow)
  * [Phase 1 - Build the container image](#phase-1---build-the-container-image)
  * [Phase 2 - Provision function and event source](#phase-2---provision-function-and-event-source)
  * [Phase 3 - Teardown](#phase-3---teardown)
  * [The policies files](#the-policies-files)
* [MAKEFILE VARIABLES](#makefile-variables)
  * [Identity and image](#identity-and-image)
  * [Build](#build)
  * [Function configuration and logging](#function-configuration-and-logging)
  * [Policies](#policies)
  * [Function URL / streaming](#function-url--streaming)
* [MAKEFILE TARGETS](#makefile-targets)
  * [Primary Targets](#primary-targets)
  * [Per-trigger Pipelines](#per-trigger-pipelines)
  * [Event Trigger and Function URL Targets](#event-trigger-and-function-url-targets)
  * [Image Layer Targets](#image-layer-targets)
  * [Internal Targets](#internal-targets)
* [REQUIRED IAM PERMISSIONS](#required-iam-permissions)
    * [ECR](#ecr)
    * [IAM](#iam)
    * [Lambda](#lambda)
    * [SQS / SNS / S3 / EventBridge / STS](#sqs--sns--s3--eventbridge--sts)
    * [Additional permissions (not verified by check)](#additional-permissions-not-verified-by-check)
    * [Handler Runtime Permissions](#handler-runtime-permissions)
* [OPTIONAL DEPENDENCIES](#optional-dependencies)
* [SEE ALSO](#see-also)
* [AUTHOR](#author)
* [LICENSE](#license)
# NAME

Amazon::Lambda::Runtime::Builder - scaffolding, environment checker, and
deployment toolchain for Perl Lambda container images

# SYNOPSIS

    # Scaffold a new project in the current directory
    alr-builder install

    # Scaffold into a specific directory
    alr-builder install --install-dir /path/to/my-lambda

    # Verify tools and IAM permissions before your first build
    alr-builder check

    # Validate lambda.env (or lambda.yaml) against this Lambda's requirements
    alr-builder check-env-file

    # Migrate an existing lambda.env to lambda.yaml
    alr-builder generate-yaml

# DESCRIPTION

`Amazon::Lambda::Runtime::Builder` is the companion deployment tool for
[Amazon::Lambda::Runtime](https://metacpan.org/pod/Amazon%3A%3ALambda%3A%3ARuntime). It handles everything outside of the Perl
runtime itself: scaffolding a new project directory, verifying your build
environment, and providing the `make`-based build/deploy pipeline that
turns a handler distribution into a deployed Lambda function wired to the
event source of your choice.

Five trigger types are supported - `s3-sqs`, `s3-direct`,
`eventbridge`, `sns`, and `alb` - selected with a single
`TRIGGER_TYPE` value and provisioned by one dispatching target
(`make lambda-pipeline`). See ["CONFIGURATION"](#configuration) and ["WORKFLOW"](#workflow).

The `alr-builder` CLI provides four commands:

- **install** - copies the project scaffold (handler template,
managed-policy list, and the `make` integration files) into a target
directory.
- **check** - verifies that required system tools are present on
your `PATH` and, if the optional IAM modules are installed, confirms
that your AWS credentials have sufficient permissions to build and deploy.
- **check-env-file** - validates `lambda.env` (or `lambda.yaml`, if
present) against this Lambda's configuration requirements, reporting
missing required values, customized values, and values using defaults.
- **generate-yaml** - migrates an existing, hand-written `lambda.env`
to a minimal `lambda.yaml`, the starting point for the generate-on-demand
workflow described in ["CONFIGURATION"](#configuration).

A second, internal CLI - `alr-helper` - wraps the AWS API calls the
Makefiles invoke (ECR, IAM, Lambda, SQS, SNS, S3, EventBridge, ELBv2,
CloudWatch Logs, STS). You do not normally call it directly; the
Makefiles do.

# COMMANDS

## install

    alr-builder install [--install-dir DIR] [--force]

Copies the project scaffold into the target directory (defaults to the
current working directory), creating the directory if it does not exist.
The set of installed files is driven by the distribution's
`share/MANIFEST.json`:

- `LambdaHandler.pm` - handler template with stub implementations
for SQS, SNS, S3, and EventBridge events, plus a streaming-response
example for Function URL invocations. Edit it in place or replace it with
your own handler module. Installed with `overwrite: never` - an existing
copy is left untouched.
- `policies` - AWS managed IAM policy ARNs to attach to the Lambda
execution role. One ARN per line; lines beginning with `#` are comments.
Installed with `overwrite: never`.
- `Makefile.builder` - the build engine. A thin, regeneratable
wrapper that `include`s the framework's `Makefile.mk` from this
distribution's share directory. Installed with `overwrite: always` -
safe to regenerate and safe to commit.
- `project.mk` - the file you include from your own `Makefile`. It
pulls in the framework's `builder.mk`, which exposes the user-facing
targets (each delegates to `make -f Makefile.builder ...`). If
`project.mk` already exists, the ALRB integration block is appended
between marker comments and a `project.mk.bak` backup is written; an
already-integrated `project.mk` is left unchanged.

The Dockerfile, the trigger Makefiles (`sqs.mk`, `sns.mk`, `s3.mk`,
`eventbridge.mk`, `alb.mk`, `streaming.mk`), and the platform/overlay/
log-group fragments are **not** copied into the project - they are read
from this distribution's share directory at build time. The `cpanfile`
used to build the image is generated on demand from your distribution
tarball's `META.json` (see ["WORKFLOW"](#workflow)).

Use `--force` to overwrite a file whose manifest policy would otherwise
refuse to replace it.

## check

    alr-builder check

Verifies that your environment is ready to build and deploy. Checks two
things:

**Required system tools** - `docker` and `make` must be on your
`PATH`. `curl` is checked as an optional tool. The tool list comes from
`MANIFEST.json`. Missing required tools are reported as errors.

**IAM permissions** - if [Amazon::API::IAM](https://metacpan.org/pod/Amazon%3A%3AAPI%3A%3AIAM), [Amazon::API::STS](https://metacpan.org/pod/Amazon%3A%3AAPI%3A%3ASTS), and
[Amazon::Credentials](https://metacpan.org/pod/Amazon%3A%3ACredentials) are installed, calls `SimulatePrincipalPolicy`
using your current credentials to confirm your IAM identity has the
permissions required to build and deploy. See ["REQUIRED IAM PERMISSIONS"](#required-iam-permissions)
for the full list.

If the IAM modules are not installed, tool checks still run but permission
checking is skipped with a warning.

## check-env-file

    alr-builder check-env-file

Validates the project's configuration against this Lambda's requirements
(see ["CONFIGURATION"](#configuration)). Reads `lambda.env` if present - an absent
`lambda.env` is treated as "nothing configured yet", useful for seeing
the full set of required and defaulted values for a brand-new project -
and reports three groups:

- **MISSING (required)** - required values with no default that are
not set. `image.handler` (`HANDLER_CLASS`) and `trigger.type`
(`TRIGGER_TYPE`) are required for every trigger type. Each trigger type
adds its own required values: `trigger.bucket` (`BUCKET_NAME`) for
`s3-sqs` and `s3-direct`, `trigger.topic_name` (`TOPIC_NAME`) for
`sns`, and `trigger.listener_arn` (`LISTENER_ARN`) for `alb`.
- **Customized** - values present in `lambda.env` that differ from
their `lambda-mapping.yml` default, or have no default at all.
- **Using defaults** - values not set in `lambda.env`, and the
default that applies in their place.

Fields are scoped to the active `trigger.type` via `lambda-mapping.yml`'s
`applies_to`, so only the values relevant to your trigger are reported.
Exits non-zero if any required values are missing.

## generate-yaml

    alr-builder generate-yaml

Migrates an existing `lambda.env` to `lambda.yaml`. Requires
`lambda.env` to exist and `lambda.yaml` to not already exist - this is a
one-time migration step, not something to re-run once `lambda.yaml` is
your source of truth (see ["CONFIGURATION"](#configuration)).

Performs the same validation as `check-env-file` first; if any required
values are missing, no `lambda.yaml` is written and the missing fields
are reported instead. Otherwise, writes a minimal `lambda.yaml`
containing only values that differ from their defaults (plus any field
with no default) - fields matching their default are omitted, since
`Makefile.mk` applies the same defaults via `lambda-mapping.yml`.

# OPTIONS

- `--install-dir|-i` DIR

    Target directory for `install`. Defaults to the current working directory.

- `--config-file|-c` FILE

    Configuration file to read. Defaults to `lambda.env` (falling back to the
    `LAMBDA_ENV`/`LAMBDA_YAML` environment variables).

- `--profile|-p` NAME

    AWS named profile to use for this invocation. Sets `AWS_PROFILE` for the
    credential lookups performed by `check`.

- `--force|-f`

    Overwrite scaffold files during `install` that would otherwise be
    preserved by their manifest policy.

- `--log-level|-l` LEVEL

    Log verbosity. Accepts Log4perl level names: `trace`, `debug`, `info`
    (default), `warn`, `error`, `fatal`.

- `--help|-h`

    Display usage information.

# CONFIGURATION

Your Lambda's configuration - function name, memory, timeout, trigger
type, trigger details, and so on - lives in `lambda.env`, a flat
`KEY = value` file that `Makefile.mk` reads via `-include lambda.env`.
Every field has a corresponding entry in `lambda-mapping.yml` (installed
as part of this distribution), which defines each field's `env` name,
default, whether it is `required`, and which trigger types it
`applies_to`.

`lambda.env` can be managed in either of two ways:

- **Hand-written** - edit `lambda.env` directly. This is the
original, and still fully supported, workflow. Run `alr-builder
check-env-file` to verify it against `lambda-mapping.yml`'s requirements.
- **Generated from lambda.yaml** - write a `lambda.yaml` describing
only the values that matter for your Lambda; everything else comes from
`lambda-mapping.yml`'s defaults. `alr-builder` regenerates `lambda.env`
from `lambda.yaml` automatically whenever `lambda.yaml` is newer than
`lambda.env`, or when `lambda-mapping.yml`'s mapping version has changed
since `lambda.env` was last generated. A generated `lambda.env` begins
with a header noting it is generated; hand edits to it are overwritten
the next time `lambda.yaml` changes.

To move an existing `lambda.env` to the `lambda.yaml` workflow, run
`alr-builder generate-yaml` once.

## Trigger types

`trigger.type` (`TRIGGER_TYPE`) selects the event source and the
pipeline that provisions it:

- **s3-sqs** - S3 object events delivered through an SQS queue (with
a dead-letter queue and configurable reserved concurrency). The recommended
pattern for serialized, at-least-once processing.
- **s3-direct** - S3 bucket notifications invoking the Lambda directly.
- **eventbridge** - an EventBridge scheduled rule.
- **sns** - an SNS topic subscription.
- **alb** - an Application Load Balancer listener rule forwarding a
path to the Lambda (requires an existing ALB and HTTPS listener).

A Function URL with streaming responses is also available for any function
(see `lambda-function-url` and `test-streaming` in ["MAKEFILE TARGETS"](#makefile-targets));
it is independent of `TRIGGER_TYPE`.

## lambda.yaml structure

Fields common to every trigger type:

    image:
      repo: ...            # ECR repository / image name (REPO_NAME)
      handler: ...         # Perl handler class (HANDLER_CLASS) - required
    lambda:
      name: ...            # function name (FUNCTION_NAME)
      timeout: ...         # seconds (TIMEOUT)
      memory: ...          # MB (MEMORY)
      concurrency: ...     # reserved concurrency (CONCURRENCY)
    role:
      name: ...            # IAM role name (ROLE_NAME)
      profile: ...         # named policy profile (ROLE_PROFILE)
    log_retention: ...     # CloudWatch retention in days (LOG_RETENTION)
    platform_image: ...    # optional platform layer image (PLATFORM_IMAGE)
    overlay: ...           # optional overlay image name (OVERLAY)
    trigger:
      type: ...            # one of s3-sqs, s3-direct, eventbridge, sns, alb - required

Trigger-specific `trigger:` keys, by `type`:

    # s3-sqs
    trigger:
      type: s3-sqs
      bucket: ...          # source S3 bucket (BUCKET_NAME) - required
      prefix: ...          # key prefix filter (KEY_PREFIX)
      event: ...           # S3 event type (S3_EVENT)
      queue:
        name: ...                     # (QUEUE_NAME)
        batch_size: ...               # (BATCH_SIZE)
        visibility_timeout: ...       # seconds (VISIBILITY_TIMEOUT)
        retention: ...                # seconds (RETENTION)
        receive_count: ...            # max receives before DLQ (RECEIVE_COUNT)
        partial_batch_response: ...   # true/false (PARTIAL_BATCH_RESPONSE)
        dlq:
          name: ...          # DLQ name (DLQ_NAME)
          retention: ...     # seconds (DLQ_RETENTION)

    # s3-direct
    trigger:
      type: s3-direct
      bucket: ...          # source S3 bucket (BUCKET_NAME) - required
      prefix: ...          # key prefix filter (KEY_PREFIX)
      event: ...           # S3 event type (S3_EVENT)

    # eventbridge
    trigger:
      type: eventbridge
      schedule: ...        # schedule expression (SCHEDULE_EXPRESSION)
      rule_name: ...       # rule name (RULE_NAME)

    # sns
    trigger:
      type: sns
      topic_name: ...      # SNS topic name (TOPIC_NAME) - required

    # alb
    trigger:
      type: alb
      listener_arn: ...    # existing HTTPS listener ARN (LISTENER_ARN) - required
      path: ...            # path pattern to route (ALB_PATH)
      priority: ...        # listener-rule priority (RULE_PRIORITY)

Every field except the ones marked **required** may be omitted, in which
case `lambda-mapping.yml`'s default applies. See ["MAKEFILE TARGETS"](#makefile-targets) for
how `role.profile` is applied.

# WORKFLOW

The typical workflow for a new Lambda function:

1. **Scaffold the project**:

        alr-builder install --install-dir my-lambda
        cd my-lambda

2. **Verify your environment**:

        alr-builder check

3. **Implement your handler** - edit `LambdaHandler.pm` or create your own
handler module, and add its dependencies to your distribution's
`cpanfile`/`META.json`.
4. **Configure the Lambda** - set `TRIGGER_TYPE` and `HANDLER_CLASS` (both
required) plus any trigger-specific values, either by editing
`lambda.env` or by writing a `lambda.yaml` (see ["CONFIGURATION"](#configuration)).
5. **Build a CPAN distribution** - turn your handler into a standard CPAN
distribution and run `make dist` (or your equivalent) to produce a
tarball. `make image` resolves `DIST_TARBALL` to the most recent
`$(DIST_NAME)-*.tar.gz` in `$(BUILDER_HOME)`, where `DIST_NAME` comes
from that distribution's `META.json`.
6. **Deploy** - provision the image, role, function, log group, and the event
source for your trigger type in one step:

        make lambda-pipeline

7. **Test**:

        make invoke          # or: make test-streaming (Function URL)

8. **Deploy subsequent changes**:

        make update-function

9. **Tear down** when finished:

        make lambda-teardown

## Phase 1 - Build the container image

`make image` requires a CPAN distribution tarball
(`$(DIST_NAME)-*.tar.gz`) to already exist in `$(BUILDER_HOME)` - see
Workflow step 5.

The image is built in layers:

- **perl-lambda-base** - the runtime base image, containing the Perl
interpreter, the `bootstrap` entrypoint, the `plambda.pl` driver, and
all `Amazon::Lambda::Runtime` dependencies. The handler image is built
`FROM` this base.
- **platform (optional)** - a layer between the base and the handler,
for stable, infrequently-changing artifacts (data files, toolchains,
shared dependencies). Enabled by setting `PLATFORM_IMAGE` and providing a
`Dockerfile.platform`; see the `platform` target.
- **handler** - your distribution, installed on top with `cpm`.

The framework Dockerfile handles all of this. Build with:

    make image

The builder stage installs your distribution and its prerequisites with
`cpm` (resolving through `RESOLVER` if a DarkPAN is configured), then the
final stage copies the installed tree onto `${PLATFORM_IMAGE}` (default
`perl-lambda-base:latest`). The handler is selected at build time by class
name:

    ARG HANDLER_CLASS="LambdaHandler"
    ENV LAMBDA_MODULE=${HANDLER_CLASS}
    ENTRYPOINT ["/usr/local/bin/bootstrap"]

`HANDLER_CLASS` is required (the build errors without it) and is passed
automatically from `lambda.env`. `ENV LAMBDA_MODULE` tells `bootstrap`
which handler class to load.

To reinstall modules that are also under active development - overriding
the versions resolved from CPAN/DarkPAN - list them (one bare
`Module@version` per line) in a `requires.reinstall` file in the project
root. When present it is copied into the build context and reinstalled in
a dedicated layer. Because that layer is otherwise cached, change
`CACHE_BUST` (or the file's contents) to force it to re-run.

## Phase 2 - Provision function and event source

`make lambda-pipeline` is the single entry point. It:

1. builds the platform image first if `PLATFORM_IMAGE` is set and a
`Dockerfile.platform` is present;
2. dispatches on `TRIGGER_TYPE` to the matching per-type pipeline
(`lambda-sqs-pipeline`, `lambda-s3-pipeline`,
`lambda-eventbridge-pipeline`, `lambda-sns-pipeline`, or
`lambda-alb-pipeline`), each of which builds and pushes the image,
creates the IAM role and attaches policies, creates the function, applies
memory/timeout and the log-group retention policy, and wires the trigger;
3. builds and applies the `overlay` image last if `OVERLAY` is set.

Every step is idempotent and tracked by sentinel files under
`.cache/$(FUNCTION_NAME)`, so re-running skips work that is already done.

To deploy a code change:

    make update-function

This rebuilds the image, pushes to ECR using the image digest (never
`:latest`), and updates the function code - and, if `OVERLAY` is set,
rebuilds and re-applies the overlay.

## Phase 3 - Teardown

    make lambda-teardown

Dispatches on `TRIGGER_TYPE` to the matching teardown, removes the
overlay (if `OVERLAY` is set), and deletes the CloudWatch log group.
Shared resources are treated conservatively: an SNS topic is **not**
deleted by default (it may have other subscribers), and the platform ECR
repository must be removed manually (see `platform-teardown`).

## The policies files

Two mechanisms control the Lambda execution role's permissions:

**Managed policies** - the `policies` file (`POLICIES_FILE`) lists AWS
managed policy ARNs, one per line:

    # required - CloudWatch logging
    arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole

    # uncomment for SQS trigger
    # arn:aws:iam::aws:policy/service-role/AWSLambdaSQSQueueExecutionRole

    # uncomment for S3 read access
    # arn:aws:iam::aws:policy/AmazonS3ReadOnlyAccess

If `ROLE_PROFILE` is set instead, the managed policies come from that
profile's list in `profiles.yml`.

**Inline custom policies** - a `custom-policies.json`
(`CUSTOM_POLICIES_FILE`) document, if present, is applied as an inline
role policy. Use this to scope permissions to a specific bucket, queue, or
topic ARN.

Apply changes at any time with `make update-policies` (managed + inline),
or `make update-managed-policies` / `make update-inline-policies`
individually.

**Note:** receiving an event from a service does not automatically grant
your handler permission to call that service's APIs. An S3 trigger allows
Lambda to invoke your function - it does not allow your function to read
or write S3 objects. Add the appropriate managed policy ARN to `policies`,
or scope a specific resource in `custom-policies.json`, then re-run
`make update-policies`.

# MAKEFILE VARIABLES

For the per-trigger configuration values (queue settings, schedule, topic,
listener, and so on) see ["CONFIGURATION"](#configuration) and `lambda-mapping.yml`. The
variables below are tool-level or build-level and apply across trigger
types.

## Identity and image

- `HANDLER_CLASS`

    Perl handler **class** name (e.g. `LambdaHandler`), not a filename.
    Required - the build errors if unset.

- `TRIGGER_TYPE`

    Event source pattern: `s3-sqs`, `s3-direct`, `eventbridge`, `sns`, or
    `alb`. Required for `lambda-pipeline`/`lambda-teardown`.

- `REPO_NAME`

    ECR repository and local image name. Default: `perl-lambda`.

- `FUNCTION_NAME`

    Lambda function name. Default: `lambda-handler`.

- `ROLE_NAME`

    IAM execution role name. Default: `lambda-role`.

- `AWS_PROFILE`

    AWS profile. Default: `default`.

- `REGION`

    AWS region. Default: `us-east-1`.

- `AWS_ACCOUNT`

    AWS account ID. Resolved automatically via `alr-helper get-account` if
    not set. Set it explicitly to avoid the STS call:

        export AWS_ACCOUNT=$(alr-helper get-account)

- `BUILDER_HOME`

    Directory searched for the distribution tarball. Default: the current
    directory.

- `DIST_NAME`

    Distribution name used to match the tarball. Default: the basename of the
    current directory.

- `DIST_TARBALL`

    The tarball to build. Default: the highest-versioned
    `$(DIST_NAME)-*.tar.gz` in `$(BUILDER_HOME)`.

- `PAYLOAD`

    Payload file for `make invoke`. Default: `payload-sns.json`.

## Build

- `RESOLVER`

    DarkPAN resolver passed to `cpm` (e.g.
    `02packages,https://cpan.openbedrock.net/orepan2`). Default: unset (public
    CPAN).

- `PLATFORM_IMAGE`

    Platform layer image the handler image is built `FROM`. Default: the
    Dockerfile's own default, `perl-lambda-base:latest`.

- `OVERLAY`

    Overlay image name. When set, `lambda-pipeline`/`update-function` build
    and apply an overlay image after the handler image.

- `EXTRA_BUILD_PACKAGES`

    Extra Debian packages installed in the builder stage (for XS modules that
    need build-time libraries, e.g. `libssl-dev`).

- `EXTRA_RUNTIME_PACKAGES`

    Extra Debian packages for the runtime layer (for XS modules that need
    shared libraries at run time).

- `CACHE_BUST`

    Arbitrary value used to invalidate the `requires.reinstall` layer.

- `NOCACHE`

    Passed through to `docker build` (set to `--no-cache` to force a clean
    build).

## Function configuration and logging

- `MEMORY`

    Function memory in MB. Default: `128`.

- `TIMEOUT`

    Function timeout in seconds. Default: `30`.

- `CONCURRENCY`

    Reserved concurrency. Default: `1`.

- `LOG_RETENTION`

    CloudWatch log-group retention in days. Default: `1`.

## Policies

- `POLICIES_FILE`

    File of AWS managed policy ARNs. Default: `policies`.

- `CUSTOM_POLICIES_FILE`

    Inline role-policy document. Default: `custom-policies.json`.

- `ROLE_PROFILE`

    Named profile in `profiles.yml` whose managed policies are attached
    instead of those in `POLICIES_FILE`.

## Function URL / streaming

- `INVOKE_MODE`

    Lambda Function URL invoke mode. Default: `RESPONSE_STREAM`.

# MAKEFILE TARGETS

## Primary Targets

- `lambda-pipeline`

    Provision everything for the configured `TRIGGER_TYPE`: platform image
    (if applicable), handler image, ECR push, IAM role and policies, function,
    memory/timeout, log-group retention, the event-source wiring, and the
    overlay (if `OVERLAY` is set). This is the target to run - and to re-run
    after editing `lambda.yaml`/`lambda.env`.

- `lambda-teardown`

    Deprovision the function and its trigger-type infrastructure, remove the
    overlay (if set), and delete the log group.

- `lambda-function`

    Create (or update) just the Lambda function from the pushed image - a
    component of the pipelines.

- `update-function`

    Deploy a code change: rebuild the image, push to ECR by digest, update the
    function code, and re-apply the overlay if `OVERLAY` is set.

- `invoke`

    Invoke the function with `$(PAYLOAD)` and print the response.

- `lambda-configuration` / `update-lambda-configuration`

    Apply (or force re-apply) the function's memory and timeout from
    `lambda.env`. `lambda-configuration` also ensures the log group and its
    retention policy exist.

- `update-policies`

    Re-attach all IAM policies - managed and inline. See
    `update-managed-policies` and `update-inline-policies` for the halves.

- `clean`

    Remove local sentinel files. AWS resources are not affected.

## Per-trigger Pipelines

Each provisions the full stack for its trigger type and has a matching
teardown. `lambda-pipeline` dispatches to the right one based on
`TRIGGER_TYPE`; run one directly only if you want to bypass the dispatch.

    lambda-sqs-pipeline          / lambda-sqs-teardown
    lambda-s3-pipeline           / lambda-s3-teardown
    lambda-eventbridge-pipeline  / lambda-eventbridge-teardown
    lambda-sns-pipeline          / lambda-sns-teardown
    lambda-alb-pipeline          / lambda-alb-teardown

## Event Trigger and Function URL Targets

- `lambda-sqs-trigger`

    Creates the SQS queue and DLQ and attaches the queue as an event source. A
    component of `lambda-sqs-pipeline`.

- `lambda-s3-trigger`

    Configures S3 bucket notifications to invoke the Lambda on `S3_EVENT`
    events (used by `s3-direct`; `s3-sqs` routes S3 notifications to the
    queue instead).

- `lambda-sns-trigger`

    Subscribes the Lambda to the SNS topic (creating the topic and permission
    as needed).

- `lambda-eventbridge-trigger`

    Registers the Lambda as the target of the EventBridge rule.

- `enable-eventbridge-rule` / `disable-eventbridge-rule`

    Enables or disables the EventBridge rule without deleting infrastructure.

- `delete-eventbridge-rule`

    Removes targets and deletes the rule.

- `lambda-function-url`

    Creates a Lambda Function URL with `auth-type NONE` and
    `InvokeMode=$(INVOKE_MODE)`.

- `test-streaming`

    Invokes the Function URL with `curl -sN` to test streaming responses.

## Image Layer Targets

- `platform` / `platform-teardown`

    Build and push the platform layer image from `Dockerfile.platform`, then
    invalidate the handler-image sentinels so the next build picks it up.
    Teardown clears the sentinels; the ECR repository must be deleted
    manually.

- `overlay` / `overlay-teardown`

    Build an overlay image and update the Lambda function to it directly.
    Teardown deletes the overlay ECR repository and clears its sentinels.

- `log-group` / `log-group-teardown`

    Create the function's CloudWatch log group and set its retention policy
    (`LOG_RETENTION`); teardown deletes the log group. `log-group` is a
    dependency of `lambda-configuration`.

## Internal Targets

Called automatically as dependencies - you should not need to invoke these
directly:

`image` - builds the Docker image.
`tarball-validated` - verifies the tarball contains `HANDLER_CLASS`.
`ecr-repo` - creates the ECR repository (with lifecycle policy) if absent.
`deploy` - logs in to ECR and pushes the image.
`image-digest` - resolves the pushed image's digest.
`lambda-role` - creates the IAM execution role if absent.
`lambda-managed-policies` / `lambda-inline-policies` - attach managed and
inline policies.
`lambda-concurrency` - sets reserved concurrency via
`PutFunctionConcurrency`.
`lambda-sqs-response-types` - sets the SQS event source mapping's
`FunctionResponseTypes` from `PARTIAL_BATCH_RESPONSE`.
`policy-document` - generates the IAM assume-role trust policy JSON.
The image build also derives a `cpanfile` and Debian package list from the
distribution tarball on the fly.

# REQUIRED IAM PERMISSIONS

The `check` command verifies the following permissions via
`SimulatePrincipalPolicy`. They cover the core build-and-deploy path for
all trigger types.

### ECR

    ecr:CreateRepository         ecr:DescribeRepositories
    ecr:GetAuthorizationToken    ecr:BatchCheckLayerAvailability
    ecr:PutImage                 ecr:InitiateLayerUpload
    ecr:UploadLayerPart          ecr:CompleteLayerUpload
    ecr:PutLifecyclePolicy       ecr:GetLifecyclePolicy

### IAM

    iam:GetRole                  iam:CreateRole
    iam:AttachRolePolicy         iam:PassRole
    iam:ListAttachedRolePolicies

**Note:** `iam:PassRole` is frequently overlooked. Its absence produces
a confusing `InvalidParameterValueException` stating the role cannot be
assumed by Lambda even though the role exists and appears correct.

### Lambda

    lambda:GetFunction              lambda:CreateFunction
    lambda:UpdateFunctionCode       lambda:UpdateFunctionConfiguration
    lambda:GetFunctionConfiguration lambda:InvokeFunction
    lambda:CreateEventSourceMapping lambda:ListEventSourceMappings
    lambda:GetPolicy                lambda:AddPermission
    lambda:RemovePermission         lambda:CreateFunctionUrlConfig
    lambda:GetFunctionUrlConfig     lambda:DeleteFunctionUrlConfig

### SQS / SNS / S3 / EventBridge / STS

    sqs:ListQueues                  sqs:CreateQueue
    sns:ListTopics                  sns:CreateTopic
    sns:Subscribe                   sns:GetTopicAttributes
    s3:CreateBucket                 s3:ListBuckets
    s3:PutBucketNotificationConfiguration
    events:DescribeRule             events:PutRule
    events:PutTargets               events:RemoveTargets
    events:DeleteRule               events:EnableRule
    events:DisableRule
    sts:GetCallerIdentity

### Additional permissions (not verified by check)

Some features and teardown paths call APIs that `check` does not yet
simulate. You will need these in addition to the list above when the
corresponding feature is used:

- **CloudWatch Logs** (`log-group` / retention): `logs:CreateLogGroup`,
`logs:PutRetentionPolicy`, `logs:DescribeLogGroups`,
`logs:DeleteLogGroup`, `logs:DeleteRetentionPolicy`.
- **ALB triggers**: `elasticloadbalancing:*` for target groups and
listener rules (`CreateTargetGroup`, `RegisterTargets`, `CreateRule`,
`DescribeTargetGroups`, `DescribeRules`, and their `Delete`/`Deregister`
counterparts).
- **Inline custom policies** (`custom-policies.json`):
`iam:PutRolePolicy` (and `iam:DeleteRolePolicy` for teardown).
- **Reserved concurrency**: `lambda:PutFunctionConcurrency`.
- **Full lifecycle / teardown**: broader `sqs:*`, `sns:*`, and
`s3:*` operations (queue/subscription/notification deletion, attribute
reads) beyond the create-and-list actions above.

### Handler Runtime Permissions

`AWSLambdaBasicExecutionRole` covers CloudWatch logging only. Any AWS
APIs your handler calls directly require additional policies - via the
`policies` file (managed) or `custom-policies.json` (inline). For
example, a handler that reads S3 objects needs `AmazonS3ReadOnlyAccess` or
an equivalent scoped policy even if its trigger is an S3 event -
the trigger and the API access are governed by separate policies.

# OPTIONAL DEPENDENCIES

IAM permission checking in `check` requires:

- [Amazon::API::IAM](https://metacpan.org/pod/Amazon%3A%3AAPI%3A%3AIAM)
- [Amazon::API::STS](https://metacpan.org/pod/Amazon%3A%3AAPI%3A%3ASTS)
- [Amazon::Credentials](https://metacpan.org/pod/Amazon%3A%3ACredentials)

These are not hard dependencies - the tool is fully functional without
them, but `check` will only verify system tools.

# SEE ALSO

[Amazon::Lambda::Runtime](https://metacpan.org/pod/Amazon%3A%3ALambda%3A%3ARuntime) - the runtime library your handler inherits from

[Amazon::Credentials](https://metacpan.org/pod/Amazon%3A%3ACredentials) - credential provider used for IAM permission checking

[Amazon::API::IAM](https://metacpan.org/pod/Amazon%3A%3AAPI%3A%3AIAM), [Amazon::API::STS](https://metacpan.org/pod/Amazon%3A%3AAPI%3A%3ASTS) - AWS API clients used by `check`

# AUTHOR

Rob Lauer - <rlauer@treasurersbriefcase.com>

# LICENSE

(c) Copyright 2019-2026 Robert C. Lauer. All rights reserved. This
module is free software. It may be used, redistributed and/or modified
under the same terms as Perl itself.
