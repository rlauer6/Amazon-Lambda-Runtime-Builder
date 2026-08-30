# NAME

Amazon::Lambda::Runtime::Builder::Tutorial - build your first Perl Lambda, start to finish

# DESCRIPTION

This is a walk-through, not a reference. By the end you will have
written a Perl Lambda that is invoked every time a file lands in an S3
bucket, deployed it, watched it fire on a real upload, changed it, and
torn it down - without creating a single AWS resource by hand. Every
step produces something you can see: a file on disk, a green check, a
line in the logs.

For what each knob does, follow the links into
[Amazon::Lambda::Runtime::Builder](https://metacpan.org/pod/Amazon%3A%3ALambda%3A%3ARuntime%3A%3ABuilder); this document stays on the happy
path.

## Before you start

You need AWS credentials (e.g. a profile `alr-builder` can use), Docker running
locally, and nothing else - not even a bucket; we will let the build create
one. When in doubt, run `alr-builder check` at any point: it inspects your
tools and permissions and tells you plainly what is missing.

_Note: `alr-builder` uses [Amazon::Credentials](https://metacpan.org/pod/Amazon%3A%3ACredentials). See
[Amazon::Credentials](https://metacpan.org/pod/Amazon%3A%3ACredentials) for details regarding how it discovers
credentials._

## Step 1 - Scaffold the project

    mkdir ~/MyApp-Lambda-Handler
    alr-builder install --install-dir MyApp-Lambda-Handler
    cd ~/MyApp-Lambda-Handler

`install` drops a starter project into `MyApp-Lambda-Handler/`: a handler with
event stubs already written (including the S3 one you'll use), the `make`
build integration, a managed-policy list, and a `lambda-s3-direct.yaml`
you'll fill in shortly. Nothing here is precious - it's your project now.

## Step 2 - Turn it into a CPAN distribution

The builder installs your handler into the Lambda image as a normal
Perl distribution, so before it can build the image your project needs
to produce a distribution tarball. Any tool that produces a distribution
tarball will do; we recommend [CPAN::Maker::Bootstrapper](https://metacpan.org/pod/CPAN%3A%3AMaker%3A%3ABootstrapper), which is
built for exactly this:

    cpanm CPAN::Maker::Bootstrapper
    cd ~/MyApp-Lambda-Handler
    cmb -I . -i . -m MyApp::Lambda::Handler

When it finishes you'll have a `MyApp-Lambda-Handler-1.0.0.tar.gz` in the directory. That
tarball - however you choose to produce it - is what the image is built
from. From now on, editing your handler and rebuilding regenerates it
automatically; you won't run the bootstrapper again.

## Step 3 - Write the handler

Open the S3 event stub - it lives under `lib/` at
`.../Lambda/Event/S3.pm`. You will be pleased to find most of the work is
already done, and that you never have to touch the top-level `Handler.pm`:
the scaffold has already wired the S3 trigger to this file for you.

You also don't walk the event by hand. The framework unpacks the S3 message
and calls `on_s3_event` **once per record**, handing you a single record. The
stub already logs what arrived:

    sub on_s3_event {
      my ( $self, $s3_record ) = @_;

      my $logger = $self->get_logger;

      my $bucket = $s3_record->{s3}{bucket}{name};
      my $key    = $s3_record->{s3}{object}{key};
      my $size   = $s3_record->{s3}{object}{size};

      $logger->info("s3://$bucket/$key ($size bytes)");

      return;
    }

For the tutorial, replace the shipped stub with the simpler version
above. The generated stub also demonstrates fetching the object with
[Amazon::S3::Lite](https://metacpan.org/pod/Amazon%3A%3AS3%3A%3ALite); you can restore that later when you want to explore
object access and IAM permissions.

The stub as shipped goes one step further: it also fetches the object with
[Amazon::S3::Lite](https://metacpan.org/pod/Amazon%3A%3AS3%3A%3ALite) and logs a sample of its contents. That's a good thing to
keep once you're past your first run, but it needs `s3:GetObject` on the
bucket and isn't required to close the loop here. Trim it back to the log
line above if you want the cleanest possible first deploy.

If your handler needs configuration - an API endpoint, a table name, a
feature flag - don't hard-code it. Put it in a `lambda-handler.env` file in
the project root, one `KEY=VALUE` per line:

    GREETING=hello
    TABLE_NAME=my-table

Each line becomes an environment variable on the deployed function, readable
in your handler exactly as you'd expect:

    my $greeting = $ENV{GREETING};

Change that file later and re-run the build (Step 6) - the framework detects
it and updates the function's configuration.

## A note on the two kinds of configuration

It's worth pausing on a distinction that trips people up, because these
files look similar and do very different things:

- **`lambda.yaml`** (and the `lambda.env` generated from it) configure
the **build and deployment** - which trigger, how much memory and timeout,
the function name, the region. These are knobs for _how the function is
provisioned_. Tune them in `lambda.yaml`: `lambda.env` is regenerated from
it, so hand-edits to `lambda.env` are overwritten. After a change, re-run
the build to apply it.
- **`lambda-handler.env`** sets the **runtime environment** your handler
code reads through `%ENV`. This is _your application's_ configuration, not
the framework's.

Rule of thumb: if your Perl reads it, it belongs in `lambda-handler.env`;
if it changes how the function is built or wired up, it belongs in
`lambda.yaml`.

## Step 4 - Configure the trigger

The scaffold includes a starter configuration for the `s3-direct` trigger.
The builder uses `lambda.yaml` as the project configuration file.  If the
scaffold left the trigger-specific file in place, copy it first:

    cp lambda-s3-direct.yaml lambda.yaml

Open `lambda.yaml`.  It should look roughly like this:

    image:
    handler: 'MyApp::Lambda::Handler'   # already set for you - leave it
    lambda:
    name: lambda-handler                # the function name; rename if you like
    trigger:
    type: s3-direct
    bucket: my-input-bucket             # <- change this
    prefix: incoming/                   # <- delete this line for the tutorial
    event: 's3:ObjectCreated:*'         # every new object; leave it

For the tutorial, there are only two things to do:

- 1. Change `trigger.bucket` to a globally unique S3 bucket name.
- 2. Delete the `prefix` line.

S3 bucket names are global, so use something unlikely to collide with an
existing bucket.  Appending your AWS account id is one simple approach:

    my-input-bucket-123456789012

The build will create this bucket and configure it to invoke the Lambda.

Delete the `prefix` line so that any object uploaded to the bucket fires the
function.  If you leave:

prefix: incoming/

in place, only objects uploaded below `incoming/` will trigger the Lambda.
That is useful in a real application, but it adds an unnecessary opportunity
for confusion during the tutorial.

You do not need to set a region here.  The builder gets the AWS region from
your environment and credentials.  The handler class was also generated from
the application name and should already be correct.

Save `lambda.yaml`.  Nothing has been created in AWS yet; this file describes
what the builder will create in the next steps.

For the complete configuration reference and the options supported by each
trigger type, see L\[Amazon::Lambda::Runtime::Builder\](Amazon::Lambda::Runtime::Builder).

## Step 5 - Preflight

Two quick checks before you spend time on a build. The first confirms your
tools and credentials are in order:

    alr-builder check

The second reads your configuration back against the mapping and reports it in
three groups - required fields still missing, values you've customized, and
values falling through to their defaults - plus any constraint warnings for
your trigger. It's the fastest way to catch a typo here instead of in a
deployed function:

    alr-builder check-env-file

If nothing shows up as missing, you're ready to build.

## Step 6 - Build and deploy

One command takes you from source to a live function:

    CREATE_BUCKET=true alr-builder build

This builds the container image, deploys the function, and wires the S3
notification to it. By default it expects the bucket to already exist and
stops with a clear message if it doesn't; to have it provision the bucket for
you on the way, set `CREATE_BUCKET` when you build:

    CREATE_BUCKET=true alr-builder build

CREATE\_BUCKET=true is only needed because this tutorial starts without
a bucket. On later builds, or when targeting an existing bucket, plain
`alr-builder` build is enough.

The first build is slow - it's assembling the image layers from scratch - but
reruns reuse what hasn't changed and finish quickly. If anything goes
sideways, the full log is at `.cache/<function-name>/build.log`.

When it finishes you have a deployed Lambda and a bucket waiting for its first
file.

## Step 7 - Prove it works

Trigger the lambda by dropping a file in the bucket you named in Step 4:

    aws s3 cp ./hello.txt s3://my-input-bucket/

(If you kept the `prefix` from Step 4, upload to
`s3://my-input-bucket/incoming/hello.txt` instead - otherwise nothing
fires.)

You can also invoke the function directly with the canned event using
make invoke when you want to test the handler without touching S3.

    make invoke

Either way, the proof is in the logs - the `s3://bucket/key (N bytes)` line
your handler wrote, or the fuller dump if you kept the shipped stub. View them
however you like: `aws-logs` (ships with
[Log::Log4perl::Appender::CloudWatch](https://metacpan.org/pod/Log%3A%3ALog4perl%3A%3AAppender%3A%3ACloudWatch)), plain `aws logs tail`, or the
third-party `awslogs`. Watch the real upload land and you've closed the loop:
file in, handler runs, log out.

## Step 8 - Iterate

There's no separate update command. Change your handler - add a field to the
log line, read a new value from `lambda-handler.env` - and run the same build
again:

    alr-builder build

It rebuilds only what changed and updates the deployed function in place. Drop
another file in the bucket and you'll see your new behavior in the logs.

## Step 9 - Tear down

When you're done, remove what the build created:

    alr-builder teardown

Note what this does _not_ do: it removes the S3 notification and the
function, but it leaves the bucket - and anything in it - in place, even a
bucket that `CREATE_BUCKET` provisioned. That's deliberate: teardown won't
delete data you might still want. If you want the bucket gone, remove it
yourself.

## Where to go next

You've built the simplest useful shape: one function, one bucket, direct
invocation. Each of these is a link into [Amazon::Lambda::Runtime::Builder](https://metacpan.org/pod/Amazon%3A%3ALambda%3A%3ARuntime%3A%3ABuilder)
for when your needs grow:

- **Bursts, retries, or a dead-letter queue** - switch the trigger to
`s3-sqs`, which puts a queue between S3 and your function.
- **Run on a schedule** - use the `eventbridge` trigger instead of an S3
event.
- **Call it over HTTP** - front it with an `alb` trigger or a Function
URL.
- **Stream a large response** - use streaming with a Function URL.
- **Heavy shared dependencies you don't want to rebuild every image** -
move them into a platform layer (`PLATFORM_IMAGE` / `Dockerfile.platform`).
- **Iterating on a module that also lives on CPAN or your DarkPAN** -
force a fresh install with `requires.reinstall`.
- **Extra IAM permissions** - add inline policies via
`CUSTOM_POLICIES_FILE`, or extend the managed-policy list.

# SEE ALSO

[Amazon::Lambda::Runtime::Builder](https://metacpan.org/pod/Amazon%3A%3ALambda%3A%3ARuntime%3A%3ABuilder), [CPAN::Maker::Bootstrapper](https://metacpan.org/pod/CPAN%3A%3AMaker%3A%3ABootstrapper),
[Amazon::Credentials](https://metacpan.org/pod/Amazon%3A%3ACredentials), [Amazon::S3::Lite](https://metacpan.org/pod/Amazon%3A%3AS3%3A%3ALite),
[Log::Log4perl::Appender::CloudWatch](https://metacpan.org/pod/Log%3A%3ALog4perl%3A%3AAppender%3A%3ACloudWatch)
