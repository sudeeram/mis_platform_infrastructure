# Platform Infrastructure

## Contribution workflow

Run `./scripts/setup-git-hooks.sh` once after cloning. All work must use a
`feature/*`, `hotfix/*`, or `bugfix/*` branch and reach `main` through a pull
request.

Helm-based Minikube development environment for the operations platform. It deploys NGINX Ingress, four application workloads, and one isolated PostgreSQL StatefulSet per Django service.

## Prerequisites

- Docker Desktop
- Minikube
- kubectl
- Helm 4
- OpenSSL

## Install

```bash
./scripts/install-minikube.sh
```

Add the emitted Minikube IP and `platform.local` to `/etc/hosts`. Development uses HTTP intentionally.

## Enabling SAML

SAML is disabled until Entra metadata and an SP certificate/key are configured. Add these files to the `platform-auth-crypto` secret:

- `entra-idp-metadata.xml`
- `saml-sp-key.pem`
- `saml-sp-cert.pem`

Then set `saml.enabled=true` and `saml.tenantId` in a local values file. Never commit identity-provider metadata containing environment-specific configuration or private keys.

The Entra enterprise application uses:

- Entity ID: `http://platform.local/api/auth/saml/metadata/`
- ACS URL: `http://platform.local/api/auth/saml/acs/`
- Sign-on URL: `http://platform.local/api/auth/entra/login`

Production deployment, RDS, EKS identity, TLS, AWS load balancing, secrets integration, and observability infrastructure are intentionally deferred.
