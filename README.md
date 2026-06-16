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
  * [lambda.yaml structure](#lambdayaml-structure)
* [WORKFLOW](#workflow)
  * [Phase 1 - Build the container image](#phase-1---build-the-container-image)
  * [Phase 2 - Deploy and create the Lambda function](#phase-2---deploy-and-create-the-lambda-function)
  * [Phase 3 - Configure event triggers](#phase-3---configure-event-triggers)
  * [The policies File](#the-policies-file)
* [MAKEFILE VARIABLES](#makefile-variables)
* [MAKEFILE TARGETS](#makefile-targets)
  * [Primary Targets](#primary-targets)
  * [Event Trigger Targets](#event-trigger-targets)
  * [Internal Targets](#internal-targets)
* [REQUIRED IAM PERMISSIONS](#required-iam-permissions)
    * [ECR](#ecr)
    * [IAM](#iam)
    * [Lambda](#lambda)
    * [SQS / SNS / S3 / EventBridge / STS](#sqs--sns--s3--eventbridge--sts)
    * [Handler Runtime Permissions](#handler-runtime-permissions)
* [OPTIONAL DEPENDENCIES](#optional-dependencies)
* [SEE ALSO](#see-also)
* [AUTHOR](#author)
* [LICENSE](#license)
# NAME

Amazon::Lambda::Runtime::Builder - Project scaffolding and environment
checker for Perl Lambda container images

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
environment, and documenting the full build and deploy workflow.

It provides four commands via the `alr-builder` CLI:

- **install** - copies the project scaffold (Dockerfile, Makefile,
handler template, cpanfile, and test fixtures) into a target directory.
- **check** - verifies that required system tools are present on
your `PATH` and, if the optional IAM modules are installed, confirms
that your AWS credentials have sufficient permissions to build and deploy.
- **check-env-file** - validates `lambda.env` (or `lambda.yaml`, if
present) against this Lambda's configuration requirements, reporting
missing required values, customized values, and values using defaults.
- **generate-yaml** - migrates an existing, hand-written `lambda.env`
to a minimal `lambda.yaml`, the starting point for the generate-on-demand
workflow described in ["CONFIGURATION"](#configuration).

# COMMANDS

## install

    alr-builder install [--install-dir DIR]

Copies the project scaffold from the distribution's `share/` directory
into the target directory (defaults to the current working directory).
Creates the directory if it does not exist.

The following files are installed:

- `Dockerfile` - multi-stage build using `debian:trixie-slim`.
The builder stage installs Perl, build tools, and your `cpanfile`
dependencies via Carton. The runtime stage is a minimal image containing
only the Perl interpreter, runtime libraries, and your handler.
- `LambdaHandler.pm.in` - handler template with stub
implementations for SQS, SNS, S3, and EventBridge events, plus a
streaming response example for Function URL invocations. Rename or copy
this file and customize it for your Lambda.
- `Makefile` (installed as `Makefile.build`, renamed on install)
- provides targets for the complete build and deployment workflow. See
["WORKFLOW"](#workflow) and ["MAKEFILE TARGETS"](#makefile-targets).
- `cpanfile` - starting point for your Perl dependencies. Add
modules here.
- Test fixture makefiles - `sqs-test.mk`, `sns-test.mk`,
`s3-test.mk`, `eventbridge-test.mk`, `streaming-test.mk` - provide
targets for creating and testing each event source trigger.
- `payload.json`, `payload-sns.json` - sample invocation payloads
for `make invoke` and `make test-sns`.
- `ecr-create-repo.mk` - creates the ECR repository if it does
not already exist.
- `policies` - IAM managed policy ARNs to attach to the Lambda
execution role. Add one ARN per line; lines beginning with `#` are
comments.

## check

    alr-builder check

Verifies that your environment is ready to build and deploy. Checks two
things:

**Required system tools** - `docker` and `make` must be on your
`PATH`. `curl` is checked as an optional tool. Missing required
tools are reported as errors.

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
not set. `image.handler` (`HANDLER_CLASS`) is required for every trigger
type; `trigger.bucket` (`BUCKET_NAME`) is additionally required for the
`s3-sqs` trigger type.
- **Customized** - values present in `lambda.env` that differ from
their `lambda-mapping.yml` default, or have no default at all.
- **Using defaults** - values not set in `lambda.env`, and the
default that applies in their place.

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
with no default, such as `trigger.bucket`/`trigger.prefix`) - fields
matching their default are omitted, since `Makefile.mk` applies the same
defaults via `lambda-mapping.yml`.

# OPTIONS

- `--install-dir|-i` DIR

    Target directory for `install`. Defaults to the current working directory.

- `--log-level|-l` LEVEL

    Log verbosity. Accepts Log4perl level names: `trace`, `debug`, `info`
    (default), `warn`, `error`, `fatal`.

- `--help|-h`

    Display usage information.

# CONFIGURATION

Your Lambda's configuration - function name, memory, timeout, trigger
details, and so on - lives in `lambda.env`, a flat `KEY = value` file
that `Makefile.mk` reads via `-include lambda.env`. Every field has a
corresponding entry in `lambda-mapping.yml` (installed as part of this
distribution), which also defines each field's default.

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

## lambda.yaml structure

For the `s3-sqs` trigger type (currently the only supported type):

    image:
      repo: ...            # ECR repository name (REPO_NAME)
      handler: ...         # Perl handler class (HANDLER_CLASS) - required
    lambda:
      name: ...            # function name (FUNCTION_NAME)
      timeout: ...         # seconds (TIMEOUT)
      memory: ...          # MB (MEMORY)
      concurrency: ...     # reserved concurrency (CONCURRENCY)
    role:
      name: ...            # IAM role name (ROLE_NAME)
      profile: ...         # named policy profile (ROLE_PROFILE)
    trigger:
      type: s3-sqs
      bucket: ...          # source S3 bucket (BUCKET_NAME) - required
      prefix: ...          # key prefix filter (KEY_PREFIX)
      event: ...           # S3 event type (S3_EVENT)
      queue:
        name: ...                     # SQS queue name (QUEUE_NAME)
        batch_size: ...               # (BATCH_SIZE)
        visibility_timeout: ...       # seconds (VISIBILITY_TIMEOUT)
        retention: ...                # seconds (RETENTION)
        receive_count: ...            # max receives before DLQ (RECEIVE_COUNT)
        partial_batch_response: ...   # true/false (PARTIAL_BATCH_RESPONSE)
        dlq:
          name: ...          # DLQ name (DLQ_NAME)
          retention: ...     # seconds (DLQ_RETENTION)

`image.handler` is required for every trigger type; `trigger.bucket` is
additionally required for `s3-sqs`. Every other field may be omitted, in
which case `lambda-mapping.yml`'s default applies. See ["MAKEFILE
TARGETS"](#makefile-targets) for how `role.profile` is applied.

# WORKFLOW

The typical workflow for a new Lambda function:

1. **Scaffold the project**:

        alr-builder install --install-dir my-lambda
        cd my-lambda

2. **Verify your environment**:

        alr-builder check

3. **Implement your handler** - edit `LambdaHandler.pm.in` or create your
own handler module. Add dependencies to `cpanfile`.
4. **Build a CPAN distribution** - `install` provides a template handler
module (`LambdaHandler.pm.in`); turn it into a standard CPAN
distribution (with its own `META.json`/`Makefile.PL` or equivalent)
using whatever tooling you prefer, then run `make dist` to produce a
distribution tarball. `make image` resolves `DIST_TARBALL` to the most
recent `$(DIST_NAME)-*.tar.gz` in `$(BUILDER_HOME)`, where `DIST_NAME`
comes from that distribution's `META.json`.
5. **First-time deployment** - builds the image, pushes to ECR, creates the
IAM role and Lambda function:

        make lambda-function

6. **Test**:

        make invoke

7. **Deploy subsequent changes**:

        make update-function

## Phase 1 - Build the container image

`make image` requires a CPAN distribution tarball
(`$(DIST_NAME)-*.tar.gz`) to already exist in `$(BUILDER_HOME)` -
see Workflow step 4.

Lambda runs your handler inside an OCI-compliant container image. The
image must contain a Perl interpreter, your CPAN dependencies,
`Amazon::Lambda::Runtime`, the `bootstrap` entrypoint, the `plambda.pl`
driver, and your handler module.

The installed Dockerfile handles all of this. Build with:

    make image

The key Dockerfile directives that wire everything together:

    ARG LAMBDA_MODULE=LambdaHandler.pm
    COPY ${LAMBDA_MODULE} /usr/src/app/local/lib/perl5

    ENV PERL5LIB=/usr/src/app/local/lib/perl5
    ENV LAMBDA_MODULE=${LAMBDA_MODULE}

    ENTRYPOINT ["/usr/local/bin/bootstrap"]

`ENV LAMBDA_MODULE` tells `bootstrap` which handler to load.
Set `LAMBDA_MODULE` at build time to use a different handler module:

    make image LAMBDA_MODULE=MyHandler.pm

## Phase 2 - Deploy and create the Lambda function

Once the image is built it must be pushed to ECR and the Lambda function
created or updated.

For a first-time deployment, a single target runs the full dependency
chain automatically:

    make lambda-function

This runs: `ecr-repo` => `deploy` => `lambda-role` => `lambda-policies`
&#x3d;> `lambda-function`. Each step is idempotent - re-running is always safe.
Sentinel files track completed steps so `make` skips what already exists.

To deploy a code change:

    make update-function

This rebuilds the image, pushes to ECR using the image digest (never
`:latest`), and updates the Lambda function code.

## Phase 3 - Configure event triggers

The installed Makefile already includes all five trigger makefiles, so
all trigger targets are available immediately. Use whichever targets
apply to your Lambda:

    make lambda-sqs-trigger QUEUE_NAME=my-queue
    make lambda-s3-trigger  BUCKET_NAME=my-bucket
    make lambda-eventbridge-trigger
    make lambda-function-url
    make test-streaming

See ["MAKEFILE TARGETS"](#makefile-targets) for the full list of targets provided by each
trigger makefile and the variables that control their behavior.

## The policies File

The `policies` file controls which IAM managed policies are attached
to the Lambda execution role. Add one policy ARN per line:

    # required - CloudWatch logging
    arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole

    # uncomment for SQS trigger
    # arn:aws:iam::aws:policy/service-role/AWSLambdaSQSQueueExecutionRole

    # uncomment for S3 read access
    # arn:aws:iam::aws:policy/AmazonS3ReadOnlyAccess

Apply changes at any time:

    make update-policies

**Note:** receiving an event from a service does not automatically grant
your handler permission to call that service's APIs. An S3 trigger allows
Lambda to invoke your function - it does not allow your function to read
or write S3 objects. For broad access, add or uncomment the appropriate
managed policy ARN in the `policies` file and run `make update-policies`.
For access to a specific resource - a particular bucket, queue, or topic -
create a custom IAM policy that scopes the permissions to that resource ARN
and attach it to the execution role (`ROLE_NAME`) via the AWS console or
CLI, then add its ARN to the `policies` file so `make update-policies`
keeps it attached on subsequent deployments.

# MAKEFILE VARIABLES

For `s3-sqs` configuration (function name, memory, timeout, queue
settings, and so on), see ["CONFIGURATION"](#configuration) and `lambda-mapping.yml`.
The variables below are either tool-level (apply regardless of trigger
type) or specific to trigger types not yet covered by `lambda.yaml`.

- `AWS_PROFILE`

    AWS profile. Default: `default`

- `REGION`

    AWS region. Default: `us-east-1`

- `PERL_LAMBDA`

    Docker image name (local). Default: `perl-lambda`

- `LAMBDA_MODULE`

    Your handler module filename. Default: `LambdaHandler.pm`

- `PAYLOAD`

    Payload file for `make invoke`. Default: `payload.json`

- `AWS_ACCOUNT`

    AWS account ID. Resolved automatically via `alr-helper get-account`
    if not set. Set it explicitly to avoid the STS call:

        export AWS_ACCOUNT=$(alr-helper get-account)

- `RULE_NAME`

    EventBridge rule name. Default: `lambda-handler-test`

- `SCHEDULE_EXPRESSION`

    EventBridge schedule. Default: `rate(1 minute)`

- `INVOKE_MODE`

    Lambda Function URL invoke mode. Default: `RESPONSE_STREAM`

# MAKEFILE TARGETS

## Primary Targets

- `lambda-function`

    First-time deployment. Runs the full dependency chain: ECR repository,
    IAM role, policies, image build, push, and function creation. Run once
    per function.

- `update-function`

    Deploy a code change. Rebuilds the image, pushes to ECR, and updates the
    Lambda function code.

- `invoke`

    Test the function with `$(PAYLOAD)` and print the response.

- `clean`

    Remove local sentinel files. AWS resources are not affected.

- `update-policies`

    Re-attach IAM policies to the execution role. If `ROLE_PROFILE` is set
    (in `lambda.env`/`lambda.yaml`), attaches the policies listed for that
    profile in `profiles.yml`; otherwise, attaches the policies listed in
    the `policies` file.

- `lambda-configuration`

    Updates the function's memory and timeout from `lambda.env` (`MEMORY`,
    `TIMEOUT`) via `UpdateFunctionConfiguration`. Useful for applying a
    configuration-only change without rebuilding the image.

## Event Trigger Targets

- `lambda-sqs-trigger`

    Creates an SQS queue (`QUEUE_NAME`) and attaches it as an event source.
    Requires `AWSLambdaSQSQueueExecutionRole` in the `policies` file. A
    component of `lambda-sqs-pipeline`; run that instead unless you
    specifically need just the queue/event-source step.

- `lambda-sqs-pipeline`

    Runs the full `s3-sqs` trigger setup: creates the SQS queue and DLQ,
    configures the S3-to-SQS event source mapping, sets reserved concurrency
    (`CONCURRENCY`), applies `lambda-configuration` (`MEMORY`/`TIMEOUT`),
    and sets the event source mapping's `FunctionResponseTypes` according to
    `PARTIAL_BATCH_RESPONSE`. This is the target to run - or re-run after
    editing `lambda.yaml`/`lambda.env` - for `s3-sqs` projects.

- `lambda-s3-trigger`

    Configures S3 bucket notifications to invoke the Lambda on `S3_EVENT`
    events.

- `lambda-eventbridge-trigger`

    Registers the Lambda as the target of an EventBridge scheduled rule.

- `enable-eventbridge-rule` / `disable-eventbridge-rule`

    Enables or disables the EventBridge rule without deleting infrastructure.
    Use `disable-eventbridge-rule` after testing to stop scheduled invocations.

- `delete-eventbridge-rule`

    Removes targets and deletes the rule. Targets must be removed before the
    rule can be deleted.

- `lambda-function-url`

    Creates a Lambda Function URL with `auth-type NONE` and
    `InvokeMode=$(INVOKE_MODE)`.

- `test-streaming`

    Invokes the Function URL with `curl -sN` to test streaming responses.

## Internal Targets

Called automatically as dependencies - you should not need to invoke
these directly:

`image` - builds the Docker image.
`ecr-repo` - creates the ECR repository if it does not exist.
`deploy` - logs in to ECR and pushes the image using the image digest.
`lambda-role` - creates the IAM execution role if it does not exist.
`lambda-policies` - attaches policies to the execution role, either from
`profiles.yml` (if `ROLE_PROFILE` is set) or the `policies` file.
`lambda-concurrency` - sets reserved concurrency (`CONCURRENCY`) via
`PutFunctionConcurrency`.
`lambda-sqs-response-types` - sets the SQS event source mapping's
`FunctionResponseTypes` according to `PARTIAL_BATCH_RESPONSE`.
`policy-document` - generates the IAM assume-role trust policy JSON.

# REQUIRED IAM PERMISSIONS

The `check` command verifies these permissions via
`SimulatePrincipalPolicy`. You will need them to run the full build and
deploy workflow.

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

### Handler Runtime Permissions

`AWSLambdaBasicExecutionRole` covers CloudWatch logging only. Any AWS
APIs your handler calls directly require additional policies in the
`policies` file. For example, a handler that reads S3 objects needs
`AmazonS3ReadOnlyAccess` even if its trigger is an S3 event notification
\- the trigger and the API access are governed by separate policies.

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
