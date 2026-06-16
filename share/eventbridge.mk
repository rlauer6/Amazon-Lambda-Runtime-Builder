#-*- mode: makefile; -*-

########################################################################
# EventBridge Lambda Handler test
# 
# make lambda-eventbridge-trigger
# make delete-eventbridge-rule
########################################################################

SCHEDULE_EXPRESSION ?= rate(1 minute)
RULE_NAME           ?= lambda-handler-test
RULE_STATE          ?= ENABLED

$(CACHE_DIR)/lambda-eventbridge-rule: | $(CACHE_DIR) ## create EventBridge schedule rule 
	$(NO_ECHO)rule="$$(alr-helper describe-rule $(RULE_NAME) 2>&1 || true)"; \
	if echo "$$rule" | grep -q 'ResourceNotFoundException'; then \
	    rule="$$(alr-helper put-rule-expression $(RULE_NAME) '$(SCHEDULE_EXPRESSION)' $(RULE_STATE))"; \
	elif echo "$$rule" | grep -q 'error\|Error'; then \
	    echo "ERROR: describe-rule failed: $$rule" >&2; \
	    exit 1; \
	fi; \
	test -e $@ || echo "$$rule" > $@

$(CACHE_DIR)/lambda-eventbridge-permission: $(CACHE_DIR)/lambda-function \
    $(CACHE_DIR)/lambda-eventbridge-rule | $(CACHE_DIR) ## grant EventBridge permission to invoke Lambda
	$(NO_ECHO)permission="$$(alr-helper get-lambda-policy $(FUNCTION_NAME) 2>/dev/null || true)"; \
	if ! echo "$$permission" | grep -q events.amazonaws.com; then \
	  SOURCE_ARN=$$(cat $(CACHE_DIR)/lambda-eventbridge-rule | \
	    perl -MJSON -0ne '$$r=decode_json($$_); print $$r->{RuleArn}'); \
	  permission="$$(alr-helper add-permission \
	    $(FUNCTION_NAME) \
	    eventbridge-trigger-$(RULE_NAME) \
	    lambda:InvokeFunction \
	    events.amazonaws.com \
	    $$SOURCE_ARN)"; \
	fi; \
	test -e $@ || echo "$$permission" > $@

$(CACHE_DIR)/lambda-eventbridge-trigger: $(CACHE_DIR)/lambda-eventbridge-permission | $(CACHE_DIR) ## add Lambda as EventBridge rule target
	$(NO_ECHO)trigger="$$(alr-helper put-lambda-target $(FUNCTION_NAME) $(RULE_NAME))"; \
	test -e $@ || echo "$$trigger" > $@; \
	echo "$(RULE_NAME) running...$(SCHEDULE_EXPRESSION). To delete rule:"; \
	echo "make delete-eventbridge-rule"

.PHONY: disable-eventbridge-rule
disable-eventbridge-rule: ## disable EventBridge rule
	$(NO_ECHO)alr-helper disable-rule $(RULE_NAME); \
	echo "$(RULE_NAME) disabled"

.PHONY: enable-eventbridge-rule
enable-eventbridge-rule: ## enable EventBridge rule
	$(NO_ECHO)alr-helper enable-rule $(RULE_NAME); \
	echo "$(RULE_NAME) enabled"

.PHONY: delete-eventbridge-rule
delete-eventbridge-rule: ## remove targets and delete EventBridge rule
	$(NO_ECHO)alr-helper remove-targets $(RULE_NAME) $(FUNCTION_NAME); \
	alr-helper delete-rule $(RULE_NAME); \
	rm -f $(CACHE_DIR)/lambda-eventbridge-rule $(CACHE_DIR)/lambda-eventbridge-permission $(CACHE_DIR)/lambda-eventbridge-trigger

.PHONY: lambda-eventbridge-pipeline
lambda-eventbridge-pipeline: \
    $(CACHE_DIR)/lambda-configuration \
    $(CACHE_DIR)/lambda-eventbridge-trigger ## full eventbridge infrastructure
