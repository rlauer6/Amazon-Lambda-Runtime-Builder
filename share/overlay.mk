$(CACHE_DIR)/overlay: $(CACHE_DIR)/image $(wildcard Dockerfile) | $(CACHE_DIR)
	$(NO_ECHO)chmod -f 644 $@ 2>/dev/null || true; \
	chmod -f 644 $(CACHE_DIR)/overlay-ecr-repo 2>/dev/null || true; \
	test -e Dockerfile || { \
	    echo "ERROR: no Dockerfile found in $(CURDIR)" >&2; exit 1; \
	}; \
	test -z "$(OVERLAY)" && { \
	    echo "ERROR: OVERLAY is required" >&2; exit 1; \
	}; \
	overlay_uri="$$(alr-helper describe-repositories $(OVERLAY) filter=repositories[0].repositoryUri)"; \
	if [[ -z "$$overlay_uri" ]]; then \
	    overlay_uri="$$(alr-helper create-repository $(OVERLAY) filter=repository.repositoryUri)"; \
	fi; \
	echo "$$overlay_uri" > $(CACHE_DIR)/overlay-ecr-repo && chmod 444 $(CACHE_DIR)/overlay-ecr-repo; \
	docker build $(NOCACHE) -t $(OVERLAY) . || exit 1; \
	docker tag $(OVERLAY):latest $$overlay_uri:latest; \
	docker push $$overlay_uri:latest || exit 1; \
	DIGEST="$$(alr-helper describe-images $(OVERLAY) filter=imageDigest)"; \
	alr-helper update-function $(FUNCTION_NAME) $$overlay_uri $$DIGEST && \
	echo "$$overlay_uri@$$DIGEST" > $@ && chmod 444 $@

.PHONY: overlay
overlay: $(CACHE_DIR)/overlay ## build overlay image and update Lambda function

.PHONY: overlay-teardown
overlay-teardown: ## delete overlay ECR repo and clear sentinels
	$(NO_ECHO)overlay_uri="$$(cat $(CACHE_DIR)/overlay-ecr-repo 2>/dev/null)"; \
	if [[ -n "$$overlay_uri" ]]; then \
	    alr-helper delete-repository $(OVERLAY) || true; \
	fi; \
	rm -f $(CACHE_DIR)/overlay $(CACHE_DIR)/overlay-ecr-repo
