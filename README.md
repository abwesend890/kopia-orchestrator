# Backup

Docker-based backup orchestration using [Kopia](https://kopia.io). A **Client** on each source server snapshots service data to a central **Server** on the backup machine.

```
SOURCE SERVER                             BACKUP SERVER
┌─────────────────────────┐               ┌──────────────────────┐
│ backup-client container │──── HTTPS ────│ kopia-server         │
│  ├── service volumes    │               │  ├── repository      │
│  ├── docker.sock        │               │  ├── web UI (opt-in) │
│  └── config.yml         │               │  └── client auth     │
└─────────────────────────┘               └──────────────────────┘
         TLS via nginx-proxy + Let's Encrypt
```

## Why not just Kopia?

Kopia handles deduplication, encryption, and scheduling well, but leaves deployment and multi-service orchestration to you. This project fills those gaps:

- **Declarative multi-service config** -- one YAML file defines all services, paths, retention policies, and schedules. No manual `kopia policy set` per path.
- **Container-aware snapshots** -- `mode: stop` automatically stops a container before snapshot and restarts it after, so databases and mail stores get consistent backups without manual scripting.
- **Live-reload** -- the client watches `config.yml` with `inotifywait`. Add a service or change retention and setup re-runs without restarting the container.
- **Reliable notifications** -- Kopia's built-in notifications have [open issues](https://github.com/kopia/kopia/issues/4402). This project provides its own SMTP email and contact form POST notifications on connection failures, snapshot errors, and policy failures.
- **Per-path retention overrides** -- set retention at the service level, then override specific paths (e.g. config dirs kept longer than data dirs).
- **Per-service schedules** -- global schedule with per-service overrides via `schedule.times`.
- **TLS out of the box** -- nginx-proxy + Let's Encrypt companion handle certificates automatically.
- **Restore helper** -- `restore.sh` wraps Kopia's snapshot listing and restore commands for quick reference.

## Quick Start

### 1. Backup Server

```bash
cp .env.example .env           # set passwords, domain, SMTP credentials
cp server/config.yml.example server/config.yml

# Start reverse proxy (once per host)
cd proxy && docker compose up -d

# Start Kopia server
cd server && docker compose up -d
```

### 2. Source Server

```bash
cp .env.example .env
cp client/config.yml.example client/config.yml
```

Edit `client/config.yml` — define your services and paths. Then mount service data in `client/docker-compose.yml`:

```yaml
services:
  backup-client:
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
      - ./config.yml:/etc/backup/config.yml:ro
      - stalwart_data:/data/stalwart:ro
```

```bash
cd client && docker compose up -d
```

## Configuration

### Client (`client/config.yml`)

```yaml
server:
  url: https://backup.example.com:51515
  password_env: KOPIA_PASSWORD

notifications:
  email:
    to:
      - admin@example.com
    smtp_host: mail.example.com
    smtp_port: 587
    username_env: SMTP_USER
    password_env: SMTP_PASSWORD

services:
  - name: stalwart
    container: stalwart-mail    # optional — omit for live-only
    mode: stop                  # stop | live
    retention:
      keep_daily: 7
      keep_weekly: 4
      keep_monthly: 12
    paths:
      - /data/stalwart/mail
      - path: /data/stalwart/config
        retention:              # per-path override
          keep_daily: 30
```

- **container** — Docker container to stop/start during snapshot. Omit for services with no container (implicitly `live`).
- **mode** — `stop` halts the container before snapshot. `live` snapshots while running.
- **retention** — Set per-service (default for all paths) or per-path (override). Supports `keep_daily`, `keep_weekly`, `keep_monthly`.
- **paths** — Simple string for a path with inherited retention, or object with `path` + `retention` for overrides.

### Server (`server/config.yml`)

```yaml
ui:
  enabled: false

notifications:
  email:
    to:
      - admin@example.com
    smtp_host: mail.example.com
    smtp_port: 587
    username_env: SMTP_USER
    password_env: SMTP_PASSWORD

clients:
  - name: mail-server
    password_env: CLIENT_MAIL_PASSWORD
```

- **ui.enabled** — Set `true` to enable the Kopia web UI.
- **clients** — Each client authenticates with a unique password from an environment variable.

### Environment (`.env`)

```bash
KOPIA_PASSWORD=changeme
CLIENT_MAIL_PASSWORD=changeme
KOPIA_VIRTUAL_HOST=backup.example.com
ACME_EMAIL=admin@example.com
SMTP_USER=notifications@example.com
SMTP_PASSWORD=changeme

# Contact form fallback (client-only, used when SMTP is not configured)
CONTACT_FORM_URL=https://example.com/contact
CONTACT_FORM_EMAIL=backup@example.com
CONTACT_FORM_NAME=Backup Agent
```

## Scheduling

Kopia handles scheduling internally. Define retention policies in the config — Kopia's built-in scheduler decides when to run snapshots.

## Config Changes

The client watches `config.yml` with `inotifywait`. Changes are detected automatically, logged to stdout, and setup re-runs without restart.

## Restore

Service volumes are mounted read-only in the client container, so restore requires a writable mount or running from outside the container. `restore.sh` is a reference for the Kopia commands involved:

```bash
# List snapshots
docker exec backup-client /restore.sh list

# List snapshots for a specific path
docker exec backup-client /restore.sh list /data/stalwart

# Restore a snapshot (needs a writable target path)
docker exec backup-client /restore.sh restore <snapshot-id> /tmp/restore
```

In practice: stop the target service, mount the volume read-write (or use a temporary container), restore, then restart.

## Testing Notifications

Verify notification connectivity from inside a running container:

```bash
# On the server host:
docker exec -i kopia-server bash < test-notify.sh

# On a client host:
docker exec -i backup-client bash < test-notify.sh
```

Auto-detects the notification method (SMTP first, contact form fallback) and sends a test message with verbose output. Shows the exact error (auth failure, DNS, connection refused) on failure.

Run `bash test-notify.sh --help` for details.

## Project Structure

```
├── proxy/
│   └── docker-compose.yml      # nginx-proxy + acme-companion
├── server/
│   ├── Dockerfile
│   ├── docker-compose.yml
│   ├── entrypoint.sh
│   └── config.yml.example
├── client/
│   ├── Dockerfile
│   ├── docker-compose.yml
│   ├── entrypoint.sh
│   ├── setup.sh
│   ├── notify.sh
│   ├── restore.sh
│   └── config.yml.example
├── test-notify.sh              # notification smoke test
└── CONTEXT.md                  # domain glossary
```
