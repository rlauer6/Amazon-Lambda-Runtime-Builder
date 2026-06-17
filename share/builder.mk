#-*- mode: makefile; -*-
ALR_BUILDER = Makefile.builder

lambda-clean:
	$(MAKE) -f $(ALR_BUILDER) clean

deploy: $(TARBALL)
	$(MAKE) -f $(ALR_BUILDER) deploy

lambda-function:
	$(MAKE) -f $(ALR_BUILDER) lambda-function

update-function: deploy
	$(MAKE) -f $(ALR_BUILDER) update-function

lambda-sqs-pipeline:
	$(MAKE) -f $(ALR_BUILDER) lambda-sqs-pipeline

lambda-eventbridge-pipeline:
	$(MAKE) -f $(ALR_BUILDER) lambda-eventbridge-pipeline

enable-eventbridge-rule:
	$(MAKE) -f $(ALR_BUILDER) enable-eventbridge-rule

disable-eventbridge-rule:
	$(MAKE) -f $(ALR_BUILDER) disable-eventbridge-rule

delete-eventbridge-rule:
	$(MAKE) -f $(ALR_BUILDER) delete-eventbridge-rule

lambda-teardown:
	$(MAKE) -f $(ALR_BUILDER) lambda-teardown

lambda-sqs-teardown:
	$(MAKE) -f $(ALR_BUILDER) lambda-sqs-teardown

lambda-eventbridge-teardown:
	$(MAKE) -f $(ALR_BUILDER) lambda-eventbridge-teardown

lambda-pipeline:
	$(MAKE) -f $(ALR_BUILDER) lambda-pipeline

update-lambda-configuration:
	$(MAKE) -f $(ALR_BUILDER) update-lambda-configuration
