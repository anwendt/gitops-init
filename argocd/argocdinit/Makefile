# Variables
IMAGE_NAME := awendt/argocdinit
DOCKERFILE := Dockerfile
GIT_VERSION := $(shell git describe --tags --always --dirty 2>/dev/null || echo "latest")
PLATFORMS := linux/amd64,linux/arm64
OUTPUT_TAR := $(GIT_VERSION).tar
BUILD_CONTEXT := .

# Docker Buildx target
BUILDER := multiarch-builder

# Default target
.PHONY: all
all: patch-dockerfile build

# Create and initialize the builder
.PHONY: builder
builder:
	@if ! docker buildx inspect $(BUILDER) >/dev/null 2>&1; then \
		docker buildx create --name $(BUILDER) --use; \
		docker buildx inspect --bootstrap; \
	else \
		echo "Builder $(BUILDER) already exists"; \
	fi

# Patch the Dockerfile to update the version label
.PHONY: patch-dockerfile
patch-dockerfile:
	@echo "Patching Dockerfile with version: $(GIT_VERSION)"
	@sed -i.bak 's/^LABEL org.opencontainers.image.version=".*"$$/LABEL org.opencontainers.image.version="$(GIT_VERSION)"/' $(DOCKERFILE)

# Build the image for multiple platforms and export as OCI tarball
.PHONY: build
build: builder
	mkdir -p $(dir $(OUTPUT_TAR)) # Ensure the output directory exists
	docker buildx build --platform $(PLATFORMS) -t $(IMAGE_NAME):$(GIT_VERSION) --output type=oci,dest=$(OUTPUT_TAR) $(BUILD_CONTEXT)

# Build the image for multiple platforms and push to Docker Hub
.PHONY: push
push: builder
	docker buildx build --platform $(PLATFORMS) -t $(IMAGE_NAME):$(GIT_VERSION) --push $(BUILD_CONTEXT)

# Build and push the image in one step
.PHONY: build-push
build-push: patch-dockerfile builder
	docker buildx build --platform $(PLATFORMS) -t $(IMAGE_NAME):$(GIT_VERSION) --push $(BUILD_CONTEXT)

# Print the Git version (for debugging)
.PHONY: version
version:
	@echo "Git Version: $(GIT_VERSION)"

# Generate SBOM using Anchore Syft against the produced OCI archive
.PHONY: sbom
sbom: build
	@echo "Generating SBOM for $(IMAGE_NAME):$(GIT_VERSION) -> $(GIT_VERSION)-sbom.json"
	@docker run --rm -v $(CURDIR):/work -w /work anchore/syft:v0.84.0 packages oci-archive:/work/$(OUTPUT_TAR) -o cyclonedx-json > $(GIT_VERSION)-sbom.json || (echo "syft failed"; exit 1)

# Run vulnerability scan using Anchore Grype against the produced OCI archive
.PHONY: security-scan
security-scan: build
	@echo "Running vulnerability scan for $(IMAGE_NAME):$(GIT_VERSION) -> $(GIT_VERSION)-vuln.json"
	@docker run --rm -v $(CURDIR):/work -w /work anchore/grype:0.72.0 grype oci-archive:/work/$(OUTPUT_TAR) -o json > $(GIT_VERSION)-vuln.json || (echo "grype failed with exit code $$?"; true)

# CI target: build, then create SBOM (and optionally run security-scan)
.PHONY: ci
ci: all sbom
	@echo "CI targets completed: image built and SBOM generated."

# Clean up the builder (optional)
.PHONY: clean
clean:
	@if docker buildx inspect $(BUILDER) >/dev/null 2>&1; then \
		docker buildx rm $(BUILDER); \
	fi
	rm -f $(OUTPUT_TAR)
	rm -f $(DOCKERFILE).bak
