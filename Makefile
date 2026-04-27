SHELL := bash
export

include makefiles/makefile_docker.mk
include makefiles/makefile_docker_compose.mk
include makefiles/makefile_format.mk
include makefiles/makefile_git.mk
include makefiles/makefile_traefik.mk
