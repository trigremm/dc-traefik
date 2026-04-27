# makefile_docker.mk
# Docker host-level commands (not docker compose)

TRAEFIK_NETWORK := traefik-public

.PHONY: docker-network-create docker-image-prune docker-builder-prune
.PHONY: docker-stop-all docker-system-prune docker-container-prune

docker-network-create:
	docker network inspect $(TRAEFIK_NETWORK) >/dev/null 2>&1 || docker network create $(TRAEFIK_NETWORK)

docker-image-prune:
	docker image prune -f || true

docker-builder-prune:
	docker builder prune --filter "until=36h" -f || true

# danger zone
docker-stop-all:
	@if [ "$(CONFIRM)" != "1" ]; then echo "Add CONFIRM=1 to proceed"; exit 1; fi
	docker stop $$(docker ps -q)

docker-system-prune:
	@if [ "$(CONFIRM)" != "1" ]; then echo "Add CONFIRM=1 to proceed"; exit 1; fi
	docker system prune -f -a || true

docker-container-prune:
	@if [ "$(CONFIRM)" != "1" ]; then echo "Add CONFIRM=1 to proceed"; exit 1; fi
	docker container prune -f || true
