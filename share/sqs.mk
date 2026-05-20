#-*- mode: makefile; -*-

########################################################################
# SQS Lambda Handler test
# 
# make QUEUE_NAME=fu-man-queue lambda-sqs-trigger
#
########################################################################

QUEUE_NAME ?= lambda-runtime
BATCH_SIZE ?= 10

$(CACHE_DIR)/sqs-queue: ## create SQS queue | $(CACHE_DIR)
	$(NO_ECHO)queue="$$(alr-helper list-queues | \
	  perl -MJSON -0ne 'for(@{decode_json($$_)->{QueueUrls}//[]}){print if /$(QUEUE_NAME)/}' 2>&1)"; \
	if echo "$$queue" | grep -q 'error\|Error'; then \
	    echo "ERROR: list-queues failed: $$queue" >&2; \
	    exit 1; \
	elif [[ -z "$$queue" || "$$queue" = "None" ]]; then \
	    alr-helper create-queue $(QUEUE_NAME); \
	    queue="$(QUEUE_NAME)"; \
	fi; \
	test -e $@ || echo "$$queue" > $@

$(CACHE_DIR)/lambda-sqs-trigger: ## create SQS event source mapping $(CACHE_DIR)/lambda-function $(CACHE_DIR)/sqs-queue | $(CACHE_DIR)
	$(NO_ECHO)trigger="$$(alr-helper list-event-source-mappings \
	    $(FUNCTION_NAME) \
	    arn:aws:sqs:$(REGION):$(AWS_ACCOUNT):$(QUEUE_NAME) | \
	  perl -MJSON -0ne '$$r=decode_json($$_); print $$r->{EventSourceMappings}[0]{UUID}//"")"; \
	if [[ -z "$$trigger" || "$$trigger" = "None" ]]; then \
	  trigger="$$(alr-helper create-event-source-mappings \
	    $(FUNCTION_NAME) \
	    arn:aws:sqs:$(REGION):$(AWS_ACCOUNT):$(QUEUE_NAME) \
	    $(BATCH_SIZE))"; \
	fi; \
	test -e $@ || echo "$$trigger" > $@
