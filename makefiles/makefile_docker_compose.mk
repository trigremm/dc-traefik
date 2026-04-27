# makefile_docker_compose.mk
# Docker Compose lifecycle for Traefik

DC_BIN ?= $(shell command -v docker >/dev/null 2>&1 && docker compose version >/dev/null 2>&1 && echo "docker compose" || echo "docker-compose")

.DEFAULT_GOAL := ps

# ===========================================================================
# Shortcuts
# ===========================================================================
.PHONY: d r l rl

d: deploy
r: recreate
l: logs
rl: r l

# ===========================================================================
# Deploy
# ===========================================================================
.PHONY: deploy recreate

deploy: git-pull recreate docker-image-prune docker-builder-prune

recreate: docker-network-create traefik-bootstrap down up ps

# ===========================================================================
# Lifecycle
# ===========================================================================
.PHONY: ps build up stop down restart config
.PHONY: build-% up-% stop-%

ps: git-commit-message
	$(DC_BIN) ps

build:
	$(DC_BIN) build

up: traefik-bootstrap
	$(DC_BIN) up -d

stop:
	$(DC_BIN) stop

down:
	$(DC_BIN) down --remove-orphans

restart: stop up

config:
	$(DC_BIN) config

# per-service patterns
build-%:
	$(DC_BIN) build $*

up-%:
	$(DC_BIN) up -d $*

stop-%:
	$(DC_BIN) stop $*

# ===========================================================================
# Logs
# ===========================================================================
.PHONY: logs last-logs logs-%

logs:
	$(DC_BIN) logs -f -n 100

last-logs:
	$(DC_BIN) logs -n 100

logs-%:
	$(DC_BIN) logs -f -n 100 $*

# ===========================================================================
# Shell
# ===========================================================================
.PHONY: shell shell-%

shell:
	$(DC_BIN) exec traefik sh

shell-%:
	$(DC_BIN) exec $* sh
