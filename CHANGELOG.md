# Changelog

Alle erwähnenswerten Änderungen dieses Repos werden in diesem Dokument festgehalten.

## [v0.4.0-beta2] - 2025-11-08

### Added
- English changelog and release process alignment.
- Parameterization of init container image via `ARGOCD_INIT_IMAGE` env var and `--argocd-init-image` CLI flag.
- Best-effort init image existence validation (docker/skopeo) with warnings.
- Startup logging of chosen init image.

### Changed
- Default init image tag updated to `v0.4.0-beta2`.
- Installer script enhanced for non-interactive robustness.

### Security / Supply Chain
- Multi-arch (amd64/arm64) image build with SBOM (CycloneDX + SPDX) and vulnerability scan (Grype).
- Fallback registry authentication using GitHub workflow token.
- Cosign keyless image signing and SLSA provenance attestation.
- Vulnerability gating (blocking HIGH/CRITICAL severities unless overridden).

### Testing
- Smoke tests and BATS functional tests retained; goss removed earlier for instability.

### Removed
- No removals in this iteration (goss was removed in prior release).

[Unreleased]: https://github.com/anwendt/gitops-init/compare/v0.4.0-beta2...HEAD
[v0.4.0-beta2]: https://github.com/anwendt/gitops-init/releases/tag/v0.4.0-beta2
[v0.4.0-beta1]: https://github.com/anwendt/gitops-init/releases/tag/v0.4.0-beta1