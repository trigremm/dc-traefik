# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with this stack.

## Purpose

Hostwide Traefik v3.5 reverse proxy for the trigremm host. Terminates TLS via Let's Encrypt, owns ports `:80` and `:443`, and routes traffic to any container attached to the `traefik-public` Docker network with `traefik.enable=true` labels.

This stack is the **single ingress** for all projects on the host. Other deploy stacks (tidaar, alphaedu, lbsb, individual `dc-*` services) attach to `traefik-public` as `external: true` and add their own routers via labels.

Traefik does **not** mount `/var/run/docker.sock`. It reads the Docker API through a sidecar **socket-proxy** (`tecnativa/docker-socket-proxy`) on an internal-only network, with only `containers`/`networks`/`events` whitelisted. Both images are pinned by digest and carry CPU/memory limits + log rotation.

## Layout

```
.
├── docker-compose.yaml               # traefik + socket-proxy (read-only docker API)
├── docker-compose.override.yaml.sample  # local dev: no LE, insecure dashboard
├── Makefile                          # only `include makefiles/*.mk`
├── makefiles/
│   ├── makefile_docker.mk            # network create + prune (CONFIRM=1 on danger)
│   ├── makefile_docker_compose.mk    # lifecycle, aliases, pattern targets
│   ├── makefile_git.mk               # git-pull, git-commit-message
│   ├── makefile_local.mk             # local-up/down/status/clean
│   └── makefile_traefik.mk           # bootstrap, htpasswd, certs, test
├── traefik/
│   ├── traefik.yml                   # static config — change requires `make reload`
│   └── dynamic/                      # hot-reloaded (watch=true)
│       ├── middlewares.yml           # shared middleware
│       └── tls.yml                   # TLS handshake policy (min TLS 1.2 + ciphers)
└── acme/
    ├── acme.json                     # LE prod certs, chmod 600, gitignored
    ├── acme-staging.json             # LE staging certs, chmod 600, gitignored
    └── dashboard.htpasswd            # dashboard basic-auth, gitignored
```

> **Docker 28+ caveat:** Traefik's Docker client pins API 1.24; Docker 28 raised the daemon minimum to 1.44, so the provider fails with `API returned a 400` there (true for the raw socket too, not just the proxy). Keep the host on Docker ≤ 27 until Traefik bumps its vendored API version.

## Build & Development Commands

```bash
make            # default: ps (with current commit info)
make d          # deploy (git-pull + recreate + prune)
make r          # recreate (network + bootstrap + down + up + ps)
make up         # bootstrap acme + start
make stop / make down / make restart
make l          # follow logs
make reload     # restart traefik (re-read static traefik.yml)

# Per-service patterns
make logs-traefik
make shell-traefik

# Traefik helpers
make htpasswd USER=admin PASS=secret   # bcrypt via httpd:alpine container
make certs                             # list issued LE domains via jq container
make dashboard                         # show dashboard URL
make test                              # smoke tests
```

## Key conventions

- **No host dependencies.** All helpers (htpasswd, jq for cert listing) run via one-shot Docker containers. Do not introduce host-installed tools.
- **`acme.json` is the only file worth backing up.** Losing it forces re-issuance — mind LE rate limits (50 certs/domain/week).
- **Static vs dynamic config:**
  - `traefik/traefik.yml` is static — entryPoints, providers, ACME resolver. Edits require `make reload`.
  - `traefik/dynamic/*.yml` is hot-reloaded (`watch: true`). Add new middleware here, no restart needed.
- **Dashboard is not exposed on a host port.** Access via `https://${TRAEFIK_DASHBOARD_HOST}/dashboard/` with basic auth from `acme/dashboard.htpasswd`.
- **`exposedByDefault: false`** in static config — every published container must explicitly opt in with `traefik.enable=true`.

## Adding a new project

In the project's compose file:

```yaml
services:
  myapp:
    networks:
      - traefik-public
      - myapp-internal
    labels:
      - 'traefik.enable=true'
      - 'traefik.docker.network=traefik-public'
      - 'traefik.http.routers.myapp.rule=Host(`api.example.com`)'
      - 'traefik.http.routers.myapp.entrypoints=websecure'
      - 'traefik.http.routers.myapp.tls.certresolver=letsencrypt'
      - 'traefik.http.routers.myapp.middlewares=secure-headers@file,rate-limit-default@file'
      - 'traefik.http.services.myapp.loadbalancer.server.port=8000'

networks:
  traefik-public:
    external: true
  myapp-internal:
    name: myapp-internal
```

`@file` suffix references middleware defined in `traefik/dynamic/middlewares.yml`.

## Shared middleware

| Name                 | Purpose                                      |
| -------------------- | -------------------------------------------- |
| `secure-headers`     | HSTS, X-Frame-Options, referrer policy, etc. |
| `rate-limit-default` | 100 req/s average, 200 burst                 |
| `rate-limit-strict`  | 20 req/s average, 40 burst                   |
| `spa-csp`            | CSP for React/Vue SPAs                       |
| `api-csp`            | CSP for JSON API (`default-src 'none'`)      |
| `compress`           | gzip/brotli response compression             |
| `admin-auth`         | Basic auth, reads `acme/dashboard.htpasswd`  |

## Files Claude should never touch

- `acme/acme.json` — Traefik manages it, manual edits corrupt cert state
- `acme/dashboard.htpasswd` — managed via `make htpasswd`
- `.env` — local config, gitignored

## Migration notes (for future k3s)

When/if this host moves to k3s:

- Traefik is the default Ingress Controller in k3s — same engine, different config surface.
- `traefik.http.routers.*` labels become `IngressRoute` CRD manifests.
- ACME moves from built-in resolver to `cert-manager` (k8s standard).
- `traefik/dynamic/middlewares.yml` entries become `Middleware` CRDs.

The mental model carries over 1:1 — only the wrapper YAML changes.
