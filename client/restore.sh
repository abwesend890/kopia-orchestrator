#!/bin/bash
set -euo pipefail

usage() {
  echo "Usage:"
  echo "  $0 list [path]           List snapshots (optionally filter by path)"
  echo "  $0 restore <id> <target> Restore snapshot to target path"
  exit 1
}

if [ $# -lt 1 ]; then
  usage
fi

case "$1" in
  list)
    if [ -n "${2:-}" ]; then
      kopia snapshot list "$2"
    else
      kopia snapshot list
    fi
    ;;
  restore)
    if [ $# -lt 3 ]; then
      echo "ERROR: restore requires snapshot ID and target path"
      usage
    fi
    echo "Restoring snapshot $2 to $3..."
    kopia restore "$2" "$3"
    echo "Restore complete."
    ;;
  *)
    usage
    ;;
esac
