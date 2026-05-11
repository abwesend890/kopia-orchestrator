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
```

## Scheduling

Kopia handles scheduling internally. Define retention policies in the config — Kopia's built-in scheduler decides when to run snapshots.

## Config Changes

The client watches `config.yml` with `inotifywait`. Changes are detected automatically, logged to stdout, and setup re-runs without restart.

## Restore

Restore is manual. Exec into the client container:

```bash
# List snapshots
docker exec backup-client /restore.sh list

# List snapshots for a specific path
docker exec backup-client /restore.sh list /data/stalwart

# Restore a snapshot
docker exec backup-client /restore.sh restore <snapshot-id> /tmp/restore
```

Stop the target container yourself before restoring, then copy data back and restart.

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
│   ├── restore.sh
│   └── config.yml.example
├── .env.example
└── CONTEXT.md                  # domain glossary
```
