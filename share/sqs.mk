#-*- mode: makefile; -*-

########################################################################
# SQS Lambda Handler Infrastructure
#
# Full indexer setup:
#   make QUEUE_NAME=orepan2-indexer \
#        BUCKET_NAME=cpan.openbedrock.net \
#        KEY_PREFIX=authors/id/ \
#        FUNCTION_NAME=orepan2-indexer \
#        lambda-sqs-indexer
#
# Test queue only:
#   make QUEUE_NAME=fu-man-queue lambda-sqs-trigger
#
########################################################################

QUEUE_NAME         ?= lambda-runtime
DLQ_NAME           ?= $(QUEUE_NAME)-dlq
DLQ_RETENTION      ?= 1209600
BATCH_SIZE         ?= 1
RETENTION          ?= 86400
VISIBILITY_TIMEOUT ?= 360
RECEIVE_COUNT      ?= 3
S3_EVENT           ?= s3:ObjectCreated:*
CONCURRENCY        ?= 1

$(CACHE_DIR)/sqs-queue-redrive: $(CACHE_DIR)/sqs-queue $(CACHE_DIR)/sqs-dlq | $(CACHE_DIR) ## ensure redrive policy is set on queue
	$(NO_ECHO)policy="$$(alr-helper get-queue-attributes $(QUEUE_NAME) RedrivePolicy | \
	  perl -MJSON -0ne '$$r=decode_json($$_); print $$r->{Attributes}{RedrivePolicy}//q{}')"; \
	if [[ -z "$$policy" ]]; then \
	    alr-helper set-queue-redrive-policy \
	        $(QUEUE_NAME) \
	        $(DLQ_NAME) \
	        $(RECEIVE_COUNT) || exit 1; \
	fi; \
	echo "$(QUEUE_NAME)" > $@ && chmod 444 $@ || rm -f $@

$(CACHE_DIR)/sqs-dlq: | $(CACHE_DIR) ## create dead letter queue
	$(NO_ECHO)queue="$$(alr-helper list-queues | \
	  perl -MJSON -0ne 'for(@{decode_json($$_)->{QueueUrls}//[]}){print if /\/$(DLQ_NAME)$$/}' 2>&1)"; \
	if echo "$$queue" | grep -q 'error\|Error'; then \
	    echo "ERROR: list-queues failed: $$queue" >&2; \
	    exit 1; \
	elif [[ -z "$$queue" || "$$queue" = "None" ]]; then \
	    alr-helper create-queue $(DLQ_NAME) \
	        retention:$(DLQ_RETENTION); \
	    queue="$(DLQ_NAME)"; \
	fi; \
	if [[ -z "$$queue" ]]; then \
	  echo "ERROR: could not create/find queue $(DLQ_NAME)" >&2; exit 1; \
	fi; \
	echo "$$queue" > $@ || { rm -f $@ && exit 1; }; \
	chmod 444 $@

$(CACHE_DIR)/sqs-queue: $(CACHE_DIR)/sqs-dlq | $(CACHE_DIR) ## create SQS queue with visibility timeout and redrive policy
	$(NO_ECHO)queue="$$(alr-helper list-queues | \
	  perl -MJSON -0ne 'for(@{decode_json($$_)->{QueueUrls}//[]}){print if /\/$(QUEUE_NAME)$$/}' 2>&1)"; \
	if echo "$$queue" | grep -q 'error\|Error'; then \
	    echo "ERROR: list-queues failed: $$queue" >&2; \
	    exit 1; \
	elif [[ -z "$$queue" || "$$queue" = "None" ]]; then \
	    alr-helper create-queue $(QUEUE_NAME) \
	        retention:$(RETENTION) \
	        timeout:$(VISIBILITY_TIMEOUT) \
	        receive_count:$(RECEIVE_COUNT) \
	        dlq:$(DLQ_NAME) || { rm -f $@ && exit 1; }; \
	   queue=$(QUEUE_NAME); \
	fi; \
	echo "$$queue" > $@ || { rm -f $@ && exit 1; }; \
	chmod 444 $@

$(CACHE_DIR)/sqs-queue-policy: $(CACHE_DIR)/sqs-queue | $(CACHE_DIR) ## grant S3 permission to send messages to the queue
	$(NO_ECHO)alr-helper set-queue-bucket-policy \
	    $(QUEUE_NAME) \
	    $(BUCKET_NAME) || exit 1; \
	echo "$(QUEUE_NAME)" > $@ || { rm -f $@ && exit 1; }; \
	chmod 444 $@

$(CACHE_DIR)/lambda-concurrency: $(CACHE_DIR)/lambda-function | $(CACHE_DIR) ## set Lambda reserved concurrency to 1 for serial indexing
	$(NO_ECHO)alr-helper put-function-concurrency $(FUNCTION_NAME) $(CONCURRENCY) || exit 1; \
	echo "$(FUNCTION_NAME)" > $@ || { rm -f $@ && exit 1; }; \
	chmod 444 $@

$(CACHE_DIR)/lambda-sqs-trigger: \
    $(CACHE_DIR)/lambda-function \
    $(CACHE_DIR)/sqs-queue \
    $(CACHE_DIR)/sqs-queue-redrive \
    $(CACHE_DIR)/lambda-sqs-permission | $(CACHE_DIR)
	$(NO_ECHO)trigger="$$(alr-helper list-eventsource-mappings \
	    $(FUNCTION_NAME) \
	    queue:$(QUEUE_NAME) | \
	  perl -MJSON -0ne '$$r=decode_json($$_); print $$r->{EventSourceMappings}[0]{UUID}//q{}')"; \
	if [[ -z "$$trigger" || "$$trigger" = "None" ]]; then \
	  trigger="$$(alr-helper create-eventsource-mappings \
	    $(FUNCTION_NAME) queue:$(QUEUE_NAME) \
	    batch-size:$(BATCH_SIZE))"; \
	  uuid=$$(echo "$$trigger" | perl -MJSON -0ne '$$r=decode_json($$_); print $$r->{UUID}//q{}'); \
	  alr-helper wait-eventsource-mapping-enabled $$uuid; \
	fi; \
	test -z "$$trigger" && { rm -f $@ && exit 1; }; \
	echo "$$trigger" > $@ || { rm -f $@ && exit 1; }; \
	chmod 444 $@

$(CACHE_DIR)/lambda-s3-sqs-trigger: $(CACHE_DIR)/sqs-queue-policy | $(CACHE_DIR) ## update S3 bucket notification to deliver to SQS
	$(NO_ECHO)alr-helper put-bucket-notification \
	    $(BUCKET_NAME) \
	    sqs:$(QUEUE_NAME) \
	    event:$(S3_EVENT) \
	    name:prefix,value:$(KEY_PREFIX) || exit 1; \
	echo "$(QUEUE_NAME)" > $@ || { rm -f $@ && exit 1; }; \
	chmod 444 $@

.PHONY: lambda-sqs-pipeline
lambda-sqs-pipeline: \
    $(CACHE_DIR)/lambda-sqs-trigger \
    $(CACHE_DIR)/lambda-concurrency \
    $(CACHE_DIR)/lambda-configuration \
    $(CACHE_DIR)/lambda-s3-sqs-trigger \
    $(CACHE_DIR)/lambda-sqs-response-types

$(CACHE_DIR)/lambda-sqs-permission: $(CACHE_DIR)/lambda-function $(CACHE_DIR)/sqs-queue | $(CACHE_DIR)
	$(NO_ECHO)permission="$$(alr-helper get-lambda-policy $(FUNCTION_NAME) 2>&1 || true)"; \
	if echo "$$permission" | grep -q 'ResourceNotFoundException' || \
	   ! echo "$$permission" | grep -q 'sqs.amazonaws.com'; then \
	    alr-helper add-permission \
	        $(FUNCTION_NAME) \
	        sqs-trigger-$(QUEUE_NAME) \
	        lambda:InvokeFunction \
	        sqs.amazonaws.com \
	        arn:aws:sqs:$(REGION):$(AWS_ACCOUNT):$(QUEUE_NAME) || { rm -f $@ && exit 1; }; \
	fi; \
	test -e $@ || echo "$(QUEUE_NAME)" > $@ || { rm -f $@ && exit 1; }; \
	chmod 444 $@ 

PARTIAL_BATCH_RESPONSE ?= false

ifeq ($(PARTIAL_BATCH_RESPONSE),true)
  RESPONSE_TYPES_ARG = response-types:@ReportBatchItemFailures
else
  RESPONSE_TYPES_ARG = response-types:@
endif

$(CACHE_DIR)/lambda-sqs-response-types: $(CACHE_DIR)/lambda-sqs-trigger lambda.env | $(CACHE_DIR)
	$(NO_ECHO)chmod -f 644 $@ 2>/dev/null || true; \
	uuid=$$(alr-helper list-eventsource-mappings $(FUNCTION_NAME) queue:$(QUEUE_NAME) | \
	  perl -MJSON -0ne '$$r=decode_json($$_); print $$r->{EventSourceMappings}[0]{UUID}//q{}'); \
	alr-helper wait-eventsource-mapping-enabled $$uuid; \
	rsp="$$(alr-helper update-eventsource-mapping uuid:$$uuid $(RESPONSE_TYPES_ARG))"; \
	test -n "$$rsp" || { rm -f $@ && exit 1; }; \
	echo "$$rsp" > $@ || { rm -f $@ && exit 1; }; \
	chmod 444 $@

.PHONY: lambda-sqs-teardown
lambda-sqs-teardown: _lambda-sqs-teardown clean ## deprovision full s3-sqs stack

.PHONY: _lambda-sqs-teardown
_lambda-sqs-teardown:
	$(NO_ECHO)alr-helper remove-bucket-notification $(BUCKET_NAME) || true; \
	uuid=$$(alr-helper list-eventsource-mappings $(FUNCTION_NAME) queue:$(QUEUE_NAME) 2>/dev/null | \
	  perl -MJSON -0ne '$$r=decode_json($$_); print $$r->{EventSourceMappings}[0]{UUID}//q{}'); \
	if [[ -n "$$uuid" ]]; then \
	  alr-helper delete-eventsource-mappings $$uuid || true; \
	fi; \
	alr-helper delete-queue $(QUEUE_NAME) || true; \
	alr-helper delete-queue $(DLQ_NAME) || true; \
	alr-helper delete-function $(FUNCTION_NAME) || true; \
	alr-helper detach-all-policies $(ROLE_NAME) || true; \
	alr-helper delete-role $(ROLE_NAME) || true; \
	alr-helper delete-repo $(REPO_NAME) || true
