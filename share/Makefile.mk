#-*- mode: makefile; -*-

SHELL := /bin/bash

.SHELLFLAGS := -ec

-include config.mk

LAMBDA_ENV  ?= lambda.env
LAMBDA_YAML ?= lambda.yaml

NEEDS_LAMBDA_ENV := $(filter-out clean,$(MAKECMDGOALS))

ifneq ($(NEEDS_LAMBDA_ENV),)
ifeq ($(wildcard $(LAMBDA_ENV)),)
  $(error $(LAMBDA_ENV) not found. \
    Run 'alr-builder check-env-file' to generate it from $(LAMBDA_YAML), \
    or copy an example $(LAMBDA_ENV) into this directory and edit it)
endif
endif

-include $(LAMBDA_ENV)

FRAMEWORK_DIR ?= $(shell perl -MFile::ShareDir=dist_dir -e 'print dist_dir("Amazon-Lambda-Runtime-Builder")')

include $(FRAMEWORK_DIR)/help.mk

REPO_NAME     ?= $(FUNCTION_NAME)
ROLE_NAME     ?= $(FUNCTION_NAME)-role
TRIGGER_TYPE  := $(strip $(TRIGGER_TYPE))
AWS_PROFILE   ?= default
REGION        ?= us-east-1
AWS_ACCOUNT   ?= $(shell alr-helper get-account)
NO_CACHE      ?=
TIMEOUT       ?= 30
BUILDER_HOME  ?= $(CURDIR)
CACHE_DIR     := $(BUILDER_HOME)/.cache/$(FUNCTION_NAME)
NO_ECHO       ?= @
DIST_NAME     ?= $(subst ::,-,$(MODULE_NAME))
DIST_TARBALL  ?= $(shell ls $(BUILDER_HOME)/$(DIST_NAME)-*.tar.gz 2>/dev/null | sort -V | tail -1)

PAYLOAD ?= $(firstword $(wildcard payload-$(TRIGGER_TYPE).json) \
                       $(wildcard $(FRAMEWORK_DIR)/payload-$(TRIGGER_TYPE).json) \
                       payload.json)

# Used when BUILDING Perl XS based modules that require additional
# libraries (ex: libssl-dev, etc)
EXTRA_BUILD_PACKAGES   ?=

# Used when USING Perl XS based modules that require additional
# libraries (ex: libssl, etc)
EXTRA_RUNTIME_PACKAGES ?=

# Used to set a DarkPAN (ex:
# 02packages,https://cpan.openbedrock.net/orepan2)
RESOLVER               ?=
PLATFORM_IMAGE         ?=
LOG_RETENTION          ?= 1

NEEDS_TARBALL := $(filter-out clean,$(MAKECMDGOALS))

ifeq ($(HANDLER_CLASS),)
  $(error You must specify the HANDLER_CLASS)
endif

ifneq ($(NEEDS_TARBALL),)
ifeq ($(DIST_TARBALL),)
  $(error No tarball $(DIST_TARBALL) found in $(BUILDER_HOME) - run 'make dist' first)
endif
endif

lambda-policies:            $(CACHE_DIR)/lambda-policies ## attach IAM policies to execution role
lambda-function:            $(CACHE_DIR)/lambda-function ## create Lambda function (builds image if needed)
lambda-role:                $(CACHE_DIR)/lambda-role ## create IAM execution role
ecr-repo:                   $(CACHE_DIR)/ecr-repo 
deploy:                     $(CACHE_DIR)/deploy ## push image to ECR and tag as latest
image:                      $(CACHE_DIR)/image ## build Docker image from distribution tarball
lambda-s3-trigger:          $(CACHE_DIR)/lambda-s3-trigger
lambda-sqs-trigger:         $(CACHE_DIR)/lambda-sqs-trigger
lambda-eventbridge-trigger: $(CACHE_DIR)/lambda-eventbridge-trigger
sns:                        $(CACHE_DIR)/sns
tarball-validated:          $(CACHE_DIR)/tarball-validated
lambda-managed-policies:    $(CACHE_DIR)/lambda-managed-policies
lambda-inline-policies:     $(CACHE_DIR)/lambda-inline-policies

update-function:            lambda-function ## update Lambda function code to latest image
ifneq ($(OVERLAY),)
	$(NO_ECHO)rm -f $(CACHE_DIR)/overlay && $(MAKE) overlay
endif

$(CACHE_DIR):
	mkdir -p $(CACHE_DIR)

########################################################################
# generate cpanfile from tarball META.json (runtime + configure prereqs)
########################################################################
$(CACHE_DIR)/cpanfile: $(DIST_TARBALL) | $(CACHE_DIR)
	$(NO_ECHO)alr-helper report-step $@ start; \
	alr-helper create-cpanfile --tarball $(DIST_TARBALL) > $@; \
	alr-helper report-step $@ done ok

########################################################################
# generate debian-packages from cpanfile via cpan-sysdeps
# falls back to empty file if cpan-sysdeps is not available
########################################################################
$(CACHE_DIR)/debian-packages: $(CACHE_DIR)/cpanfile
	$(NO_ECHO)if command -v cpan-sysdeps > /dev/null 2>&1; then \
	  alr-helper report-step $@ start; \
	  cpan-sysdeps find-deps --cpanfile $< > $@; \
	  alr-helper report-step $@ done ok; \
	else \
	  touch $@; \
	fi

########################################################################
# validate tarball contains LambdaHandler.pm before building image
########################################################################
$(CACHE_DIR)/tarball-validated: $(DIST_TARBALL) | $(CACHE_DIR)
	$(NO_ECHO)alr-helper report-step $@ start; \
	module_path=$$(echo $(HANDLER_CLASS) | sed -e 's/::/\//g'); \
	alr-helper --tarball $(DIST_TARBALL) check "lib/$${module_path}.pm" || { \
	  echo "ERROR: $(HANDLER_CLASS) not found in $(DIST_TARBALL)" >&2; \
	  alr-helper report-step $@ done fail; \
	  exit 1; \
	}; \
	touch $@ && chmod 444 $@; \
	alr-helper report-step $@ done ok

########################################################################
# create Docker image
########################################################################
$(CACHE_DIR)/image: \
    $(CACHE_DIR)/cpanfile \
    $(DIST_TARBALL) \
    $(CACHE_DIR)/debian-packages \
    $(CACHE_DIR)/tarball-validated | $(CACHE_DIR)
	$(NO_ECHO)alr-helper report-step $@ start; \
	test -e $@ && chmod -f 644 $@; \
	buildctx=$$(mktemp -d); trap 'rm -rf $$buildctx' EXIT; \
	cp $(FRAMEWORK_DIR)/Dockerfile $$buildctx/; \
	cp $(CACHE_DIR)/cpanfile $$buildctx/; \
	cp $(DIST_TARBALL) $$buildctx/; \
        test -e requires.reinstall && cp requires.reinstall $$buildctx/; \
	if [[ -n "$(RESOLVER)" ]]; then \
	  resolver="--build-arg RESOLVER=\"--resolver $(RESOLVER)\""; \
	fi; \
	alr-helper report-step $@ docker-build start; \
	docker build $(NO_CACHE) \
	  --build-arg DIST_TARBALL=$$(basename $(DIST_TARBALL)) \
	  --build-arg CACHE_BUST="$(CACHE_BUST)" \
	  --build-arg HANDLER_CLASS=$(HANDLER_CLASS) \
	  --build-arg EXTRA_BUILD_PACKAGES="$(EXTRA_BUILD_PACKAGES)" \
	  --build-arg EXTRA_RUNTIME_PACKAGES="$(EXTRA_RUNTIME_PACKAGES)" \
	  $$(test -n "$(PLATFORM_IMAGE)" && echo "--build-arg PLATFORM_IMAGE=$(PLATFORM_IMAGE)") \
	  $$resolver \
	  -f $$buildctx/Dockerfile -t $(REPO_NAME) $$buildctx 2>&1 && \
	alr-helper report-step $@ docker-build ok; \
	docker inspect $(REPO_NAME):latest > $@ && chmod 444 $@ || { rm -f $@; exit 1; }; \
	alr-helper report-step $@ docker-inspect ok; \
	alr-helper report-step $@ done ok


include $(FRAMEWORK_DIR)/ecr-create-repo.mk

########################################################################
# push image to ECR repository
########################################################################
$(CACHE_DIR)/deploy: $(CACHE_DIR)/ecr-repo $(CACHE_DIR)/image | $(CACHE_DIR)
	$(NO_ECHO)alr-helper report-step $@ start; \
	chmod -f 644 $@ 2>/dev/null || true; \
	URI="$$(cat $(CACHE_DIR)/ecr-repo)"; \
	PASSWORD="$$(alr-helper --report-step $@ get-login-password)"; \
	echo "$$PASSWORD" | docker login --username AWS --password-stdin $$URI; \
	alr-helper report-step $@ docker-login ok; \
	docker tag $(REPO_NAME):latest $$URI:latest; \
	alr-helper report-step $@ docker-tag ok; \
	alr-helper report-step $@ docker-push start; \
	docker push $$URI:latest > $@ && chmod 444 $@ || { rm -f $@; exit 1; }; \
	alr-helper report-step $@ docker-push ok; \
	alr-helper report-step $@ done ok

########################################################################
# create Lambda role & policy
########################################################################

$(CACHE_DIR)/policy-document: | $(CACHE_DIR)
	$(NO_ECHO)alr-helper report-step $@ start; \
	chmod -f 644 $@ || true; \
	alr-helper --report-step $@ create-assume-policy lambda.amazonaws.com > $@ && \
	chmod 444 $@ || { rm -f $@; exit 1; }; \
	alr-helper report-step $@ done ok

$(CACHE_DIR)/lambda-role: $(CACHE_DIR)/policy-document | $(CACHE_DIR)
	$(NO_ECHO)alr-helper report-step $@ start; \
	chmod -f 644 $@ 2>/dev/null || true; \
	if alr-helper --report-step $@ get-role $(ROLE_NAME) > $@ 2>/dev/null; then \
	  echo "role $(ROLE_NAME) already exists"; \
	  chmod 444 $@; \
	else \
	  alr-helper --report-step $@ create-role $(ROLE_NAME) $< > $@ && chmod 444 $@ || { rm -f $@; exit 1; }; \
	fi; \
	alr-helper report-step $@ done ok

POLICIES_FILE        ?= policies
CUSTOM_POLICIES_FILE ?= custom-policies.json

ifeq ($(ROLE_PROFILE),)
  ifeq ($(wildcard $(POLICIES_FILE)),)
    $(error No policies file '$(POLICIES_FILE)' found and ROLE_PROFILE is not set. \
      Either create a policies file or set ROLE_PROFILE in $(LAMBDA_ENV))
  endif
  ATTACH_POLICIES_CMD = alr-helper attach-policy $(ROLE_NAME) $(POLICIES_FILE)
  POLICIES_PREREQ     = $(POLICIES_FILE)
else
  ATTACH_POLICIES_CMD = alr-helper attach-policies-from-profile $(ROLE_NAME) $(ROLE_PROFILE)
  POLICIES_PREREQ     = $(LAMBDA_ENV)
endif

$(CACHE_DIR)/lambda-managed-policies: $(CACHE_DIR)/lambda-role $(POLICIES_PREREQ) | $(CACHE_DIR)
	$(NO_ECHO)alr-helper report-step $@ start; \
	chmod -f 644 $@ 2>/dev/null || true; \
	policies=$$(mktemp); trap 'rm -f $$policies' EXIT; \
	$(ATTACH_POLICIES_CMD) --report-step $@ > $$policies && cp $$policies $@ && chmod 444 $@ || { rm -f $@; exit 1; }; \
	alr-helper report-step $@ done ok;


$(CACHE_DIR)/lambda-inline-policies: $(CACHE_DIR)/lambda-role $(wildcard $(CUSTOM_POLICIES_FILE)) | $(CACHE_DIR)
	$(NO_ECHO)alr-helper report-step $@ start; \
	chmod -f 644 $@ 2>/dev/null || true; \
	if [[ -e "$(CUSTOM_POLICIES_FILE)" ]]; then \
	  alr-helper --report-step $@ put-role-policies role-name:$(ROLE_NAME) policy-document:file://$(CUSTOM_POLICIES_FILE) || { rm -f $@; exit 1; }; \
	fi; \
	echo "$(CUSTOM_POLICIES_FILE)" > $@ && chmod 444 $@; \
	alr-helper report-step $@ done ok

$(CACHE_DIR)/lambda-policies: $(CACHE_DIR)/lambda-managed-policies $(CACHE_DIR)/lambda-inline-policies | $(CACHE_DIR)
	$(NO_ECHO)touch $@ && chmod 444 $@

.PHONY: update-managed-policies
update-managed-policies: $(POLICIES_PREREQ) ## re-attach AWS managed IAM policies
	$(NO_ECHO)alr-helper report-step $@ start; \
	chmod -f 644 $(CACHE_DIR)/lambda-managed-policies 2>/dev/null || true; \
	rm -f $(CACHE_DIR)/lambda-managed-policies; \
	$(MAKE) -f $(firstword $(MAKEFILE_LIST)) $(CACHE_DIR)/lambda-managed-policies; \
	alr-helper report-step $@ done ok

.PHONY: update-inline-policies
update-inline-policies: ## re-apply custom inline IAM policies from $(CUSTOM_POLICIES_FILE)
	$(NO_ECHO)alr-helper report-step $@ start; \
	chmod -f 644 $(CACHE_DIR)/lambda-inline-policies 2>/dev/null || true; \
	rm -f $(CACHE_DIR)/lambda-inline-policies; \
	$(MAKE) -f $(firstword $(MAKEFILE_LIST)) $(CACHE_DIR)/lambda-inline-policies;
	alr-helper report-step $@ done ok

.PHONY: update-policies
update-policies: update-managed-policies update-inline-policies ## re-attach all IAM policies (managed + custom inline)

########################################################################
# create/update Lambda function
########################################################################

$(CACHE_DIR)/image-digest: $(CACHE_DIR)/deploy | $(CACHE_DIR)
	$(NO_ECHO)alr-helper report-step $@ start; \
	chmod -f 644 $@ 2>/dev/null || true; \
	digest="$$(alr-helper --report-step $@ describe-images $(REPO_NAME) filter=imageDigest)"; \
	echo "$$digest" > $@ && chmod 444 $@ || { rm -f $@; exit 1; }; \
	alr-helper report-step $@ done ok;

$(CACHE_DIR)/lambda-function: \
    $(CACHE_DIR)/image-digest \
    $(CACHE_DIR)/ecr-repo \
    $(CACHE_DIR)/lambda-role \
    $(CACHE_DIR)/lambda-policies | $(CACHE_DIR)
	$(NO_ECHO)alr-helper report-step $@ start; \
	chmod -f 644 $@ 2>/dev/null || true; \
	DIGEST="$$(cat $(CACHE_DIR)/image-digest)"; \
	URI="$$(cat $(CACHE_DIR)/ecr-repo)"; \
	function="$$(alr-helper --report-step $@ get-function $(FUNCTION_NAME) 2>/dev/null)"; \
	if echo "$$function" | grep -q '"FunctionName"'; then \
	  response="$$(alr-helper --report-step $@ update-function $(FUNCTION_NAME) $$URI $$DIGEST)"; \
	elif [[ -z "$$function" ]]; then \
	  response="$$(alr-helper --report-step $@ create-function $(FUNCTION_NAME) $(ROLE_NAME) $$URI)"; \
	else \
	  echo "ERROR: get-function failed: $$function" >&2; exit 1; \
	fi; \
	echo "$$URI@$$DIGEST" > $@ && chmod 444 $@ || { rm -f $@; exit 1; }; \
	alr-helper report-step $@ done ok;

MEMORY ?= 128

$(CACHE_DIR)/lambda-configuration: $(CACHE_DIR)/lambda-function $(CACHE_DIR)/log-group $(LAMBDA_ENV) $(wildcard lambda-handler.env) | $(CACHE_DIR)
	$(NO_ECHO)alr-helper report-step $@ start; \
	chmod -f 644 $@ 2>/dev/null || true; \
	alr-helper --report-step $@ update-function-configuration $(FUNCTION_NAME) \
	  memory-size:$(MEMORY) timeout:$(TIMEOUT) > $@ && chmod 444 $@; \
	alr-helper report-step $@ done ok

lambda-configuration: $(CACHE_DIR)/lambda-configuration ## update function memory/timeout from $(LAMBDA_ENV)

.PHONY: update-lambda-configuration
update-lambda-configuration: ## force update of Lambda function configuration from $(LAMBDA_ENV)
	$(NO_ECHO)alr-helper report-step $@ start; \
	rm -f $(CACHE_DIR)/lambda-configuration || true; \
	$(MAKE) -f $(firstword $(MAKEFILE_LIST)) lambda-configuration; \
	alr-helper report-step $@ done ok

.PHONY: lambda-pipeline
lambda-pipeline: ## provision full Lambda infrastructure for trigger type
ifneq ($(PLATFORM_IMAGE),)
ifneq ($(wildcard Dockerfile.platform),)
	$(MAKE) platform
endif
endif
ifeq ($(TRIGGER_TYPE),eventbridge)
	$(MAKE) lambda-eventbridge-pipeline
else ifeq ($(TRIGGER_TYPE),s3-sqs)
	$(MAKE) lambda-sqs-pipeline
else ifeq ($(TRIGGER_TYPE),s3-direct)
	$(MAKE) lambda-s3-pipeline
else ifeq ($(TRIGGER_TYPE),sns)
	$(MAKE) lambda-sns-pipeline
else ifeq ($(TRIGGER_TYPE),alb)
	$(MAKE) lambda-alb-pipeline
else
	$(error Unknown or unset TRIGGER_TYPE: '$(TRIGGER_TYPE)'. \
	  Set TRIGGER_TYPE in lambda.env to one of: s3-sqs, eventbridge, s3-direct, sns, alb)
endif
ifneq ($(OVERLAY),)
	$(MAKE) overlay
endif

.PHONY: lambda-teardown
lambda-teardown: ## deprovision Lambda and all trigger-type infrastructure
ifeq ($(TRIGGER_TYPE),eventbridge)
	$(MAKE) lambda-eventbridge-teardown
else ifeq ($(TRIGGER_TYPE),s3-sqs)
	$(MAKE) lambda-sqs-teardown
else ifeq ($(TRIGGER_TYPE),s3-direct)
	$(MAKE) lambda-s3-teardown
else ifeq ($(TRIGGER_TYPE),sns)
	$(MAKE) lambda-sns-teardown
else ifeq ($(TRIGGER_TYPE),alb)
	$(MAKE) lambda-alb-teardown
else
	$(error Unknown or unset TRIGGER_TYPE: '$(TRIGGER_TYPE)'. \
	  Set TRIGGER_TYPE in lambda.env to one of: s3-sqs, eventbridge, s3-direct, sns, alb)
endif
ifneq ($(OVERLAY),)
	$(MAKE) overlay-teardown
endif
	$(MAKE) log-group-teardown

########################################################################
# invoke Lambda function
########################################################################

invoke: ## invoke Lambda function with test payload $(CACHE_DIR)/lambda-function payload.json
	$(NO_ECHO)alr-helper invoke-function $(FUNCTION_NAME) $(PAYLOAD)

########################################################################
# SNS
#   make TOPIC_NAME=my-topic FUNCTION_NAME=my-fn lambda-sns-pipeline
#   make lambda-sns-teardown
#   make sns   (test-invoke only)
########################################################################
include $(FRAMEWORK_DIR)/sns.mk

########################################################################
# SQS
#   make lambda-sqs-trigger QUEUE_NAME=lambda-runtime
########################################################################
include $(FRAMEWORK_DIR)/sqs.mk

########################################################################
# EventBridge
#   make lambda-eventbridge-trigger
#   make disable-eventbridge-rule
#   make enable-eventbridge-rule
#   make delete-eventbridge-rule
########################################################################
include $(FRAMEWORK_DIR)/eventbridge.mk

########################################################################
# S3
#   make lambda-s3-trigger BUCKET_NAME=some-bucket
#   aws s3 cp some-file s3://some-bucket/some-file
########################################################################
include $(FRAMEWORK_DIR)/s3.mk

include $(FRAMEWORK_DIR)/alb.mk

include $(FRAMEWORK_DIR)/log-group.mk

include $(FRAMEWORK_DIR)/overlay.mk

include $(FRAMEWORK_DIR)/platform.mk

include $(FRAMEWORK_DIR)/streaming.mk

CLEANFILES = \
    $(CACHE_DIR)/tarball-validated \
    $(CACHE_DIR)/deploy \
    $(CACHE_DIR)/ecr-repo \
    $(CACHE_DIR)/ecr-uri \
    $(CACHE_DIR)/ecr-lifecycle-policy \
    $(CACHE_DIR)/image \
    $(CACHE_DIR)/image-digest \
    $(CACHE_DIR)/lambda-function \
    $(CACHE_DIR)/lambda-function-url \
    $(CACHE_DIR)/lambda-function-url-permission \
    $(CACHE_DIR)/lambda-function-url-invoke-permission \
    $(CACHE_DIR)/lambda-policies \
    $(CACHE_DIR)/lambda-managed-policies \
    $(CACHE_DIR)/lambda-inline-policies \
    $(CACHE_DIR)/lambda-role \
    $(CACHE_DIR)/lambda-s3-permission \
    $(CACHE_DIR)/lambda-eventbridge-rule \
    $(CACHE_DIR)/lambda-eventbridge-permission \
    $(CACHE_DIR)/lambda-eventbridge-trigger \
    $(CACHE_DIR)/lambda-sqs-trigger \
    $(CACHE_DIR)/lambda-s3-trigger \
    $(CACHE_DIR)/lambda-configuration \
    $(CACHE_DIR)/lambda-sqs-response-types \
    $(CACHE_DIR)/policy-document \
    $(CACHE_DIR)/sns \
    $(CACHE_DIR)/sns-topic \
    $(CACHE_DIR)/lambda-sns-permission \
    $(CACHE_DIR)/lambda-sns-trigger \
    $(CACHE_DIR)/sqs-queue \
    $(CACHE_DIR)/s3-bucket \
    $(CACHE_DIR)/sqs-dlq \
    $(CACHE_DIR)/sqs-queue-policy \
    $(CACHE_DIR)/sqs-queue-redrive \
    $(CACHE_DIR)/lambda-sqs-permission \
    $(CACHE_DIR)/lambda-s3-sqs-trigger \
    $(CACHE_DIR)/lambda-concurrency \
    $(CACHE_DIR)/alb-lambda-permission \
    $(CACHE_DIR)/alb-target-group \
    $(CACHE_DIR)/alb-target-group-registration \
    $(CACHE_DIR)/alb-listener-rule \
    $(CACHE_DIR)/cpanfile \
    $(CACHE_DIR)/log-group \
    $(CACHE_DIR)/debian-packages \
    $(CACHE_DIR)/overlay-ecr-repo \
    $(CACHE_DIR)/platform \
    $(CACHE_DIR)/platform-ecr-repo

clean: ## remove all generated sentinels and docker artifacts
	$(NO_ECHO)for a in $(CLEANFILES); do \
	  chmod 644 $$a 2>/dev/null || true; \
	done; \
	rm -f $(CLEANFILES)

.PHONY: \
    lambda-policies \
    lambda-function \
    lambda-eventbridge-trigger \
    lambda-role \
    ecr-repo \
    ecr-uri \
    ecr-lifecycle-policy \
    deploy \
    image \
    invoke \
    update-policies \
    update-managed-policies \
    update-inline-policies \
    lambda-s3-trigger \
    lambda-sqs-trigger \
    lambda-sns-trigger \
    sns

.PHONY: show-makefiles
show-makefiles:
	echo $(MAKEFILE_LIST)
