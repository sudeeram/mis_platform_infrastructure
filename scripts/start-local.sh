#!/bin/sh
set -eu
. "$(dirname -- "$0")/local-common.sh"

require_command uv
require_command pnpm
mkdir -p "$RUNTIME_DIR/logs"

for name in auth network aws frontend; do
  if [ -f "$RUNTIME_DIR/$name.pid" ] && kill -0 "$(cat "$RUNTIME_DIR/$name.pid")" 2>/dev/null; then
    printf '%s\n' "$name is already running. Run ./scripts/stop-local.sh first." >&2
    exit 1
  fi
done

start_django() {
  name=$1
  service_dir=$2
  port=$3
  database=$4
  username=$5
  password=$6
  (
    cd "$service_dir"
    exec env MYSQL_HOST="$MYSQL_HOST" MYSQL_PORT="$MYSQL_PORT" MYSQL_DATABASE="$database" \
      MYSQL_USER="$username" MYSQL_PASSWORD="$password" \
      DJANGO_ALLOWED_HOSTS="localhost,127.0.0.1" \
      JWT_ISSUER="$FRONTEND_ORIGIN/api/auth" \
      JWT_JWKS_URL="http://127.0.0.1:$AUTH_PORT/api/auth/.well-known/jwks.json" \
      uv run python manage.py runserver "127.0.0.1:$port"
  ) >"$RUNTIME_DIR/logs/$name.log" 2>&1 &
  echo $! >"$RUNTIME_DIR/$name.pid"
}

(
  cd "$AUTH_DIR"
  exec env MYSQL_HOST="$MYSQL_HOST" MYSQL_PORT="$MYSQL_PORT" MYSQL_DATABASE="$AUTH_MYSQL_DATABASE" \
    MYSQL_USER="$AUTH_MYSQL_USER" MYSQL_PASSWORD="$AUTH_MYSQL_PASSWORD" \
    DJANGO_ALLOWED_HOSTS="localhost,127.0.0.1" CSRF_TRUSTED_ORIGINS="$FRONTEND_ORIGIN" \
    PLATFORM_PUBLIC_ORIGIN="$FRONTEND_ORIGIN" JWT_ISSUER="$FRONTEND_ORIGIN/api/auth" \
    JWT_PRIVATE_KEY_FILE=dev-certs/jwt-private.pem JWT_PUBLIC_KEY_FILE=dev-certs/jwt-public.pem \
    AUTH_COOKIE_SECURE=false SAML_ENABLED=false \
    uv run python manage.py runserver "127.0.0.1:$AUTH_PORT"
) >"$RUNTIME_DIR/logs/auth.log" 2>&1 &
echo $! >"$RUNTIME_DIR/auth.pid"

start_django network "$NETWORK_DIR" "$NETWORK_PORT" "$NETWORK_MYSQL_DATABASE" "$NETWORK_MYSQL_USER" "$NETWORK_MYSQL_PASSWORD"
start_django aws "$AWS_DIR" "$AWS_PORT" "$AWS_MYSQL_DATABASE" "$AWS_MYSQL_USER" "$AWS_MYSQL_PASSWORD"

(
  cd "$FRONTEND_DIR"
  exec env AUTH_PROXY_TARGET="http://127.0.0.1:$AUTH_PORT" \
    NETWORK_PROXY_TARGET="http://127.0.0.1:$NETWORK_PORT" \
    AWS_PROXY_TARGET="http://127.0.0.1:$AWS_PORT" pnpm dev
) >"$RUNTIME_DIR/logs/frontend.log" 2>&1 &
echo $! >"$RUNTIME_DIR/frontend.pid"

printf '%s\n' "Full stack is starting at $FRONTEND_ORIGIN"
printf '%s\n' "Logs: $RUNTIME_DIR/logs"
printf '%s\n' "Stop: ./scripts/stop-local.sh"
