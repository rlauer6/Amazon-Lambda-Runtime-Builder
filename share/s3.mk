#-*- mode: makefile; -*-

########################################################################
# S3 Lambda Handler test
# 
#  make BUCKET_NAME=cpan.openbedrock.net lambda-s3-trigger
#
########################################################################

BUCKET_NAME ?= my-bucket
S3_EVENT    ?= s3:ObjectCreated:*

$(CACHE_DIR)/s3-bucket: ## create S3 bucket for Lambda trigger | $(CACHE_DIR)
	$(NO_ECHO)bucket="$$(alr-helper list-buckets | \
	  perl -MJSON -0ne 'for(@{decode_json($$_)}){print $$_->{Name} if $$_->{Name} eq "$(BUCKET_NAME)"}')"; \
	if [[ -z "$$bucket" ]]; then \
	  alr-helper create-bucket $(BUCKET_NAME); \
	  bucket="$(BUCKET_NAME)"; \
	fi; \
	test -e $@ || echo "$$bucket" > $@

$(CACHE_DIR)/lambda-s3-permission: ## grant S3 permission to invoke Lambda $(CACHE_DIR)/lambda-function $(CACHE_DIR)/s3-bucket | $(CACHE_DIR)
	$(NO_ECHO)permission="$$(alr-helper get-lambda-policy $(FUNCTION_NAME) 2>&1 || true)"; \
	if echo "$$permission" | grep -q 'ResourceNotFoundException' || \
	   ! echo "$$permission" | grep -q s3.amazonaws.com; then \
	    permission="$$(alr-helper add-permission \
	        $(FUNCTION_NAME) \
	        s3-trigger-$(BUCKET_NAME) \
	        lambda:InvokeFunction \
	        s3.amazonaws.com \
	        arn:aws:s3:::$(BUCKET_NAME))"; \
	elif echo "$$permission" | grep -q 'error\|Error'; then \
	    echo "ERROR: get-lambda-policy failed: $$permission" >&2; \
	    exit 1; \
	fi; \
	if [[ -n "$$permission" ]]; then \
	    test -e $@ || echo "$$permission" > $@; \
	else \
	    rm -f $@; \
	fi

$(CACHE_DIR)/lambda-s3-trigger: ## configure S3 bucket notification trigger $(CACHE_DIR)/lambda-s3-permission | $(CACHE_DIR)
	$(NO_ECHO)if [[ -z "$(KEY_PREFIX)" ]]; then \
	  echo >&2 "ERROR: missing KEY_PREFIX"; \
	  exit 1; \
	fi; \
	trigger="$$(alr-helper put-bucket-notification \
	    $(BUCKET_NAME) \
	    $(FUNCTION_NAME) \
	    event:$(S3_EVENT) \
	    name:prefix,value:$(KEY_PREFIX))"; \
	test -e $@ || echo "$$trigger" > $@
