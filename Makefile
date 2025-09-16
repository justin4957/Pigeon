# Pigeon Development Makefile
# Provides convenient shortcuts for common development tasks

.PHONY: help dev start stop restart status logs clean test ci format check deps docs setup

# Default target
help: ## Show this help message
	@echo "Pigeon Development Commands"
	@echo "=========================="
	@echo ""
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-15s\033[0m %s\n", $$1, $$2}'
	@echo ""
	@echo "Environment Management:"
	@echo "  make dev         # Start development environment"
	@echo "  make stop        # Stop development environment"
	@echo "  make status      # Check environment status"
	@echo ""
	@echo "Testing & Quality:"
	@echo "  make test        # Run local tests"
	@echo "  make ci          # Run CI/CD pipeline locally"
	@echo "  make check       # Quick code quality check"
	@echo ""

# Development Environment
dev: ## Start the development environment
	@./scripts/dev.sh start

start: dev ## Alias for dev

stop: ## Stop the development environment
	@./scripts/dev.sh stop

restart: ## Restart the development environment
	@./scripts/dev.sh restart

status: ## Show environment status
	@./scripts/dev.sh status

logs: ## Show container logs
	@./scripts/dev.sh logs

clean: ## Clean up containers and images
	@./scripts/dev.sh clean

# Extended environment
extended: ## Start extended environment (CPU/Memory workers)
	@./scripts/dev.sh start --extended

# Testing & Quality
test: ## Run local Elixir tests
	@mix test

ci: ## Run complete CI/CD pipeline locally
	@./scripts/pod-test.sh

ci-quick: ## Run CI pipeline without tests
	@./scripts/pod-test.sh --skip-tests

ci-debug: ## Run CI pipeline in debug mode
	@./scripts/pod-test.sh --debug --no-cleanup

# Code Quality
format: ## Format code
	@mix format

format-check: ## Check code formatting
	@mix format --check-formatted

check: format-check ## Quick code quality check
	@echo "✅ Code formatting check passed"
	@if command -v mix credo >/dev/null 2>&1; then \
		echo "Running static analysis..."; \
		mix credo --strict; \
		echo "✅ Static analysis passed"; \
	else \
		echo "ℹ️ Credo not available, skipping static analysis"; \
	fi
	@echo "Running compilation check..."
	@mix compile --warnings-as-errors
	@echo "✅ Compilation check passed"

# Dependencies
deps: ## Get and compile dependencies
	@mix deps.get
	@mix deps.compile

deps-update: ## Update dependencies
	@mix deps.update --all

# Documentation
docs: ## Generate documentation
	@if command -v mix docs >/dev/null 2>&1; then \
		mix docs; \
		echo "✅ Documentation generated in doc/"; \
	else \
		echo "❌ ex_doc not available. Add {:ex_doc, \"~> 0.31\", only: :dev, runtime: false} to deps"; \
	fi

# Setup & Installation
setup: ## Initial project setup
	@echo "🚀 Setting up Pigeon development environment..."
	@echo ""
	@echo "1. Installing Elixir dependencies..."
	@mix local.hex --force --if-missing
	@mix local.rebar --force --if-missing
	@make deps
	@echo ""
	@echo "2. Setting up environment configuration..."
	@if [ ! -f .env.local ]; then \
		cp .env.example .env.local; \
		echo "📝 Created .env.local from .env.example"; \
		echo "   Please review and customize it for your setup"; \
	else \
		echo "ℹ️ .env.local already exists"; \
	fi
	@echo ""
	@echo "3. Checking Podman setup..."
	@if command -v podman >/dev/null 2>&1; then \
		echo "✅ Podman found"; \
		if podman machine list --format '{{.Running}}' | grep -q true; then \
			echo "✅ Podman machine running"; \
		else \
			echo "⚠️ Podman machine not running. Start with: podman machine start"; \
		fi \
	else \
		echo "❌ Podman not found. Install with: brew install podman"; \
	fi
	@echo ""
	@echo "4. Making scripts executable..."
	@chmod +x scripts/*.sh
	@echo ""
	@echo "🎉 Setup complete! Next steps:"
	@echo "   make dev     # Start development environment"
	@echo "   make ci      # Run CI/CD pipeline locally"
	@echo "   make help    # See all available commands"

# Utility targets
rebuild: ## Rebuild and restart environment
	@./scripts/dev.sh restart --rebuild

# Integration shortcuts
vscode: ## Open project in VS Code
	@code .

# Health checks
health: ## Check all service health
	@echo "🏥 Health Check Report"
	@echo "===================="
	@echo ""
	@if curl -s http://localhost:4040/health >/dev/null 2>&1; then \
		echo "✅ Control Node (port 4040)"; \
	else \
		echo "❌ Control Node (port 4040)"; \
	fi
	@for port in 8081 8082 8083 8084; do \
		if curl -s http://localhost:$$port/health >/dev/null 2>&1; then \
			echo "✅ Worker (port $$port)"; \
		else \
			echo "❌ Worker (port $$port)"; \
		fi \
	done

# Quick commands for common workflows
quick-start: setup dev ## Complete setup and start development

quick-test: format-check test ## Quick format check and test

full-check: check test docs ## Complete code quality and test check

# Development server (without containers)
server: ## Start Pigeon server locally (no containers)
	@mix run --no-halt