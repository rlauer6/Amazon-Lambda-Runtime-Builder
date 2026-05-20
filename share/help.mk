#-*- mode: makefile; -*-

.PHONY: help

help: ## show this help message
	@echo ""
	@echo "Usage: make [target] [VARIABLE=value]"
	@echo ""
	@echo "Targets:"
	@grep -Eh '^[a-zA-Z_-]+:.*?##' $(MAKEFILE_LIST) \
	  | sort \
	  | awk 'BEGIN {FS = ":.*?## "}; {printf "  %-34s %s\n", $$1, $$2}'
	@echo ""
	@echo "Core variables (override in project.mk):"
	@echo "  FUNCTION_NAME=name              Lambda function name (default: lambda-handler)"
	@echo "  ROLE_NAME=name                  IAM role name (default: lambda-role)"
	@echo "  REPO_NAME=name                  ECR repository name (default: perl-lambda)"
	@echo "  HANDLER_CLASS=Class::Name       Perl class implementing handler (default: LambdaHandler)"
	@echo "  REGION=region                   AWS region (default: us-east-1)"
	@echo "  AWS_PROFILE=profile             AWS credentials profile (default: default)"
	@echo "  TIMEOUT=seconds                 Lambda timeout in seconds (default: 30)"
	@echo ""
	@echo "Build variables:"
	@echo "  DIST_TARBALL=path               path to distribution tarball (auto-detected)"
	@echo "  EXTRA_BUILD_PACKAGES=pkgs       additional Debian packages for builder stage"
	@echo "  EXTRA_RUNTIME_PACKAGES=pkgs     additional Debian packages for runtime stage"
	@echo "  REINSTALL_PACKAGES=mods         CPAN modules to force reinstall in image"
	@echo "  RESOLVER=url                    cpm DarkPAN resolver URL"
	@echo "  NOCACHE=--no-cache              force Docker layer rebuild"
	@echo ""
	@echo "Trigger variables:"
	@echo "  POLICIES_FILE=file              IAM policies file (default: policies)"
	@echo "  PAYLOAD=file                    Lambda test payload file (default: payload-sns.json)"
	@echo "  BUCKET_NAME=name                S3 bucket name for S3 trigger"
	@echo "  S3_EVENT=event                  S3 event type (default: s3:ObjectCreated:*)"
	@echo "  KEY_PREFIX=prefix               S3 key prefix filter for S3 trigger"
	@echo "  QUEUE_NAME=name                 SQS queue name (default: lambda-runtime)"
	@echo "  BATCH_SIZE=n                    SQS batch size (default: 10)"
	@echo "  RULE_NAME=name                  EventBridge rule name"
	@echo "  SCHEDULE_EXPRESSION=expr        EventBridge schedule (default: rate(1 minute))"
	@echo "  INVOKE_MODE=mode                Lambda URL invoke mode (default: RESPONSE_STREAM)"
	@echo ""
