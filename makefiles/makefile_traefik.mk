# makefile_traefik.mk
# Traefik-specific helpers

.PHONY: traefik-bootstrap htpasswd certs reload dashboard test

# Idempotent: ensure acme stores + htpasswd exist with correct permissions
traefik-bootstrap:
	@touch acme/acme.json acme/acme-staging.json
	@chmod 600 acme/acme.json acme/acme-staging.json
	@touch acme/dashboard.htpasswd

# Set basic-auth credentials in acme/dashboard.htpasswd (idempotent: replaces
# any existing line for the same user instead of appending a duplicate).
# Usage: make htpasswd USER=admin PASS=changeme
htpasswd:
	@if [ -z "$(USER)" ] || [ -z "$(PASS)" ]; then \
		echo "Usage: make htpasswd USER=<user> PASS=<password>"; exit 1; \
	fi
	@line=$$(docker run --rm httpd:2.4-alpine htpasswd -nbB "$(USER)" "$(PASS)"); \
	touch acme/dashboard.htpasswd; \
	grep -v "^$(USER):" acme/dashboard.htpasswd > acme/dashboard.htpasswd.tmp 2>/dev/null || true; \
	printf '%s\n' "$$line" >> acme/dashboard.htpasswd.tmp; \
	mv acme/dashboard.htpasswd.tmp acme/dashboard.htpasswd; \
	echo "Set password for user $(USER) in acme/dashboard.htpasswd"

# List issued ACME certificates
certs:
	@if [ -s acme/acme.json ]; then \
		docker run --rm -v $(PWD)/acme:/acme:ro ghcr.io/jqlang/jq:latest \
			'.letsencrypt.Certificates[]?.domain.main // "no certs yet"' /acme/acme.json; \
	else \
		echo "acme.json is empty - no certificates issued yet"; \
	fi

# file provider has watch=true; restart only needed for static traefik.yml changes
reload:
	$(DC_BIN) restart traefik

dashboard:
	@echo "Dashboard URL: https://$${TRAEFIK_DASHBOARD_HOST}/dashboard/"
	@echo "Add credentials with: make htpasswd USER=<user> PASS=<password>"

test:
	@echo "Bring traefik up..."
	$(MAKE) up
	@echo "Wait for healthcheck..."
	@for i in 1 2 3 4 5 6 7 8 9 10; do \
		$(DC_BIN) ps traefik --format json 2>/dev/null | grep -q '"Health":"healthy"' && break || sleep 2; \
	done
	@echo "Test container running..."
	@$(DC_BIN) ps traefik --format json 2>/dev/null | grep -q '"State":"running"' && echo "PASS: running" || (echo "FAIL: not running" && exit 1)
	@echo "Test traefik-public network..."
	@docker network inspect $(TRAEFIK_NETWORK) >/dev/null && echo "PASS: network" || (echo "FAIL: network" && exit 1)
	@echo "Test acme.json permissions..."
	@[ "$$(stat -c '%a' acme/acme.json 2>/dev/null || stat -f '%A' acme/acme.json)" = "600" ] && echo "PASS: acme.json 600" || (echo "FAIL: acme.json wrong perms" && exit 1)
	@echo ""
	@echo "All tests passed!"
