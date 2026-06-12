#-*- mode: makefile; -*-

########################################################################
# SNS Lambda Handler test
# 
# make PAYLOAD=payload-sns.json sns
#
########################################################################

$(CACHE_DIR)/sns: $(CACHE_DIR)/lambda-function $(PAYLOAD) | $(CACHE_DIR) ## invoke Lambda with SNS test payload
	$(NO_ECHO)alr-helper invoke-function $(FUNCTION_NAME) $(PAYLOAD) | tee $@
