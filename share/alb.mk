#-*- mode: makefile; -*-

########################################################################
# ALB Lambda trigger pipeline
#
# Wires an existing ALB listener rule to invoke a Lambda function for
# a specific path. Requires an existing ALB and HTTPS listener.
#
# Usage:
#   make LISTENER_ARN=arn:aws:... \
#        ALB_PATH=/build \
#        RULE_PRIORITY=10 \
#        lambda-alb-pipeline
#
# Teardown:
#   make lambda-alb-teardown
########################################################################

LISTENER_ARN  ?=
ALB_PATH      ?= /build
RULE_PRIORITY ?= 10

########################################################################
# grant ALB permission to invoke the Lambda function
########################################################################
$(CACHE_DIR)/alb-lambda-permission: $(CACHE_DIR)/lambda-function | $(CACHE_DIR)
	$(NO_ECHO)chmod -f 644 $@ 2>/dev/null || true; \
	permission="$$(alr-helper get-lambda-policy $(FUNCTION_NAME) 2>&1 || true)"; \
	if echo "$$permission" | grep -q 'ResourceNotFoundException' || \
	   ! echo "$$permission" | grep -q 'elasticloadbalancing.amazonaws.com'; then \
	    alr-helper add-permission \
	        $(FUNCTION_NAME) \
	        alb-trigger-$(FUNCTION_NAME) \
	        lambda:InvokeFunction \
	        elasticloadbalancing.amazonaws.com || exit 1; \
	elif echo "$$permission" | grep -q 'error\|Error'; then \
	    echo "ERROR: get-lambda-policy failed: $$permission" >&2; \
	    exit 1; \
	fi; \
	echo "$(FUNCTION_NAME)" > $@ || { rm -f $@ && exit 1; }; \
	chmod 444 $@

########################################################################
# create Lambda target group
########################################################################
$(CACHE_DIR)/alb-target-group: $(CACHE_DIR)/alb-lambda-permission | $(CACHE_DIR)
	$(NO_ECHO)chmod -f 644 $@ 2>/dev/null || true; \
	test -z "$(LISTENER_ARN)" && { \
	    echo "ERROR: LISTENER_ARN is required for alb trigger type" >&2; exit 1; \
	}; \
	tg="$$(alr-helper get-alb-target-group $(FUNCTION_NAME))"; \
	if [[ -z "$$tg" || "$$tg" = "None" ]]; then \
	    tg="$$(alr-helper create-alb-target-group $(FUNCTION_NAME))"; \
	fi; \
	echo $$tg; \
	test -z "$$tg" && { rm -f $@ && exit 1; }; \
	echo "$$tg" > $@ || { rm -f $@ && exit 1; }; \
	chmod 444 $@

########################################################################
# register Lambda function with target group
########################################################################
$(CACHE_DIR)/alb-target-group-registration: \
    $(CACHE_DIR)/alb-target-group \
    $(CACHE_DIR)/lambda-function | $(CACHE_DIR)
	$(NO_ECHO)chmod -f 644 $@ || true; \
	tg_arn="$$(cat $(CACHE_DIR)/alb-target-group | \
	  perl -MJSON -0ne 'print decode_json($$_)->{TargetGroupArn}//q{}')" ; \
	alr-helper register-alb-target \
	    $$tg_arn \
	    $(FUNCTION_NAME) || exit 1; \
	echo "$$tg_arn" > $@ || { rm -f $@ && exit 1; }; \
	chmod 444 $@

########################################################################
# create listener rule forwarding ALB_PATH to Lambda target group
########################################################################
$(CACHE_DIR)/alb-listener-rule: \
    $(CACHE_DIR)/alb-target-group-registration | $(CACHE_DIR)
	$(NO_ECHO)chmod -f 644 $@ || true; \
	tg_arn="$$(cat $(CACHE_DIR)/alb-target-group | \
	  perl -MJSON -0ne 'print decode_json($$_)->{TargetGroupArn}//q{}')" ; \
	rule="$$(alr-helper get-alb-listener-rule \
	    $(LISTENER_ARN) \
	    $(ALB_PATH) 2>/dev/null)"; \
	if [[ -z "$$rule" || "$$rule" = "None" ]]; then \
	    rule="$$(alr-helper create-alb-listener-rule \
	        $(LISTENER_ARN) \
	        $$tg_arn \
	        path:$(ALB_PATH) \
	        priority:$(RULE_PRIORITY))"; \
	fi; \
	test -z "$$rule" && { rm -f $@ && exit 1; }; \
	echo "$$rule" > $@ || { rm -f $@ && exit 1; }; \
	chmod 444 $@

.PHONY: lambda-alb-pipeline
lambda-alb-pipeline: \
    $(CACHE_DIR)/alb-listener-rule \
    $(CACHE_DIR)/lambda-configuration ## full ALB Lambda infrastructure

.PHONY: _lambda-alb-teardown
_lambda-alb-teardown:
	$(NO_ECHO)rule_arn="$$(cat $(CACHE_DIR)/alb-listener-rule 2>/dev/null | \
	  perl -MJSON -0ne 'print decode_json($$_)->{RuleArn}//q{}')" ; \
	if [[ -n "$$rule_arn" ]]; then \
	    alr-helper delete-alb-listener-rule $$rule_arn || true; \
	fi; \
	tg_arn="$$(cat $(CACHE_DIR)/alb-target-group 2>/dev/null | \
	  perl -MJSON -0ne 'print decode_json($$_)->{TargetGroupArn}//q{}')" ; \
	if [[ -n "$$tg_arn" ]]; then \
	    alr-helper deregister-alb-target $$tg_arn $(FUNCTION_NAME) || true; \
	    alr-helper delete-alb-target-group $$tg_arn || true; \
	fi; \
	alr-helper remove-permission $(FUNCTION_NAME) alb-trigger-$(FUNCTION_NAME) || true; \
	alr-helper delete-function $(FUNCTION_NAME) || true; \
	alr-helper detach-all-policies $(ROLE_NAME) || true; \
	alr-helper delete-role $(ROLE_NAME) || true; \
	alr-helper delete-repo $(REPO_NAME) || true

.PHONY: lambda-alb-teardown
lambda-alb-teardown: _lambda-alb-teardown clean ## deprovision full ALB Lambda stack
