#-*- mode: makefile; -*-

########################################################################
# CloudWatch log group management
#
# Creates the Lambda function's log group with a retention policy,
# ensuring it exists before the function is configured and that
# retention is applied even if Lambda auto-created the group on first
# invocation.
#
# Variables:
#   LOG_RETENTION - retention in days (default: 1)
#
# Targets:
#   log-group         - create log group and set retention
#   log-group-teardown - delete log group
########################################################################

LOG_RETENTION ?= 1

########################################################################
$(CACHE_DIR)/log-group: $(CACHE_DIR)/lambda-function | $(CACHE_DIR)
########################################################################
	$(NO_ECHO)chmod -f 644 $@ 2>/dev/null || true; \
	log_group="/aws/lambda/$(FUNCTION_NAME)"; \
	existing="$$(alr-helper describe-log-groups $$log_group filter=logGroups[0].arn 2>/dev/null)"; \
	if [[ -z "$$existing" ]]; then \
	    alr-helper create-log-group $$log_group || exit 1; \
	fi; \
	alr-helper put-retention-policy $$log_group $(LOG_RETENTION) || exit 1; \
	echo "$(LOG_RETENTION)" > $@ && chmod 444 $@

.PHONY: log-group
log-group: $(CACHE_DIR)/log-group ## create Lambda log group and set retention policy

.PHONY: log-group-teardown
log-group-teardown: ## delete Lambda CloudWatch log group
	$(NO_ECHO)alr-helper delete-log-group /aws/lambda/$(FUNCTION_NAME) || true; \
	chmod -f 644 $(CACHE_DIR)/log-group 2>/dev/null || true; \
	rm -f $(CACHE_DIR)/log-group
