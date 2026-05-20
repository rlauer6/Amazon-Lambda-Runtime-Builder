# Table of Contents

* [NAME](#name)
* [SYNOPSIS](#synopsis)
* [DESCRIPTION](#description)
* [COMMANDS](#commands)
  * [install](#install)
  * [check](#check)
* [OPTIONS](#options)
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

# DESCRIPTION

`Amazon::Lambda::Runtime::Builder` is the companion deployment tool for
[Amazon::Lambda::Runtime](https://metacpan.org/pod/Amazon%3A%3ALambda%3A%3ARuntime). It handles everything outside of the Perl
runtime itself: scaffolding a new project directory, verifying your build
environment, and documenting the full build and deploy workflow.

It provides two commands via the `alr-builder` CLI:

- **install** - copies the project scaffold (Dockerfile, Makefile,
handler template, cpanfile, and test fixtures) into a target directory.
- **check** - verifies that required system tools are present on
your `PATH` and, if the optional IAM modules are installed, confirms
that your AWS credentials have sufficient permissions to build and deploy.

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

# OPTIONS

- `--install-dir|-i` DIR

    Target directory for `install`. Defaults to the current working directory.

- `--log-level|-l` LEVEL

    Log verbosity. Accepts Log4perl level names: `trace`, `debug`, `info`
    (default), `warn`, `error`, `fatal`.

- `--help|-h`

    Display usage information.

# WORKFLOW

The typical workflow for a new Lambda function:

1. **Scaffold the project**:

        alr-builder install --install-dir my-lambda
        cd my-lambda

2. **Verify your environment**:

        alr-builder check

3. **Implement your handler** - edit `LambdaHandler.pm.in` or create your
own handler module. Add dependencies to `cpanfile`.
4. **First-time deployment** - builds the image, pushes to ECR, creates the
IAM role and Lambda function:

        make lambda-function

5. **Test**:

        make invoke

6. **Deploy subsequent changes**:

        make update-function

## Phase 1 - Build the container image

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

Set these in your environment or pass as `make` arguments:

- `AWS_PROFILE`

    AWS profile. Default: `default`

- `REGION`

    AWS region. Default: `us-east-1`

- `REPO_NAME`

    ECR repository name. Default: `perl-lambda`

- `FUNCTION_NAME`

    Lambda function name. Default: `lambda-handler`

- `ROLE_NAME`

    IAM execution role name. Default: `lambda-role`

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

- `TIMEOUT`

    Lambda function timeout in seconds. Default: `30`

- `QUEUE_NAME`

    SQS queue name. Default: `lambda-runtime`

- `BATCH_SIZE`

    SQS messages per invocation. Default: `10`

- `BUCKET_NAME`

    S3 bucket for `make lambda-s3-trigger`. Default: `my-bucket`

- `S3_EVENT`

    S3 event type. Default: `s3:ObjectCreated:*`

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

- `update-policies`

    Re-attach policies after editing the `policies` file.

- `clean`

    Remove local sentinel files. AWS resources are not affected.

## Event Trigger Targets

- `lambda-sqs-trigger`

    Creates an SQS queue (`QUEUE_NAME`) and attaches it as an event source.
    Requires `AWSLambdaSQSQueueExecutionRole` in the `policies` file.

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
`lambda-policies` - attaches all policies in the `policies` file.
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
