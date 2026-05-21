#!/bin/bash
set -euo pipefail

CONFIG_FILE="${CONFIG_FILE:-/etc/backup/config.yml}"

USAGE="SMTP notification smoke test

Sends a test email using the SMTP config from config.yml to verify
connectivity and authentication. Uses verbose output to surface errors.

Usage:
  docker exec -i <container> bash < test-notify.sh
  bash test-notify.sh [--help]

Options:
  --help    Show this help message

Examples:
  docker exec -i kopia-server bash < test-notify.sh
  docker exec -i backup-client bash < test-notify.sh"

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
  echo "$USAGE"
  exit 0
fi

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

if ! command -v yq &>/dev/null; then
  fail "yq not found in PATH"
fi

if ! command -v curl &>/dev/null; then
  fail "curl not found in PATH"
fi

if [ ! -f "$CONFIG_FILE" ]; then
  fail "config not found at $CONFIG_FILE (set CONFIG_FILE to override)"
fi

enabled=$(yq '.notifications.email // ""' "$CONFIG_FILE")
if [ -z "$enabled" ] || [ "$enabled" = "null" ]; then
  fail "no notifications.email section in $CONFIG_FILE"
fi

smtp_host=$(yq '.notifications.email.smtp_host' "$CONFIG_FILE")
smtp_port=$(yq '.notifications.email.smtp_port' "$CONFIG_FILE")
username_env=$(yq '.notifications.email.username_env' "$CONFIG_FILE")
password_env=$(yq '.notifications.email.password_env' "$CONFIG_FILE")

for field in smtp_host smtp_port username_env password_env; do
  val="${!field}"
  if [ -z "$val" ] || [ "$val" = "null" ]; then
    fail "notifications.email.${field} is missing or empty in $CONFIG_FILE"
  fi
done

username="${!username_env:-}"
password="${!password_env:-}"

if [ -z "$username" ]; then
  fail "env var $username_env is not set (SMTP username)"
fi

if [ -z "$password" ]; then
  fail "env var $password_env is not set (SMTP password)"
fi

recipient_count=$(yq '.notifications.email.to | length' "$CONFIG_FILE")
if [ "$recipient_count" -eq 0 ]; then
  fail "notifications.email.to is empty -- no recipients"
fi

first_recipient=$(yq '.notifications.email.to[0]' "$CONFIG_FILE")

echo "Checking SMTP config..."
echo "  smtp_host:        $smtp_host"
echo "  smtp_port:        $smtp_port"
echo "  username:         $username"
echo "  recipient:        $first_recipient (first of $recipient_count)"
echo "  letsencrypt_host: ${LETSENCRYPT_HOST:-<not set>}"
echo ""
echo "Sending test email..."
echo ""

CURL_ARGS=("--verbose")
if [ "$smtp_port" = "465" ]; then
  CURL_ARGS+=("--url" "smtps://${smtp_host}:${smtp_port}")
else
  CURL_ARGS+=("--url" "smtp://${smtp_host}:${smtp_port}" "--ssl-reqd")
fi

CURL_EXIT=0
curl "${CURL_ARGS[@]}" \
  --mail-from "$username" \
  --mail-rcpt "$first_recipient" \
  --user "${username}:${password}" \
  -T - <<EOF || CURL_EXIT=$?
From: $username
To: $first_recipient
Subject: [Backup Test] SMTP connectivity check

This is a test email from test-notify.sh.
Host: $(hostname)
Letsencrypt Host: ${LETSENCRYPT_HOST:-<not set>}
Date: $(date -u +"%Y-%m-%d %H:%M:%S UTC")

If you received this, SMTP notifications are working.
EOF

echo ""
if [ "$CURL_EXIT" -eq 0 ]; then
  echo "PASS: test email sent to $first_recipient"
else
  case "$CURL_EXIT" in
    6)  echo "FAIL: curl exit $CURL_EXIT -- could not resolve host '$smtp_host'" ;;
    7)  echo "FAIL: curl exit $CURL_EXIT -- could not connect to $smtp_host:$smtp_port" ;;
    67) echo "FAIL: curl exit $CURL_EXIT -- SMTP authentication failed (check $username_env / $password_env)" ;;
    56) echo "FAIL: curl exit $CURL_EXIT -- network error during SMTP session" ;;
    *)  echo "FAIL: curl exit $CURL_EXIT -- see verbose output above" ;;
  esac
  exit 1
fi
