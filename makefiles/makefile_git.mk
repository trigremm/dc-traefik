# makefile_git.mk

.PHONY: git-pull git-commit-message

git-pull:
	git pull

git-commit-message:
	@echo "Current Git commit: $(shell git rev-parse --short HEAD 2>/dev/null || echo 'n/a')"
	@echo "Git commit message: $(shell git log -1 --pretty=%s 2>/dev/null || echo 'n/a')"
