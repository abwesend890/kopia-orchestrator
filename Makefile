# ── Hosts ────────────────────────────────────────────────────────
# Format: user@host:remote_dir  (set in .env)
include .env

# ── Targets ──────────────────────────────────────────────────────

.PHONY: push-server push-proxy push-clients push-all

push-all: push-server push-proxy push-clients

push-server:
	rsync -avz --delete --exclude='.env' --exclude='config.yml' --exclude='data/' \
		server/ \
		$(word 1,$(subst :, ,$(BACKUP_HOST))):$(word 2,$(subst :, ,$(BACKUP_HOST)))/server/

push-proxy:
	rsync -avz --delete --exclude='.env' --exclude='config.yml' \
		proxy/ \
		$(word 1,$(subst :, ,$(BACKUP_HOST))):$(word 2,$(subst :, ,$(BACKUP_HOST)))/proxy/

push-clients:
	@for entry in $(CLIENT_HOSTS); do \
		host=$${entry%%:*}; \
		dir=$${entry#*:}; \
		echo "→ $$host ($$dir)"; \
		rsync -avz --delete --exclude='.env' --exclude='config.yml' --exclude='docker-compose.yml' --exclude='data/' \
			client/ \
			$$host:$$dir/client/; \
	done
