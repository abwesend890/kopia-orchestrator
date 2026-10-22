# ── Hosts ────────────────────────────────────────────────────────
# Format: user@host:clone_dir  (set in .env). Optional so `make test`
# works in a fresh clone.
-include .env

# Fast-forwards the clone on each host to origin/main.
# $(1): space-separated user@host:clone_dir entries
define pull_hosts
set -e; \
for entry in $(1); do \
	echo "→ $$entry"; \
	ssh "$${entry%%:*}" "git -C '$${entry#*:}' pull --ff-only"; \
done
endef

# ── Targets ──────────────────────────────────────────────────────

.PHONY: help pull-server pull-clients pull-all test test-client test-server test-notify test-make test-deps

# Every target carrying a `## ` comment is listed by `make help`.
.DEFAULT_GOAL := help

help: ## Show this help
	@echo "Usage: make <target>"
	@echo
	@awk -F ':.*## ' '/^[a-z][a-z-]*:.*## /{ printf "  %-14s %s\n", $$1, $$2 }' $(MAKEFILE_LIST)

pull-all: pull-server pull-clients ## Pull main on the backup host and every client host

pull-server: ## Pull main on the backup host
	@$(call pull_hosts,$(BACKUP_HOST))

pull-clients: ## Pull main on every client host
	@$(call pull_hosts,$(CLIENT_HOSTS))

# ── Tests ───────────────────────────────────────────────────────

test: test-client test-server test-notify test-make ## Run every test suite

test-client: ## Run the client bats tests
	tests/libs/bats-core/bin/bats tests/client/

test-server: ## Run the server bats tests
	tests/libs/bats-core/bin/bats tests/server/

test-notify: ## Run the notification bats tests
	tests/libs/bats-core/bin/bats tests/test-notify.bats

test-make: ## Run the Makefile bats tests
	tests/libs/bats-core/bin/bats tests/make.bats

test-deps: ## Fetch the bats submodules
	git submodule update --init --recursive
