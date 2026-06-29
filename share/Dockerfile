# Perl Lambda handler image
# Installs the handler distribution on top of perl-lambda-base.
#
# Layer 1: perl-lambda-base (runtime + all ALR deps)
# Layer 2: this image (handler distribution installed on top)
#
# Override PLATFORM_IMAGE to use a custom platform layer between
# perl-lambda-base and the handler e.g.:
#   docker build --build-arg PLATFORM_IMAGE=my-platform:latest ...

ARG PLATFORM_IMAGE=perl-lambda-base:latest

########################################################################
FROM debian:trixie-slim AS builder
########################################################################

ARG RESOLVER="--resolver 02packages,https://cpan.openbedrock.net/orepan2"
ARG EXTRA_BUILD_PACKAGES=""
ARG DIST_TARBALL=""

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        perl libssl3 libexpat1 zlib1g ca-certificates \
        gcc make rsync libssl-dev libexpat-dev zlib1g-dev libperl-dev curl \
        ${EXTRA_BUILD_PACKAGES} && \
    curl -fsSL https://raw.githubusercontent.com/skaji/cpm/main/cpm | perl - install -g App::cpm && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /usr/src/app
RUN mkdir -p /usr/src/app/local

COPY cpanfile /usr/src/app

RUN --mount=type=cache,target=/cache/local-debian \
  rsync -a /usr/src/app/local/ /cache/local-debian && \
  PERL5LIB=/cache/local-debian/lib/perl5 cpm install --show-build-log-on-failure --use-install-command -L /cache/local-debian ${RESOLVER} && \
  rm -rf /usr/src/app/local && \
  cp -a /cache/local-debian /usr/src/app/local

COPY ${DIST_TARBALL} /usr/src/app/
RUN cpm install -L /usr/src/app/local ${RESOLVER} ${DIST_TARBALL}

########################################################################
# Runtime stage — built on perl-lambda-base which already contains the
# Perl runtime, bootstrap, plambda.pl, and all ALR dependencies.
# Only the handler distribution's installed modules are added here.
########################################################################
FROM ${PLATFORM_IMAGE}
########################################################################

ARG HANDLER_CLASS="LambdaHandler"

WORKDIR /usr/src/app

# Add only the handler distribution — everything else is in the base image
COPY --from=builder /usr/src/app/local /usr/src/app/local

ENV LAMBDA_MODULE=${HANDLER_CLASS}

ENTRYPOINT ["/usr/local/bin/bootstrap"]
