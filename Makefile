SHELL := /bin/bash
SCRIPTS := apps/cli/scripts

.PHONY: help install uninstall up down update backup restore add-app

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*## ' $(MAKEFILE_LIST) | sed -E 's/:.*## /\t/' | sort

install: ## Install app(s), or pick interactively if none given: make install ARGS="offline-maps"
	./$(SCRIPTS)/install.sh $(ARGS)

uninstall: ## Uninstall app(s), or everything if none given: make uninstall ARGS="offline-maps"
	./$(SCRIPTS)/uninstall.sh $(ARGS)

up: ## Start app(s): make up ARGS="offline-maps"
	./$(SCRIPTS)/up.sh $(ARGS)

down: ## Stop app(s): make down ARGS="offline-maps"
	./$(SCRIPTS)/down.sh $(ARGS)

update: ## git pull + update installed app(s): make update ARGS="offline-maps"
	./$(SCRIPTS)/update.sh $(ARGS)

backup: ## Back up app data + .env: make backup ARGS="offline-maps"
	./$(SCRIPTS)/backup.sh $(ARGS)

restore: ## Restore an app from a backup: make restore ARGS="offline-maps"
	./$(SCRIPTS)/restore.sh $(ARGS)

add-app: ## Scaffold a new app: make add-app ARGS="my-app 3020"
	./$(SCRIPTS)/add-app.sh $(ARGS)
