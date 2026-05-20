########################################################################
# create ECR repository
########################################################################
$(CACHE_DIR)/ecr-uri: ## create or locate ECR repository URI | $(CACHE_DIR)
	$(NO_ECHO)repo_uri=$$(alr-helper describe-repositories $(REPO_NAME) 2>/dev/null | \
	  perl -MJSON -0ne '$$r=decode_json($$_); print $$r->{repositories}[0]{repositoryUri}//"" '); \
	if [[ -z "$$repo_uri" ]] || echo "$$repo_uri" | grep -qv "$(REPO_NAME)"; then \
	  repo_uri=$$(alr-helper create-repository $(REPO_NAME) | \
	    perl -MJSON -0ne '$$r=decode_json($$_); print $$r->{repository}{repositoryUri}'); \
	fi; \
	test -e $@ || echo "$$repo_uri" > $@

$(CACHE_DIR)/ecr-lifecycle-policy: ## apply ECR image lifecycle policy $(CACHE_DIR)/ecr-uri | $(CACHE_DIR)
	$(NO_ECHO)lifecycle_policy=$$(alr-helper get-lifecycle-policy $(REPO_NAME) 2>&1 || true); \
	if echo "$$lifecycle_policy" | grep -q "LifecyclePolicyNotFoundException"; then \
	  lifecycle_policy=$$(alr-helper put-lifecycle-policy $(REPO_NAME)); \
	fi; \
	test -e $@ || echo "$$lifecycle_policy" > $@

$(CACHE_DIR)/ecr-repo: ## provision ECR repository with lifecycle policy $(CACHE_DIR)/ecr-uri $(CACHE_DIR)/ecr-lifecycle-policy | $(CACHE_DIR)
	$(NO_ECHO)cp $< $@
