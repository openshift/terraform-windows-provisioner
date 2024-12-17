# Makefile for BYOH Provisioner

# Variables
IMAGE_REGISTRY ?= quay.io
IMAGE_ORG ?= openshift
IMAGE_NAME ?= byoh-provisioner
IMAGE_TAG ?= latest
IMAGE ?= $(IMAGE_REGISTRY)/$(IMAGE_ORG)/$(IMAGE_NAME):$(IMAGE_TAG)

TERRAFORM_VERSION ?= 1.9.5
CONTAINER_ENGINE ?= podman

# Detect container engine if not set
ifeq ($(shell command -v podman 2> /dev/null),)
    CONTAINER_ENGINE = docker
endif

.PHONY: help
help: ## Show this help message
	@echo "BYOH Provisioner - Makefile targets:"
	@echo ""
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-20s\033[0m %s\n", $$1, $$2}'
	@echo ""
	@echo "Variables:"
	@echo "  IMAGE_REGISTRY=$(IMAGE_REGISTRY)"
	@echo "  IMAGE_ORG=$(IMAGE_ORG)"
	@echo "  IMAGE_NAME=$(IMAGE_NAME)"
	@echo "  IMAGE_TAG=$(IMAGE_TAG)"
	@echo "  IMAGE=$(IMAGE)"
	@echo "  CONTAINER_ENGINE=$(CONTAINER_ENGINE)"

.PHONY: validate
validate: ## Validate bash scripts with shellcheck
	@echo "Validating bash scripts..."
	shellcheck byoh.sh lib/*.sh || echo "Install shellcheck: https://github.com/koalaman/shellcheck"

.PHONY: fmt-check
fmt-check: ## Check Terraform formatting
	@echo "Checking Terraform formatting..."
	terraform fmt -check -recursive aws/ azure/ gcp/ vsphere/ nutanix/ none/

.PHONY: fmt
fmt: ## Format Terraform files
	@echo "Formatting Terraform files..."
	terraform fmt -recursive aws/ azure/ gcp/ vsphere/ nutanix/ none/

.PHONY: test
test: validate ## Run all tests (shellcheck, terraform fmt)
	@echo "Running tests..."
	@$(MAKE) fmt-check

.PHONY: build
build: ## Build container image
	@echo "Building container image: $(IMAGE)"
	$(CONTAINER_ENGINE) build \
		--build-arg TERRAFORM_VERSION=$(TERRAFORM_VERSION) \
		-t $(IMAGE) \
		-f Dockerfile \
		.

.PHONY: build-no-cache
build-no-cache: ## Build container image without cache
	@echo "Building container image (no cache): $(IMAGE)"
	$(CONTAINER_ENGINE) build \
		--no-cache \
		--build-arg TERRAFORM_VERSION=$(TERRAFORM_VERSION) \
		-t $(IMAGE) \
		-f Dockerfile \
		.

.PHONY: push
push: ## Push container image to registry
	@echo "Pushing image: $(IMAGE)"
	$(CONTAINER_ENGINE) push $(IMAGE)

.PHONY: run
run: ## Run container interactively
	@echo "Running container: $(IMAGE)"
	$(CONTAINER_ENGINE) run -it --rm \
		-v $(HOME)/.kube:/root/.kube:ro \
		-e KUBECONFIG=/root/.kube/config \
		$(IMAGE) help

.PHONY: shell
shell: ## Open shell in container
	@echo "Opening shell in: $(IMAGE)"
	$(CONTAINER_ENGINE) run -it --rm \
		-v $(HOME)/.kube:/root/.kube:ro \
		-e KUBECONFIG=/root/.kube/config \
		--entrypoint /bin/bash \
		$(IMAGE)

.PHONY: clean
clean: ## Clean up local artifacts
	@echo "Cleaning up..."
	rm -rf /tmp/terraform_byoh/*
	@echo "Cleaned temporary terraform directories"

.PHONY: install-deps
install-deps: ## Install development dependencies (macOS)
	@echo "Installing development dependencies..."
	@command -v brew >/dev/null 2>&1 || { echo "Homebrew not found. Install from https://brew.sh"; exit 1; }
	brew install terraform shellcheck jq
	@echo "Dependencies installed!"

.PHONY: version
version: ## Show version information
	@echo "BYOH Provisioner"
	@echo "Version: $$(cat VERSION)"
	@echo ""
	@echo "Dependencies:"
	@terraform version 2>/dev/null || echo "  Terraform: not installed"
	@oc version --client 2>/dev/null || echo "  oc: not installed"
	@jq --version 2>/dev/null || echo "  jq: not installed"
	@shellcheck --version 2>/dev/null | head -1 || echo "  shellcheck: not installed"

.PHONY: ci-build
ci-build: test build ## CI build target (test + build)

.PHONY: ci-publish
ci-publish: ci-build push ## CI publish target (test + build + push)

# Local development targets

.PHONY: dev-setup
dev-setup: ## Set up local development environment
	@echo "Setting up development environment..."
	@mkdir -p ~/.config/byoh-provisioner
	@if [ ! -f ~/.config/byoh-provisioner/config ]; then \
		cp configs/examples/defaults.conf.example ~/.config/byoh-provisioner/config; \
		chmod 600 ~/.config/byoh-provisioner/config; \
		echo "Created config file at ~/.config/byoh-provisioner/config"; \
		echo "Please edit it with your credentials!"; \
	else \
		echo "Config file already exists at ~/.config/byoh-provisioner/config"; \
	fi

.PHONY: lint
lint: validate ## Alias for validate

.PHONY: check
check: test ## Alias for test

# Container registry targets for different registries

.PHONY: build-quay
build-quay: ## Build and tag for quay.io
	@$(MAKE) build IMAGE_REGISTRY=quay.io

.PHONY: push-quay
push-quay: ## Push to quay.io
	@$(MAKE) push IMAGE_REGISTRY=quay.io

.PHONY: build-ci
build-ci: ## Build for OpenShift CI registry
	@$(MAKE) build IMAGE_REGISTRY=registry.ci.openshift.org IMAGE_ORG=ocp IMAGE_NAME=4.17 IMAGE_TAG=byoh-provisioner

# Documentation

.PHONY: docs
docs: ## Generate/update documentation
	@echo "Documentation location:"
	@echo "  README.md - Main documentation"
	@echo "  CONTRIBUTING.md - Contribution guidelines"
	@echo "  docs/PROW_CI_INTEGRATION.md - Prow CI integration guide"

.PHONY: all
all: test build ## Run tests and build image

.DEFAULT_GOAL := help
