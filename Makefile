CLI := node apps/cli/bin/catasophie.js

.PHONY: setup install uninstall up down update backup restore add-app

setup: ## Optional: install the CLI's own deps (none currently - it's a thin dispatcher over apps/cli/scripts/*.sh)
	npm install --prefix apps/cli

install: ## Interactively pick + install app(s). ARGS="<app-id>..." to skip the wizard
	$(CLI) install $(ARGS)

uninstall: ## Uninstall app(s), or everything if ARGS is empty
	$(CLI) uninstall $(ARGS)

up: ## Start app(s): make up ARGS="offline-maps"
	$(CLI) up $(ARGS)

down: ## Stop app(s): make down ARGS="offline-maps"
	$(CLI) down $(ARGS)

update: ## git pull + update installed app(s) (or ARGS), with backup/rollback
	$(CLI) update $(ARGS)

backup: ## Back up installed app(s), or ARGS
	$(CLI) backup $(ARGS)

restore: ## Restore an app from backup: make restore ARGS="offline-maps latest"
	$(CLI) restore $(ARGS)

add-app: ## Scaffold a new app: make add-app ARGS="my-tool 8000"
	$(CLI) add-app $(ARGS)
