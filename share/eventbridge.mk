#-*- mode: makefile; -*-

########################################################################
# EventBridge Lambda Handler test
# 
# make lambda-eventbridge-trigger
# make delete-eventbridge-rule
########################################################################

SCHEDULE_EXPRESSION ?= rate(1 day)
RULE_NAME           ?= $(FUNCTON_NAME)-rule
RULE_STATE          ?= ENABLED

$(CACHE_DIR)/lambda-eventbridge-rule: | $(CACHE_DIR) ## create EventBridge schedule rule 
	$(NO_ECHO)alr-helper report-step $@ start; \
	rule="$$(alr-helper describe-rule $(RULE_NAME) 2>&1 || true)"; \
	if echo "$$rule" | grep -q 'ResourceNotFoundException'; then \
	  rule="$$(alr-helper --report-step $@ put-rule-expression $(RULE_NAME) '$(SCHEDULE_EXPRESSION)' $(RULE_STATE))"; \
	elif echo "$$rule" | grep -q 'error\|Error'; then \
	  echo "ERROR: describe-rule failed: $$rule" >&2; \
	  alr-helper report-step $@ done fail; \
	  rm -f $@ && exit 1; \
	fi; \
	test -z "$$rule" && { rm -f $@ && exit 1; }; \
	echo "$$rule" > $@ || { rm -f $@ && exit 1; }; \
	chmod 444 $@; \
	alr-helper report-step $@ done ok

$(CACHE_DIR)/lambda-eventbridge-permission: $(CACHE_DIR)/lambda-function \
    $(CACHE_DIR)/lambda-eventbridge-rule | $(CACHE_DIR) ## grant EventBridge permission to invoke Lambda
	$(NO_ECHO)alr-helper report-step $@ start; \
	permission="$$(alr-helper get-lambda-policy $(FUNCTION_NAME) 2>/dev/null || true)"; \
	if ! echo "$$permission" | grep -q events.amazonaws.com; then \
	  SOURCE_ARN="$$(cat $(CACHE_DIR)/lambda-eventbridge-rule | dnk get RuleArn)"; \
	  permission="$$(alr-helper --report-step $@ add-permission \
	    $(FUNCTION_NAME) \
	    eventbridge-trigger-$(RULE_NAME) \
	    lambda:InvokeFunction \
	    events.amazonaws.com \
	    $$SOURCE_ARN)"; \
	fi; \
	test -e $@ || echo "$$permission" > $@; \
	alr-helper report-step $@ done ok

$(CACHE_DIR)/lambda-eventbridge-trigger: $(CACHE_DIR)/lambda-eventbridge-permission | $(CACHE_DIR) ## add Lambda as EventBridge rule target
	$(NO_ECHO)alr-helper report-step $@ start; \
	trigger="$$(alr-helper --report-step $@ put-lambda-target $(FUNCTION_NAME) $(RULE_NAME))"; \
	test -z "$$trigger" && { rm -f $@; exit 1; }; \
	echo "$$trigger" > $@ || { rm -f $@ && alr-helper report-step $@ done fail; exit 1; }; \
	chmod 444 $@; \
	echo "$(RULE_NAME) running...$(SCHEDULE_EXPRESSION). To delete rule:"; \
	echo "make delete-eventbridge-rule"
	alr-helper report-step $@ done ok

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
	$(NO_ECHO)alr-helper report-step $@ start; \
	alr-helper --report-step $@ remove-targets $(RULE_NAME) $(FUNCTION_NAME) || true; \
	alr-helper --report-step $@ delete-rule $(RULE_NAME) || true ;  \
	rm -f $(CACHE_DIR)/lambda-eventbridge-rule $(CACHE_DIR)/lambda-eventbridge-permission $(CACHE_DIR)/lambda-eventbridge-trigger; \
	alr-helper report-step $@ done ok

.PHONY: lambda-eventbridge-pipeline
lambda-eventbridge-pipeline: \
    $(CACHE_DIR)/lambda-configuration \
    $(CACHE_DIR)/lambda-eventbridge-trigger ## full eventbridge infrastructure

.PHONY: lambda-eventbridge-teardown
lambda-eventbridge-teardown: _lambda-eventbridge-teardown clean ## deprovision full EventBridge stack

.PHONY: _lambda-eventbridge-teardown
_lambda-eventbridge-teardown: ## deprovision full EventBridge stack
	$(NO_ECHO)alr-helper report-step $@ start; \
	alr-helper --report-step $@ disable-rule $(RULE_NAME) || true; \
	alr-helper --report-step $@ remove-targets $(RULE_NAME) $(FUNCTION_NAME) || true; \
	alr-helper --report-step $@ delete-rule $(RULE_NAME) || true; \
	alr-helper --report-step $@ delete-function $(FUNCTION_NAME) || true; \
	alr-helper --report-step $@ detach-all-policies $(ROLE_NAME) || true; \
	alr-helper --report-step $@ delete-role $(ROLE_NAME) || true; \
	alr-helper --report-step $@ delete-repo $(REPO_NAME) || true
	alr-helper report-step $@ done ok
