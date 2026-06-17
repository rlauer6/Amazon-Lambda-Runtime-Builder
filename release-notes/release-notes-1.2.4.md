# Amazon::Lambda::Runtime::Builder 1.2.4 Release Notes

## Overview

1.2.4 is a sentinel hardening release. Every Makefile recipe that writes a
sentinel file has been audited and corrected to ensure that partial failures
do not leave stale sentinels behind. The `test -e $@` anti-pattern (write
sentinel only if absent) has been replaced throughout with explicit empty-value
guards and proper `|| { rm -f $@ && exit 1; }` error handling. Four specific
bugs in `sqs.mk` and `eventbridge.mk` are also fixed.

---

## Changes

### ecr-create-repo.mk - sentinel hardening

**`ecr-uri`** - replaced `test -e $@ || echo "$repo_uri" > $@` with an
explicit empty-value guard (`if [[ -z "$repo_uri" ]]; then error; fi`) and
`echo "$repo_uri" > $@ && chmod 444 $@ || rm -f $@`. An empty URI from a
failed `create-repository` call no longer produces a valid-looking sentinel.

**`ecr-lifecycle-policy`** - replaced `test -e $@ || echo "$lifecycle_policy" > $@`
with an error-string guard (`grep -q "error|Error|Exception"`) and
`echo "$lifecycle_policy" > $@ && chmod 444 $@ || rm -f $@`. A policy
containing an error JSON string no longer gets written as a sentinel.

### Makefile.mk - sentinel hardening

**`policy-document`** - added `|| rm -f $@` to the write.

**`lambda-policies`** - added `|| rm -f $@` to the tempfile-based write.

**`image-digest`** - added `|| rm -f $@` to the write.

**`lambda-function`** - added `|| rm -f $@` to the write.

**`lambda-configuration`** - added `|| rm -f $@` to the write.

### sqs.mk - sentinel hardening and bug fixes

**`sqs-dlq` / `sqs-queue`** - replaced `test -e $@ || echo` with explicit
empty-value guard and `echo "$queue" > $@ || { rm -f $@ && exit 1; }`.

**`sqs-queue-redrive`** - added `|| exit 1` to `set-queue-redrive-policy`
call; replaced `test -e $@ || echo` with proper write pattern.

**`sqs-queue-policy`** - added `|| exit 1` to `set-queue-bucket-policy` call;
replaced `test-e $@ || echo` with proper write pattern.

**`lambda-concurrency` (bug fix)** - `chmod 444` was missing `$@` - `chmod
444` with no argument is a no-op. Fixed to `chmod 444 $@`.

**`lambda-sqs-trigger`** - replaced `test -e $@ || echo` with
`test -z "$$trigger" && { rm -f $@ && exit 1; }` empty guard pattern, matching
the correct idiom for captured-value sentinels.

**`lambda-s3-sqs-trigger` (bug fix)** - sentinel write used `|` (pipe) instead
of `||` (logical OR): `echo "$(QUEUE_NAME)" > $@ | { rm -f $@ && exit 1; }`.
The pipe connected stdout of echo to the error handler as stdin rather than
triggering it on failure. Fixed to `||`.

**`lambda-sqs-permission` (bug fix)** - `|| { rm -f $@ && exit 1}` was missing
the semicolon before `}`, causing a shell syntax error. Fixed to
`|| { rm -f $@ && exit 1; }`.

### eventbridge.mk - sentinel hardening and bug fixes

**`lambda-eventbridge-rule`** - replaced `test -e $@ || echo "$rule" > $@`
with `test -z "$$rule" && { rm -f $@ && exit 1; }` guard pattern.

**`lambda-eventbridge-permission`** - replaced `test -e $@ || echo "$permission" > $@`
with proper write pattern.

**`lambda-eventbridge-trigger` (bug fix)** - two bugs: (1) logic was inverted -
`test -z "$$trigger" || { rm -f ... }` failed when trigger WAS set; corrected
to `&&`. (2) the sentinel was never written - the recipe printed the
confirmation message but never wrote `$@`. Fixed to write `$$trigger` to `$@`
before printing.

---

## Sentinel Hardening Principles

The consistent patterns now used throughout:

**For captured-value sentinels** (value built up in a shell variable):
```makefile
test -z "$$value" && { rm -f $@ && exit 1; }; \
echo "$$value" > $@ || { rm -f $@ && exit 1; }; \
chmod 444 $@
```

**For command-output sentinels** (command output piped directly to file):
```makefile
some-command > $@ && chmod 444 $@ || rm -f $@
```

**For side-effect sentinels** (command has no useful output to store):
```makefile
some-command || exit 1; \
echo "marker" > $@ || { rm -f $@ && exit 1; }; \
chmod 444 $@
```
