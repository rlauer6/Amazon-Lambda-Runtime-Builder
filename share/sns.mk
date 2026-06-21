#-*- mode: makefile; -*-

########################################################################
# SNS Lambda Handler Infrastructure
#
# Full pipeline:
#   make TOPIC_NAME=orepan2-events \
#        FUNCTION_NAME=orepan2-s3-handler \
#        lambda-sns-pipeline
#
# Test invoke only:
#   make PAYLOAD=payload-sns.json sns
########################################################################

TOPIC_NAME ?= lambda-runtime

$(CACHE_DIR)/sns-topic: | $(CACHE_DIR) ## create SNS topic (CreateTopic is naturally idempotent)
	$(NO_ECHO)topic_arn="$$(alr-helper create-topic $(TOPIC_NAME) | \
	  perl -MJSON -0ne '$$r=decode_json($$_); print $$r->{TopicArn}//q{}')"; \
	test -z "$$topic_arn" && { rm -f $@ && exit 1; }; \
	echo "$$topic_arn" > $@ || { rm -f $@ && exit 1; }; \
	chmod 444 $@

$(CACHE_DIR)/lambda-sns-permission: $(CACHE_DIR)/lambda-function $(CACHE_DIR)/sns-topic | $(CACHE_DIR) ## grant SNS permission to invoke Lambda
	$(NO_ECHO)permission="$$(alr-helper get-lambda-policy $(FUNCTION_NAME) 2>&1 || true)"; \
	if echo "$$permission" | grep -q 'ResourceNotFoundException' || \
	   ! echo "$$permission" | grep -q 'sns.amazonaws.com'; then \
	    topic_arn="$$(cat $(CACHE_DIR)/sns-topic)"; \
	    alr-helper add-permission \
	        $(FUNCTION_NAME) \
	        sns-trigger-$(TOPIC_NAME) \
	        lambda:InvokeFunction \
	        sns.amazonaws.com \
	        $$topic_arn || { rm -f $@ && exit 1; }; \
	fi; \
	test -e $@ || echo "$(TOPIC_NAME)" > $@ || { rm -f $@ && exit 1; }; \
	chmod 444 $@

$(CACHE_DIR)/lambda-sns-trigger: \
    $(CACHE_DIR)/lambda-function \
    $(CACHE_DIR)/sns-topic \
    $(CACHE_DIR)/lambda-sns-permission | $(CACHE_DIR) ## subscribe Lambda function to SNS topic
	$(NO_ECHO)topic_arn="$$(cat $(CACHE_DIR)/sns-topic) || true"; \
	if [[ -n "$$topic_arn" ]]; then \
	  lambda_arn="$$(alr-helper get-function-arn $(FUNCTION_NAME))"; \
	  test -z "$$lambda_arn" && { rm -f $@ && exit 1; }; \
	  rsp="$$(alr-helper get-subscription $$topic_arn $$lambda_arn 2>/dev/null)"; \
	  if [[ -z "$$rsp" || "$$rsp" = "None" ]]; then \
	    rsp="$$(alr-helper --log-level debug subscribe \
	      $$topic_arn \
	      protocol:lambda \
	      endpoint=$$lambda_arn)"; \
	  fi; \
	  test -z "$$rsp" && { rm -f $@ && exit 1; }; \
	  echo "$$rsp" > $@ || { rm -f $@ && exit 1; }; \
	  chmod 444 $@
	fi
	# Lambda-protocol same-account SNS subscriptions are auto-confirmed by
	# AWS — confirmation is only required for http/https/email endpoints or
	# cross-account subscriptions (see AWS Subscribe API docs). No
	# wait-subscription-confirmed step is needed here. ReturnSubscriptionArn
	# is set to true in cmd_sns_subscribe regardless, so the real ARN comes
	# back rather than the literal string "pending confirmation" even in
	# edge cases.

.PHONY: lambda-sns-pipeline
lambda-sns-pipeline: \
    $(CACHE_DIR)/lambda-sns-trigger \
    $(CACHE_DIR)/lambda-configuration ## full SNS infrastructure: topic, permission, subscription

.PHONY: lambda-sns-teardown
lambda-sns-teardown: _lambda-sns-teardown clean ## deprovision full SNS stack

# NOTE: topic deletion is NOT included in _lambda-sns-teardown by default.
# Topics may be shared across multiple subscribers (unlike a single
# Lambda's queue), so deleting it here could break other consumers.
# Unsubscribe is always safe and always performed. Uncomment the
# delete-topic line below only if you know this topic is exclusive to
# this Lambda.
.PHONY: _lambda-sns-teardown
_lambda-sns-teardown:
	$(NO_ECHO)topic_arn="$$(cat $(CACHE_DIR)/sns-topic 2>/dev/null || true)"; \
	if [[ -n "$$topic_arn" ]]; then \
	  sub_arn="$$(cat $(CACHE_DIR)/lambda-sns-trigger 2>/dev/null | \
	    perl -MJSON -0ne '$$r=eval{decode_json($$_)}; print ref $$r ? $$r->{SubscriptionArn}//q{} : q{}')"; \
	  if [[ -n "$$sub_arn" && "$$sub_arn" != "pending confirmation" ]]; then \
	    alr-helper unsubscribe $$sub_arn || true; \
	  fi; \
	fi;

	# alr-helper delete-topic $(TOPIC_NAME) || true; \
	alr-helper delete-function $(FUNCTION_NAME) || true; \
	alr-helper detach-all-policies $(ROLE_NAME) || true; \
	alr-helper delete-role $(ROLE_NAME) || true; \
	alr-helper delete-repo $(REPO_NAME) || true

########################################################################
# SNS Lambda Handler test
#
# make PAYLOAD=payload-sns.json sns
#
########################################################################

$(CACHE_DIR)/sns: $(CACHE_DIR)/lambda-function $(PAYLOAD) | $(CACHE_DIR) ## invoke Lambda with SNS test payload
	$(NO_ECHO)alr-helper invoke-function $(FUNCTION_NAME) $(PAYLOAD) | tee $@
