# Perl Lambda Runtime POC
# Base: debian:trixie-slim

########################################################################
FROM debian:trixie-slim AS builder
########################################################################

ARG RESOLVER="--resolver 02packages,https://cpan.openbedrock.net/orepan2"
ARG EXTRA_BUILD_PACKAGES=""
ARG DIST_TARBALL=""

# Install build tools and runtime deps
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
FROM debian:trixie-slim
########################################################################

ARG HANDLER_CLASS="LambdaHandler"
ARG RESOLVER=""
ARG EXTRA_RUNTIME_PACKAGES=""

WORKDIR /usr/src/app

COPY --from=builder /usr/src/app/local /usr/src/app/local
COPY --from=builder /usr/src/app/local/bin/bootstrap /usr/local/bin/bootstrap
COPY --from=builder /usr/src/app/local/bin/plambda.pl /usr/local/bin/plambda.pl

RUN apt-get update --fix-missing && \
    apt-get install -y --no-install-recommends \
       perl libssl3 libexpat1 zlib1g ca-certificates \
    ${EXTRA_RUNTIME_PACKAGES} && \
    apt-get autoremove -y && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/* /root/.cpanm /tmp/*.tar.gz

ENV PERL5LIB=/usr/src/app/local/lib/perl5
ENV LAMBDA_MODULE=${HANDLER_CLASS}

ENTRYPOINT ["/usr/local/bin/bootstrap"]
