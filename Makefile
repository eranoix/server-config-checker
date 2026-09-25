# config-check: everything is plain POSIX sh, so there is nothing to build.

SHELL_FILES := bin/config-check bin/drift-lock bin/drift-queue \
	$(wildcard lib/*.sh lib/checks/*.sh lib/remote/*.sh tests/*.sh tests/checks/*.sh) \
	$(wildcard demo/*.sh demo/host/*.sh demo/control/*.sh demo/hosts/*/setup.sh)

.PHONY: check lint test demo help

help:
	@echo "make lint   shellcheck every script"
	@echo "make test   offline test suite (no network, no docker)"
	@echo "make check  lint + test (the merge queue gate)"
	@echo "make demo   docker compose demo: green, then drift"

lint:
	shellcheck -s sh $(SHELL_FILES)

test:
	sh tests/run.sh

check: lint test

demo:
	sh demo/demo.sh
