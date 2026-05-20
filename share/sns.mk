#-*- mode: makefile; -*-

########################################################################
# SNS Lambda Handler test
# 
# make PAYLOAD=payload-sns.json sns
#
########################################################################

$(CACHE_DIR)/sns: ## invoke Lambda with SNS test payload $(CACHE_DIR)/lambda-function $(PAYLOAD) | $(CACHE_DIR)
	$(NO_ECHO)alr-helper invoke-function $(FUNCTION_NAME) $(PAYLOAD) | tee $@
