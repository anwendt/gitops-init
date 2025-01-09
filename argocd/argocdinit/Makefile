# Variables
IMAGE_NAME := awendt/argocdinit
DOCKERFILE := Dockerfile
GIT_VERSION := $(shell git describe --tags --always --dirty 2>/dev/null || echo "latest")
PLATFORMS := linux/amd64
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

# Clean up the builder (optional)
.PHONY: clean
clean:
	@if docker buildx inspect $(BUILDER) >/dev/null 2>&1; then \
		docker buildx rm $(BUILDER); \
	fi
	rm -f $(OUTPUT_TAR)
	rm -f $(DOCKERFILE).bak
