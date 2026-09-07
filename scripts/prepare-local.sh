#!/bin/sh
set -eu
. "$(dirname -- "$0")/local-common.sh"

require_command mysql
require_command openssl
require_command uv
require_command pnpm
require_repo "$FRONTEND_DIR"
require_repo "$AUTH_DIR"
require_repo "$NETWORK_DIR"
require_repo "$AWS_DIR"

mysql_admin() {
  if [ -n "$MYSQL_ADMIN_PASSWORD" ]; then
    MYSQL_PWD=$MYSQL_ADMIN_PASSWORD mysql -h "$MYSQL_HOST" -P "$MYSQL_PORT" -u "$MYSQL_ADMIN_USER" "$@"
  else
    mysql -h "$MYSQL_HOST" -P "$MYSQL_PORT" -u "$MYSQL_ADMIN_USER" "$@"
  fi
}

mysql_admin <<SQL
CREATE DATABASE IF NOT EXISTS \`$AUTH_MYSQL_DATABASE\` CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
CREATE DATABASE IF NOT EXISTS \`$NETWORK_MYSQL_DATABASE\` CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
CREATE DATABASE IF NOT EXISTS \`$AWS_MYSQL_DATABASE\` CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
CREATE USER IF NOT EXISTS '$AUTH_MYSQL_USER'@'%' IDENTIFIED BY '$AUTH_MYSQL_PASSWORD';
ALTER USER '$AUTH_MYSQL_USER'@'%' IDENTIFIED BY '$AUTH_MYSQL_PASSWORD';
CREATE USER IF NOT EXISTS '$NETWORK_MYSQL_USER'@'%' IDENTIFIED BY '$NETWORK_MYSQL_PASSWORD';
ALTER USER '$NETWORK_MYSQL_USER'@'%' IDENTIFIED BY '$NETWORK_MYSQL_PASSWORD';
CREATE USER IF NOT EXISTS '$AWS_MYSQL_USER'@'%' IDENTIFIED BY '$AWS_MYSQL_PASSWORD';
ALTER USER '$AWS_MYSQL_USER'@'%' IDENTIFIED BY '$AWS_MYSQL_PASSWORD';
GRANT ALL PRIVILEGES ON \`$AUTH_MYSQL_DATABASE\`.* TO '$AUTH_MYSQL_USER'@'%';
GRANT ALL PRIVILEGES ON \`$NETWORK_MYSQL_DATABASE\`.* TO '$NETWORK_MYSQL_USER'@'%';
GRANT ALL PRIVILEGES ON \`$AWS_MYSQL_DATABASE\`.* TO '$AWS_MYSQL_USER'@'%';
FLUSH PRIVILEGES;
SQL

mkdir -p "$AUTH_DIR/dev-certs"
if [ ! -f "$AUTH_DIR/dev-certs/jwt-private.pem" ]; then
  openssl genpkey -algorithm RSA -out "$AUTH_DIR/dev-certs/jwt-private.pem" -pkeyopt rsa_keygen_bits:2048
  openssl rsa -pubout -in "$AUTH_DIR/dev-certs/jwt-private.pem" -out "$AUTH_DIR/dev-certs/jwt-public.pem"
fi

prepare_django() {
  service_dir=$1
  database=$2
  username=$3
  password=$4
  (
    cd "$service_dir"
    uv sync --frozen
    MYSQL_HOST=$MYSQL_HOST MYSQL_PORT=$MYSQL_PORT MYSQL_DATABASE=$database \
      MYSQL_USER=$username MYSQL_PASSWORD=$password uv run python manage.py migrate --noinput
  )
}

prepare_django "$AUTH_DIR" "$AUTH_MYSQL_DATABASE" "$AUTH_MYSQL_USER" "$AUTH_MYSQL_PASSWORD"
prepare_django "$NETWORK_DIR" "$NETWORK_MYSQL_DATABASE" "$NETWORK_MYSQL_USER" "$NETWORK_MYSQL_PASSWORD"
prepare_django "$AWS_DIR" "$AWS_MYSQL_DATABASE" "$AWS_MYSQL_USER" "$AWS_MYSQL_PASSWORD"
(
  cd "$AUTH_DIR"
  MYSQL_HOST=$MYSQL_HOST MYSQL_PORT=$MYSQL_PORT MYSQL_DATABASE=$AUTH_MYSQL_DATABASE \
    MYSQL_USER=$AUTH_MYSQL_USER MYSQL_PASSWORD=$AUTH_MYSQL_PASSWORD \
    JWT_PRIVATE_KEY_FILE=dev-certs/jwt-private.pem JWT_PUBLIC_KEY_FILE=dev-certs/jwt-public.pem \
    uv run python manage.py seed_rbac
)
(
  cd "$FRONTEND_DIR"
  pnpm install --frozen-lockfile
)

printf '%s\n' "Local databases, Python environments, migrations, RBAC data, and frontend dependencies are ready."
