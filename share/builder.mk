#-*- mode: makefile; -*-
ALR_BUILDER = Makefile.builder

lambda-clean:
	$(MAKE) -f $(ALR_BUILDER) clean

deploy: $(TARBALL)
	$(MAKE) -f $(ALR_BUILDER) deploy

update-function: deploy
	$(MAKE) -f $(ALR_BUILDER) update-function

lambda-sqs-pipeline:
	$(MAKE) -f $(ALR_BUILDER) lambda-sqs-pipeline
