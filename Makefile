# Home Security Stack - Makefile
# Common operations for managing the security stack

.PHONY: help setup start stop restart logs status update health test-pre test-post gpu backup

COMPOSE = docker compose
SERVICES = mqtt frigate compreface-postgres compreface-admin compreface-api compreface double-take

help:
	@echo "Home Security Stack Operations"
	@echo ""
	@echo "Usage: make <target>"
	@echo ""
	@echo "Setup & Deployment:"
	@echo "  setup        - Initial setup (run once)"
	@echo "  start        - Start all services"
	@echo "  stop         - Stop all services"
	@echo "  restart      - Restart all services"
	@echo "  update       - Pull latest images and restart"
	@echo ""
	@echo "Monitoring & Logs:"
	@echo "  status       - Show service status and endpoints"
	@echo "  logs         - Tail logs for all services"
	@echo "  health       - Run health check"
	@echo "  gpu          - Monitor GPU usage"
	@echo ""
	@echo "Service-specific:"
	@echo "  logs-SERVICE    - Tail logs for specific service"
	@echo "  restart-SERVICE - Restart specific service"
	@echo "  shell-SERVICE   - Get shell in container"
	@echo ""
	@echo "Examples:"
	@echo "  make logs-frigate"
	@echo "  make restart-frigate"
	@echo "  make shell-mqtt"
	@echo ""
	@echo "Testing:"
	@echo "  test-pre     - Run pre-deployment tests"
	@echo "  test-post    - Run post-deployment tests"
	@echo "  test-camera  - Test camera connectivity (requires IP)"
	@echo ""
	@echo "Maintenance:"
	@echo "  backup       - Backup configurations"
	@echo "  clean        - Remove stopped containers and volumes"
	@echo ""

setup:
	@./scripts/setup.sh

start:
	$(COMPOSE) up -d $(SERVICES)

stop:
	$(COMPOSE) down

restart:
	$(COMPOSE) restart $(SERVICES)

logs:
	$(COMPOSE) logs -f --tail=100

logs-%:
	$(COMPOSE) logs -f --tail=100 $*

restart-%:
	$(COMPOSE) restart $*

status:
	@echo "======================================"
	@echo "Service Status"
	@echo "======================================"
	@$(COMPOSE) ps
	@echo ""
	@echo "======================================"
	@echo "Endpoints"
	@echo "======================================"
	@echo "Frigate:     http://localhost:5000"
	@echo "CompreFace:  http://localhost:8000"
	@echo "Double-Take: http://localhost:3000"
	@echo "MQTT:        mqtt://localhost:1883"
	@echo ""

update:
	@echo "Pulling latest images..."
	$(COMPOSE) pull
	@echo "Restarting services..."
	$(COMPOSE) up -d $(SERVICES)
	@echo "Update complete!"

health:
	@./scripts/health-check.sh

gpu:
	@watch -n 1 nvidia-smi

shell-%:
	@docker exec -it $* /bin/bash 2>/dev/null || docker exec -it $* /bin/sh

test-pre:
	@./scripts/test-pre-deploy.sh

test-post:
	@./scripts/test-post-deploy.sh

test-camera:
	@echo "Usage: make test-camera IP=<camera-ip> PASS=<password>"
	@if [ -z "$(IP)" ] || [ -z "$(PASS)" ]; then \
		echo "Error: IP and PASS variables required"; \
		echo "Example: make test-camera IP=192.168.1.100 PASS=mypassword"; \
		exit 1; \
	fi
	@./scripts/test-camera.sh $(IP) admin $(PASS)

backup:
	@if [ ! -f scripts/backup.sh ]; then \
		echo "Backup script not yet created"; \
		exit 1; \
	fi
	@./scripts/backup.sh

clean:
	$(COMPOSE) down -v
	@echo "Cleaned up containers and volumes"

# Development helpers
dev-install:
	uv sync --all-extras

dev-format:
	uv run ruff format .

dev-lint:
	uv run ruff check .

dev-test:
	uv run pytest
