########################################################################
# create ECR repository
########################################################################
.PHONY: ecr-uri
ecr-uri: $(CACHE_DIR)/ecr-uri
ecr-repo: $(CACHE_DIR)/ecr-repo
ecr-lifecycle-policy: $(CACHE_DIR)/ecr-lifecycle-policy

$(CACHE_DIR)/ecr-uri: | $(CACHE_DIR)
	$(NO_ECHO)alr-helper report-step $@ start; \
	repo_uri="$$(alr-helper --report-step @ describe-repositories $(REPO_NAME) filter=repositories[0].repositoryUri 2>/dev/null)"; \
	if [[ -z "$$repo_uri" ]] || echo "$$repo_uri" | grep -qv "$(REPO_NAME)"; then \
	  repo_uri="$$(alr-helper --report-step $@ create-repository $(REPO_NAME) filter=repository.repositoryUri)"; \
	fi; \
	if [[ -z "$$repo_uri" ]]; then \
	  echo "ERROR: could not determine ECR repository URI for $(REPO_NAME)" >&2; \
	  exit 1; \
	fi; \
	echo "$$repo_uri" > $@ && chmod 444 $@; \
	alr-helper report-step $@ done ok

$(CACHE_DIR)/ecr-lifecycle-policy: $(CACHE_DIR)/ecr-uri | $(CACHE_DIR)
	$(NO_ECHO)alr-helper report-step $@ start; \
	lifecycle_policy=$$(alr-helper --report-step $@ get-lifecycle-policy $(REPO_NAME) 2>&1 || true); \
	if echo "$$lifecycle_policy" | grep -q "LifecyclePolicyNotFoundException"; then \
	  lifecycle_policy=$$(alr-helper --report-step $@ put-lifecycle-policy $(REPO_NAME)); \
	fi; \
	if echo "$$lifecycle_policy" | grep -q "error\|Error\|Exception"; then \
	  echo "ERROR: could not apply lifecycle policy to $(REPO_NAME)" >&2; \
	  exit 1; \
	fi; \
	echo "$$lifecycle_policy" > $@ && chmod 444 $@; \
	alr-helper report-step $@ done ok

$(CACHE_DIR)/ecr-repo: $(CACHE_DIR)/ecr-uri $(CACHE_DIR)/ecr-lifecycle-policy | $(CACHE_DIR) ## provision ECR repository with lifecycle policy 
	$(NO_ECHO)cp $< $@
