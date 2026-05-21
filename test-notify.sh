#!/bin/bash
set -euo pipefail

CONFIG_FILE="${CONFIG_FILE:-/etc/backup/config.yml}"
NOTIFY_SUBJECT_PREFIX="${NOTIFY_SUBJECT_PREFIX:-Backup}"

USAGE="Notification smoke test

Tests the first available notification path:
  1. SMTP email (from config.yml notifications.email section)
  2. Contact form POST (from CONTACT_FORM_URL env var)

Uses verbose output to surface errors.

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

if ! command -v curl &>/dev/null; then
  fail "curl not found in PATH"
fi

test_smtp() {
  if ! command -v yq &>/dev/null; then
    return 1
  fi

  if [ ! -f "$CONFIG_FILE" ]; then
    return 1
  fi

  local enabled
  enabled=$(yq '.notifications.email // ""' "$CONFIG_FILE")
  if [ -z "$enabled" ] || [ "$enabled" = "null" ]; then
    return 1
  fi

  local smtp_host smtp_port username_env password_env
  smtp_host=$(yq '.notifications.email.smtp_host' "$CONFIG_FILE")
  smtp_port=$(yq '.notifications.email.smtp_port' "$CONFIG_FILE")
  username_env=$(yq '.notifications.email.username_env' "$CONFIG_FILE")
  password_env=$(yq '.notifications.email.password_env' "$CONFIG_FILE")

  for field in smtp_host smtp_port username_env password_env; do
    local val="${!field}"
    if [ -z "$val" ] || [ "$val" = "null" ]; then
      fail "notifications.email.${field} is missing or empty in $CONFIG_FILE"
    fi
  done

  local username="${!username_env:-}"
  local password="${!password_env:-}"

  if [ -z "$username" ]; then
    fail "env var $username_env is not set (SMTP username)"
  fi

  if [ -z "$password" ]; then
    fail "env var $password_env is not set (SMTP password)"
  fi

  local recipient_count
  recipient_count=$(yq '.notifications.email.to | length' "$CONFIG_FILE")
  if [ "$recipient_count" -eq 0 ]; then
    fail "notifications.email.to is empty -- no recipients"
  fi

  local first_recipient
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

  local curl_args=("--verbose")
  if [ "$smtp_port" = "465" ]; then
    curl_args+=("--url" "smtps://${smtp_host}:${smtp_port}")
  else
    curl_args+=("--url" "smtp://${smtp_host}:${smtp_port}" "--ssl-reqd")
  fi

  local curl_exit=0
  curl "${curl_args[@]}" \
    --mail-from "$username" \
    --mail-rcpt "$first_recipient" \
    --user "${username}:${password}" \
    -T - <<EOF || curl_exit=$?
From: $username
To: $first_recipient
Subject: [${NOTIFY_SUBJECT_PREFIX}] SMTP connectivity check

This is a test email from test-notify.sh.
Host: $(hostname)
Letsencrypt Host: ${LETSENCRYPT_HOST:-<not set>}
Date: $(date -u +"%Y-%m-%d %H:%M:%S UTC")

If you received this, SMTP notifications are working.
EOF

  echo ""
  if [ "$curl_exit" -eq 0 ]; then
    echo "PASS: test email sent to $first_recipient"
  else
    case "$curl_exit" in
      6)  echo "FAIL: curl exit $curl_exit -- could not resolve host '$smtp_host'" ;;
      7)  echo "FAIL: curl exit $curl_exit -- could not connect to $smtp_host:$smtp_port" ;;
      67) echo "FAIL: curl exit $curl_exit -- SMTP authentication failed (check $username_env / $password_env)" ;;
      56) echo "FAIL: curl exit $curl_exit -- network error during SMTP session" ;;
      *)  echo "FAIL: curl exit $curl_exit -- see verbose output above" ;;
    esac
    exit 1
  fi
}

test_contact_form() {
  if [ -z "${CONTACT_FORM_URL:-}" ]; then
    return 1
  fi

  if [ -z "${CONTACT_FORM_EMAIL:-}" ] || [ -z "${CONTACT_FORM_NAME:-}" ]; then
    fail "CONTACT_FORM_URL set but CONTACT_FORM_EMAIL or CONTACT_FORM_NAME missing"
  fi

  echo "Checking contact form config..."
  echo "  url:   $CONTACT_FORM_URL"
  echo "  email: $CONTACT_FORM_EMAIL"
  echo "  name:  $CONTACT_FORM_NAME"
  echo ""
  echo "Sending test POST..."
  echo ""

  local curl_exit=0
  curl --verbose \
    --data-urlencode "email=${CONTACT_FORM_EMAIL}" \
    --data-urlencode "name=${CONTACT_FORM_NAME}" \
    --data-urlencode "subject=[${NOTIFY_SUBJECT_PREFIX}] Contact form connectivity check" \
    --data-urlencode "message=Test from test-notify.sh on $(hostname) at $(date -u +'%Y-%m-%d %H:%M:%S UTC')" \
    "$CONTACT_FORM_URL" || curl_exit=$?

  echo ""
  if [ "$curl_exit" -eq 0 ]; then
    echo "PASS: contact form POST sent to $CONTACT_FORM_URL"
  else
    case "$curl_exit" in
      6)  echo "FAIL: curl exit $curl_exit -- could not resolve host" ;;
      7)  echo "FAIL: curl exit $curl_exit -- could not connect" ;;
      *)  echo "FAIL: curl exit $curl_exit -- see verbose output above" ;;
    esac
    exit 1
  fi
}

test_smtp && exit 0
test_contact_form && exit 0
fail "no notification method configured (need SMTP in config.yml or CONTACT_FORM_URL env var)"
