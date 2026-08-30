.PHONY: install
install: $(TARBALL)
	cpanm -n -v -l $(HOME) $<

DEPS += TUTORIAL.md

TUTORIAL.md: lib/Amazon/Lambda/Runtime/Builder/Tutorial.pm	
	$(NO_ECHO)pod2markdown $< > $@

publish: $(TARBALL)
	$(NO_ECHO)orepan2-s3 add $(TARBALL); \
	if [[ -n "$$CPAN" ]]; then \
	  upload2cpan; \
	fi
