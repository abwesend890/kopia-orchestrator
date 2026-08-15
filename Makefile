# ── Hosts ────────────────────────────────────────────────────────
# Format: user@host:remote_dir  (set in .env)
include .env

# ── Targets ──────────────────────────────────────────────────────

.PHONY: help push-server push-proxy push-clients push-all test test-client test-server test-notify test-deps

# Every target carrying a `## ` comment is listed by `make help`.
.DEFAULT_GOAL := help

help: ## Show this help
	@echo "Usage: make <target>"
	@echo
	@awk -F ':.*## ' '/^[a-z][a-z-]*:.*## /{ printf "  %-14s %s\n", $$1, $$2 }' $(MAKEFILE_LIST)

push-all: push-server push-proxy push-clients ## Sync server, proxy and every client host

push-server: ## Sync server/ and test-notify.sh to the backup host
	rsync -avz --delete --exclude='.env' --exclude='config.yml' --exclude='data/' \
		server/ \
		$(word 1,$(subst :, ,$(BACKUP_HOST))):$(word 2,$(subst :, ,$(BACKUP_HOST)))/server/
	rsync -avz test-notify.sh \
		$(word 1,$(subst :, ,$(BACKUP_HOST))):$(word 2,$(subst :, ,$(BACKUP_HOST)))/test-notify.sh

push-proxy: ## Sync proxy/ to the backup host
	rsync -avz --delete --exclude='.env' --exclude='config.yml' \
		proxy/ \
		$(word 1,$(subst :, ,$(BACKUP_HOST))):$(word 2,$(subst :, ,$(BACKUP_HOST)))/proxy/

push-clients: ## Sync client/ and test-notify.sh to every client host
	@for entry in $(CLIENT_HOSTS); do \
		host=$${entry%%:*}; \
		dir=$${entry#*:}; \
		echo "→ $$host ($$dir)"; \
		rsync -avz --delete --exclude='.env' --exclude='config.yml' --exclude='docker-compose.yml' --exclude='data/' \
			client/ \
			$$host:$$dir/client/; \
		rsync -avz test-notify.sh \
			$$host:$$dir/test-notify.sh; \
	done

# ── Tests ───────────────────────────────────────────────────────

test: test-client test-server test-notify ## Run every test suite

test-client: ## Run the client bats tests
	tests/libs/bats-core/bin/bats tests/client/

test-server: ## Run the server bats tests
	tests/libs/bats-core/bin/bats tests/server/

test-notify: ## Run the notification bats tests
	tests/libs/bats-core/bin/bats tests/test-notify.bats

test-deps: ## Fetch the bats submodules
	git submodule update --init --recursive
