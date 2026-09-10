SHELL := /bin/bash
SCRIPTS := apps/cli/scripts

.PHONY: help bootstrap install uninstall update backup restore add-app hotspot-up hotspot-down

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*## ' $(MAKEFILE_LIST) | sed -E 's/:.*## /\t/' | sort

bootstrap: ## One-time host setup: installs podman, podman-compose, make, git, etc.
	./$(SCRIPTS)/bootstrap.sh

install: ## Install app(s), or pick interactively if none given: make install ARGS="offline-maps"
	./$(SCRIPTS)/install.sh $(ARGS)

uninstall: ## Uninstall app(s), or everything if none given: make uninstall ARGS="offline-maps"
	./$(SCRIPTS)/uninstall.sh $(ARGS)

update: ## git pull + update installed app(s): make update ARGS="offline-maps"
	./$(SCRIPTS)/update.sh $(ARGS)

backup: ## Back up app data + .env: make backup ARGS="offline-maps"
	./$(SCRIPTS)/backup.sh $(ARGS)

restore: ## Restore an app from a backup: make restore ARGS="offline-maps"
	./$(SCRIPTS)/restore.sh $(ARGS)

add-app: ## Scaffold a new app (prompts for app id + port): make add-app
	./$(SCRIPTS)/add-app.sh

hotspot-up: ## Turn this device's WiFi into a local access point for clients to connect to
	./$(SCRIPTS)/hotspot-up.sh

hotspot-down: ## Stop the WiFi access point started by hotspot-up (ARGS="--remove" to forget it)
	./$(SCRIPTS)/hotspot-down.sh $(ARGS)

start:
	./apps/dashboard/up.sh
