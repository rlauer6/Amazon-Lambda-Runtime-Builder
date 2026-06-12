#-*- mode; gnumakefile; -*-

define ecr_login
	$(NO_ECHO)URI=$$(cat $(CACHE_DIR)/ecr-repo); \
	PASSWORD="$$(perl -MAmazon::API::ECR -MMIME::Base64 -e \
	  'my $$ecr = Amazon::API::ECR->new; \
	   my (undef, $$pw) = split /:/, \
	     decode_base64($$ecr->GetAuthorizationToken->{authorizationData}[0]{authorizationToken}), 2; \
	   print $$pw')"; \
	echo "$$PASSWORD" | docker login \
	  --username AWS \
	  --password-stdin $$URI
endef
