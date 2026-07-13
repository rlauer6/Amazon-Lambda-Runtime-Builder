#-*- mode: makefile; -*-

BUCKET_NAME ?= my-bucket
S3_EVENT    ?= s3:ObjectCreated:*

########################################################################
# s3-direct pipeline
########################################################################

CREATE_BUCKET ?= false

$(CACHE_DIR)/s3-bucket: | $(CACHE_DIR)
	$(NO_ECHO)alr-helper report-step $@ start; \
	chmod -f 644 $@ || true; \
	bucket="$$(alr-helper list-buckets $(BUCKET_NAME))"; \
	if [[ -z "$$bucket" ]]; then \
	  if [[ "$(CREATE_BUCKET)" != "true" ]]; then \
	    echo "ERROR: bucket '$(BUCKET_NAME)' does not exist. CREATE_BUCKET=true to create it." >&2; \
	    exit 1; \
	  fi; \
	  echo "Creating bucket $(BUCKET_NAME)..." >&2; \
	  alr-helper --report-step $@ create-bucket $(BUCKET_NAME) || exit 1; \
	  bucket="$(BUCKET_NAME)"; \
	fi; \
	echo "$$bucket" > $@ || { rm -f $@ && exit 1; }; \
	chmod 444 $@; \
	alr-helper report-step $@ done ok

$(CACHE_DIR)/lambda-s3-permission: \
    $(CACHE_DIR)/lambda-function \
    $(CACHE_DIR)/s3-bucket | $(CACHE_DIR)
	$(NO_ECHO)alr-helper report-step $@ start; \
	chmod -f 644 $@ || true; \
	permission="$$(alr-helper get-lambda-policy $(FUNCTION_NAME) 2>&1 || true)"; \
	if echo "$$permission" | grep -q 'ResourceNotFoundException' || \
	   ! echo "$$permission" | grep -q 's3.amazonaws.com'; then \
	    alr-helper --report-step $@ add-permission \
	        $(FUNCTION_NAME) \
	        s3-trigger-$(BUCKET_NAME) \
	        lambda:InvokeFunction \
	        s3.amazonaws.com \
	        arn:aws:s3:::$(BUCKET_NAME) || exit 1; \
	elif echo "$$permission" | grep -q 'error\|Error'; then \
	  echo "ERROR: get-lambda-policy failed: $$permission" >&2; \
	  alr-helper report-step $@ done fail; \
	  exit 1; \
	fi; \
	echo "$(BUCKET_NAME)" > $@ || { rm -f $@ && exit 1; }; \
	chmod 444 $@; \
	alr-helper report-step $@ done ok

$(CACHE_DIR)/lambda-s3-trigger: \
    $(CACHE_DIR)/lambda-s3-permission \
    $(CACHE_DIR)/lambda-configuration | $(CACHE_DIR)
	$(NO_ECHO)alr-helper report-step $@ start; \
	chmod -f 644 $@ || true; \
	notification_args="$(BUCKET_NAME) lambda:$(FUNCTION_NAME) event:$(S3_EVENT)"; \
	if [[ -n "$(KEY_PREFIX)" ]]; then \
	  notification_args="$$notification_args name:prefix,value:$(KEY_PREFIX)"; \
	fi; \
	alr-helper --report-step $@ put-bucket-notification $$notification_args || exit 1; \
	echo "$(BUCKET_NAME)" > $@ || { rm -f $@ && exit 1; }; \
	chmod 444 $@; \
	alr-helper report-step $@ done ok

.PHONY: lambda-s3-pipeline
lambda-s3-pipeline: \
    $(CACHE_DIR)/lambda-s3-trigger ## full s3-direct infrastructure

.PHONY: _lambda-s3-teardown
_lambda-s3-teardown:
	$(NO_ECHO)alr-helper report-step $@ start; \
	alr-helper --report-step $@ remove-bucket-notification $(BUCKET_NAME) || true; \
	alr-helper --report-step $@ remove-permission $(FUNCTION_NAME) s3-trigger-$(BUCKET_NAME) || true; \
	alr-helper --report-step $@ delete-function $(FUNCTION_NAME) || true; \
	alr-helper --report-step $@ detach-all-policies $(ROLE_NAME) || true; \
	alr-helper --report-step $@ delete-role $(ROLE_NAME) || true; \
	alr-helper --report-step $@ delete-repo $(REPO_NAME) || true; \
	alr-helper --report-step $@ report-step $@ done ok

.PHONY: lambda-s3-teardown
lambda-s3-teardown: _lambda-s3-teardown clean ## deprovision full s3-direct stack
