#!/bin/sh
set -eu

PLATFORM_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
ENV_FILE=${LOCAL_ENV_FILE:-"$PLATFORM_DIR/.env"}

if [ ! -f "$ENV_FILE" ]; then
  printf '%s\n' "Missing $ENV_FILE. Copy .env.example to .env and review it." >&2
  exit 1
fi

set -a
. "$ENV_FILE"
set +a

resolve_repo_dir() {
  case "$1" in
    /*) printf '%s\n' "$1" ;;
    *) printf '%s\n' "$PLATFORM_DIR/$1" ;;
  esac
}

FRONTEND_DIR=$(resolve_repo_dir "${FRONTEND_SERVICE_DIR:-../frontend-service}")
AUTH_DIR=$(resolve_repo_dir "${AUTH_SERVICE_DIR:-../auth-service}")
NETWORK_DIR=$(resolve_repo_dir "${NETWORK_SERVICE_DIR:-../network-service}")
AWS_DIR=$(resolve_repo_dir "${AWS_SERVICE_DIR:-../aws-service}")
RUNTIME_DIR="$PLATFORM_DIR/.local-run"

MYSQL_HOST=${MYSQL_HOST:-127.0.0.1}
MYSQL_PORT=${MYSQL_PORT:-3306}
MYSQL_ADMIN_USER=${MYSQL_ADMIN_USER:-root}
MYSQL_ADMIN_PASSWORD=${MYSQL_ADMIN_PASSWORD:-}
AUTH_MYSQL_DATABASE=${AUTH_MYSQL_DATABASE:-mis_auth}
AUTH_MYSQL_USER=${AUTH_MYSQL_USER:-mis_auth}
AUTH_MYSQL_PASSWORD=${AUTH_MYSQL_PASSWORD:-auth-dev-password}
NETWORK_MYSQL_DATABASE=${NETWORK_MYSQL_DATABASE:-mis_network}
NETWORK_MYSQL_USER=${NETWORK_MYSQL_USER:-mis_network}
NETWORK_MYSQL_PASSWORD=${NETWORK_MYSQL_PASSWORD:-network-dev-password}
AWS_MYSQL_DATABASE=${AWS_MYSQL_DATABASE:-mis_aws}
AWS_MYSQL_USER=${AWS_MYSQL_USER:-mis_aws}
AWS_MYSQL_PASSWORD=${AWS_MYSQL_PASSWORD:-aws-dev-password}
FRONTEND_ORIGIN=${FRONTEND_ORIGIN:-http://localhost:5173}
AUTH_PORT=${AUTH_PORT:-8000}
NETWORK_PORT=${NETWORK_PORT:-8001}
AWS_PORT=${AWS_PORT:-8002}

require_command() {
  command -v "$1" >/dev/null 2>&1 || {
    printf '%s\n' "Required command '$1' was not found." >&2
    exit 1
  }
}

require_repo() {
  [ -d "$1/.git" ] || {
    printf '%s\n' "Expected repository not found: $1" >&2
    exit 1
  }
}
