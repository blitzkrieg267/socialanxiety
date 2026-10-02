# Convenience wrapper around docker compose. Run `make help` for the list.
.DEFAULT_GOAL := help

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN{FS=":.*?## "}{printf "  \033[36m%-10s\033[0m %s\n",$$1,$$2}'

up: ## Start the whole stack in the background
	docker compose up -d

down: ## Stop the stack (keeps data volumes)
	docker compose down

restart: ## Recreate the stack (use after changing .env)
	docker compose down && docker compose up -d

pull: ## Pull the latest images
	docker compose pull

update: ## Pull latest code + images and recreate (what the CD pipeline runs)
	git fetch --prune origin && git reset --hard origin/main && docker compose pull && docker compose up -d --remove-orphans && docker image prune -f

logs: ## Tail the Postiz app logs
	docker compose logs -f postiz

ps: ## Show service status
	docker compose ps

.PHONY: help up down restart pull update logs ps
