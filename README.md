# Platform Infrastructure

Development orchestration and Helm deployment for the operations platform. The
browser reaches only the frontend gateway; it routes `/api/auth`, `/api/network`,
and `/api/aws` to the independently owned services.

The standalone, build-from-empty-repositories specification is available in
[`docs/COMPLETE_BUILD_BLUEPRINT.md`](docs/COMPLETE_BUILD_BLUEPRINT.md).

## Contribution and delivery workflow

Run `./scripts/setup-git-hooks.sh` once after cloning.

- `feature/*` and `bugfix/*` branches start from and merge into `develop`.
- `hotfix/*` branches start from and merge into `main`; merge `main` back into
  `develop` immediately afterward.
- Direct commits and pushes to `develop` and `main` are blocked locally and must
  also be protected with GitHub rulesets.
- CI validates every pull request. Minikube deployments are run only from
  `develop`; production image/deployment automation runs only from `main`.

The first PR introducing `develop` is a one-time bootstrap and therefore targets
`main`. After it is merged, create and protect `develop` before starting more
feature work.

## Full stack on the local machine

This mode uses one existing local MySQL 8 server with three isolated databases,
three Django development servers, and Vite as the local gateway.

Prerequisites: Python 3.12, uv, Node 20, pnpm, MySQL 8 client/server, and OpenSSL.

```bash
cp .env.example .env
./scripts/prepare-local.sh
./scripts/start-local.sh
```

Open `http://localhost:5173`. Logs are written under `.local-run/logs`.

```bash
./scripts/status-local.sh
./scripts/stop-local.sh
```

Create the first local administrator separately so its password is never stored
in a script or committed file:

```bash
cd ../auth-service
set -a; . ../platform-infrastructure/.env; set +a
MYSQL_DATABASE="$AUTH_MYSQL_DATABASE" MYSQL_USER="$AUTH_MYSQL_USER" \
MYSQL_PASSWORD="$AUTH_MYSQL_PASSWORD" uv run python manage.py createsuperuser
```

Local HTTP mode supports local-password authentication. Entra SAML is disabled
there because its cross-site session cookie requires HTTPS. Exercise real Entra
SAML through the Minikube ingress with TLS when that integration is configured.

## Minikube development deployment

Prerequisites: Docker Desktop, Minikube, kubectl, Helm, and OpenSSL. Check out the
`develop` branch in this repository and run:

```bash
./scripts/install-minikube.sh
```

The chart deploys NGINX Ingress, the four application workloads, and one MySQL
8.4 StatefulSet per Django service. Add the emitted Minikube IP and
`platform.local` to `/etc/hosts`; development uses HTTP until SAML/TLS testing is
enabled.

## Enabling SAML

Add `entra-idp-metadata.xml`, `saml-sp-key.pem`, and `saml-sp-cert.pem` to the
`platform-auth-crypto` secret, then set the SAML values in an ignored local Helm
values file. Never commit private keys or environment-specific identity metadata.

Production EKS/RDS identity, TLS, load balancing, secrets integration, and
observability remain intentionally deferred until their target infrastructure
and credentials are selected.
