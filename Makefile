SHELL := /usr/bin/env bash
HOST  := $(shell . ./config.env 2>/dev/null && echo $$PI_HOSTNAME)

.PHONY: help flash connect bootstrap audit all clean version-commit
help:
	@awk 'BEGIN{FS=":.*##"; printf "targets:\n"} /^[a-zA-Z0-9_-]+:.*##/ {printf "  %-10s %s\n",$$1,$$2}' $(MAKEFILE_LIST)

config.env: ## initialize config
	@[ -f $@ ] || cp config.env.example $@
	@echo "edit config.env, then: make flash"

flash: config.env ## flash SD + firstboot config (macOS)
	bash ./01-flash.sh

connect: ## discover Pi + add ~/.ssh/config entry
	bash ./02-connect.sh

bootstrap: ## run idempotent Pi-side setup over SSH
	ssh $(HOST) 'bash -s' < 03-bootstrap.sh

audit: ## run audit on the Pi
	ssh $(HOST) 'bash -s' < 04-audit.sh

all: flash connect bootstrap audit ## full first-time run

clean: ## remove cached image
	rm -rf .cache

version-commit: ## bump VERSION (patch) + commit; need 10 keywords: make version-commit KEYWORDS="k1 k2 k3 k4 k5 k6 k7 k8 k9 k10"
	@test -n "$(KEYWORDS)" || { echo "usage: make version-commit KEYWORDS='w1 w2 w3 w4 w5 w6 w7 w8 w9 w10'"; exit 1; }
	@KEYWORDS="$(KEYWORDS)" bash ./tools/version-commit.sh
