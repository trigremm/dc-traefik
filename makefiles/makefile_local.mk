# makefile_local.mk
# Local development helpers (no Let's Encrypt, no host port conflicts on dashboard)

OVERRIDE_FILE := docker-compose.override.yaml
OVERRIDE_SAMPLE := docker-compose.override.yaml.sample

.PHONY: local-init local-up local-down local-status local-clean

# Copy override sample if missing (idempotent), then bring stack up
local-up: docker-network-create local-init traefik-bootstrap
	$(DC_BIN) up -d
	@echo ""
	@echo "Traefik dashboard: http://localhost:8080/dashboard/"
	@echo "Route apps to *.localhost (e.g. http://myapp.localhost)"

local-init:
	@if [ ! -f $(OVERRIDE_FILE) ]; then \
		cp $(OVERRIDE_SAMPLE) $(OVERRIDE_FILE); \
		echo "Created $(OVERRIDE_FILE) from sample"; \
	else \
		echo "$(OVERRIDE_FILE) already exists, leaving as is"; \
	fi
	@if [ ! -f .env ]; then \
		cp .env.sample .env; \
		echo "Created .env from sample (placeholder values are fine for local)"; \
	fi

local-status:
	@echo "Override active: $$([ -f $(OVERRIDE_FILE) ] && echo yes || echo no)"
	@$(DC_BIN) ps

local-down:
	$(DC_BIN) down --remove-orphans

# Wipe local override + state to start clean (does NOT touch acme.json on remote)
local-clean: local-down
	rm -f $(OVERRIDE_FILE)
	@echo "Removed $(OVERRIDE_FILE). Run 'make local-up' to start fresh."
