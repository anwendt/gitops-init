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

# Generate SBOM using Anchore Syft against a single-platform image
# NOTE: Syft has issues parsing OCI index/manifest lists (multi-arch tars). Build a linux/amd64 image and load it locally,
# then run syft against the local docker image to produce CycloneDX and SPDX SBOMs.
.PHONY: sbom
sbom: builder
	@echo "Building single-platform image (linux/amd64) for SBOM generation"
	@docker buildx build --platform linux/amd64 -t $(IMAGE_NAME):$(GIT_VERSION)-sbom --load $(BUILD_CONTEXT)
	@echo "Checking Docker daemon availability..."
	@docker info >/dev/null 2>&1 || (echo "Docker daemon not running or not reachable at /var/run/docker.sock. Start Docker Desktop or ensure docker daemon is available."; exit 1)
	@echo "Generating CycloneDX SBOM for $(IMAGE_NAME):$(GIT_VERSION)-sbom -> $(GIT_VERSION)-sbom-cyclonedx.json"
	@docker run --rm -v /var/run/docker.sock:/var/run/docker.sock -v $(CURDIR):/work -w /work anchore/syft:v0.84.0 packages docker:$(IMAGE_NAME):$(GIT_VERSION)-sbom -o cyclonedx-json > $(GIT_VERSION)-sbom-cyclonedx.json || (echo "syft cyclonedx failed"; exit 1)
	@echo "Generating SPDX SBOM for $(IMAGE_NAME):$(GIT_VERSION)-sbom -> $(GIT_VERSION)-sbom-spdx.json"
	@docker run --rm -v /var/run/docker.sock:/var/run/docker.sock -v $(CURDIR):/work -w /work anchore/syft:v0.84.0 packages docker:$(IMAGE_NAME):$(GIT_VERSION)-sbom -o spdx-json > $(GIT_VERSION)-sbom-spdx.json || (echo "syft spdx failed"; exit 1)

# Run vulnerability scan using Anchore Grype against the single-platform image
# Use the same single-platform image built for SBOM generation to avoid OCI index parsing issues.
.PHONY: security-scan
security-scan: sbom
	@echo "Running vulnerability scans (Grype + Trivy) for $(IMAGE_NAME):$(GIT_VERSION)-sbom"
	@# --- Grype Scan ---
	@echo "[Grype] table output -> $(GIT_VERSION)-vuln.txt"
	@docker run --rm -v /var/run/docker.sock:/var/run/docker.sock anchore/grype:latest docker:$(IMAGE_NAME):$(GIT_VERSION)-sbom | tee $(GIT_VERSION)-vuln.txt || true
	@echo "[Grype] json output -> $(GIT_VERSION)-vuln.json"
	@docker run --rm -v /var/run/docker.sock:/var/run/docker.sock anchore/grype:latest docker:$(IMAGE_NAME):$(GIT_VERSION)-sbom -o json > $(GIT_VERSION)-vuln.json || (echo "grype (json) failed with exit code $$?"; true)
	@# --- Trivy Scan ---
	@echo "[Trivy] table output -> $(GIT_VERSION)-trivy.txt"
	@docker run --rm -v /var/run/docker.sock:/var/run/docker.sock aquasec/trivy:latest image --scanners vuln --format table $(IMAGE_NAME):$(GIT_VERSION)-sbom | tee $(GIT_VERSION)-trivy.txt || true
	@echo "[Trivy] json output -> $(GIT_VERSION)-trivy.json"
	@docker run --rm -v /var/run/docker.sock:/var/run/docker.sock aquasec/trivy:latest image --scanners vuln --format json $(IMAGE_NAME):$(GIT_VERSION)-sbom > $(GIT_VERSION)-trivy.json || (echo "trivy (json) failed with exit code $$?"; true)
	@# Provide quick combined severity summary (unique HIGH/CRITICAL across both)
	@echo "[Summary] Counting unique HIGH/CRITICAL (Grype + Trivy)"; \
	jq -r '.matches[] | select(.vulnerability.severity!=null) | "\(.vulnerability.id):\(.vulnerability.severity)"' $(GIT_VERSION)-vuln.json 2>/dev/null | awk -F: 'tolower($$2)=="high"||tolower($$2)=="critical"{print $$1}' > .grype_hc  || true; \
	jq -r '.Results[].Vulnerabilities[]? | select(.Severity=="HIGH" or .Severity=="CRITICAL") | .VulnerabilityID' $(GIT_VERSION)-trivy.json 2>/dev/null > .trivy_hc || true; \
	cat .grype_hc .trivy_hc 2>/dev/null | sort -u > .combined_hc || true; \
	count=$$(wc -l < .combined_hc 2>/dev/null || echo 0); echo "Unique HIGH/CRITICAL across scanners: $$count"; rm -f .grype_hc .trivy_hc .combined_hc || true

# CI target: build, then create SBOM (and optionally run security-scan)
.PHONY: ci
ci: all sbom
	@echo "CI targets completed: image built and SBOM generated."

# Local CI runner: build, generate SBOM and run security scan (for local testing)
.PHONY: ci-local
ci-local: all sbom security-scan
	@echo "ci-local completed: build, sbom and security-scan finished."

.PHONY: test
test: builder
	@# PLATFORM may be set externally (e.g. PLATFORM=linux/arm64). Default to amd64
	@PLATFORM=$${PLATFORM:-linux/amd64}; \
	SHORT=$$(echo $$PLATFORM | tr "/" "-"); \
	IMAGE_TAG=$(IMAGE_NAME):$(GIT_VERSION)-test-$$SHORT; \
	echo "Building image for local test and loading into docker ($$PLATFORM)..."; \
	docker buildx build $(BUILD_CACHE_ARGS) --platform $$PLATFORM -t $$IMAGE_TAG --load $(BUILD_CONTEXT); \
	./test/run-tests.sh $$IMAGE_TAG

# Login to GitHub Container Registry (GHCR)
.PHONY: login-ghcr
login-ghcr:
	@if [ -z "$(GHCR_OWNER)" ]; then \
		echo "GHCR_OWNER is not set. Export GHCR_OWNER and GHCR_TOKEN before running login-ghcr."; exit 1; \
	fi
	@echo "Logging in to ghcr.io as $(GHCR_OWNER)"
	@echo $(GHCR_TOKEN) | docker login ghcr.io -u $(GHCR_OWNER) --password-stdin

# Push image to GitHub Container Registry (requires GHCR_OWNER & GHCR_TOKEN or prior login)
.PHONY: push-ghcr
push-ghcr: builder
	@echo "Pushing image to GHCR with tags: ghcr.io/$(GHCR_OWNER)/argocdinit:$(GIT_VERSION) $(EXTRA_TAGS)"
	@if [ -z "$(GHCR_OWNER)" ]; then \
		echo "GHCR_OWNER not set. Export GHCR_OWNER and GHCR_TOKEN or run make login-ghcr."; exit 1; \
	fi
	@extra_tags_args="$(foreach T,$(EXTRA_TAGS),-t ghcr.io/$(GHCR_OWNER)/argocdinit:$(T))"; \
	echo "Computed extra tag args: $$extra_tags_args"; \
	docker buildx build --platform $(PLATFORMS) -t ghcr.io/$(GHCR_OWNER)/argocdinit:$(GIT_VERSION) $$extra_tags_args --push $(BUILD_CONTEXT)

# Clean up the builder (optional)
.PHONY: clean
clean:
	@if docker buildx inspect $(BUILDER) >/dev/null 2>&1; then \
		docker buildx rm $(BUILDER); \
	fi
	rm -f $(OUTPUT_TAR)
	rm -f $(DOCKERFILE).bak
