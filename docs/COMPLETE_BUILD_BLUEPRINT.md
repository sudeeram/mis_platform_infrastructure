# Operations Platform: Complete Build Blueprint

## 1. Purpose

This document is a standalone blueprint for building an internal operations
platform composed of five independently versioned repositories:

1. A React and shadcn-style frontend.
2. A Django authentication service supporting local accounts and single-tenant
   Microsoft Entra ID SAML 2.0 SSO.
3. A Django network-domain service.
4. A Django AWS-domain service.
5. A platform-infrastructure repository containing local orchestration, NGINX
   ingress, Kubernetes manifests, and delivery conventions.

It describes both the implemented foundation and the additional controls needed
for a production-grade deployment. A team should be able to use this document to
recreate a similar platform without copying the original source repositories.

The platform is intended for one internal organization. Local and Entra accounts
are deliberately separate identities and are never automatically linked. Local
accounts are invitation- or administrator-provisioned. Eligible Entra users may
self-provision on first SAML login, but receive no business-service access until
an administrator assigns one or more roles.

### Document map

1. Purpose and architectural principles
2. System routing and repository ownership
3. Technology, Git, and delivery standards
4. Local and SAML authentication, tokens, CSRF, and authorization
5. Auth, network, AWS, and frontend service designs
6. MySQL ownership and migration strategy
7. Native, mock, Docker, Minikube, Docker-host, and EKS deployments
8. CI/CD, testing, observability, and security controls
9. Operational troubleshooting and build-from-empty sequence
10. Concrete scaffolding commands, configuration templates, and acceptance gates

## 2. Architectural principles

- The browser communicates with one public origin only.
- Business services are never directly exposed to the browser.
- Authentication is centralized; business data remains service-owned.
- Every Django service owns a separate database and database credential.
- Services do not share Django models or database tables.
- Authorization is feature-based and expressed as explicit permission strings.
- Users may hold multiple roles in the same or different services.
- Authentication and authorization are independent: a valid identity can have
  zero business permissions.
- Local and Entra identities may use the same email address because account type
  is part of identity uniqueness.
- Entra eligibility is controlled by assignment to the Entra Enterprise
  Application, normally through an Entra group.
- Microsoft Graph is not required for authentication or provisioning.
- Development and production use the same URL layout and token contract.
- Repositories are independently buildable and releasable.
- No feature work is committed directly to `develop` or `main`.

## 3. System context and request routing

```text
                       Browser
                          |
                          | one public origin
                          v
               Frontend / NGINX Gateway
                          |
          +---------------+---------------+
          |               |               |
          v               v               v
   /api/auth/*      /api/network/*     /api/aws/*
    auth-service     network-service     aws-service
          |               |               |
          v               v               v
      Auth MySQL      Network MySQL       AWS MySQL
```

Public paths remain stable in every environment:

| Public prefix | Owner | Purpose |
| --- | --- | --- |
| `/` | frontend-service | Single-page application and static assets |
| `/api/auth` | auth-service | Login, SAML, sessions, users, roles, JWKS |
| `/api/network` | network-service | Network-domain APIs |
| `/api/aws` | aws-service | AWS-domain APIs |

Routing implementations differ by environment:

- Frontend-only development uses Vite with mock API data.
- Native full-stack development uses the Vite proxy as the gateway.
- Minikube uses the Kubernetes NGINX Ingress Controller.
- Production Kubernetes should use an approved ingress/gateway implementation.
- A production Docker-host deployment should put NGINX, Envoy, Traefik, or an
  equivalent reverse proxy in front of the four containers.

The browser must never be configured with business-service hostnames. It uses
relative URLs such as `/api/network/dashboard`, which preserves same-origin
cookies and avoids browser CORS complexity.

## 4. Repository layout and ownership

Use five peer repositories under one developer workspace:

```text
project_microservices/
├── frontend-service/
├── auth-service/
├── network-service/
├── aws-service/
└── platform-infrastructure/
```

Reference repository names used by the original implementation are:

| Component | Repository |
| --- | --- |
| Frontend | `mis_frontend_service` |
| Authentication | `mis_auth_service` |
| Network | `mis_network_service` |
| AWS | `mis_aws_service` |
| Infrastructure | `mis_platform_infrastructure` |

Do not create a root-level Docker Compose file or root monorepo build. Each
component has its own Git history, dependency lockfile, Dockerfile, CI workflow,
and release lifecycle. The infrastructure repository may assume that the other
repositories are sibling directories for local orchestration.

### 4.1 frontend-service responsibility

- Render the login, no-access, dashboard, service, and administration pages.
- Use TanStack Router for route definitions and route-level permission guards.
- Use TanStack Query for server state, caching, invalidation, and retries.
- Use relative `/api/...` requests with `credentials: include`.
- Obtain and submit Django CSRF tokens for state-changing requests.
- Never store access or refresh tokens in localStorage or sessionStorage.
- Derive navigation visibility from the authenticated user's permissions.
- Provide an explicitly development-only mock-authentication mode.
- Build to static files and serve them from an unprivileged NGINX container port.

### 4.2 auth-service responsibility

- Own all user records, local password hashes, Entra identity mappings, roles,
  permissions, refresh sessions, and security audit events.
- Authenticate local email/password accounts.
- act as the SAML 2.0 Service Provider for Microsoft Entra ID.
- Self-provision eligible Entra users on first successful SAML response.
- Issue RS256 access tokens and opaque rotating refresh tokens.
- Publish public JWT keys as JWKS.
- Provide user and role administration APIs.
- Remain the source of truth for account status and effective access.

### 4.3 network-service responsibility

- Own network-domain records and feature endpoints.
- Validate platform JWTs through the auth-service JWKS endpoint.
- Enforce network permission strings locally at each endpoint.
- Store the creating user's UUID as data, not as a cross-database foreign key.
- Never query the auth database directly.

### 4.4 aws-service responsibility

- Own AWS connection metadata and later AWS-domain resources and operations.
- Validate platform JWTs through the auth-service JWKS endpoint.
- Enforce AWS permission strings locally.
- Store no long-lived AWS access keys or secrets.
- Prefer workload identity, IAM roles, EKS Pod Identity, or STS role assumption
  when real AWS execution is added.

### 4.5 platform-infrastructure responsibility

- Define the stable ingress routes.
- Provide repeatable native local-development scripts.
- Build images into Minikube and install the Helm chart.
- Define development MySQL StatefulSets and network policies.
- Generate development JWT signing keys.
- Document deployment, recovery, configuration, and branching conventions.
- Never become a shared application-code library.

## 5. Technology baseline

### 5.1 Frontend

- React 19
- TypeScript 5.9
- Vite 7
- TanStack Router
- TanStack Query
- Tailwind CSS 4
- shadcn-style local components
- Lucide icons
- Vitest
- ESLint 9 flat configuration
- pnpm with a committed lockfile
- Node.js 20, pinned with `.nvmrc`

Use `satnaing/shadcn-admin` as a visual and organizational reference only. Do
not copy its code, authentication provider, or licensing assumptions. TanStack
Router is preferred over React Router here because route definitions, typed
navigation, loaders, and route context integrate cleanly with TanStack Query.

### 5.2 Backend services

- Python 3.12, pinned with `.python-version`
- uv for virtual environments and dependency locking
- Django 5.2 LTS-compatible series
- Django REST Framework 3.16
- Gunicorn for container execution
- mysqlclient for MySQL connectivity
- PyJWT with cryptography for RS256 JWTs
- WhiteNoise for Django static assets where needed
- djangosaml2 and PySAML2 in auth-service
- Argon2 as the preferred local password hasher

Each Django repository contains `pyproject.toml` and `uv.lock`. Do not install
runtime dependencies globally.

### 5.3 Data and infrastructure

- MySQL 8.4 LTS-compatible behavior
- InnoDB tables
- `utf8mb4` character set
- `READ COMMITTED` transaction isolation
- Docker images per component
- Kubernetes and Helm for Minikube and production-compatible packaging
- NGINX Ingress for the current development cluster
- GitHub Actions for CI and image publishing
- GitHub Container Registry for immutable release images

## 6. Git and delivery model

### 6.1 Permanent branches

- `develop` represents the integrated development environment.
- `main` represents production-ready code.

Protect both branches against deletion, force pushes, and direct updates. Require
pull requests and successful CI. Add approval requirements appropriate to team
size. For a private repository whose GitHub plan does not support repository
rulesets, use classic branch protection or upgrade the plan; local hooks alone
are a guardrail, not an adequate server-side control.

### 6.2 Working branches

| Branch | Starts from | Pull request target | Use |
| --- | --- | --- | --- |
| `feature/*` | `develop` | `develop` | New capability |
| `bugfix/*` | `develop` | `develop` | Normal defect correction |
| `hotfix/*` | `main` | `main` | Urgent production correction |

After merging a hotfix into `main`, immediately merge or forward-port `main`
back into `develop`.

### 6.3 Cross-repository changes

A feature spanning multiple services must use a matching branch name in every
affected repository and a separate pull request per repository. Document merge
order and backward compatibility in each PR. Prefer compatibility windows:

1. Deploy additive provider/API changes.
2. Deploy consumers.
3. Remove deprecated behavior in a later release.

Do not rely on simultaneous commits or deployments across repositories.

### 6.4 Repository hooks

Install tracked hooks after cloning:

```bash
./scripts/setup-git-hooks.sh
```

The pre-commit hook permits only `feature/*`, `bugfix/*`, and `hotfix/*`. The
pre-push hook rejects direct pushes to `develop`, `main`, or `master` and rejects
unexpected branch names. Server-side GitHub protection remains authoritative.

## 7. Authentication and session design

### 7.1 Custom user model

Create the user model before the first migration by extending
`django.contrib.auth.models.AbstractUser`. Set:

```python
AUTH_USER_MODEL = "accounts.User"
```

Retain Django's battle-tested password hashing, permissions compatibility,
administration integration, last-login behavior, and superuser mechanics while
adding platform fields.

Core fields:

| Field | Type | Notes |
| --- | --- | --- |
| `id` | UUID | Primary key |
| `username` | string | Internal Django identifier; not the login UI field |
| `email` | email | Normalized to lowercase before save |
| `account_type` | enum | `LOCAL` or `ENTRA` |
| `status` | enum | `ACTIVE`, `SUSPENDED`, or `DISABLED` |
| `display_name` | string | Optional friendly name |
| `created_at` | timestamp | Audit metadata |
| `updated_at` | timestamp | Audit metadata |

Enforce a unique constraint on `(account_type, email)`. This allows a local and
an Entra account to share an email while preventing duplicates within one
account type. Entra accounts always have unusable Django passwords.

Do not use Django's default `User` model and migrate later. Changing
`AUTH_USER_MODEL` after tables and foreign keys exist is costly and error-prone.

### 7.2 Local authentication

Local users are provisioned only by an administrator or invitation workflow.
There is no public local-registration endpoint.

Implement a `LocalEmailBackend` that:

1. Selects a user by case-insensitive email and `account_type=LOCAL`.
2. Performs a dummy password hash when no user is found to reduce timing leaks.
3. Requires `status=ACTIVE`.
4. Calls Django's `check_password`.

Use Argon2 first and PBKDF2 as fallback. Apply Django's standard password
validators. Password reset email and invitation delivery can be added later with
Mailpit in development and an approved provider in production.

### 7.3 Entra ID SAML 2.0 authentication

Create one single-tenant Microsoft Entra Enterprise Application. Require user
assignment and assign the approved Entra group to that application. Entra then
controls who may reach the Service Provider; the platform controls what an
authenticated user may do.

The minimum SAML flow is:

```text
Browser -> GET /api/auth/entra/login
Auth service -> SAML AuthnRequest redirect to Entra
Entra -> signed SAMLResponse POST to /api/auth/saml/acs/
Auth service -> validate response, issuer, signature, audience, timestamps
Auth service -> locate or provision Entra identity
Auth service -> issue platform cookies
Auth service -> redirect browser to frontend dashboard/no-access page
```

Configure the Service Provider endpoints for the public origin:

| Setting | Value pattern |
| --- | --- |
| Entity ID | `https://<host>/api/auth/saml/metadata/` |
| ACS/Reply URL | `https://<host>/api/auth/saml/acs/` |
| Sign-on URL | `https://<host>/api/auth/entra/login` |
| Redirect logout | `https://<host>/api/auth/saml/ls/` |
| POST logout | `https://<host>/api/auth/saml/ls/post/` |

Request or map these claims:

| Claim | Purpose |
| --- | --- |
| Entra object identifier | Immutable per-user provisioning identifier |
| Email address | Display and contact identifier |
| Display name | Friendly profile name |

Persist Entra identity using `(tenant_id, object_id)` as the unique key. Do not
use email as the immutable SSO key. Validate that the assertion issuer equals the
configured tenant IdP entity ID. Require signed responses and assertions; sign
authentication and logout requests.

On first successful login:

1. Create an `ENTRA` user with an unusable password.
2. Create the tenant/object identity record.
3. Mark the account active.
4. Assign no roles.
5. Permit profile/no-access pages only.

Do not look for or link a local user with the same email. Microsoft Graph is not
needed for this flow.

SAML requires correctly configured HTTPS in realistic environments. Do not test
real Entra SAML over the plain-HTTP native workflow. Use an HTTPS Minikube or
shared development ingress with a hostname and certificate trusted by the
browser and accepted in the Entra application.

### 7.4 Platform tokens

After either authentication method succeeds, issue:

- An RS256 access JWT in an HTTP-only cookie.
- A cryptographically random opaque refresh token in an HTTP-only cookie.

Recommended defaults implemented by the skeleton:

| Property | Access token | Refresh token |
| --- | --- | --- |
| Lifetime | 10 minutes | 7 days |
| Cookie path | `/api/` | `/api/auth/` |
| JavaScript readable | No | No |
| SameSite | `Lax` | `Lax` |
| Secure in production | Yes | Yes |
| Storage | Browser cookie only | Hash and metadata in Auth DB |

The refresh cookie contains `<session-uuid>.<random-secret>`. Store only a
SHA-256 hash of the random secret. Compare hashes in constant time. Rotate the
refresh session each time it is used and revoke the previous session.

Access-token claims:

```json
{
  "iss": "https://platform.example.com/api/auth",
  "sub": "user-uuid",
  "aud": "platform-api",
  "iat": 0,
  "nbf": 0,
  "exp": 0,
  "jti": "random-id",
  "account_type": "LOCAL",
  "roles": ["network.operator"],
  "permissions": ["network:devices:view"],
  "services": ["network"]
}
```

Publish the matching RSA public key from
`/api/auth/.well-known/jwks.json`. Include a stable `kid`. Business services use
the JWKS endpoint, validate RS256, issuer, audience, expiry, and not-before, and
cache signing keys briefly. Plan a rotation window in which old and new public
keys are both published.

For non-browser clients, optionally accept the same JWT as a Bearer token. Do not
enable password grant or copy private signing keys into business services.

### 7.5 CSRF and cookie handling

Cookie authentication requires CSRF protection on unsafe methods. Provide
`GET /api/auth/csrf`, return Django's CSRF token, and set the CSRF cookie. The
frontend sends the token in `X-CSRFToken` for POST, PUT, PATCH, and DELETE.

Because Django REST Framework API views are otherwise CSRF-exempt in some
configurations, add an explicit authentication class that invokes Django's
`CSRFCheck`. Configure the exact public frontend origins in
`CSRF_TRUSTED_ORIGINS`.

Typical local failure:

```text
Origin checking failed - http://localhost:5173 does not match any trusted origins
```

This means the auth server was started without the coordinated environment or an
older server is occupying port 8000.

### 7.6 Logout, disabling, and revocation

- Logout revokes the presented refresh session and deletes both cookies.
- Suspending or disabling a user revokes all active refresh sessions.
- Access JWTs already issued to business services remain usable until their
  short expiry. Keep the access TTL short or add a centralized/introspected
  revocation mechanism only if immediate revocation is a firm requirement.
- Role changes become visible when a new access token is issued. Force a refresh
  or re-login when immediate new privileges are required.

## 8. Authorization model

Use platform-owned RBAC with feature-level permissions. Do not use resource-level
assignments unless future requirements change.

Data model:

```text
Service 1---* Permission
Service 1---* Role
Role    *---* Permission  through RolePermission
User    *---* Role        through UserRole
```

Seed this initial catalog idempotently:

| Role | Permissions |
| --- | --- |
| `platform.user_administrator` | `platform:users:admin` |
| `platform.security_administrator` | `platform:users:admin`, `platform:security:admin` |
| `network.viewer` | dashboard view, device view |
| `network.operator` | viewer permissions, create/update devices, execute operations |
| `network.administrator` | operator permissions, delete devices, network administration |
| `aws.viewer` | dashboard, connections, and resources view |
| `aws.operator` | viewer permissions and operation execution |
| `aws.administrator` | operator permissions, connection CRUD, AWS administration |

Represent permissions with stable namespaced strings, for example:

```text
network:devices:view
network:devices:create
network:devices:update
network:devices:delete
aws:connections:view
aws:operations:execute
platform:users:admin
```

Each business endpoint declares its required permission. The frontend also uses
permissions to hide navigation and guard routes, but frontend checks are only a
user-experience feature. The backend permission check is authoritative.

Django `is_superuser` is intentionally distinct from business-service roles.
Bootstrap administrators must receive explicit platform/network/AWS roles if
they need those features. This avoids silently turning Django framework
administrators into universal distributed-service principals.

## 9. Auth-service design

Recommended structure:

```text
auth-service/
├── .github/workflows/
│   ├── ci.yml
│   └── release-image.yml
├── accounts/
│   ├── management/commands/seed_rbac.py
│   ├── migrations/
│   ├── admin.py
│   ├── authentication.py
│   ├── backends.py
│   ├── middleware.py
│   ├── models.py
│   ├── saml_backend.py
│   ├── serializers.py
│   ├── tokens.py
│   ├── urls.py
│   └── views.py
├── config/
│   ├── settings.py
│   ├── urls.py
│   └── wsgi.py
├── scripts/setup-git-hooks.sh
├── .env.example
├── .python-version
├── Dockerfile
├── manage.py
├── pyproject.toml
└── uv.lock
```

### 9.1 Auth database entities

| Entity | Key behavior |
| --- | --- |
| User | Custom UUID user; local or Entra; status-controlled |
| EntraIdentity | Unique tenant/object ID mapped one-to-one to User |
| Service | Authorization namespace such as platform/network/aws |
| Permission | Stable feature permission key |
| Role | Named permission bundle owned by a service |
| RolePermission | Unique role/permission membership |
| UserRole | Unique user/role assignment with assigning user and time |
| RefreshSession | Hashed opaque token, auth method, expiry, revocation |
| SecurityAuditEvent | User, event type, outcome, IP, details, timestamp |

### 9.2 Auth API

| Method and path | Authentication | Purpose |
| --- | --- | --- |
| `GET /api/auth/csrf` | Public | Initialize CSRF token |
| `POST /api/auth/login` | CSRF | Local email/password login |
| `POST /api/auth/refresh` | Refresh cookie + CSRF | Rotate session and JWT |
| `POST /api/auth/logout` | Cookie + CSRF | Revoke and clear cookies |
| `GET /api/auth/me` | JWT | Current profile and access |
| `GET /api/auth/.well-known/jwks.json` | Public | JWT public keys |
| `GET /api/auth/entra/login` | Public | Begin SAML login |
| `GET /api/auth/saml/metadata/` | Public | SAML SP metadata |
| `POST /api/auth/saml/acs/` | SAML response | Assertion consumer service |
| `GET /api/auth/admin/users` | User admin | List users |
| `POST /api/auth/admin/users` | User admin | Provision local user |
| `GET /api/auth/admin/users/{uuid}` | User admin | User detail |
| `PATCH /api/auth/admin/users/{uuid}` | User admin | Change status |
| `GET /api/auth/admin/roles` | User admin | List assignable roles |
| `POST /api/auth/admin/users/{uuid}/roles` | User admin | Assign role |
| `DELETE /api/auth/admin/users/{uuid}/roles/{role_uuid}` | User admin | Remove role |
| `GET /api/auth/health/live` | Public | Process liveness |
| `GET /api/auth/health/ready` | Public | Database readiness |

Add pagination, search, audit-event APIs, invitation endpoints, password reset,
rate limiting, and structured API schemas before exposing large-scale production
administration.

### 9.3 Auth environment variables

| Variable | Purpose |
| --- | --- |
| `DJANGO_SECRET_KEY` | Django signing secret |
| `DJANGO_DEBUG` | Debug mode; false in production |
| `DJANGO_ALLOWED_HOSTS` | Accepted Host headers |
| `CSRF_TRUSTED_ORIGINS` | Exact public HTTPS origins |
| `MYSQL_HOST`, `MYSQL_PORT` | Auth database endpoint |
| `MYSQL_DATABASE`, `MYSQL_USER`, `MYSQL_PASSWORD` | Auth database identity |
| `PLATFORM_PUBLIC_ORIGIN` | Browser-visible base origin |
| `FRONTEND_AFTER_LOGIN`, `FRONTEND_AFTER_LOGOUT` | Redirect destinations |
| `JWT_ISSUER`, `JWT_AUDIENCE`, `JWT_KEY_ID` | JWT validation contract |
| `JWT_PRIVATE_KEY_FILE`, `JWT_PUBLIC_KEY_FILE` | Mounted RSA keys |
| `ACCESS_TOKEN_TTL_SECONDS` | Access lifetime |
| `REFRESH_TOKEN_TTL_SECONDS` | Refresh lifetime |
| `AUTH_COOKIE_SECURE` | Must be true under production HTTPS |
| `SAML_ENABLED` | Enable only with complete SAML material |
| `SAML_TENANT_ID` | Single Entra tenant UUID |
| `SAML_IDP_ENTITY_ID` | Expected Entra issuer |
| `SAML_IDP_METADATA_FILE` | Mounted Entra metadata XML |
| `SAML_SP_PRIVATE_KEY_FILE` | Mounted SP private key |
| `SAML_SP_CERT_FILE` | Mounted SP certificate |
| `XMLSEC_BINARY` | xmlsec1 executable path |

`USE_SQLITE_FOR_TESTS=true` is an isolated test convenience only. Explicitly
unset it before provisioning or modifying MySQL users.

## 10. Network-service design

Recommended structure mirrors a normal small Django service with a `network`
application and a `config` project.

Initial `Device` entity:

| Field | Type |
| --- | --- |
| `id` | UUID primary key |
| `name` | 120-character string |
| `hostname_or_address` | 255-character string |
| `description` | optional text |
| `status` | `UNKNOWN`, `ACTIVE`, or `INACTIVE` |
| `created_by_user_id` | auth user UUID, no database FK |
| `created_at`, `updated_at` | timestamps |

Initial endpoints:

| Method and path | Permission |
| --- | --- |
| `GET /api/network/dashboard` | `network:dashboard:view` |
| `GET /api/network/devices` | `network:devices:view` |
| `GET /api/network/devices/{uuid}` | `network:devices:view` |
| `POST /api/network/devices` | `network:devices:create` |
| `PUT/PATCH /api/network/devices/{uuid}` | `network:devices:update` |
| `DELETE /api/network/devices/{uuid}` | `network:devices:delete` |
| `GET /api/network/health/live` | Public |
| `GET /api/network/health/ready` | Public plus DB check |

Real device credentials, inventory collection, job execution, secrets handling,
and asynchronous automation are intentionally outside the initial skeleton. Add
them behind explicit permissions, audit records, and a job queue rather than in
HTTP request handlers.

## 11. AWS-service design

Initial `AwsConnection` entity:

| Field | Type |
| --- | --- |
| `id` | UUID primary key |
| `name` | 120-character string |
| `aws_account_id` | exactly 12 digits |
| `default_region` | 32-character string |
| `authentication_method` | `IAM_ROLE` or development placeholder |
| `status` | `UNVERIFIED`, `ACTIVE`, or `DISABLED` |
| `created_by_user_id` | auth user UUID, no database FK |
| `created_at`, `updated_at` | timestamps |

Initial endpoints:

| Method and path | Permission |
| --- | --- |
| `GET /api/aws/dashboard` | `aws:dashboard:view` |
| `GET /api/aws/connections` | `aws:connections:view` |
| `GET /api/aws/connections/{uuid}` | `aws:connections:view` |
| `POST /api/aws/connections` | `aws:connections:create` |
| `PUT/PATCH /api/aws/connections/{uuid}` | `aws:connections:update` |
| `DELETE /api/aws/connections/{uuid}` | `aws:connections:delete` |
| `GET /api/aws/health/live` | Public |
| `GET /api/aws/health/ready` | Public plus DB check |

Never store AWS secret access keys in this table. In production, store role ARNs
and external IDs where appropriate and obtain short-lived credentials through a
workload identity and STS.

## 12. Shared business-service conventions

Each business service:

1. Reads the JWT from the `platform_access` cookie or Bearer header.
2. Obtains the signing key from auth-service JWKS.
3. Validates issuer, audience, signature, and time claims.
4. Constructs a lightweight principal using `sub`.
5. Checks the endpoint's required permission against JWT claims.
6. Never loads the user from its own database.

Add a correlation-ID middleware. Accept a safe incoming identifier or generate a
UUID, attach it to the request and response, and include it in structured logs.
Normalize errors:

```json
{
  "error": {
    "code": "permission_denied",
    "message": "You do not have permission to perform this action.",
    "correlationId": "..."
  }
}
```

Use explicit serializers and read-only ownership/timestamp fields. Add pagination
before list endpoints can grow substantially. Publish an OpenAPI contract and
version breaking changes rather than coupling frontend code to internal models.

## 13. Frontend design

Recommended structure:

```text
frontend-service/
├── .github/workflows/
├── src/
│   ├── components/
│   │   ├── ui/
│   │   ├── app-shell.tsx
│   │   └── ui-showcase.tsx
│   ├── lib/
│   │   ├── api.ts
│   │   └── auth.tsx
│   ├── main.tsx
│   ├── routes.tsx
│   └── index.css
├── .env.example
├── .nvmrc
├── Dockerfile
├── nginx.conf
├── package.json
├── pnpm-lock.yaml
├── tsconfig.json
└── vite.config.ts
```

### 13.1 Route model

| Route | Guard |
| --- | --- |
| `/login` | Public |
| `/dashboard` | Authenticated |
| `/no-access` | Authenticated; zero business grants |
| `/ui-showcase` | Authenticated demonstration page |
| `/network` | `network:dashboard:view` |
| `/aws` | `aws:dashboard:view` |
| `/admin/users` | `platform:users:admin` |
| `/admin/users/{uuid}` | `platform:users:admin` |
| `/forbidden` | Authenticated |

The protected parent route loads `/api/auth/me`. Failed authentication redirects
to `/login`. Individual route guards verify permissions. Navigation shows
Network or AWS from the `services` claim and Users from
`platform:users:admin`.

### 13.2 API client behavior

- Use relative paths and `credentials: include`.
- Fetch a CSRF token lazily before the first unsafe request.
- Set `Content-Type: application/json` when a body exists.
- On a 401, attempt one refresh unless the failing endpoint is refresh itself.
- Retry the original request only after successful refresh.
- Convert the platform error envelope into a user-readable error.
- Do not log credentials, cookies, JWTs, or SAML assertions.

### 13.3 Development mock mode

Start the frontend without backends:

```bash
VITE_MOCK_AUTH=true pnpm dev
```

Mock mode must be guarded by both the explicit environment variable and Vite's
development flag so it cannot be enabled in a production build. Label mock data
visibly. Mock role and user changes remain in memory only.

## 14. Database strategy

Use three logical databases and three application users even when all schemas
are hosted by one local MySQL server:

| Service | Database | User |
| --- | --- | --- |
| Auth | `mis_auth` | `mis_auth` |
| Network | `mis_network` | `mis_network` |
| AWS | `mis_aws` | `mis_aws` |

Each credential receives privileges only on its database. Never reuse the root
credential in an application. Django settings should resemble:

```python
DATABASES = {
    "default": {
        "ENGINE": "django.db.backends.mysql",
        "NAME": env("MYSQL_DATABASE"),
        "USER": env("MYSQL_USER"),
        "PASSWORD": env("MYSQL_PASSWORD"),
        "HOST": env("MYSQL_HOST"),
        "PORT": env("MYSQL_PORT", "3306"),
        "OPTIONS": {
            "charset": "utf8mb4",
            "isolation_level": "read committed",
        },
    }
}
```

Development Kubernetes may use one MySQL StatefulSet per service to emphasize
ownership. Production should normally use managed MySQL-compatible databases,
separate schemas/users, encrypted storage, backups, point-in-time recovery,
Multi-AZ topology, monitoring, and tested restoration procedures. Application
pods should not contain production databases.

Migration rules:

- Create migrations in the owning repository.
- Run `makemigrations --check --dry-run` in CI.
- Apply migrations before application rollout through a controlled job or init
  phase.
- Prefer backward-compatible expand/migrate/contract changes.
- Back up production data before destructive migrations.
- Never edit an already deployed migration; the initial migration was edited in
  this skeleton only because it preceded any production deployment.

## 15. Native local full-stack development

### 15.1 Prerequisites

- macOS or Linux shell
- Git and GitHub CLI if PR automation is desired
- Python 3.12
- uv
- Node.js 20.20 or compatible Node 20
- pnpm version pinned by the frontend
- MySQL 8 server and client
- OpenSSL

Clone all five repositories as siblings. In the infrastructure repository:

```bash
cp .env.example .env
```

The ignored `.env` defines repository paths, MySQL administrator connection,
three application databases/users/passwords, ports, and frontend origin. Use
strong local-only values and never commit the file.

### 15.2 Prepare

```bash
./scripts/prepare-local.sh
```

The preparation script should be idempotent and:

1. Verify `mysql`, `openssl`, `uv`, and `pnpm`.
2. Verify all sibling Git repositories.
3. Create the three `utf8mb4` databases.
4. Create/update the three application users and grants.
5. Generate an ignored development JWT keypair if absent.
6. Run `uv sync --frozen` in every Django repository.
7. Apply every Django migration.
8. Run the idempotent RBAC seed command.
9. Run `pnpm install --frozen-lockfile`.

### 15.3 Bootstrap the first administrator

`createsuperuser` creates a Django administrator but does not automatically add
business roles. Ensure MySQL, not SQLite, is selected:

```bash
cd ../auth-service
unset USE_SQLITE_FOR_TESTS
set -a
. ../platform-infrastructure/.env
set +a
export MYSQL_DATABASE="$AUTH_MYSQL_DATABASE"
export MYSQL_USER="$AUTH_MYSQL_USER"
export MYSQL_PASSWORD="$AUTH_MYSQL_PASSWORD"
export JWT_PRIVATE_KEY_FILE=dev-certs/jwt-private.pem
export JWT_PUBLIC_KEY_FILE=dev-certs/jwt-public.pem
uv run python manage.py createsuperuser
```

Assign bootstrap roles through a one-time management command or Django shell:

```text
platform.user_administrator
platform.security_administrator
network.administrator
aws.administrator
```

For a reusable implementation, add an idempotent `bootstrap_admin` management
command that accepts an existing email and role keys, never a password. Keep the
interactive password prompt in `createsuperuser`.

### 15.4 Start and stop

From platform-infrastructure:

```bash
./scripts/start-local.sh
./scripts/status-local.sh
```

Default processes:

| Process | Address |
| --- | --- |
| Frontend/Vite gateway | `http://localhost:5173` |
| Auth Django | `http://127.0.0.1:8000` |
| Network Django | `http://127.0.0.1:8001` |
| AWS Django | `http://127.0.0.1:8002` |
| MySQL | `127.0.0.1:3306` |

Vite proxies the public API prefixes to the appropriate Django ports. Logs and
PID files live under ignored `.local-run/`.

Stop only launcher-managed application processes:

```bash
./scripts/stop-local.sh
```

Do not stop MySQL unless the developer explicitly wants the database server
stopped. Before starting, inspect occupied ports with `lsof` or the operating
system equivalent. A partial startup commonly means an older manual runserver is
still listening.

### 15.5 Local health checks

```bash
curl http://localhost:5173/api/auth/health/ready
curl http://localhost:5173/api/network/health/ready
curl http://localhost:5173/api/aws/health/ready
```

Each should return HTTP 200 and `status=ready`. Test the platform through port
5173, not by calling business ports from the browser.

## 16. Docker images

### 16.1 Django image pattern

Use `python:3.12-slim`, copy uv from its official image, and install only required
native packages. `mysqlclient` requires compiler/client headers while building;
auth additionally needs `xmlsec1` and XML libraries. A production refinement
should use separate build and runtime stages to omit compilers from the final
image.

Build dependencies from the committed lockfile:

```text
uv sync --frozen --no-cache --no-dev
```

Run as a non-root application user. Expose 8000 and run Gunicorn, not Django's
development server. Add graceful shutdown, configurable worker counts, request
timeouts, and structured access logs before production load.

### 16.2 Frontend image pattern

Use a Node build stage and an NGINX runtime stage:

1. Enable Corepack.
2. Install the locked pnpm dependencies.
3. Run the TypeScript and Vite production build.
4. Copy `dist/` into NGINX.
5. Configure SPA fallback to `/index.html`.
6. Provide a liveness endpoint.
7. Expose an unprivileged port such as 8080.

The frontend NGINX container serves static files. Cluster ingress or the external
reverse proxy owns API routing; do not add business-service addresses to the
compiled JavaScript bundle.

## 17. Minikube deployment

### 17.1 Prerequisites

- Docker Desktop
- Minikube using the Docker driver
- kubectl
- Helm
- OpenSSL
- All application repositories available as siblings
- `platform-infrastructure` checked out on `develop`

Run:

```bash
./scripts/install-minikube.sh
```

The script:

1. Refuses deployment from a branch other than `develop`.
2. Starts Minikube with the Docker driver if needed.
3. Enables the NGINX ingress addon.
4. Generates a development RSA JWT keypair in a temporary directory.
5. Creates/updates `platform-auth-crypto` in the namespace.
6. Builds all four images directly into Minikube.
7. Runs `helm upgrade --install`.

Map the Minikube IP to the configured host:

```text
<minikube-ip> platform.local
```

Then open `http://platform.local` for non-SAML development.

### 17.2 Helm resources

The chart creates:

- One frontend Deployment and ClusterIP Service.
- Auth, network, and AWS Deployments and ClusterIP Services.
- A migration init container for each Django service.
- An additional auth RBAC-seed init container.
- Three MySQL 8.4 StatefulSets, headless Services, and PVCs.
- ConfigMaps for non-secret application settings.
- Development Secrets for database and Django values.
- The separately generated auth cryptographic Secret.
- An NGINX Ingress with API-prefix routing.
- Database ingress NetworkPolicies allowing only the matching service.

Use readiness endpoints that query the database and liveness endpoints that do
not depend on downstream services. Disable automatic service-account token mounts
when pods do not call the Kubernetes API.

### 17.3 Development-only warnings

The committed Helm password defaults and in-cluster MySQL databases are for local
development only. They must never be reused in production. The chart currently
uses HTTP and cannot safely exercise the final Entra SAML cookie flow without a
TLS extension.

## 18. Production deployment scenarios

### 18.1 Common production requirements

Regardless of target platform:

- Use one HTTPS public origin.
- Redirect HTTP to HTTPS.
- Set `AUTH_COOKIE_SECURE=true` and `DJANGO_DEBUG=false`.
- Set exact `ALLOWED_HOSTS` and `CSRF_TRUSTED_ORIGINS`.
- Keep signing keys, SAML keys, database credentials, and Django secrets in an
  approved secrets manager.
- Use externally managed MySQL-compatible databases with encryption and backups.
- Use immutable image tags or digests, never deploy `latest` as the release pin.
- Run migrations as a controlled release step with one executor.
- Add centralized logs, metrics, traces, alerts, and audit retention.
- Add a Web Application Firewall/rate limiting appropriate to risk.
- Define rollback and database restoration procedures.

### 18.2 Production on Docker hosts

This is a valid small-scale target, but no root-level Compose file is required or
recommended as the source of truth.

Provide:

- One or more hardened Linux Docker hosts.
- A reverse-proxy container or external load balancer terminating TLS.
- Four application containers pinned by digest.
- External MySQL endpoints; do not run production databases in the application
  Docker host unless explicitly accepted as a risk.
- A host-level service manager or deployment tool for restart and health policy.
- A private network so only the gateway is public.
- Read-only root filesystems and dropped Linux capabilities where compatible.

Example logical routing:

```text
443 gateway
  /api/auth    -> auth:8000
  /api/network -> network:8000
  /api/aws     -> aws:8000
  /            -> frontend:8080
```

The pipeline should connect to the host through an approved deployment mechanism,
pull exact SHA/digest images, run migrations once, update containers, perform
health checks, and roll back application images on failure. Do not place SSH keys
or host credentials in repository variables; use protected environment secrets
and required deployment approvals.

### 18.3 Production on Amazon EKS

Adapt the Helm chart rather than reusing development values unchanged:

- Replace MySQL StatefulSets with Amazon RDS/Aurora MySQL endpoints.
- Use AWS Load Balancer Controller or an approved ingress/gateway.
- Use AWS Certificate Manager for public TLS where applicable.
- Store runtime secrets in AWS Secrets Manager and mount/synchronize them through
  an approved controller.
- Use EKS Pod Identity or IAM Roles for Service Accounts for AWS-service.
- Push images to ECR or consume appropriately secured GHCR images.
- Configure requests, limits, PodDisruptionBudgets, topology spread, and multiple
  replicas.
- Configure autoscaling based on meaningful signals.
- Apply default-deny network policies with explicit DNS, database, JWKS, and
  external IdP egress.
- Add CloudWatch or OpenTelemetry logs, metrics, traces, and alerts.
- Use separate AWS accounts/clusters/namespaces and secrets per environment.

Production deployment should use a promotion model: test an immutable image in
development, promote the same digest to production, and never rebuild source for
the production promotion.

## 19. CI/CD workflows

### 19.1 Frontend CI

Run for PRs and pushes to `develop` and `main`:

```text
pnpm install --frozen-lockfile
pnpm lint
pnpm test
pnpm build
docker build
```

### 19.2 Django CI

Run each service against a MySQL 8.4 service container:

1. Install Python 3.12 and uv.
2. Install native MySQL build dependencies; auth also installs xmlsec1.
3. Run `uv sync --frozen`.
4. Generate ephemeral auth JWT keys in the runner.
5. Run `makemigrations --check --dry-run`.
6. Run migrations.
7. Run `manage.py check`.
8. Run the full test suite.
9. Build the Docker image.

Use a CI database principal permitted to create and destroy test databases. Do
not use CI credentials outside the ephemeral runner.

### 19.3 Infrastructure CI

Run:

```bash
helm lint helm/platform
helm template operations-platform helm/platform
```

Add kubeconform/kubeval, policy-as-code, shell linting, container scanning, and
secret scanning as the platform matures.

### 19.4 Development deployment

A GitHub-hosted runner cannot deploy to Minikube on a developer laptop. Choose
one explicit model:

- Keep Minikube deployment as a developer-triggered local command from a clean
  `develop` checkout; or
- Register a tightly scoped self-hosted runner on the development machine and
  trigger deployment only after successful `develop` checks.

If using a self-hosted runner, serialize deployments, restrict repository access,
avoid running untrusted fork PR code, verify each checked-out repository SHA, and
protect the runner host.

### 19.5 Production image and deployment

On a push to `main`, each application repository currently has enough information
to build and publish:

```text
ghcr.io/<owner>/<repository>:<git-sha>
ghcr.io/<owner>/<repository>:latest
```

Use the SHA tag or digest for deployment. Treat publishing and deploying as
separate jobs. Add a GitHub Environment for production with approvals and
environment-scoped secrets. The actual deployment job cannot be completed until
the target Docker hosts or EKS cluster, registry access, and rollback mechanism
are selected.

## 20. Testing strategy

### 20.1 Unit tests

Auth tests should cover:

- Local and Entra identities sharing an email.
- Case-insensitive uniqueness within an account type.
- Entra accounts having unusable passwords.
- First SAML login provisioning exactly one zero-role user.
- Repeat SAML login resolving the same tenant/object identity.
- Multiple roles combining permissions correctly.
- CSRF enforcement on login/refresh/logout.
- Secure, HTTP-only cookie attributes by environment.
- Refresh rotation, expiry, tampering, and revocation.
- Account suspension behavior.

Business-service tests should cover:

- JWT signature, issuer, audience, expiry, and `kid` failures.
- Every HTTP action mapped to the correct feature permission.
- Ownership UUID populated from `sub`.
- Serializer validation.
- Consistent error envelope and correlation ID.

Frontend tests should cover:

- Login and no-access redirects.
- Permission-protected routes and navigation.
- CSRF initialization and refresh retry behavior.
- User role toggling and cache invalidation.
- Empty, loading, error, and forbidden states.
- Tables, sorting, filters, pagination, and invalid URL state.

### 20.2 Integration tests

- Test Django migrations and suites against real MySQL 8.4 in CI.
- Start all services with generated signing keys and test login through the
  gateway.
- Verify auth JWTs against both business services.
- Change a role, refresh the token, and verify access changes.
- Suspend a user and verify refresh denial.
- Validate health probes when databases are available/unavailable.
- Validate a signed SAML response in a non-production Entra application.

### 20.3 End-to-end tests

Add Playwright or an equivalent browser suite for:

1. Local administrator login.
2. User provisioning and multi-role assignment.
3. Zero-access Entra first login.
4. Network viewer versus administrator actions.
5. AWS viewer versus administrator actions.
6. Refresh-token recovery after access expiry.
7. Logout and cookie removal.
8. Disabled-account behavior.

Never run destructive end-to-end tests against production.

## 21. Observability and auditing

The skeleton includes correlation IDs and auth security-audit storage, but a
production implementation should add:

- JSON application logs with timestamp, service, environment, severity,
  correlation ID, route, status, duration, and authenticated subject ID.
- No passwords, cookies, JWTs, refresh secrets, private keys, or SAML assertions
  in logs.
- Metrics for request count/latency/errors, authentication outcomes, refresh
  failures, database pool health, and SAML failures.
- Traces propagated through ingress and services.
- Alerts for repeated authentication failures, elevated 5xx rates, failed
  migrations, unavailable JWKS, database saturation, and certificate expiry.
- Defined retention and access policy for security audit events.

## 22. Security checklist

- [ ] Entra application is single-tenant and requires assignment.
- [ ] Only the approved Entra group is assigned.
- [ ] SAML issuer, audience, destination, signature, timestamps, and replay risk
      are validated.
- [ ] Production is HTTPS-only with secure cookies and HSTS.
- [ ] Access and refresh tokens are HTTP-only and never placed in browser storage.
- [ ] CSRF is enforced on every unsafe cookie-authenticated endpoint.
- [ ] Local passwords use Argon2 and standard validators.
- [ ] Login, refresh, SAML, and administration endpoints are rate-limited.
- [ ] JWT private keys exist only in auth-service.
- [ ] A documented JWT key-rotation procedure exists.
- [ ] Each database credential is least-privileged and independently rotated.
- [ ] Production secrets are absent from Git, Helm values, images, and logs.
- [ ] Business APIs enforce permissions server-side.
- [ ] Service and user status changes are audited.
- [ ] Container images are scanned and ideally signed/attested.
- [ ] Dependencies and base images receive automated security updates.
- [ ] Backups are encrypted and restoration is tested.
- [ ] Network policies include explicit ingress and egress controls.
- [ ] Administrative actions require appropriate separation and review.

## 23. Operational runbooks

### 23.1 Verify local databases

For each service user, connect to its database and confirm `django_migrations`
exists. Then run:

```bash
uv run python manage.py migrate --check
uv run python manage.py check
```

Expected initial scale is approximately 18 auth tables and 9 tables in each
business database, but migration state—not a hard-coded table count—is the
authoritative health check.

### 23.2 Reset a local user's password

Find the Django username by local account email, then use the interactive command:

```bash
uv run python manage.py changepassword '<username>'
```

Ensure the MySQL variables are active and `USE_SQLITE_FOR_TESTS` is unset. Never
place the password in a command line, script, PR, or chat transcript.

### 23.3 User logs in but sees only generic pages

Authentication succeeded but effective business access is empty. Confirm
`UserRole` assignments, grant the required platform/network/AWS roles, then log
out and back in or refresh the session so a new JWT is issued.

### 23.4 Invalid credentials after moving from SQLite

Fresh MySQL migrations do not copy old SQLite users. Inspect both databases. If
the MySQL auth database is empty, create the administrator in MySQL. Do not assume
that changing a password in an old SQLite file affects MySQL.

### 23.5 Local 403 during login

Fetch `/api/auth/csrf` and inspect the response. If origin validation fails:

- Confirm the browser uses the configured frontend origin.
- Confirm `CSRF_TRUSTED_ORIGINS` includes that exact scheme/host/port.
- Stop older processes occupying port 8000.
- Restart using the coordinated launcher rather than a bare runserver command.

### 23.6 Partial local startup

Inspect `.local-run/logs/*.log` and listeners on ports 5173 and 8000-8002. Stop
only confirmed stale development PIDs, then run stop/start again. Do not kill
unrelated processes based solely on a process name.

### 23.7 JWKS or downstream authentication failure

- Verify `/api/auth/.well-known/jwks.json` is reachable from the business pod.
- Compare JWT `iss`, `aud`, and `kid` with service configuration.
- Confirm clocks are synchronized.
- Confirm ingress does not rewrite the issuer-visible path unexpectedly.
- During rotation, confirm the old signing public key remains published long
  enough for all old access tokens to expire.

## 24. Build order from empty repositories

Use this sequence for a clean reimplementation:

1. Create the five repositories and add grouped `.gitignore`, `AGENTS.md`, hooks,
   branch protections, `develop`, and CI placeholders.
2. Scaffold auth-service with Python 3.12, uv, Django, DRF, the custom user model,
   and MySQL before generating the first migration.
3. Implement local authentication, CSRF, cookies, JWT signing, refresh sessions,
   JWKS, account state, audit events, and tests.
4. Implement the Service/Permission/Role/UserRole model and idempotent seed data.
5. Add SAML dependencies, SP configuration, Entra identity model, first-login
   provisioning, session bridge, metadata/ACS/logout routes, and tests.
6. Scaffold network-service with independent MySQL settings, JWT/JWKS validation,
   permission enforcement, health endpoints, the Device model/API, and tests.
7. Scaffold aws-service in the same pattern with AwsConnection and strict account
   ID validation.
8. Scaffold the frontend with React, TypeScript, Vite, Tailwind, TanStack Router,
   TanStack Query, API/CSRF client, auth context, guarded routes, and basic pages.
9. Add the user/role administration UI and explicit no-access experience.
10. Add mock-auth mode and the UI showcase without bypassing production auth.
11. Add multi-stage Dockerfiles, non-root execution, health endpoints, and CI
    image builds.
12. Add the infrastructure repository, local `.env.example`, MySQL bootstrap,
    key generation, migrations, RBAC seeding, and lifecycle scripts.
13. Add the Helm chart with applications, development databases, Secrets,
    ConfigMaps, probes, network policies, and path ingress.
14. Validate the native full-stack flow and Minikube flow.
15. Configure the non-production Entra application and test SAML over HTTPS.
16. Add immutable image publishing from `main`.
17. Select production Docker hosts or EKS, external MySQL, secrets, TLS,
    observability, and deployment approvals.
18. Run security review, restore test, rollback drill, and production-readiness
    acceptance before first release.

## 25. Definition of done for the foundation

- Five repositories build independently from committed lockfiles.
- No direct browser route reaches a business service.
- Local password login succeeds through the gateway with CSRF protection.
- Entra SAML metadata and first-login provisioning are implemented and tested in
  an HTTPS non-production environment.
- Local and Entra accounts remain independent.
- A valid zero-role account reaches only profile/no-access functionality.
- Multiple roles combine permissions deterministically.
- Every business endpoint enforces a feature permission.
- Each service uses only its own database credential.
- Native local setup is repeatable from a documented `.env.example`.
- All health endpoints work through the public gateway.
- CI tests against MySQL, builds application assets, lints Helm, and builds every
  container.
- `develop` and `main` are protected and releases use immutable images.
- Production-specific gaps are explicitly tracked rather than represented by
  insecure development defaults.

## 26. Production-hardening backlog

The following are intentionally not complete in the initial skeleton and must be
planned before production:

1. HTTPS/TLS for shared development and production, including SAML validation.
2. Real Entra tenant metadata, SP certificate lifecycle, and key rotation.
3. Managed MySQL/RDS topology, backups, restore drills, pooling, and migrations.
4. Production secret management and automatic rotation.
5. Concrete Docker-host or EKS deployment automation and rollback.
6. EKS workload identity for real AWS operations.
7. Default-deny ingress and egress network policies.
8. Centralized logs, metrics, traces, alerts, and audit retention.
9. Login and administrative rate limiting and abuse monitoring.
10. Email invitations and password-reset delivery.
11. OpenAPI publication, client generation, and API compatibility policy.
12. End-to-end browser tests including real non-production SAML.
13. Dependency, image, IaC, and secret scanning with remediation policy.
14. High availability, autoscaling, disruption budgets, and capacity tests.
15. Disaster recovery objectives, incident response, and access-review runbooks.

This backlog is part of the architecture, not optional polish. Development
defaults must not be promoted unchanged into a production environment.

## 27. Concrete scaffolding recipe

The commands below are an implementation aid, not a substitute for reviewing the
architecture and security sections above. Run them inside new feature branches.

### 27.1 Create Django repositories

For auth-service:

```bash
uv init --python 3.12
uv add 'django>=5.2,<5.3' 'djangorestframework>=3.16,<3.17'
uv add 'mysqlclient>=2.2,<3' 'gunicorn>=23,<24' 'whitenoise>=6.9,<7'
uv add 'argon2-cffi>=25,<26' 'pyjwt[crypto]>=2.10,<3'
uv add 'djangosaml2>=1.12,<1.13'
uv run django-admin startproject config .
uv run python manage.py startapp accounts
```

For network-service:

```bash
uv init --python 3.12
uv add 'django>=5.2,<5.3' 'djangorestframework>=3.16,<3.17'
uv add 'mysqlclient>=2.2,<3' 'gunicorn>=23,<24' 'whitenoise>=6.9,<7'
uv add 'pyjwt[crypto]>=2.10,<3'
uv run django-admin startproject config .
uv run python manage.py startapp network
```

For aws-service, use the same dependencies as network-service and create the
`cloud` application:

```bash
uv run django-admin startproject config .
uv run python manage.py startapp cloud
```

Set this Python constraint in every backend `pyproject.toml`:

```toml
[project]
requires-python = ">=3.12,<3.13"

[tool.uv]
package = false
```

Set `.python-version` to `3.12`, run `uv lock`, and commit the lockfile. Install
MySQL native development headers before syncing on systems where mysqlclient has
no compatible wheel.

### 27.2 Wire Django URL prefixes

Auth `config/urls.py` should mount platform routes and add djangosaml2 routes
only when SAML is fully configured:

```python
from django.conf import settings
from django.contrib import admin
from django.urls import include, path

urlpatterns = [
    path("admin/", admin.site.urls),
    path("api/auth/", include("accounts.urls")),
]

if settings.SAML_ENABLED:
    urlpatterns.append(path("api/auth/saml/", include("djangosaml2.urls")))
```

Network:

```python
from django.urls import include, path

urlpatterns = [path("api/network/", include("network.urls"))]
```

AWS:

```python
from django.urls import include, path

urlpatterns = [path("api/aws/", include("cloud.urls"))]
```

Keeping the public prefixes inside the services means Vite and ingress can
forward requests without path rewriting.

### 27.3 Create the frontend repository

```bash
pnpm create vite . --template react-ts
pnpm add react react-dom @tanstack/react-router @tanstack/react-query
pnpm add tailwindcss @tailwindcss/vite lucide-react
pnpm add class-variance-authority clsx tailwind-merge
pnpm add -D vitest eslint typescript-eslint
pnpm add -D eslint-plugin-react-hooks eslint-plugin-react-refresh globals
```

Pin the package manager and Node engine:

```json
{
  "packageManager": "pnpm@10.17.1",
  "engines": { "node": ">=20.19 <21" }
}
```

Create `.nvmrc`, commit `pnpm-lock.yaml`, add Vite proxy targets, then implement
the API client before building pages so every route uses the same cookie, CSRF,
refresh, and error behavior.

### 27.4 Create the infrastructure repository

```text
platform-infrastructure/
├── .github/workflows/ci.yml
├── docs/
├── helm/platform/
│   ├── Chart.yaml
│   ├── values.yaml
│   └── templates/
│       ├── _helpers.tpl
│       ├── applications.yaml
│       ├── configmaps.yaml
│       ├── frontend.yaml
│       ├── ingress.yaml
│       ├── mysql.yaml
│       ├── network-policies.yaml
│       └── secrets.yaml
├── scripts/
│   ├── build-images.sh
│   ├── create-development-crypto.sh
│   ├── install-minikube.sh
│   ├── local-common.sh
│   ├── prepare-local.sh
│   ├── start-local.sh
│   ├── status-local.sh
│   └── stop-local.sh
└── .env.example
```

Make lifecycle scripts executable and validate them with `sh -n`. Ensure runtime
PID/log directories, real `.env` files, generated keys, metadata, certificates,
local Helm overrides, and kubeconfig files are ignored.

## 28. Configuration templates

### 28.1 Native orchestration `.env.example`

```dotenv
FRONTEND_SERVICE_DIR=../frontend-service
AUTH_SERVICE_DIR=../auth-service
NETWORK_SERVICE_DIR=../network-service
AWS_SERVICE_DIR=../aws-service

MYSQL_HOST=127.0.0.1
MYSQL_PORT=3306
MYSQL_ADMIN_USER=root
MYSQL_ADMIN_PASSWORD=

AUTH_MYSQL_DATABASE=mis_auth
AUTH_MYSQL_USER=mis_auth
AUTH_MYSQL_PASSWORD=replace-local-auth-password
NETWORK_MYSQL_DATABASE=mis_network
NETWORK_MYSQL_USER=mis_network
NETWORK_MYSQL_PASSWORD=replace-local-network-password
AWS_MYSQL_DATABASE=mis_aws
AWS_MYSQL_USER=mis_aws
AWS_MYSQL_PASSWORD=replace-local-aws-password

FRONTEND_ORIGIN=http://localhost:5173
AUTH_PORT=8000
NETWORK_PORT=8001
AWS_PORT=8002
```

### 28.2 Frontend `.env.example`

```dotenv
AUTH_PROXY_TARGET=http://127.0.0.1:8000
NETWORK_PROXY_TARGET=http://127.0.0.1:8001
AWS_PROXY_TARGET=http://127.0.0.1:8002
```

Do not prefix server-only Vite proxy targets with `VITE_`; values with that prefix
are exposed to browser code at build time.

### 28.3 Business-service `.env.example`

```dotenv
DJANGO_SECRET_KEY=replace-me
DJANGO_DEBUG=true
DJANGO_ALLOWED_HOSTS=localhost,127.0.0.1
MYSQL_HOST=127.0.0.1
MYSQL_PORT=3306
MYSQL_DATABASE=mis_network
MYSQL_USER=mis_network
MYSQL_PASSWORD=replace-me
JWT_ISSUER=http://localhost:5173/api/auth
JWT_AUDIENCE=platform-api
JWT_JWKS_URL=http://127.0.0.1:8000/api/auth/.well-known/jwks.json
```

Use the AWS database values in aws-service. Environment files are examples for
operators; Django does not automatically load them unless an explicit settings
library is added. The orchestration scripts export them to child processes.

### 28.4 Production configuration matrix

| Concern | Development | Production |
| --- | --- | --- |
| Public origin | localhost/platform.local HTTP | Approved HTTPS FQDN |
| Django debug | true | false |
| Cookie secure | false for local HTTP | true |
| Database | local or in-cluster MySQL | managed external MySQL |
| Secrets | ignored env/dev K8s Secret | approved secrets manager |
| JWT keys | generated development key | managed, rotated key material |
| SAML | disabled on plain HTTP | enabled with validated metadata and TLS |
| Image tag | `dev` | immutable SHA or digest |
| Replicas | one | multiple where state allows |
| Observability | local logs | centralized logs, metrics, traces, alerts |

## 29. Reverse-proxy contract

A non-Kubernetes gateway can implement the same contract with configuration
equivalent to:

```nginx
server {
    listen 443 ssl http2;
    server_name platform.example.com;

    location /api/auth/ {
        proxy_pass http://auth-service:8000;
        proxy_set_header Host $host;
        proxy_set_header X-Forwarded-Proto https;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    }

    location /api/network/ {
        proxy_pass http://network-service:8000;
        proxy_set_header Host $host;
        proxy_set_header X-Forwarded-Proto https;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    }

    location /api/aws/ {
        proxy_pass http://aws-service:8000;
        proxy_set_header Host $host;
        proxy_set_header X-Forwarded-Proto https;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    }

    location / {
        proxy_pass http://frontend-service:8080;
        proxy_set_header Host $host;
        proxy_set_header X-Forwarded-Proto https;
    }
}
```

Add certificates, modern TLS policy, timeouts, request-size limits, rate limiting,
security headers, health checks, and trusted proxy settings. Preserve the full
original path unless service URL configuration is changed deliberately.

In Django production settings, configure secure-proxy header handling only when
requests can arrive exclusively through trusted proxies. Do not trust arbitrary
client-supplied `X-Forwarded-Proto` headers.

## 30. Final acceptance gates

Before calling a similar build complete, collect evidence for every gate:

### Source and supply chain

- Every repository is clean, independently cloneable, and reproducible from its
  lockfile.
- Branch protection and required checks are enforced server-side.
- Images are built once, scanned, identified by digest, and promoted unchanged.
- No secret is present in Git history, build arguments, artifacts, or logs.

### Identity and access

- Local login, Entra SAML login, logout, refresh, expiry, suspension, and role
  changes have automated tests.
- A first-time Entra user has zero business access.
- A local and Entra identity with the same email remain separate.
- Each API action is denied without its exact permission.
- Bootstrap administration and emergency recovery are documented and audited.

### Runtime

- Liveness and readiness probes behave differently and correctly.
- Database unavailability prevents readiness without causing destructive restart
  loops.
- Graceful shutdown completes within deployment termination limits.
- At least one rollback and one database restoration have been demonstrated.
- Capacity, timeout, and dependency-failure behavior are understood.

### Deployment

- `develop` deploys only to the development environment.
- `main` produces production-eligible immutable images.
- Production deployment requires explicit approval and uses a defined target.
- Environment configuration is validated before rollout.
- Post-deployment smoke tests cover frontend, auth, JWKS, and both business APIs.

### Operations

- Dashboards and alerts identify authentication failures, service errors,
  database failures, and certificate/key expiry.
- Logs correlate a browser request across gateway and service boundaries without
  leaking credentials.
- On-call staff have incident, rollback, key-rotation, account-disable, and data
  restoration runbooks.
