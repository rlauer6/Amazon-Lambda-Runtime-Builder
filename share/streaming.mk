#-*- mode: makefile; -*-

INVOKE_MODE ?= RESPONSE_STREAM

$(CACHE_DIR)/lambda-function-url:  $(CACHE_DIR)/lambda-function-url-permission \
    $(CACHE_DIR)/lambda-function-url-invoke-permission | $(CACHE_DIR) ## create Lambda function URL for streaming \
	$(NO_ECHO)url="$$(alr-helper get-function-url-config $(FUNCTION_NAME) 2>&1 || true)"; \
	if echo "$$url" | grep -q 'ResourceNotFoundException'; then \
	    url="$$(alr-helper create-function-url-config $(FUNCTION_NAME) $(INVOKE_MODE) | \
	      perl -MJSON -0ne 'print decode_json($$_)->{FunctionUrl}')"; \
	elif echo "$$url" | grep -q 'error\|Error'; then \
	    echo "ERROR: get-function-url-config failed: $$url" >&2; \
	    exit 1; \
	else \
	    url="$$(echo "$$url" | perl -MJSON -0ne 'print decode_json($$_)->{FunctionUrl}')"; \
	fi; \
	test -e $@ || echo "$$url" > $@

$(CACHE_DIR)/lambda-function-url-permission: $(CACHE_DIR)/lambda-function | $(CACHE_DIR)
	$(NO_ECHO)permission="$$(alr-helper get-lambda-policy $(FUNCTION_NAME) 2>&1 || true)"; \
	if echo "$$permission" | grep -q 'ResourceNotFoundException' || \
	   ! echo "$$permission" | grep -q 'InvokeFunctionUrl'; then \
	    permission="$$(alr-helper add-permission \
	        $(FUNCTION_NAME) \
	        allow-public-url \
	        lambda:InvokeFunctionUrl \
	        '*' )"; \
	fi; \
	test -e $@ || echo "$$permission" > $@

$(CACHE_DIR)/lambda-function-url-invoke-permission: $(CACHE_DIR)/lambda-function | $(CACHE_DIR)
	$(NO_ECHO)permission="$$(alr-helper get-lambda-policy $(FUNCTION_NAME) 2>&1 || true)"; \
	if echo "$$permission" | grep -q 'ResourceNotFoundException' || \
	   ! echo "$$permission" | grep -q 'allow-public-url-invoke'; then \
	    permission="$$(alr-helper add-permission \
	        $(FUNCTION_NAME) \
	        allow-public-url-invoke \
	        lambda:InvokeFunction \
	        '*' )"; \
	fi; \
	test -e $@ || echo "$$permission" > $@

.PHONY: test-streaming
test-streaming:  $(CACHE_DIR)/lambda-function-url ## invoke Lambda function URL with curl
	$(NO_ECHO)curl -sN $$(cat $(CACHE_DIR)/lambda-function-url)
