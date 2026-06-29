#-*- mode: makefile; -*-

########################################################################
# Platform image build pipeline
#
# Builds and pushes a platform layer image that sits between the
# perl-lambda-base runtime and the application handler layer.
#
# The platform image is built from Dockerfile.platform in the project
# root. It is intended to contain stable, infrequently-changing
# artifacts such as data files, toolchains, or shared dependencies.
#
# Usage:
#   Set PLATFORM_IMAGE in lambda.env to the ECR URI or local image name.
#   Place a Dockerfile.platform in the project root.
#   Run: make platform
#
# The platform image is rebuilt automatically when Dockerfile.platform
# changes. After rebuilding, the handler image ($(CACHE_DIR)/image) is
# invalidated so the next make lambda-pipeline picks up the new platform.
########################################################################

PLATFORM_REPO ?= $(PLATFORM_IMAGE)

########################################################################
$(CACHE_DIR)/platform: $(wildcard Dockerfile.platform) | $(CACHE_DIR)
########################################################################
	$(NO_ECHO)chmod -f 644 $@ 2>/dev/null || true; \
	chmod -f 644 $(CACHE_DIR)/platform-ecr-repo 2>/dev/null || true; \
	test -e Dockerfile.platform || { \
	    echo "ERROR: no Dockerfile.platform found in $(CURDIR)" >&2; exit 1; \
	}; \
	test -z "$(PLATFORM_REPO)" && { \
	    echo "ERROR: PLATFORM_IMAGE is required in lambda.env" >&2; exit 1; \
	}; \
	platform_uri="$$(alr-helper describe-repositories $(PLATFORM_REPO) filter=repositories[0].repositoryUri 2>/dev/null)"; \
	if [[ -z "$$platform_uri" ]]; then \
	    platform_uri="$$(alr-helper create-repository $(PLATFORM_REPO) filter=repository.repositoryUri)"; \
	fi; \
	test -z "$$platform_uri" && { \
	    echo "ERROR: could not determine ECR URI for $(PLATFORM_REPO)" >&2; exit 1; \
	}; \
	echo "$$platform_uri" > $(CACHE_DIR)/platform-ecr-repo && chmod 444 $(CACHE_DIR)/platform-ecr-repo; \
	docker build -t $(PLATFORM_REPO) -f Dockerfile.platform . || exit 1; \
	docker tag $(PLATFORM_REPO):latest $$platform_uri:latest; \
	docker push $$platform_uri:latest || exit 1; \
	echo "$$platform_uri" > $@ && chmod 444 $@; \
	chmod -f 644 $(CACHE_DIR)/image 2>/dev/null || true; \
	rm -f $(CACHE_DIR)/image \
	      $(CACHE_DIR)/deploy \
	      $(CACHE_DIR)/image-digest \
	      $(CACHE_DIR)/lambda-function \
	      $(CACHE_DIR)/lambda-configuration; \
	echo "Platform image pushed — handler image sentinels cleared for rebuild"

.PHONY: platform
platform: $(CACHE_DIR)/platform ## build and push platform image, invalidate handler image

.PHONY: platform-teardown
platform-teardown: ## clear platform sentinels (ECR repo must be deleted manually)
	$(NO_ECHO)echo "WARNING: platform ECR repo $(PLATFORM_REPO) not deleted - remove manually if no longer needed"; \
	rm -f $(CACHE_DIR)/platform $(CACHE_DIR)/platform-ecr-repo
