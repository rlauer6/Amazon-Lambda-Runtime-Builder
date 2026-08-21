.PHONY: install
install: $(TARBALL)
	cpanm -n -v -l $(HOME) $<

publish: $(TARBALL)
	$(NO_ECHO)orepan2-s3 add $(TARBALL); \
	if [[ -n "$$CPAN" ]]; then \
	  upload2cpan; \
	fi
