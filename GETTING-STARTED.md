# Amazon::Lambda::Runtime::Builder — A Getting-Started Guide

> **Complete draft.** §1–§14 and Appendices A–B. Framework notes for the source are tracked at the end.

---

# Part I — Getting Started

## 1. Introduction

Amazon Web Services runs Lambda functions on a fixed set of managed
language runtimes — Java, Python, Node.js, .NET, and Ruby. Perl is not
one of them, and never has been. That doesn't mean you can't run Perl
on Lambda; it means AWS gives you the lower-level building blocks — a
runtime API you talk to through your own bootstrap, and a
container-image format to ship your interpreter in — and leaves the
assembly to you. In practice that assembly is considerable: a
bootstrap that speaks Lambda's runtime API, a base image carrying a
Perl interpreter and your dependencies, an ECR repository to hold it,
an execution role with the right policies, the function itself, and
the plumbing that connects an event source to your
code. Amazon::Lambda::Runtime::Builder (ALRB) is the toolchain that
does all of that for you. You write a Perl handler; ALRB packages it
as a container image and deploys it as a fully-wired Lambda function —
so that shipping a Perl Lambda is about as turnkey as shipping a
Python one, without giving up the interpreter, the modules, and the
idioms you already reach for.

What sets ALRB apart is less *what* it does than *how* it does
it. Most attempts to put a language on Lambda take one of two shapes:
a runtime layer that gets you an interpreter and stops there, or a
large deployment framework — AWS SAM, the Serverless Framework, the
CDK, Terraform — that manages your infrastructure through its own
template language and a CloudFormation-style state model you're
expected to adopt wholesale. ALRB is neither. It is a thin,
transparent build-and-deploy pipeline assembled from tools a Perl
systems programmer already trusts: `make` for orchestration, `cpm` for
dependency resolution, Docker for the image, and a set of small Perl
wrappers over the AWS APIs. Every step is an ordinary `make` target
you can read, run in isolation, and debug; the only state is sentinel
files on disk, so re-running is always safe and nothing hides behind a
framework you have to reverse-engineer when something breaks.

That thinness carries through to the artifact itself. A Lambda's
memory footprint — and the bill and the cold-start time that track it
— is largely the weight of the runtime and libraries loaded before
your own code even runs. A Python function stays small until it
imports `boto3` and a handful of other packages, at which point its
baseline can grow substantially. ALRB is built to keep the container
lean: the base image carries only the Perl interpreter, the runtime
driver, and your handler's actual
dependencies. Amazon::Lambda::Runtime asks nothing of a heavyweight
AWS SDK — it does not require Amazon::API at all — and when your
handler does need to call AWS, you can reach for a library like
Amazon::API that instantiates only the single service client a call
needs, rather than a monolithic SDK such as `boto3` or Paws whose
footprint reflects far more of the AWS surface than any one function
uses.

If you are a Perl developer, there is a practical question underneath
all of this: why bring Lambda to Perl at all, rather than pick up one
of the out of the box runtimes for the occasion? The answer has
nothing to do with language rivalry. Lambda is a genuinely powerful
tool — event-driven, scaled automatically from zero, billed only for
the milliseconds you use, and wired directly into S3, SQS, SNS,
EventBridge, and the load balancer — and that power is entirely
independent of the language the handler is written in. What you bring
to it is already in Perl: your expertise, the CPAN modules you depend
on, and very often substantial bodies of working code you have no
reason to rewrite.

That last point is where ALRB earns its place. A great deal of
production Perl lives as long-running daemons and scheduled jobs: a
process that polls a queue, a watcher that reacts to files landing in
a directory, a cron task that wakes on a timer. Each of those has a
direct analogue in Lambda's event model — an SQS trigger, an S3
trigger, an EventBridge schedule — which means a daemon that once
required an always-on server can become an event-triggered function
that costs nothing while idle and scales on its own under load. ALRB
is what makes that migration approachable: an existing script becomes
a handler, a module you already ship comes along unchanged, and a
daemon you have maintained for years becomes a lean serverless
replacement rather than a rewrite. The aim of this guide is to give
you the shortest credible path from that starting point — a working
piece of Perl — to a deployed, event-triggered function, and to keep
the machinery transparent enough that you stay in control of it.

A note on how to read what follows. This guide is in two parts. Part I
is a single, unbroken path: follow it start to finish and you will end
with one Perl function built, deployed, invoked, and — so you can
experiment without leaving anything running — torn back down. It
assumes you'd rather *see it work first* and understand the details
afterward, so it moves quickly and leaves most of the "why" to Part
II. Part II is the reverse: a section-by-section treatment of the
handler contract, configuration, the trigger types, the three-layer
image, dependencies, IAM, and day-to-day operation — written to be
read in order once and consulted piecemeal thereafter. Two appendices
close the guide: a rebuild matrix that answers "I changed *this* —
what do I run?", and a note on two companion projects that make
packaging a distribution smoother.

Nothing here asks you to take the framework on faith. By the end of
Part I you'll have deployed a real function to your own AWS account,
and every step you ran will be an ordinary `make` target you could
have read first. Before any of that, two short sections: a page of
vocabulary so the commands aren't opaque, and then the handful of
tools and credentials to have in place before you begin.

## 2. How it works, in one page

A Perl Lambda is a container image. When an event arrives, Lambda
starts a fresh container from your image — or reuses a warm one from a
recent invocation — and expects something inside it to ask, "is there
work for me?" That something is the *bootstrap*: a small program that
speaks Lambda's runtime API, polling for the next event, handing it to
your code, returning the result, and looping. You don't write the
bootstrap. Amazon::Lambda::Runtime (ALR) provides it, along with the
driver (`plambda.pl`) that loads your handler and the base image
(`perl-lambda-base`) that carries a Perl interpreter and the runtime's
own dependencies. Your responsibility stops at the handler; everything
beneath it is machinery ALR already ships.

Your *handler* is an ordinary Perl class. ALR inspects each incoming event, works out what kind it is, and calls the matching method on your handler — `on_message` for an SQS message, `on_s3_event` for an S3 notification, and so on — so you write logic only for the events you care about and ignore the rest. In configuration this class is named by `HANDLER_CLASS`, and the container loads it by that name at startup. That is the whole contract for now; Section 6 covers it in full.

Nothing invokes a Lambda on its own; something has to deliver an event, and that something is the *trigger* (or event source). It is the serverless replacement for the loop a daemon used to run itself: a process that polled a queue becomes an SQS trigger, a watcher waiting on files becomes an S3 trigger, a cron job becomes an EventBridge schedule, a topic fan-out becomes SNS, and an HTTP path on a load balancer becomes ALB. You choose one with a single value, `TRIGGER_TYPE`, and ALRB wires the AWS side of it to your function. Section 8 takes the five types one at a time.

Between "a container image on your laptop" and "a running function wired to an event source" sits a short list of AWS resources, and it helps to recognize their names before you watch them scroll past. The image has to live somewhere Lambda can pull it from — that is **ECR**, the Elastic Container Registry. The function runs under an *execution role* — an **IAM** identity that declares what the function is permitted to do — to which *policies* are attached. There is the **Lambda function** itself, and a **CloudWatch log group** where its output lands. ALRB creates each of these for you and you rarely touch them directly, but when something misbehaves it is usually one of them, so knowing them by name is worth the paragraph.

All of that provisioning is driven by `make`. Each step — build the image, push it to ECR, create the role, attach policies, create the function, wire the trigger — is an ordinary target, and `make lambda-pipeline` walks the whole chain in order. What makes that chain safe to re-run is a single idea worth holding onto: every step records its completion as a *sentinel* file on disk, and a step counts as done until its sentinel is removed. Re-running the pipeline skips whatever is already finished, so there is no penalty for running it twice; and when you deliberately want to redo a step, you invalidate its sentinel and `make` rebuilds exactly that step and whatever depends on it. That one mechanism — *done until invalidated* — is what makes the framework safe to poke at, and it is the same mechanism Section 9 leans on when the question becomes "I changed one thing; what has to be rebuilt?"

With that vocabulary in hand — image and bootstrap, handler, trigger, the AWS resources, and the `make`-and-sentinel pipeline — the commands in the sections ahead should read as steps you understand rather than incantations. Next: the handful of tools and credentials to have in place before you begin.

## 3. Before you begin

ALRB orchestrates other tools rather than replacing them, so a short list of things needs to be in place before your first build. None of it is exotic; most of it you likely already have.

**A Perl toolchain with `cpm`.** You need a Perl you can install modules into, and the `cpm` installer (`App::cpm`). `cpm` is what the framework uses inside the image to resolve dependencies, and it's the smoothest way to install the framework itself. If you can already install from CPAN, you're set; if `cpm` isn't present, install it the way you install anything else (`cpanm App::cpm`, or fetch the standalone script).

**Docker.** The handler is a container image, so a working Docker (a running daemon and a `docker` you can invoke) is non-negotiable. ALRB shells out to `docker build` and `docker push`; it doesn't wrap or hide it.

**`make`.** GNU `make` drives the whole pipeline. Any reasonably current version is fine.

**AWS credentials the tools can find.** This is the one prerequisite worth a second sentence for a reader who lives more in Perl than in AWS. ALRB doesn't take a key and secret as arguments; it looks for credentials the way every AWS tool does, in a fixed order — a shared credentials file (`~/.aws/credentials`, optionally selected by profile), then environment variables (`AWS_ACCESS_KEY_ID` and friends), then, when running on AWS infrastructure, an instance or container role. Any one of those is enough. If you've used the `aws` CLI from this machine, you already have the first; if not, the shortest path is to create the shared file with an access key for an IAM user, or export the environment variables for the shell you'll build from. You'll also want a default region (ALRB assumes `us-east-1` if you don't set one). What those credentials are *permitted to do* is a separate question — the build-and-deploy path needs a specific set of permissions — and Section 11 covers that in full; for now, credentials that resolve are enough to proceed, and the check below will tell you whether they carry the permissions you'll need.

**Install the framework:**

```
cpm install -g Amazon::Lambda::Runtime::Builder
```

(or `cpanm Amazon::Lambda::Runtime::Builder` — either works). This gives you the two CLIs the guide uses, `alr-builder` and `alr-helper`, and the shared build machinery they read at deploy time.

**Optionally, install the permission-check modules.** ALRB can confirm your credentials actually carry the permissions to build and deploy, but that check is only active if three modules are present — `Amazon::API::IAM`, `Amazon::API::STS`, and `Amazon::Credentials`. They aren't hard dependencies (the framework runs fine without them), so install them only if you want the check:

```
cpm install -g Amazon::API::IAM Amazon::API::STS Amazon::Credentials
```

**Confirm your environment:**

```
alr-builder check
```

This verifies the required tools are on your `PATH` (`docker` and `make`; `curl` is checked as optional) and, if the three modules above are installed, simulates the IAM permissions the full workflow needs against your current identity and reports anything missing. Run it now, before you invest time in a build: a green result means the rest of the guide should proceed without environment surprises, and a red one points at exactly the tool or permission to fix first. If the permission modules aren't installed, `check` still validates your tools and simply notes that it can't assess IAM — you can proceed, but you'll discover any permission gaps later, mid-deploy, rather than up front.

With tools, credentials, and the framework in place, you're ready to build something. The next section is the one to follow without skipping: scaffold, write a handler, configure, build, deploy, invoke, and tear down — one unbroken pass.

## 4. Your first Lambda

This is the section to follow straight through. By the end you'll have a Perl function deployed to your own account, invoked, confirmed in the logs, and torn back down. It uses the `eventbridge` trigger — the serverless form of a cron job — because it's the fewest moving parts: no bucket, no queue, no topic, just a schedule.

### 4.1 Scaffold the project

Create a directory and scaffold into it:

```
alr-builder install --install-dir hello-lambda
cd hello-lambda
```

Four files land, and it's worth knowing what each is before you touch them:

- **`LambdaHandler.pm`** — a handler template with worked examples for every event type. In the next step you'll strip it down to just the one you need.
- **`policies`** — the AWS managed-policy ARNs attached to your function's execution role. The default entry grants CloudWatch logging, which is all this function needs.
- **`Makefile.builder`** — the build engine. You don't edit it; it pulls in the framework's machinery from the installed distribution.
- **`project.mk`** — the file your own `Makefile` includes to expose the `make` targets you'll run. (If you already had a `project.mk`, ALRB appends its section and leaves a `.bak` backup.)

Notably absent: no Dockerfile, no per-trigger makefiles. Those live in the framework and are read at build time — there's nothing project-local to maintain.

### 4.2 Write a trivial handler

The scaffolded `LambdaHandler.pm` handles SQS, SNS, S3, and EventBridge to show you the shape of each. For a first function, delete all of that and keep the smallest thing that proves the loop works — an EventBridge handler that logs a greeting:

```perl
package Event::EventBridge;

use strict;
use warnings;

use parent qw(Amazon::Lambda::Runtime::Event::EventBridge);

sub on_event {
  my ( $self, $detail_type, $detail, $event ) = @_;

  $self->get_logger->info(
    sprintf 'hello from a Perl Lambda! detail-type=%s source=%s',
    $detail_type, $event->{source} );

  return;
}

package LambdaHandler;

use strict;
use warnings;

use parent qw(Amazon::Lambda::Runtime);

use Amazon::Lambda::Runtime::Event qw(:all);

__PACKAGE__->register_event_handler( $EVENT_EVENTBRIDGE => 'Event::EventBridge' );

1;
```

Two things are happening here. `LambdaHandler` is your handler *class* — the one you'll name in configuration — and it inherits the runtime and registers a mapping: "when an EventBridge event arrives, dispatch it to `Event::EventBridge`." That second class inherits the EventBridge base and implements `on_event`, which receives the event's detail-type, its detail payload, and the raw event. The runtime does the routing; you write only the method for the event you care about. That's the entire handler contract, and Section 6 covers the rest of it.

Keeping the handler to a single event type isn't just tidiness — every `use` in this file becomes a dependency baked into the image, so a focused handler is a leaner container. That thread runs through the whole framework and gets its own section (9).

### 4.3 Configure it

Your Lambda's configuration lives in `lambda.env`, but the friendlier way to start is a small `lambda.yaml` that lists only what you care about; ALRB fills in every other value from its defaults. Create `lambda.yaml`:

```yaml
image:
  handler: LambdaHandler
lambda:
  name: hello-lambda
trigger:
  type: eventbridge
  schedule: rate(1 minute)
```

Only two values are strictly required — `handler` (which handler class the container loads) and `trigger.type` — and everything else here is just to make the demo concrete: a function name, and a one-minute schedule so you don't wait long to see it fire. You can confirm what's set versus defaulted at any time:

```
alr-builder check-env-file
```

Section 7 covers the `lambda.yaml`/`lambda.env` model in full; for now this is enough.

### 4.4 Build a distribution tarball

ALRB deploys a *standard CPAN distribution* — it does not care how you produce one. The contract is simple: build a distribution whose primary module is your handler class (so `LambdaHandler` installs as `lib/LambdaHandler.pm`), and leave the resulting `*.tar.gz` in the project directory. ALRB picks up the newest tarball whose name matches the distribution and reads its `META.json` to learn the distribution name and the prerequisites to install into the image.

Use whatever you already use — `ExtUtils::MakeMaker` and `make dist`, `Dist::Zilla`, `Minilla`, or anything else that emits a conventional tarball. If you'd like a packaging path that dovetails with ALRB (and shares its minimal-dependency lineage), see **Appendix B**.

Once built, you should have something like `hello-lambda-1.0.0.tar.gz` sitting alongside `lambda.yaml`.

### 4.5 Deploy and invoke

One command provisions everything for the configured trigger type:

```
make lambda-pipeline
```

Watch it work through the chain from Section 2: it builds the image (installing your distribution with `cpm`), pushes it to ECR, creates the execution role and attaches the policy, creates the function, sets its log-group retention, and wires the EventBridge schedule to invoke it. Every step announces itself, and every step is idempotent — if anything fails partway, fix it and run the same command again; it resumes where it left off.

To invoke the function directly, without waiting for the schedule:

```
make invoke
```

`make invoke` sends the function a sample event matching your trigger type — for `eventbridge`, an EventBridge-shaped event that reaches `on_event` — so there's nothing to hand-write. (If you want to send your own, drop a `payload-eventbridge.json` in the project or pass `PAYLOAD=your-file.json`.)

A clean return with no error is your first success: the function is live and your handler ran. The greeting itself goes to the function's logs rather than the invoke response, so to *see* it, look at the CloudWatch log group `/aws/lambda/hello-lambda` — in the AWS console, or with `aws logs tail /aws/lambda/hello-lambda --follow`. And because you wired a one-minute schedule, the function is now also invoking itself; give it a minute and you'll see the same line appear on its own. That is the trigger doing its job — the cron daemon you didn't have to run.

### 4.6 Tear it down

Because the schedule is live, leave nothing running once you've seen it work:

```
make lambda-teardown
```

This disables and deletes the EventBridge rule, deletes the function, detaches policies and deletes the role, removes the ECR repository, and deletes the log group — the exact inverse of the pipeline. You can rebuild the whole thing at any time by running `make lambda-pipeline` again.

That's the full loop: scaffold, handle, configure, build, deploy, invoke, tear down. The next section walks back through what just happened, so the machinery stops being a black box.

## 5. What just happened

`make lambda-pipeline` ran a dozen steps in a few seconds and scrolled most of them past you. None of it was magic, and none of it was hidden — every line was an ordinary `make` target doing one small, inspectable thing. Here's the same sequence at walking pace, because understanding it once is what turns the pipeline from something you trust into something you can *drive*.

1. **The image was built.** First the framework validated your tarball actually contains the handler you named (`lib/LambdaHandler.pm`) — a fast failure now beats a broken container later. Then it read your distribution's `META.json`, generated a `cpanfile` from its prerequisites on the fly, and ran `docker build`: starting from the `perl-lambda-base` image (interpreter, bootstrap, runtime driver already in place), it installed your distribution and its dependencies with `cpm` on top. Your handler's `use` lines are exactly what got installed here — the whole of what makes this image bigger than the base.

2. **The image was pushed to ECR.** The registry repository was created if it didn't already exist, Docker authenticated to it, and the image was pushed. From this point Lambda has somewhere to pull your code from. Note that the framework tracks the image by its *digest*, not by a `:latest` tag — so when you later update the function, it points at the exact image you just built, with no ambiguity about which version is running.

3. **The execution role was created.** A Lambda runs as an IAM identity, and that identity has to (a) be assumable by the Lambda service and (b) carry the permissions your function needs. ALRB created the role with the right trust relationship, then attached the managed policies listed in your `policies` file — here, just the CloudWatch logging permission. (If you'd supplied a `custom-policies.json`, its inline permissions would have gone on here too.) This is the single most common place first deployments stumble, almost always over a missing `iam:PassRole`; Section 11 covers the permission model and Section 13 the specific failure.

4. **The function was created.** With an image to run and a role to run as, the function itself came into being — pointed at the pushed image by digest, with the memory, timeout, and reserved concurrency from your configuration (all defaulted, since you didn't set them).

5. **The log group was created.** Its CloudWatch log group was created explicitly, with the retention you configured (the default is one day), rather than left to appear implicitly on first invocation. That's why `aws logs tail` had something to point at immediately, and why old logs won't accumulate cost indefinitely.

6. **The trigger was wired.** Only now, with a working function in place, did the EventBridge side get built: the schedule rule was created, your function was registered as its target, and — the easily-missed piece — EventBridge was granted permission to invoke your function. Receiving an event and being *allowed* to deliver it are two separate grants, and the pipeline handled both.

Notice the shape of that sequence: the function is built completely before anything is allowed to invoke it. That's the function-versus-trigger split from Section 2 made concrete — steps 1–5 build a function you could invoke by hand (as `make invoke` did), and step 6 is the event source that invokes it for you. The two halves are independent, which is why you can change a trigger later without rebuilding the function, or invoke the function directly to debug it in isolation from its trigger.

And this is where the "safe to re-run" promise pays off. Each of those steps recorded its completion as a sentinel file under `.cache/hello-lambda/`. Run `make lambda-pipeline` again right now and almost nothing happens — every sentinel is present, so every step reports itself already done. That's not a special "resume" mode; it's the same *done-until-invalidated* rule every time. It means a half-finished deploy is never a wedged deploy: fix whatever failed, run the identical command, and the pipeline picks up exactly where it stopped. It also means you're never guessing about state — the sentinels *are* the state, sitting in a directory you can list, and any single step is a target you can force by removing its sentinel. Which is precisely the lever Section 9 reaches for when the question becomes "I changed one thing — what has to rebuild?"

That's the whole pipeline, demystified. From here the guide stops moving in a straight line: Part II takes the pieces you just watched — the handler, the configuration, the triggers, the image, the permissions — one at a time, in depth. If you only wanted a working Perl Lambda, you already have the recipe. If you want to *understand* it, read on.

---

# Part II — Going Deeper

## 6. The handler contract

In Section 4 you wrote a handler class, registered one event type, and implemented one method. This section is the whole of what you were participating in — how an event finds its way to your code, every method you can implement, and what the runtime does with what you return. It's reference more than narrative; read it once and come back to it.

**How an event reaches your method.** When Lambda invokes your container, the runtime's loop pulls the event, and calls the `handler` method on your class. The base `handler` — the one you inherit from `Amazon::Lambda::Runtime` — does three things: it *detects the source* of the raw event, looks up the handler class you *registered* for that source, and instantiates it to *process* the event, which unwraps it and calls the specific `on_*` method for each record. Detection is structural, not configured: an SQS or S3 event carries `Records` with an `eventSource`; SNS carries `Records` with an `EventSource`; an EventBridge event has a `detail-type`; an ALB request has `requestContext.elb`. You never write that detection — you register interest and implement the method.

**Registration.** Your handler class inherits the runtime and maps event sources to the classes that handle them:

```perl
package MyHandler;
use parent qw(Amazon::Lambda::Runtime);
use Amazon::Lambda::Runtime::Event qw(:all);

__PACKAGE__->register_event_handler( $EVENT_SQS         => 'Event::SQS' );
__PACKAGE__->register_event_handler( $EVENT_EVENTBRIDGE => 'Event::EventBridge' );
```

The `$EVENT_*` constants (`$EVENT_SQS`, `$EVENT_SNS`, `$EVENT_S3`, `$EVENT_EVENTBRIDGE`, `$EVENT_ALB`) name the sources; the second argument names *your* class that handles each. Those classes inherit the matching `Amazon::Lambda::Runtime::Event::*` base and override the `on_*` method. Register only the sources you care about; anything unregistered still falls back to the runtime's own base class, which logs and returns an `unhandled` marker rather than erroring.

**The methods, by event type.** Each base class does the unwrapping and hands your method exactly what it needs:

- **SQS** — `on_message($body, $record)`. The runtime decodes each message body from JSON when it can, transparently unwraps an SNS-to-SQS envelope so you get the inner message, and silently drops S3's `s3:TestEvent` probe. So `$body` is usually a ready-to-use data structure, not a raw string; `$record` is the untouched SQS record if you need metadata.

- **SNS** — `on_notification($message, $sns, $record)`. `$message` is the decoded notification payload, `$sns` is the SNS envelope (`TopicArn`, `Subject`, `Message`), and `$record` is the raw record.

- **S3** — `on_s3_event($record)` catches every object event, and each `$record` carries the bucket and object under `$record->{s3}`. If you want finer granularity, the base also dispatches by operation to `on_object_created`, `on_object_removed`, `on_object_restored`, `on_object_tagged`, and `on_lifecycle_expiration` — each receiving `($record)` and, unless you override it, delegating to `on_s3_event`. (S3 notifications wrapped in SNS are unwrapped for you.)

- **EventBridge** — `on_event($detail_type, $detail, $event)`, as in Section 4: the rule's detail-type, its detail payload, and the whole event.

- **ALB** — `on_request($method, $path, $params, $event)`. The base parses the HTTP method and path, decodes a form-encoded body (base64-decoding first when ALB flags it) into `$params`, and expects you to return an ALB-shaped response — for which the base provides a helper so you don't hand-assemble the `statusCode`/`headers`/`body` structure. Note the scaffolded `LambdaHandler.pm` ships stubs for SQS, SNS, S3, and EventBridge but *not* ALB; the runtime fully supports it, so an ALB handler is one you write from this contract rather than edit from an example.

**What you return.** The runtime inspects your handler's return value and does one of four things: if it *dies*, the exception is caught, logged, and reported to Lambda as an invocation error; if it returns a *string*, that becomes the invocation response; if it returns *undef*, the runtime assumes you've already sent the response yourself and does nothing; and if it returns a *code reference*, that's treated as a streaming response. In practice the `on_*` methods return nothing, and the base `process` returns a small `{"status":"ok"}` JSON string on your behalf — which is exactly the response you saw come back from `make invoke` in Section 4, while your logged greeting went to CloudWatch.

**Streaming (Function URL).** Streaming is the one case that bypasses the registry. If your top-level `handler` returns a code reference, the runtime opens a streaming response and calls your reference with a writer:

```perl
sub handler {
  my ( $self, $event, $context ) = @_;

  return sub {
    my ($writer) = @_;
    $writer->write('{"chunk":1}');
    $writer->write('{"chunk":2}');
    $writer->close;
  };
}
```

Because this lives in `handler` itself, a handler that streams for Function URL invocations but dispatches normally for everything else overrides `handler`, returns the code reference when the event looks like a Function URL request, and otherwise defers to the inherited dispatch — which is precisely the shape of the scaffolded template.

**What every handler has.** Inside any `on_*` method, `$self->get_logger` returns the runtime's `Log::Log4perl` logger (output goes to CloudWatch; verbosity follows the `LOG_LEVEL` environment variable, defaulting to info), and `$self->get_context` returns the invocation's `Amazon::Lambda::Runtime::Context`. The raw event and its records remain available through `get_event` and `get_records` if you need to reach past what your method was handed.

**Bringing existing code in.** This contract is deliberately thin because the point is that your handler method is a *place to call code you already have*, not a place to rewrite it. The mapping from a daemon or job to a handler is usually direct: the body of a queue-polling loop becomes `on_message`; a routine that processes a dropped file becomes `on_s3_event`; the `main` of a cron script becomes `on_event`. The modules you `use` today come along unchanged — you install them into the image as ordinary dependencies (Section 10) and call them exactly as you do now. Two habits carry over from long-running processes and matter here for the same reason they always did: put expensive setup — a database handle, a client object, a loaded config — at file scope or behind a memoized accessor rather than inside the `on_*` method, so a warm container reuses it across invocations instead of rebuilding it each time (the scaffold's memoized S3 client is the pattern); and keep the handler's own logic idempotent, since an event source may deliver the same event more than once. What you are really doing when you "port" a daemon to Lambda is deleting its loop and its process-management scaffolding — the runtime is now the loop — and keeping the part that did the work.

## 7. Configuration

Everything about a function that isn't its code — its name, memory, timeout, trigger type, and the trigger's details — is configuration, and all of it resolves to one flat file the build reads: `lambda.env`, a plain list of `KEY = value` lines that the Makefiles pull in. You can write that file by hand, and for a long time that was the only way. But hand-maintaining two dozen `KEY = value` lines, most of them left at their defaults, is tedious and easy to get subtly wrong, so ALRB offers a second, layered model on top of it. Understanding both — and the small schema file that ties them together — is the whole of this section.

**The mapping.** `lambda-mapping.yml`, installed with the framework, is the schema that defines every configuration field exactly once. Each entry records four things: the `env` variable the Makefiles read (e.g. `MEMORY`), the `yaml` path it corresponds to (`lambda.memory`), its default if any, whether it's `required`, and — importantly — which trigger types it `applies_to`. That last field is what lets the tooling talk about only the settings relevant to *your* trigger: a queue's visibility timeout is meaningful for `s3-sqs` and silently irrelevant for `eventbridge`, and the mapping encodes that rather than leaving you to know it. The mapping also carries a version number, which matters for regeneration below.

**Two ways to manage it.** You choose per project:

*Hand-written `lambda.env`.* Edit the flat file directly. This is still fully supported, and if there's no `lambda.yaml` in the project, ALRB treats `lambda.env` as authoritative and never touches it. Validate it against the mapping's requirements with `alr-builder check-env-file`.

*Generated from `lambda.yaml`.* Write a small structured `lambda.yaml` describing only the values that matter for your function; everything else comes from the mapping's defaults. This is the model Section 4 used, and the one to prefer — a five-line `lambda.yaml` is far easier to read and reason about than a `lambda.env` padded out with defaults.

**How generation works.** When `lambda.yaml` is present, ALRB keeps `lambda.env` in sync with it automatically — the regeneration check runs at the start of *every* `alr-builder` invocation, so by the time the Makefiles read `lambda.env` it is already current. Regeneration happens when any of three things is true: `lambda.env` doesn't exist yet, `lambda.yaml` is newer than `lambda.env`, or the mapping's version has changed since `lambda.env` was last generated (its version is stamped into the file's header). When it regenerates, ALRB walks the mapping, filters to the fields that apply to your `trigger.type`, pulls each value from `lambda.yaml` or falls back to the mapping default, and writes `lambda.env` with a header noting that it's generated and should not be hand-edited. If `lambda.yaml` omits a field the mapping marks required, regeneration refuses — it warns and leaves the existing file alone rather than emit a broken one. And the escape hatch is deliberate and stated in that header: delete `lambda.yaml`, and `lambda.env` becomes a hand-editable file again.

The consequence worth internalizing: with a `lambda.yaml` in the project, `lambda.env` is a *build artifact*, not a source file. Don't edit it — your edits are overwritten the next time `lambda.yaml` changes. Edit `lambda.yaml`, or remove it to take manual control.

**Checking configuration.** `alr-builder check-env-file` reads whatever you have (a `lambda.yaml`, a `lambda.env`, or neither) and reports against the mapping, scoped to your trigger type. It sorts every applicable field into three groups — *missing* required values with no default, values you've *customized* away from the default, and values *using defaults* — so you can see at a glance what you've set, what you've inherited, and what you still owe. Running it against a brand-new project with nothing configured is a useful way to see the full set of required and defaulted fields for a given trigger before you write anything. Beyond presence, it also applies a few per-trigger sanity checks and warns on values that are individually valid but collectively suspect — an `alb` listener ARN that doesn't look like an ELBv2 ARN, or an `s3-sqs` visibility timeout set below the six-times-the-function-timeout floor that keeps a message from being redelivered while it's still being processed. It exits non-zero if anything required is missing, so it slots naturally into a check before deploy.

**Migrating an existing `lambda.env`.** If you have a hand-written `lambda.env` and want to move to the `lambda.yaml` model, `alr-builder generate-yaml` does the one-time conversion: it validates the `lambda.env` first (refusing, with a list, if required values are missing), then writes a minimal `lambda.yaml` containing only the values that differ from their defaults. It won't clobber an existing `lambda.yaml` — remove that first if you mean to regenerate. From that point forward the generate-on-demand flow above takes over, and `lambda.env` becomes the artifact.

Which trigger types exist, and the specific fields each one needs in `lambda.yaml`, is the subject of the next section; the consolidated field-by-field schema lives in the reference at the end.

## 8. Trigger types

A trigger is the event source that invokes your function — the serverless replacement for the loop a daemon used to run itself. You select one with `trigger.type`, and `make lambda-pipeline` provisions it. Every trigger sits on the same foundation: the pipeline builds the image, pushes it to ECR, creates the execution role and attaches policies, creates the function, and sets its configuration and log-group retention — and then adds the event source specific to the type. `lambda-pipeline` simply dispatches to the matching per-type pipeline based on `trigger.type`; you can run that pipeline directly, but you rarely need to.

Teardown follows the same shape in reverse and is deliberately conservative about shared and stateful resources. Every `*-teardown` removes the trigger wiring and the function, role, and ECR repository — but it leaves your data and anything that might be shared: an S3 bucket is never deleted (it holds objects), an SNS topic is left in place (it may have other subscribers), and an ALB is never touched (you brought your own). What each teardown removes is noted per type below.

The five types, roughly in order of how much they ask of you:

**`eventbridge` — the scheduled job.** The replacement for cron. You give it a schedule and it invokes your function on that cadence; your handler implements `on_event`.

```yaml
image:
  handler: MyHandler
trigger:
  type: eventbridge
  schedule: rate(1 hour)     # or a cron() expression; default rate(1 day)
```

The pipeline creates the schedule rule (enabled by default), grants EventBridge permission to invoke the function, and registers the function as the rule's target. Beyond deploy, `enable-eventbridge-rule` and `disable-eventbridge-rule` pause and resume it without tearing anything down, and `delete-eventbridge-rule` removes just the rule. Teardown disables and deletes the rule, then removes the function, role, and repository.

**`s3-direct` — the file watcher, unbuffered.** The replacement for a process watching a directory, when you want the object event delivered straight to your function. Your handler implements `on_s3_event` (or the per-operation hooks from Section 6).

```yaml
image:
  handler: MyHandler
trigger:
  type: s3-direct
  bucket: my-input-bucket        # required
  prefix: incoming/              # optional key filter
  event: 's3:ObjectCreated:*'    # default
```

The pipeline creates the bucket if it doesn't already exist, grants S3 permission to invoke the function, and configures the bucket notification to call the function directly on matching events. Teardown removes the notification and the invoke permission and deletes the function, role, and repository — but leaves the bucket and its contents.

**`s3-sqs` — the file watcher, durable.** The same S3 trigger with a queue between the bucket and the function, and the pattern to reach for when the work matters: a queue-polling worker with buffering, retry/redrive, a dead-letter queue, and serialized processing. S3 notifications land in an SQS queue; the queue drives the function; failures that exceed the receive count move to a DLQ. Your handler implements `on_message` (Section 6 unwraps the S3 record inside the SQS body for you).

```yaml
image:
  handler: MyHandler
lambda:
  concurrency: 1                 # serialized processing; default 1
trigger:
  type: s3-sqs
  bucket: my-input-bucket        # required
  queue:
    name: my-work-queue          # default lambda-runtime
    visibility_timeout: 360      # default; keep it >= 6x the function timeout
    receive_count: 3             # deliveries before a message goes to the DLQ
    dlq:
      name: my-work-queue-dlq    # default: <queue>-dlq
```

The pipeline creates the queue and its dead-letter queue, sets the redrive policy from `receive_count`, grants S3 permission to send to the queue, points the bucket notification at the queue, and creates the event-source mapping that drives the function — pinned to your reserved concurrency (the default of 1 gives you strictly serial processing, which is what makes this a safe replacement for a single-threaded worker). Setting `partial_batch_response: true` enables `ReportBatchItemFailures` on the mapping, so a handler can fail individual records without redriving the whole batch. The visibility-timeout floor `check-env-file` warns about (Section 7) lives here — a message must stay invisible at least as long as your function might take to process it. Teardown removes the bucket notification, deletes both queues, and removes the function, role, and repository; the bucket is left alone.

**`sns` — the broadcast consumer.** The replacement for a process reacting to a published notification, and the natural fit for fan-out, where one event should reach several independent consumers. Your handler implements `on_notification`.

```yaml
image:
  handler: MyHandler
trigger:
  type: sns
  topic_name: my-topic           # required
```

The pipeline creates the topic (creation is idempotent, so an existing topic is reused), grants SNS permission to invoke the function, and subscribes the function to the topic. Teardown unsubscribes the function and removes the function, role, and repository — but pointedly does *not* delete the topic, since other subscribers may depend on it. If you truly own the topic and want it gone, remove it yourself.

**`alb` — the HTTP endpoint.** The replacement for a small web service or CGI/`mod_perl` handler — an HTTP path served by a function instead of a running web server. This is the one type that expects infrastructure you already have: an Application Load Balancer with an HTTPS listener, whose ARN you supply. Your handler implements `on_request` (Section 6), and note the scaffold ships no ALB stub, so you write that handler from the contract rather than editing an example.

```yaml
image:
  handler: MyHandler
trigger:
  type: alb
  listener_arn: arn:aws:elasticloadbalancing:...:listener/app/...  # required
  path: /report                  # default /build
  priority: 10                   # listener-rule priority; default 10
```

The pipeline grants the load balancer permission to invoke the function, creates a Lambda target group and registers the function into it, and adds a listener rule that routes the given path to that target group on your existing listener. Teardown removes the listener rule, deregisters and deletes the target group, removes the invoke permission, and deletes the function, role, and repository — leaving your ALB and its listener untouched. (Two ALB specifics that bite people — the auto-generated `*.elb.amazonaws.com` name has no HTTPS certificate, so a real deployment needs a custom domain, and the response `statusCode` must be a JSON integer — are covered in Troubleshooting.)

A note that spans all five: the Function URL streaming path from Section 6 is independent of `trigger.type`. Any function can expose a streaming HTTP endpoint via `lambda-function-url` regardless of which of these triggers (if any) it also carries.

## 9. The three-layer image: controlling size, content, and rebuilds

This is the section that pays off a claim from the introduction — that ALRB gives you real control over what ends up in your container and what it costs to change. That control comes from a single structural idea: the image is built in *layers*, each one holding things that change at a different rate, so a change to fast-moving code never forces you to rebuild slow, expensive content. Understanding the layers is half of it; the other half is knowing, when you change something, exactly what rebuilds and how to force a rebuild when you need one. That "what and when to rebuild" question is the spine of this section.

### 9.1 The three layers

Your deployed image is a stack of three layers, from the bottom up:

```
  ┌────────────────────────────────────────────────┐
  │  handler image           rebuilds every change  │   your distribution
  ├────────────────────────────────────────────────┤
  │  platform image (opt.)   rebuilds rarely         │   Dockerfile.platform
  ├────────────────────────────────────────────────┤
  │  perl-lambda-base        prebuilt, never local   │   interpreter + runtime
  └────────────────────────────────────────────────┘
```

**`perl-lambda-base`** is the foundation: a prebuilt image carrying the Perl interpreter, the `bootstrap` entrypoint, the `plambda.pl` driver, and all of `Amazon::Lambda::Runtime`'s own dependencies. You never build it per project — it's the stable floor every Perl Lambda stands on.

**The platform image** is an optional middle layer, built *from* `perl-lambda-base`, for artifacts that change far less often than your handler but are yours rather than the runtime's: a large CPAN dependency, a data file, a shared toolchain, a system library. It's built from a `Dockerfile.platform` you author and is entirely opt-in (9.5).

**The handler image** is the top: the framework's own Dockerfile, built *from* whichever image is beneath it (the base, or your platform layer if you have one), adding only your distribution's installed module tree. Internally this happens in two stages — a `debian:trixie-slim` builder stage installs your distribution and its prerequisites with `cpm`, and the final stage copies just that installed tree onto the layer beneath — so the build tools never ship in the deployed image.

The organizing principle is the whole point: *put each thing in the layer that changes at its rate*. Your handler code changes constantly and rebuilds a thin top layer in seconds; a heavy dependency you touch twice a year lives in the platform layer and is rebuilt only when you actually change it; the runtime itself never rebuilds at all. That is how the container stays lean and how iteration stays fast — the two usually trade off against each other, and layering is what buys you both.

### 9.2 The rebuild model

There are two caches between you and a rebuilt image, and they answer two different questions. Keeping them straight is what makes the rest of this section predictable rather than mysterious.

The first is ALRB's own **sentinel** layer, which answers *does a build step run at all?* Every step records completion as a read-only file under `.cache/<function-name>/`, and the image build is an ordinary `make` target with ordinary dependencies:

```
                 ┌──► cpanfile ──────────┐
DIST_TARBALL ────┤                       ├──► image ──► deploy ──► image-digest ──► lambda-function ──► lambda-configuration
                 └──► tarball-validated ──┘
```

Because `image` depends on your distribution tarball (and on the `cpanfile` derived from its `META.json`), building a *new* tarball is what naturally invalidates the image and everything downstream of it — push, digest, function update. Build the same tarball twice and the sentinel is already present, so nothing rebuilds. This is why the normal development loop is simply "rebuild your distribution, run `make lambda-pipeline`" — the new tarball pulls the rest of the chain along behind it.

The second is **Docker's own layer cache**, which answers *once `docker build` runs, which layers inside it rebuild?* The Dockerfile is ordered so that stable things sit below volatile ones: the base OS packages, then the `cpm` install of your `cpanfile` dependencies (kept warm across builds by a build cache mount, so unchanged dependencies aren't reinstalled), then the install of your distribution tarball, then the reinstall layer (9.4), then the copy onto the layer beneath. A change high in that order rebuilds only from that point up.

The practical consequence: to rebuild because your *code* changed, you don't do anything special — a new tarball drives it. To rebuild the *same* tarball anyway — because something outside the tarball changed, or you want to force a clean build — you either invalidate a sentinel (the `make` level) or bust Docker's layer cache (the Docker level). Those are the levers of the next two subsections.

### 9.3 Forcing rebuilds: cache busting

Two variables reach the Docker layer cache, one surgical and one blunt:

**`CACHE_BUST`** — the surgical one. Setting it to any new value invalidates the reinstall layer (9.4) and everything after it, while leaving the expensive dependency install below untouched. This is the lever for "a module I depend on was republished under the same version, and I need the image to pick it up" — the situation where nothing in your tarball changed but the resolved contents did.

```
make image CACHE_BUST=$(date +%s)
```

**`NOCACHE`** — the sledgehammer. Set it to `--no-cache` and `docker build` ignores its layer cache entirely, rebuilding every layer from the base OS up. Reach for it when you suspect the cache itself is stale or wrong, and accept that it's slow.

```
make image NOCACHE=--no-cache
```

**Removing a sentinel** operates one level up — it forces `docker build` to *run* again, though the build may still hit Docker's layer cache unless paired with one of the above:

```
rm .cache/<function-name>/image && make image
```

### 9.4 `requires.reinstall`

The reinstall layer exists for a specific, common situation: you depend on a module that *you* are also actively developing, and the version resolved from CPAN or your DarkPAN isn't the one you want baked into the image. List such modules — one bare `Module@version` per line — in a `requires.reinstall` file in your project root:

```
My::Module::Under::Development@1.2.3
Another::WIP::Dist@0.9.0
```

When that file is present, ALRB copies it into the build context and the Dockerfile reinstalls exactly those modules with `cpm --reinstall`, on top of whatever was already resolved, in a dedicated layer near the top of the image. Because that layer is otherwise Docker-cached, changing a version string in the file naturally busts it — but if you need to re-run the reinstall *without* changing the version (you rebuilt the same version of your in-development module and want it picked up again), that's exactly what `CACHE_BUST` from 9.3 is for. The two work together: the file says *what* to reinstall, `CACHE_BUST` forces *when*.

### 9.5 The platform layer in practice

Reach for a platform layer when something in your handler image is both slow to build and slow to change — a large XS dependency, a bundled dataset, a system library — and you're tired of paying for it on every handler rebuild. Move it into the middle layer and it's built once and reused until you actually change it.

Two things enable it: set `PLATFORM_IMAGE` (to the image name or ECR repository the platform layer will occupy), and author a `Dockerfile.platform` in your project root that builds `FROM perl-lambda-base` and adds the stable artifacts. Then:

```
make platform
```

builds and pushes the platform image — and, importantly, clears the handler-image sentinels (`image`, `deploy`, `image-digest`, `lambda-function`, `lambda-configuration`) so the next `make lambda-pipeline` rebuilds your handler *on top of* the new platform. You don't usually run `make platform` by hand, though: `lambda-pipeline` builds the platform first whenever `PLATFORM_IMAGE` is set and a `Dockerfile.platform` is present, so the layer is kept current as part of a normal deploy. The platform image is itself rebuilt only when `Dockerfile.platform` changes.

`platform-teardown` clears the platform sentinels but deliberately leaves the ECR repository in place — a platform image is often shared across functions, so removing it is a manual, considered act.

### 9.6 The overlay

The overlay is the other end of the spectrum from the platform layer. Both let you reuse a handler and add artifacts to it, but they differ on where the artifacts attach and when. The platform layer sits *below* the handler and is consumed when the handler image is built (the handler is built `FROM` it); the overlay sits *above* an already-built handler and is applied when the function is deployed. That makes the overlay the tool for artifacts you want to ship *with* a finished handler without rebuilding or re-releasing it — a data layer is the canonical case: one handler distribution, deployed against different data bundles, each bundle an overlay.

The mechanism is what makes this work cleanly. The handler image is built from the *framework's* Dockerfile, in a temporary build context you never see. The overlay is built from a `Dockerfile` that *you* provide in your project root — a different file entirely — and this is where the additive content goes: your overlay Dockerfile builds `FROM` the handler image and layers your artifacts on top. Set `OVERLAY` to a repository name, place your `Dockerfile` in the project root, and ALRB builds that image, pushes it to the overlay repository, and updates the deployed function to it directly:

```dockerfile
# ./Dockerfile — your overlay, built on top of the handler image
FROM perl-lambda:latest
COPY data/reference-2026.db /var/task/data/
```

The overlay is wired into the normal flow, gated on `OVERLAY` being set: `lambda-pipeline` applies it after the trigger is provisioned, `update-function` rebuilds and re-applies it on a change, and `lambda-teardown` removes it (deleting the overlay's ECR repository, which — unlike the platform repository — it *does* own). Its build depends on the handler image existing and on your `Dockerfile`, so the overlay rebuilds whenever either changes, and a missing project-root `Dockerfile` is a hard error rather than a silent skip.

### 9.7 The picture, together

The layers and the rebuild rules are one idea seen twice — a stack ordered by rate of change, and a sentinel chain that invalidates downward from whatever you touched:

```
  CHANGE THIS...                          ...AND THIS REBUILDS

  handler code / tarball    ─────────►    handler image → deploy → function
  cpanfile dependency       ─────────►    (dep layer up) → handler image → …
  a same-version module      ──CACHE_BUST►  reinstall layer → handler image → …
  Dockerfile.platform       ─────────►    platform image → (clears handler chain)
  perl-lambda-base          ─────────►    everything (rare; not a local build)
```

Appendix A turns this into a lookup table — every change you might make, the target to run, and the cache lever if one applies — for when you want the answer without re-deriving it.

## 10. Dependencies and the DarkPAN

A Lambda image is only as lean as the dependencies you put in it, and one of ALRB's quieter design decisions is that you never maintain a separate list of them. Your distribution already declares what it needs; the image installs exactly that. This section is about where those dependencies come from, where they're resolved from, and the two places — system libraries and AWS API calls — where a little knowledge saves you a frustrating build.

### 10.1 Your dependencies are your distribution's dependencies

When ALRB builds the image, it generates the `cpanfile` it installs from — you don't write one. It reads your distribution tarball's `META.json` and emits a `cpanfile` containing the `runtime` and `configure` prerequisites your distribution already declares. That's the whole dependency list: whatever your `Makefile.PL`, `dist.ini`, or `cpanfile`-driven build recorded as your distribution's requirements is what gets installed into the container, and nothing else. Test and develop-phase prerequisites are deliberately left out — they have no place in a deployed function.

The practical upshot is that you manage dependencies in exactly one place, your distribution's own metadata, using the workflow you already use to build it. Add a module to your distribution's prerequisites, rebuild the tarball, and the next image picks it up — the regenerated `cpanfile` changes, which (per Section 9) invalidates the image and rebuilds it. There is no second list to keep in sync and no way for the image's dependencies to drift from your distribution's.

### 10.2 Where dependencies resolve: CPAN and the DarkPAN

By default, `cpm` resolves those prerequisites against public CPAN. For many functions that's fine. But two situations push you toward a private mirror — a *DarkPAN* — and ALRB is built with that in mind:

- You depend on modules that aren't on CPAN: your own distributions, a client's, or forks you maintain.
- You want builds to be *reproducible* — pinned to a known index rather than whatever CPAN served the day you built — which matters for a serverless artifact you may need to rebuild identically months later.

A DarkPAN is just a CPAN-shaped mirror: an index (`02packages.details.txt`) over a tree of distribution tarballs, which you can host on S3 behind CloudFront, on a plain web server, or anywhere `cpm` can fetch from. You point ALRB at one with the `RESOLVER` variable, whose value is a `cpm` resolver spec — the mirror index and its URL:

```
make image RESOLVER=02packages,https://cpan.example.com/orepan2
```

That becomes `cpm --resolver 02packages,https://cpan.example.com/orepan2`, so your own and CPAN's modules resolve through the same mirror in one pass. Set it once in `lambda.env` (or `lambda.yaml`) and every build — handler, reinstall layer, and all — resolves through your DarkPAN. This is also the seam that connects ALRB to the rest of the ecosystem: the same OrePAN2-on-S3 DarkPAN you publish your distributions to is the one your Lambda images install from.

> **Sidebar — Why `cpm`, not `cpanm`?**
>
> ALRB installs dependencies *inside the image* with `cpm` (`App::cpm`) rather than the more familiar `cpanm`. Three reasons drove that choice:
>
> - **Speed.** `cpm` resolves and installs in parallel and, depending on your build hardware and configuration, can be substantially faster than `cpanm` — and every image build pays the dependency-install cost.
> - **Active maintenance.** Its author maintains `cpm` aggressively as a modern replacement for `cpanm`, so it tracks current CPAN and toolchain behavior closely.
> - **Cleaner DarkPAN handling.** For resolving against a private mirror (above), `cpm`'s resolver model is — in our view — more robust and less confusing than `cpanm`'s overlapping `--mirror` and `--mirror-only` options.
>
> None of this constrains *you*: for installing the framework or your own modules locally, use whatever you prefer (§3). The choice is specifically about the tool that runs inside the image build.

### 10.3 System libraries and XS modules

Pure-Perl modules install without ceremony. XS modules — anything that compiles against a C library — need that library at two different moments, and the framework treats them differently.

At *build* time, the builder stage compiles XS against development headers. The base builder already carries the common ones (OpenSSL, expat, zlib, and the Perl development files), which covers a large fraction of CPAN. When a module needs one that isn't there, add it with `EXTRA_BUILD_PACKAGES`, appended to the builder stage's package install:

```
make image EXTRA_BUILD_PACKAGES="libpq-dev libxml2-dev"
```

At *run* time, an XS module needs the shared library itself — not the `-dev` headers — present in the deployed image. Add it with `EXTRA_RUNTIME_PACKAGES`, the runtime-stage counterpart to `EXTRA_BUILD_PACKAGES` (note the runtime package name, not the `-dev` one):

```
make image EXTRA_RUNTIME_PACKAGES="libpq5 libxml2"
```

When a runtime library is shared across several functions, a platform layer (§9.5) is the better home — install it once in a `Dockerfile.platform` and every handler built on that platform inherits it — but for a library a single function needs, `EXTRA_RUNTIME_PACKAGES` keeps it local to that handler's image.

### 10.4 Calling AWS from your handler

Receiving an event is one thing; calling back into AWS from your handler — reading an S3 object, writing to DynamoDB, publishing to SNS — is another, and it's where the leanness argument from the introduction becomes concrete. `Amazon::Lambda::Runtime` requires no AWS SDK at all, so nothing heavyweight is in your image unless you put it there.

When you do need to call AWS, prefer a pay-for-what-you-use client over a monolithic SDK. `Amazon::API` and its companions let you load and instantiate only the single service client a given call needs — an S3 client, a DynamoDB client — rather than pulling in a library that models the entire AWS surface the way Paws does in Perl or `boto3` does in Python. They lean on lightweight HTTP (`HTTP::Tiny`) and request signing rather than a large transport stack, so a handler that touches one or two services adds one or two services' worth of weight to the image, not the whole cloud. Credentials come from the same chain everything else uses — `Amazon::Credentials` resolves the execution role's credentials inside Lambda automatically, which is exactly what the scaffolded S3 example relies on.

You install such a client the same way you install anything else: declare it as a prerequisite of your distribution, and it flows through `META.json` into the image (10.1). Nothing about it is special to ALRB — that's the point. It's an ordinary CPAN dependency, kept as small as the work demands.

## 11. IAM and permissions

IAM is where Lambda deployments most often stumble, almost always because two different sets of permissions get conflated. This section separates them and shows where each is configured. Keep one distinction in mind throughout: the permissions *you* need to deploy a function are not the permissions the *function* needs to run, and they live in entirely different places.

### 11.1 The execution role

Every Lambda function runs as an IAM identity — its *execution role* — and that role is what the running function is allowed to do. It has two parts. A *trust policy* declares who may assume the role; ALRB generates one automatically (the `policy-document` step) that permits the Lambda service to assume it, and creates the role from it (`lambda-role`). And a set of *permission policies* declares what the role may do once assumed — which is the part you configure, below.

This role is entirely separate from the credentials you deploy with (Section 3). Your credentials are the identity that *builds and creates* the function; the execution role is the identity the function *becomes* when it runs. A deployment can succeed — your credentials were sufficient — and the function can still fail at runtime because its execution role lacks a permission. The two are configured independently and fail independently.

### 11.2 Triggers grant invocation, not access

The single most common runtime surprise: wiring a trigger does not grant your function permission to call that service's API. They are separate grants pointing in opposite directions. When Section 8 says an S3 trigger "grants S3 permission to invoke the function," that permission lets S3 *call your function* — it says nothing about your function *calling S3*. A handler triggered by an S3 upload that then tries to read the uploaded object needs S3 read permission *on its execution role*, added as a policy here. The trigger and the API access are two doors, and the pipeline only opens the one that lets the event in.

### 11.3 Managed policies: the `policies` file or a profile

AWS managed policies — the broad, AWS-maintained permission sets — are the usual way to grant a function what it needs, and ALRB gives you two ways to attach them. They're mutually exclusive: one or the other, not both.

The default is the **`policies` file** in your project (`POLICIES_FILE`, default `policies`): a plain list of managed-policy ARNs, one per line, with `#` comments. The scaffold ships it with CloudWatch logging enabled and a menu of common grants commented out, ready to uncomment:

```
# Basic Lambda execution (CloudWatch logging) - required
arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole

# S3 access
# arn:aws:iam::aws:policy/AmazonS3ReadOnlyAccess
```

The alternative is a **profile** (`ROLE_PROFILE`): the name of a predefined bundle in the framework's `profiles.yml`, each a curated list of managed policies for a common shape of function — `basic` (logging only), `s3-read`, `s3-sqs`, `s3`, `eventbridge`. Set `ROLE_PROFILE: s3-read` and the role gets logging plus S3 read without your hand-listing ARNs. If `ROLE_PROFILE` is unset, a `policies` file must exist (ALRB errors if neither is present); if it's set, the profile's list is used instead of the file.

### 11.4 Inline custom policies: scoping to a resource

Managed policies are broad by design — `AmazonS3ReadOnlyAccess` grants read on *every* bucket in the account. When you want to grant exactly what a function needs and no more — read on *one* bucket, publish to *one* topic — reach for an inline custom policy. Drop an IAM policy *document* (not a list of ARNs, but a real policy with `Statement`s and resource ARNs) into `custom-policies.json` (`CUSTOM_POLICIES_FILE`), and ALRB attaches it inline to the execution role:

```json
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Action": ["s3:GetObject"],
    "Resource": "arn:aws:s3:::my-input-bucket/*"
  }]
}
```

The file is optional — absent, the step is a no-op — and it composes with whichever managed policies you attached. Use managed policies for broad, standard grants and an inline `custom-policies.json` for the resource-scoped ones, which is the shape most least-privilege setups want.

### 11.5 Applying and updating policies

The pipeline attaches both kinds when it creates the function — `lambda-managed-policies` runs the file-or-profile attachment, `lambda-inline-policies` applies the custom document. When you change a policy afterward — uncomment a managed ARN, tighten a resource in `custom-policies.json` — re-apply without redeploying anything else:

```
make update-policies              # both managed and inline
make update-managed-policies      # just the file/profile
make update-inline-policies       # just custom-policies.json
```

Each removes the relevant sentinel and re-runs its attachment, so the change lands on the live role immediately.

### 11.6 What `check` verifies — and what it doesn't

`alr-builder check` (Section 3) simulates, against your *deploying* identity, the permissions the build-and-deploy path needs — creating and pushing to ECR, creating the role and passing it to Lambda, creating and invoking the function, and provisioning the SQS, SNS, S3, and EventBridge resources the triggers use. If your credentials fall short, it tells you before you spend time on a build. The full simulated list is in the reference (Section 14).

Two limits are worth knowing. First, `check` validates your *deploying* credentials, not the execution role's *runtime* permissions — it cannot know what your handler will try to call, so the trigger-versus-access gap in 11.2 is yours to close. Second, a few deploy-time actions aren't simulated as shipped — CloudWatch Logs (the log group), ELBv2 (ALB triggers), and the inline `PutRolePolicy` used by custom policies — so if you use those features and the relevant permission is missing, it surfaces during the deploy rather than in `check`. The one gotcha that catches nearly everyone, `iam:PassRole`, *is* simulated; Section 13 covers the confusing error it produces when absent.

## 12. Day-two operations

The first deploy is the interesting one; everything after is small, targeted changes to a function that already exists. This section covers those — code, configuration, policies, logs, and teardown — and doubles as a practical reference to the targets you'll reach for most. The through-line is the sentinel model from Section 9: almost every "update" target works by invalidating one sentinel and letting `make` redo exactly that step.

### 12.1 Deploying a code change

Change your handler, rebuild your distribution tarball, and run:

```
make update-function
```

The rebuilt tarball is what drives everything: it's newer than the image sentinel, so the image rebuilds, pushes to ECR, and the function's code is updated to the new image *by digest* — no `:latest` ambiguity about what's running. If `OVERLAY` is set, the overlay is rebuilt and re-applied on top (Section 9.6). The corollary is worth stating plainly: `update-function` without a rebuilt tarball is a no-op, because nothing upstream changed. The unit of a code deploy is a new tarball, not the command.

### 12.2 Changing configuration

To change memory or timeout, edit `lambda.yaml` (or `lambda.env`) and force the configuration step:

```
make update-lambda-configuration
```

This re-applies memory and timeout to the live function from your current config. Remember the model from Section 7: if you keep a `lambda.yaml`, edit *that* — `lambda.env` is regenerated from it, and hand edits to `lambda.env` are overwritten.

Changing a **trigger** setting — a schedule, a bucket, a queue parameter — is a different operation: re-run `make lambda-pipeline`, which is idempotent and re-provisions the trigger from your updated configuration. One caveat rooted in how AWS works: settings that *name* a resource identify it rather than reconfigure it. Renaming a queue in `lambda.yaml` doesn't rename the queue in AWS — it points the pipeline at a differently-named queue and creates that one, leaving the old behind. For changes to a resource's identity, tear down and redeploy; for changes to its parameters, re-running the pipeline is enough.

### 12.3 Changing policies

Covered in Section 11.5: edit the `policies` file or `custom-policies.json` and run `make update-policies` (or the `-managed`/`-inline` halves). The change lands on the live execution role immediately, with no need to touch the function itself.

### 12.4 Logs and retention

Your function's output — everything sent through `$self->get_logger` — goes to the CloudWatch log group `/aws/lambda/<function-name>`. Log verbosity is controlled at runtime by the `LOG_LEVEL` environment variable (default `info`), so you can raise it to `debug` without a code change. To watch a function live:

```
aws logs tail /aws/lambda/<function-name> --follow
```

Retention is governed by `LOG_RETENTION` (default one day), applied by the `log-group` target, which the configuration step ensures exists. The short default is deliberate — a chatty function left at infinite retention is a slow, silent cost. Raise it for functions whose history you actually need. `log-group-teardown` deletes the log group outright, and a full `lambda-teardown` does so as its last step.

### 12.5 Reserved concurrency

The `s3-sqs` pipeline pins the function's *reserved concurrency* (from `concurrency`, default 1) as part of provisioning — this is what makes that trigger a safe replacement for a single-threaded worker, since a reserved concurrency of 1 means AWS runs at most one invocation at a time and your queue is drained strictly in series. Raise it when the work is parallelizable and you want throughput; keep it at 1 when ordering or a shared external resource demands serialization.

### 12.6 Testing an invocation

To invoke the deployed function directly with a sample event:

```
make invoke
```

`invoke` sends a sample event matching your `TRIGGER_TYPE` (resolving `payload-<trigger>.json`), calls the function synchronously, and prints the response — the fastest way to confirm a change works without waiting for the real trigger to fire. To send a specific event, drop a `payload-<trigger>.json` in the project or pass `PAYLOAD=your-file.json`. For a function exposing a streaming Function URL, `make test-streaming` exercises the streaming path with `curl` instead.

### 12.7 Tearing down versus cleaning

Two commands look similar and do very different things. `make lambda-teardown` removes the deployed **AWS resources** — the function, role, trigger wiring, log group — dispatched by trigger type and conservative about shared or stateful resources (Section 8): buckets, SNS topics, and your ALB survive. `make clean`, by contrast, touches **nothing in AWS** — it removes the local sentinel files (and local Docker build artifacts), which makes the pipeline "forget" what it has done so the next run rebuilds from scratch. Use `clean` to force a fresh local rebuild of a function you want to keep; use `lambda-teardown` to actually remove the function from your account. Confusing the two is harmless in one direction (a stray `clean` just causes a rebuild) and merely inconvenient in the other (`lambda-teardown` is reversible by re-running the pipeline).

## 13. Troubleshooting

When something goes wrong, three habits locate almost any problem quickly. Read the logs first — set `LOG_LEVEL=debug` (Section 12.4) and the runtime becomes voluble about what it received and dispatched. Check the sentinels — `.cache/<function-name>/` shows exactly which pipeline step last completed, so a failed deploy tells you where it stopped. And isolate with `make invoke` — invoking directly separates "my handler is broken" from "my trigger is misconfigured," because it exercises the function without the event source. The specific failures below are the ones that account for most first-deploy frustration.

### 13.1 "The role cannot be assumed by Lambda"

**Symptom:** the deploy fails creating the function, with an `InvalidParameterValueException` claiming the execution role cannot be assumed — even though the role plainly exists and looks correct. **Cause:** your *deploying* credentials are missing `iam:PassRole`. Creating a function hands (passes) the execution role to the Lambda service, and without permission to do so AWS reports it as an assume-role failure, which sends people to debug the role's trust policy — the wrong place entirely. **Fix:** grant `iam:PassRole` to your deploying identity. `alr-builder check` simulates this permission, so running it first surfaces the real problem with a clear name instead of the misleading runtime error.

### 13.2 "HANDLER_CLASS not found in the tarball"

**Symptom:** the build stops immediately with `ERROR: <YourClass> not found in <tarball>`. **Cause:** the `tarball-validated` step looks for your handler class as `lib/<Your>/<Class>.pm` inside the distribution tarball and didn't find it — usually because the distribution's primary module doesn't match `HANDLER_CLASS`, or the tarball ALRB picked up is stale. **Fix:** confirm your handler class is installed at the expected `lib/` path in the distribution (`HANDLER_CLASS` of `My::Handler` must live at `lib/My/Handler.pm`), and that the newest `*.tar.gz` in the project directory is the one you meant to deploy. This check is deliberately early and cheap — it fails here rather than after a full image build.

### 13.3 Writes fail at runtime with "read-only file system"

**Symptom:** the handler runs but dies trying to write a file. **Cause:** a Lambda container's filesystem is read-only *except* for `/tmp`. Code that writes anywhere else — a temp file in the working directory, a cache beside a module — works on your workstation and fails in Lambda. **Fix:** write only under `/tmp`. With `File::Temp`, pass `DIR => '/tmp'` explicitly rather than relying on a default that may resolve elsewhere; for anything else, root the path at `/tmp`. This is the single most common "works locally, fails deployed" surprise when porting existing code.

### 13.4 Credentials fail inside the function

**Symptom:** a handler that calls AWS works locally but, deployed, fails to find credentials or names a profile that doesn't exist. **Cause:** there is no `~/.aws/credentials` and no named profiles inside a Lambda container. The function's credentials come from its execution role, delivered through the container credential chain. Code that requests a specific named profile — fine on your workstation — has nothing to resolve against in Lambda. **Fix:** don't specify a profile in deployed code. `Amazon::Credentials` resolves the execution role's credentials from the container/IMDS chain automatically when you don't pin a profile (Section 10.4); let it. If you share code between a workstation and Lambda, make the profile conditional rather than hard-coded.

### 13.5 An ALB target returns 502 Bad Gateway

**Symptom:** the function runs cleanly, logs success, and the load balancer still returns 502. **Cause:** ALB requires the response `statusCode` to be a JSON *integer*; a string like `"400"` is rejected and surfaces as a 502. **Fix:** return your response through the ALB base class's response helper (Section 6), which coerces the status to a number for you. If you hand-build the response hash, make sure `statusCode` is numeric (`200`, not `"200"`) — a bare `+ 0` is enough to force it.

### 13.6 An ALB endpoint has no working HTTPS

**Symptom:** you can't reach the function over HTTPS at the load balancer's own DNS name. **Cause:** the auto-generated `*.elb.amazonaws.com` name has no TLS certificate — AWS doesn't issue one for it. **Fix:** front the ALB with a custom domain: an ACM certificate on the HTTPS listener and a DNS record pointing your domain at the load balancer. Once the listener has a valid certificate, the listener rule ALRB created for your path works over HTTPS automatically; nothing about the function changes.

### 13.7 SQS messages are processed more than once

**Symptom:** an `s3-sqs` function reprocesses the same message, sometimes while a previous invocation is still running. **Cause:** the queue's visibility timeout is shorter than the function actually takes, so SQS makes the message visible again and redelivers it before the first invocation finishes. **Fix:** set the visibility timeout to comfortably exceed your function timeout — the rule of thumb, which `check-env-file` enforces as a warning (Section 7), is at least six times the function timeout. Independently, design the handler to be idempotent: at-least-once delivery means a duplicate is always possible, timeout tuning or not. (Relatedly, you may see `ignoring s3:TestEvent` in the logs when a bucket notification is first configured — that's the runtime discarding S3's one-time probe message, not an error.)

## 14. Reference

### 14.1 Make targets

**Primary**

| Target | Does |
|---|---|
| `lambda-pipeline` | Provision the full stack for the configured `trigger.type` |
| `lambda-teardown` | Deprovision the function and its trigger-type infrastructure |
| `lambda-function` | Create the function (builds the image if needed) |
| `update-function` | Rebuild and update the function's code to the latest image |
| `lambda-configuration` | Apply memory/timeout (and ensure the log group) from config |
| `update-lambda-configuration` | Force re-apply of memory/timeout |
| `update-policies` | Re-attach all IAM policies (managed + inline) |
| `update-managed-policies` | Re-attach managed policies (file or profile) |
| `update-inline-policies` | Re-apply the inline `custom-policies.json` |
| `invoke` | Invoke the function with `$(PAYLOAD)` and print the response |
| `clean` | Remove local sentinels and Docker artifacts (no AWS changes) |

**Per-trigger pipelines** (each has a matching `…-teardown`)

| Target | Trigger type |
|---|---|
| `lambda-eventbridge-pipeline` / `-teardown` | `eventbridge` |
| `lambda-s3-pipeline` / `-teardown` | `s3-direct` |
| `lambda-sqs-pipeline` / `-teardown` | `s3-sqs` |
| `lambda-sns-pipeline` / `-teardown` | `sns` |
| `lambda-alb-pipeline` / `-teardown` | `alb` |

**Function URL and EventBridge control**

| Target | Does |
|---|---|
| `lambda-function-url` | Create a streaming Function URL for the function |
| `test-streaming` | Invoke the Function URL with `curl` |
| `enable-eventbridge-rule` / `disable-eventbridge-rule` | Resume / pause the schedule without teardown |
| `delete-eventbridge-rule` | Remove targets and delete the rule |

**Image layers**

| Target | Does |
|---|---|
| `platform` / `platform-teardown` | Build & push the platform image (clears handler sentinels) / clear platform sentinels (ECR repo kept) |
| `overlay` / `overlay-teardown` | Build the overlay image & update the function / delete the overlay repo |
| `log-group` / `log-group-teardown` | Create the log group & set retention / delete the log group |

**Internal** (run automatically as dependencies): `image`, `tarball-validated`, `ecr-repo`, `deploy`, `image-digest`, `lambda-role`, `lambda-managed-policies`, `lambda-inline-policies`, `lambda-concurrency` (s3-sqs), `policy-document`, and the per-trigger `lambda-*-trigger` steps.

### 14.2 Configuration reference (`lambda.yaml` → `lambda.env`)

Every configurable field, its `lambda.yaml` path, the `lambda.env` variable it maps to, its default, whether it's required, and the trigger types it applies to. Fields with no `applies_to` apply to every type.

| `lambda.yaml` path | Variable | Default | Req. | Applies to |
|---|---|---|:--:|---|
| `image.repo` | `REPO_NAME` | `perl-lambda` | | all |
| `image.handler` | `HANDLER_CLASS` | — | ✔ | all |
| `lambda.name` | `FUNCTION_NAME` | `lambda-handler` | | all |
| `lambda.timeout` | `TIMEOUT` | `30` | | all |
| `lambda.memory` | `MEMORY` | `128` | | all |
| `lambda.concurrency` | `CONCURRENCY` | `1` | | all † |
| `role.name` | `ROLE_NAME` | `lambda-role` | | all |
| `role.profile` | `ROLE_PROFILE` | — | | all |
| `trigger.type` | `TRIGGER_TYPE` | — | ✔ | all |
| `platform_image` | `PLATFORM_IMAGE` | — | | all |
| `overlay` | `OVERLAY` | — | | all |
| `log_retention` | `LOG_RETENTION` | `1` | | all |
| `trigger.bucket` | `BUCKET_NAME` | — | ✔ | s3-sqs, s3-direct |
| `trigger.prefix` | `KEY_PREFIX` | — | | s3-sqs, s3-direct |
| `trigger.event` | `S3_EVENT` | `s3:ObjectCreated:*` | | s3-sqs, s3-direct |
| `trigger.queue.name` | `QUEUE_NAME` | `lambda-runtime` | | s3-sqs |
| `trigger.queue.batch_size` | `BATCH_SIZE` | `1` | | s3-sqs |
| `trigger.queue.visibility_timeout` | `VISIBILITY_TIMEOUT` | `360` | | s3-sqs |
| `trigger.queue.retention` | `RETENTION` | `86400` | | s3-sqs |
| `trigger.queue.receive_count` | `RECEIVE_COUNT` | `3` | | s3-sqs |
| `trigger.queue.dlq.name` | `DLQ_NAME` | `<queue>-dlq` | | s3-sqs |
| `trigger.queue.dlq.retention` | `DLQ_RETENTION` | `1209600` | | s3-sqs |
| `trigger.queue.partial_batch_response` | `PARTIAL_BATCH_RESPONSE` | `false` | | s3-sqs |
| `trigger.schedule` | `SCHEDULE_EXPRESSION` | `rate(1 day)` | | eventbridge |
| `trigger.rule_name` | `RULE_NAME` | `lambda-handler-rule` ‡ | | eventbridge |
| `trigger.topic_name` | `TOPIC_NAME` | — | ✔ | sns |
| `trigger.listener_arn` | `LISTENER_ARN` | — | ✔ | alb |
| `trigger.path` | `ALB_PATH` | `/build` | | alb |
| `trigger.priority` | `RULE_PRIORITY` | `10` | | alb |

† `concurrency` is currently applied only by the `s3-sqs` pipeline (§12.5).

### 14.3 Build and CLI variables

Knobs set on the `make` command line or in `lambda.env`, not part of the `lambda.yaml` schema.

| Variable | Default | Purpose |
|---|---|---|
| `AWS_PROFILE` | `default` | Named profile for *deploy* credentials |
| `REGION` | `us-east-1` | AWS region |
| `AWS_ACCOUNT` | (from STS) | Account ID; auto-resolved via `alr-helper get-account` |
| `BUILDER_HOME` | `.` | Directory searched for the distribution tarball |
| `DIST_NAME` | *(dir name)* | Distribution name used to match the tarball |
| `DIST_TARBALL` | *(newest match)* | The `$(DIST_NAME)-*.tar.gz` to build |
| `PAYLOAD` | `payload-<trigger>.json` | Sample event for `make invoke`; resolves per `TRIGGER_TYPE` (local → framework → generic `payload.json`) |
| `RESOLVER` | *(public CPAN)* | `cpm` DarkPAN resolver spec (§10.2) |
| `EXTRA_BUILD_PACKAGES` | *(none)* | Extra Debian packages, builder stage (§10.3) |
| `EXTRA_RUNTIME_PACKAGES` | *(none)* | Extra Debian packages, runtime stage (§10.3) |
| `CACHE_BUST` | *(unset)* | Any new value busts the reinstall layer (§9.3) |
| `NOCACHE` | *(unset)* | Set to `--no-cache` for a clean Docker build (§9.3) |
| `POLICIES_FILE` | `policies` | Managed-policy ARN list (§11.3) |
| `CUSTOM_POLICIES_FILE` | `custom-policies.json` | Inline policy document (§11.4) |
| `INVOKE_MODE` | `RESPONSE_STREAM` | Function URL invoke mode |

### 14.4 IAM permissions verified by `alr-builder check`

Simulated against your *deploying* identity via `SimulatePrincipalPolicy` (§11.6):

- **ECR:** `CreateRepository`, `DescribeRepositories`, `GetAuthorizationToken`, `BatchCheckLayerAvailability`, `PutImage`, `InitiateLayerUpload`, `UploadLayerPart`, `CompleteLayerUpload`, `PutLifecyclePolicy`, `GetLifecyclePolicy`
- **IAM:** `GetRole`, `CreateRole`, `AttachRolePolicy`, `PassRole`, `ListAttachedRolePolicies`
- **Lambda:** `GetFunction`, `CreateFunction`, `UpdateFunctionCode`, `GetFunctionConfiguration`, `UpdateFunctionConfiguration`, `InvokeFunction`, `CreateEventSourceMapping`, `ListEventSourceMappings`, `GetPolicy`, `AddPermission`, `RemovePermission`, `CreateFunctionUrlConfig`, `GetFunctionUrlConfig`, `DeleteFunctionUrlConfig`
- **SQS:** `ListQueues`, `CreateQueue` — **SNS:** `ListTopics`, `CreateTopic`, `Subscribe`, `GetTopicAttributes` — **S3:** `CreateBucket`, `ListBuckets`, `PutBucketNotificationConfiguration`
- **EventBridge:** `DescribeRule`, `PutRule`, `PutTargets`, `RemoveTargets`, `DeleteRule`, `EnableRule`, `DisableRule` — **STS:** `GetCallerIdentity`

**Not simulated** (may surface at deploy time): CloudWatch Logs (`logs:*` for the log group), ELBv2 (`elasticloadbalancing:*` for ALB triggers), and the inline `iam:PutRolePolicy` used by custom policies.

### 14.5 See also

The `alr-builder` POD (`perldoc Amazon::Lambda::Runtime::Builder`) documents the CLI in full; a companion document covering the internal `alr-helper` CLI is planned. For packaging the distribution ALRB deploys, see Appendix B.

---

# Appendix A — The rebuild matrix

Section 9 explains *why* things rebuild; this is the lookup table for *what to run*. Find the thing you changed, run the command, and the listed steps rebuild (each pulling its own downstream steps along the sentinel chain). When in doubt, the universal escape hatch is at the bottom.

| You changed… | Run | What rebuilds | Cache lever |
|---|---|---|---|
| Handler code (→ new tarball) | `make update-function` | image → push → digest → function code | — |
| A dependency (→ new tarball metadata) | `make update-function` | cpanfile → image → … | — |
| A module republished at the *same* version | `make update-function CACHE_BUST=$(date +%s)` | reinstall layer → image → … | `CACHE_BUST` |
| `requires.reinstall` (bumped a version) | `make update-function` | reinstall layer → image → … | — |
| `requires.reinstall` (same version, rebuilt) | `make update-function CACHE_BUST=$(date +%s)` | reinstall layer → image → … | `CACHE_BUST` |
| `Dockerfile.platform` | `make lambda-pipeline` | platform image → (clears & rebuilds handler chain) | — |
| `./Dockerfile` (overlay, `OVERLAY` set) | `make update-function` | overlay image → function | — |
| Memory or timeout | `make update-lambda-configuration` | lambda-configuration | — |
| A trigger setting (schedule, prefix, queue param) | `make lambda-pipeline` | the changed trigger step | — |
| `policies` or `custom-policies.json` | `make update-policies` | managed / inline attachment | — |
| `LOG_RETENTION` | `rm .cache/<fn>/log-group && make log-group` | log-group | — |
| Nothing — want a guaranteed clean image | `make image NOCACHE=--no-cache` | every image layer | `NOCACHE` |

**Universal escape hatch.** Every step is a sentinel file under `.cache/<function-name>/`. To force *any* single step to re-run regardless of the above, delete its sentinel and run its target: `rm .cache/<fn>/<step> && make <step>`. That works because a step is "done" only while its sentinel exists (§9.2) — removing it is how you tell `make` to do that one thing again.

---

# Appendix B — Better together: CPAN::Maker and CPAN::Maker::Bootstrapper

Section 4.4 deploys a distribution tarball and takes no position on how you build it — `Dist::Zilla`, `ExtUtils::MakeMaker`, or anything else that emits a conventional tarball works, because ALRB reads only the standard result. This appendix is for readers who'd like a build path that was designed alongside ALRB and shares its idioms end to end. Nothing here is required; it's the "if you liked how ALRB works, you'll recognize these" option.

Two companion distributions, by the same author, cover the two ends ALRB doesn't:

- **CPAN::Maker** turns a `buildspec.yml` — a short declaration of your module, its paths, and its dependencies — into a standard CPAN distribution tarball. It is one concrete answer to "your favorite CPAN tool" from Section 4.4: the thing that produces the artifact ALRB consumes.
- **CPAN::Maker::Bootstrapper** scaffolds a ready-to-build project in one command (`cpan-maker-bootstrapper -m My::Handler`): a project `Makefile`, a `buildspec.yml` pre-filled from your git config, stub sources, supporting makefiles, and an immediate first build. It also *imports* existing code into a distribution and layers on development tooling.

Together they close a clean three-stage loop: **Bootstrapper** scaffolds or imports → **CPAN::Maker** builds the tarball → **ALRB** deploys it as a Lambda.

**Why the seams line up.** The reason these feel like one system rather than three is that they're built from the same parts. Bootstrapper installs a project `Makefile` that includes supporting makefiles from a share directory and extends them through a `project.mk` — exactly ALRB's own layout, down to the naming. Both use `.pm.in` source templates, CLI::Simple modulinos, and sentinel-driven `make` builds. A developer who has internalized ALRB's build model from Section 9 already knows how a Bootstrapper project behaves, because the model is the same one. There is no code coupling between them — Bootstrapper doesn't know ALRB exists — but the shared design means the handoff from one to the next has no impedance.

Three of those seams are worth calling out because they map directly onto things earlier sections asked you to do by hand:

- **Importing existing code is the porting story.** Bootstrapper's `-I lib -I bin` pulls loose modules and scripts into a proper distribution — which is precisely the "turn a daemon or script into a handler" move from Sections 1 and 6. Bootstrapper makes it a distribution; ALRB makes that distribution a Lambda.
- **Dependency scanning feeds ALRB's cpanfile.** Bootstrapper scans your sources for prerequisites and records them in the distribution's metadata. That metadata is exactly what ALRB reads to generate the image's `cpanfile` (Section 10.1) — so the dependency list ALRB installs is maintained for you upstream rather than by hand.
- **A shared DarkPAN closes the loop.** If you publish your own distributions to a DarkPAN, the modules CPAN::Maker builds and the modules ALRB resolves against (via `RESOLVER`, Section 10.2) are the same mirror — private code flows from build to deployed image without a detour through public CPAN.

Beyond the build, Bootstrapper adds development tooling that's orthogonal to ALRB but pleasant to have in the same workflow — quality gates (syntax and `perlcritic` checks wired into the build), AI-assisted code review, POD review and generation, and generated release notes via the Anthropic API. None of it touches deployment; it just means the distribution you eventually hand to ALRB was built, checked, and documented in one consistent place.

**Where to look.** `perldoc CPAN::Maker::Bootstrapper` for the
scaffolding, import, and review workflow; `perldoc CPAN::Maker` for
the `buildspec.yml` format and the tarball build. Neither is a
prerequisite for ALRB — they're the same-grain option for readers who
want one.

---

