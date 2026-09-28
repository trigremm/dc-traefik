# dc-traefik

Hostwide Traefik v3.5 reverse proxy. Listens on `:80` and `:443`, terminates TLS via Let's Encrypt, and routes traffic to any container attached to the `traefik-public` network with `traefik.enable=true` labels.

Traefik reads the Docker API through a read-only [socket-proxy](https://github.com/Tecnativa/docker-socket-proxy) (only `containers`/`networks`/`events` exposed) — it never touches `/var/run/docker.sock` directly, so a compromised Traefik can't take over the host. Images are pinned by digest, both services carry CPU/memory limits and log rotation, and TLS handshake policy is pinned to TLS 1.2+ with a modern cipher set.

> **Docker 28+ caveat:** Traefik's Docker client pins API version 1.24, which Docker 28 dropped (daemon minimum is now 1.44) — the provider fails with `API returned a 400` on such hosts. This affects the raw socket too, not just the proxy. Run the host on Docker ≤ 27 until Traefik bumps its vendored API version.

## Quick start

```bash
cp .env.sample .env
vim .env                                      # set ACME email + dashboard host
make docker-network-create                    # create traefik-public network
make htpasswd USER=admin PASS=<your-password> # add dashboard credential
make up                                       # bootstrap acme + start
make test                                     # smoke checks
```

## Commands

### Lifecycle

```
make            # default: ps
make d          # deploy (git-pull + recreate + prune)
make r          # recreate (network + bootstrap + down + up + ps)
make up         # bootstrap acme + start
make stop       # stop
make down       # stop and remove
make restart    # stop + up
make ps         # status (with current commit info)
make config     # render merged compose config
make l          # follow logs
make last-logs  # last 100 lines, no follow
make reload     # restart traefik (re-read static config)
```

### Per-service patterns

```
make build-traefik
make up-traefik
make stop-traefik
make logs-traefik
make shell-traefik
```

### Traefik helpers

```
make htpasswd USER=admin PASS=secret   # add dashboard user (bcrypt via httpd image)
make certs                             # list issued Let's Encrypt domains
make dashboard                         # show dashboard URL
make test                              # smoke tests
```

### Docker host (prune / cleanup)

```
make docker-network-create             # create traefik-public network
make docker-image-prune                # remove dangling images
make docker-builder-prune              # remove builder cache >36h
make docker-system-prune CONFIRM=1     # danger: nuke everything unused
make docker-stop-all CONFIRM=1         # danger: stop ALL running containers
```

### Git

```
make git-pull
make git-commit-message                # show current commit + message
```

### Format

```
make f                                 # alias for `make format`
make format                            # prettier --write on yml/yaml/md/json (Docker, no host deps)
make format-check                      # prettier --check (CI-friendly, exits non-zero on diff)
```

### Local development

Skips Let's Encrypt and exposes the dashboard on `http://localhost:8080/dashboard/` (no auth, no TLS) via a gitignored `docker-compose.override.yaml`.

```
make local-up        # copy override sample if missing + start
make local-status    # show override + container state
make local-down      # stop and remove
make local-clean     # remove override file (next local-up regenerates from sample)
```

Route test apps to `*.localhost` — browsers resolve those to 127.0.0.1 without `/etc/hosts` edits:

```yaml
labels:
  - traefik.enable=true
  - traefik.http.routers.myapp.rule=Host(`myapp.localhost`)
  - traefik.http.routers.myapp.entrypoints=web
```

## Connecting a project

In any other compose stack:

```yaml
services:
  myapp:
    image: ghcr.io/org/myapp:tag
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

## Shared middleware (file provider)

Defined in `traefik/dynamic/middlewares.yml`, referenced from any project as `<name>@file`:

| Name                 | Purpose                                      |
| -------------------- | -------------------------------------------- |
| `secure-headers`     | HSTS, X-Frame-Options, referrer policy, etc. |
| `rate-limit-default` | 100 req/s average, 200 burst                 |
| `rate-limit-strict`  | 20 req/s average, 40 burst                   |
| `spa-csp`            | CSP suitable for React/Vue SPAs              |
| `api-csp`            | CSP for JSON API (`default-src 'none'`)      |
| `compress`           | gzip/brotli response compression             |
| `admin-auth`         | Basic auth, reads `acme/dashboard.htpasswd`  |

To change middleware, edit the YAML — `watch: true` is enabled, no restart needed.

`secure-headers@file` and `compress@file` are applied to **every** websecure router by default (set on the entrypoint in `traefik.yml`), so a service that forgets its label still gets hardened headers and compression. Rate limits stay opt-in per-router. TLS handshake defaults (min TLS 1.2, modern ciphers) live in `traefik/dynamic/tls.yml`.

### Certificate resolvers

| Resolver              | Use                                                             |
| --------------------- | --------------------------------------------------------------- |
| `letsencrypt`         | production HTTP-01 (default)                                    |
| `letsencrypt-staging` | LE staging — debug issuance without burning the prod rate limit |
| `letsencrypt-dns`     | commented template for wildcard certs (DNS-01, needs provider)  |

## Layout

```
.
├── docker-compose.yaml               # traefik + read-only docker socket-proxy
├── docker-compose.override.yaml.sample  # local dev (no LE, insecure dashboard)
├── Makefile                          # SHELL/export + explicit `include makefiles/…` lines
├── makefiles/
│   ├── makefile_docker.mk            # network create + prune (with CONFIRM=1)
│   ├── makefile_docker_compose.mk    # lifecycle, aliases, pattern targets
│   ├── makefile_format.mk            # prettier format / format-check
│   ├── makefile_git.mk               # git-pull, git-commit-message
│   ├── makefile_local.mk             # local-up/down/status/clean
│   └── makefile_traefik.mk           # bootstrap, htpasswd, certs, test
├── .env.sample
├── traefik/
│   ├── traefik.yml                   # static config (entryPoints, providers, ACME)
│   └── dynamic/
│       ├── middlewares.yml           # shared middleware (hot-reloaded)
│       └── tls.yml                   # TLS handshake policy (hot-reloaded)
└── acme/
    ├── acme.json                     # Let's Encrypt certs (chmod 600, gitignored)
    ├── acme-staging.json             # LE staging certs (chmod 600, gitignored)
    └── dashboard.htpasswd            # dashboard basic-auth users (gitignored)
```

## Backup

The only stateful files worth backing up:

- `acme/acme.json` — losing it forces re-issuance of all certs (mind LE rate limits)
- `acme/dashboard.htpasswd` — dashboard credentials
- `.env` — configuration

## Notes

- `acme.json` must be `chmod 600`, the bootstrap target enforces this.
- Dashboard is **not** exposed on a host port. Access via `https://${TRAEFIK_DASHBOARD_HOST}/dashboard/` with basic auth.
- For wildcard certs (e.g. `*.example.com`), uncomment the `letsencrypt-dns` resolver template in `traefik.yml` (DNS-01), add provider credentials via env (Cloudflare, Route53, etc.), and point routers at `certresolver=letsencrypt-dns`.
- While debugging issuance, point a router at `certresolver=letsencrypt-staging` to avoid the production LE rate limit (50 certs/domain/week); switch back once it works.
