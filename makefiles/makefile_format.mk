# makefile_format.mk
# Formatting via prettier (host-installed npx, like docline)

PRETTIER_GLOB := "**/*.{yml,yaml,md,json}"

.PHONY: f format format-check format-update

f: format

format:
	npx --yes prettier@3 --write --ignore-path .gitignore $(PRETTIER_GLOB)

format-check:
	npx --yes prettier@3 --check --ignore-path .gitignore $(PRETTIER_GLOB)

format-update:
	npm install -g prettier
