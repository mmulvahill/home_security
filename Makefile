# Home Security Stack - Makefile

.PHONY: help deploy setup start stop restart status logs health gpu update backup clean \
        test-pre test-post test-camera

COMPOSE := docker compose
SERVICES := mqtt frigate

help:
	@echo "Home Security Stack"
	@echo ""
	@echo "Lifecycle:"
	@echo "  deploy       Idempotent deploy (setup + start + verify)"
	@echo "  start        Start all services"
	@echo "  stop         Stop all services"
	@echo "  restart      Restart all services"
	@echo "  update       Pull latest images and redeploy"
	@echo ""
	@echo "Monitoring:"
	@echo "  status       Show service status and endpoints"
	@echo "  logs         Tail all service logs"
	@echo "  logs-NAME    Tail logs for one service (e.g. make logs-frigate)"
	@echo "  health       Run health check"
	@echo "  gpu          Watch GPU utilization"
	@echo ""
	@echo "Testing:"
	@echo "  test-pre     Pre-deployment validation"
	@echo "  test-post    Post-deployment validation"
	@echo "  test-camera  Test camera (make test-camera IP=x PASS=y)"
	@echo ""
	@echo "Maintenance:"
	@echo "  backup       Backup configurations to NFS"
	@echo "  clean        Remove stopped containers and volumes"
	@echo ""
	@echo "Service shortcuts:"
	@echo "  restart-NAME  Restart one service (e.g. make restart-frigate)"
	@echo "  shell-NAME    Shell into container (e.g. make shell-mqtt)"

# --- Lifecycle ---

deploy:
	@./scripts/setup.sh

setup: deploy

start:
	$(COMPOSE) up -d $(SERVICES)

stop:
	$(COMPOSE) down

restart:
	$(COMPOSE) restart $(SERVICES)

update:
	@echo "Pulling latest images..."
	$(COMPOSE) pull
	$(COMPOSE) up -d $(SERVICES)
	@echo "Update complete."

# --- Monitoring ---

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
	@echo "MQTT:        mqtt://localhost:1883"

logs:
	$(COMPOSE) logs -f --tail=100

logs-%:
	$(COMPOSE) logs -f --tail=100 $*

health:
	@./scripts/health-check.sh

gpu:
	@watch -n 1 nvidia-smi

# --- Service shortcuts ---

restart-%:
	$(COMPOSE) restart $*

shell-%:
	@docker exec -it $* /bin/bash 2>/dev/null || docker exec -it $* /bin/sh

# --- Testing ---

test-pre:
	@./scripts/test-pre-deploy.sh

test-post:
	@./scripts/test-post-deploy.sh

test-camera:
ifndef IP
	$(error Usage: make test-camera IP=<camera-ip> PASS=<password>)
endif
ifndef PASS
	$(error Usage: make test-camera IP=<camera-ip> PASS=<password>)
endif
	@./scripts/test-camera.sh $(IP) admin $(PASS)

# --- Maintenance ---

backup:
	@./scripts/backup.sh

clean:
	$(COMPOSE) down -v
	@echo "Cleaned up containers and volumes."

# --- Development ---

dev-install:
	uv sync --all-extras

dev-format:
	uv run ruff format .

dev-lint:
	uv run ruff check .

dev-test:
	uv run pytest
