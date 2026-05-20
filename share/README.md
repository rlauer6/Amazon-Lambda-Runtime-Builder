# Amazon Lambda Runtime Builder Quick Start

The purpose of this README is to help you get started using
the 
[Amazon-Lambda-Runtime-Builder (ALRB)](https://github.com/rlauer6/Amazon-Lambda-Runtime-Builder.git)
project. The project produces the `alr-builder` script that is used to scaffold
an [Amazon Lambda Runtime Builder](https://github.com/rlauer6/Amazon-Lambda-Runtime-Builder.git) project used to build a docker image suitable
for use with the [Perl
Lambda Runtime](https://github.com/rlauer6/Amazon-Lambda-Runtime.git)
framework. These projects work together to help you build Lambdas that
are based on Perl handlers.

| Project | Purpose |
| ------- | ------- |
| Amazon-Lambda-Runtime | Provides the components that implement the Amazon Lambda Runtime protocol | 
| Amazon-Lambda-Runtime-Builder | Provides a script for scaffolding a project that will build your container image which implements your Lambda application. |

# Prerequisites

| Requirement | Purpose
| `cpm` or `cpanm` | Install `Amazon::Lambda::Runtime::Builder` | 
| `make` | Runs the recipes that build and configure you Lambda environment | 
| `docker` | Required to build your container image that implements your Lambda handler |
| AWS account | An AWS account and credentials with the required permissions |

# Architecture & Workflow

You can think of the ALRB as layer 2 of a two layer build system for
your Lambdas.

## Layer 1

Layer 1 is your application code. The Lambda handler that you will
create. By convention your handler should be encapsulated in a class
named `LambdaHandler`. The method name must be `handler`. Your Layer1
is responsible for producing a CPAN distribution tarball.  That
tarball is input to Layer 2. You can include whatever other classes
and artifacts necessary to implement your application inside that
tarball.

## Layer 2

Layer 2 consists of the scaffolded `builder`.  When you run
`alr-builder` it creates a `Makefile` that implements recipes for
buliding the necessary components and environment to execute your
Lambda. Depending on your application this may include:

* a Docker image containing your Lambda handler and application code
* IAM roles and policies granting the necessary permissions
* SQS queues 
* S3 buckets
* Lambda triggers
* EventBridge rules

## The Workflow

1. Install the builder.
   ```
   cpanm Amazon::Lambda::Runtime::Builder
   ```
2. Scaffold a new build project.
   ```
   mkdir -p ~/My-App/builder
   cd ~/My-App && alr-builder -i builder install
   ```
3. Verify you environment is ready to build and run a Lambda
   ```
   alr-builder check
   ```
4. Create your application and tarball.
5. Build your Docker image and provision the Lambda environment.
   ```
   cd builder
   make lambda-function
   ```
6. Test your Lambda
   ```
   make invoke
   ```
7. Iterate on your application if necessary.
   ```
   make update-function
   ```

See `perldoc Amazon::Lambda::Runtime::Builder` for more details.
