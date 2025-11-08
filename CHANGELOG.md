# Changelog

Alle erwähnenswerten Änderungen dieses Repos werden in diesem Dokument festgehalten.

## [v0.4.0-beta1] - 2025-11-08

### Added
- CI-Pipeline erzeugt SBOM (CycloneDX, SPDX) via Syft und Vulnerability-Report via Grype.
- Multi-Arch Build (amd64, arm64) mit OCI-Tar-Export als Artefakt.
- Smoke-/Functional-Tests und BATS-Tests in GitHub Actions.

### Changed
- Workflow `build-argocdinit.yml` restrukturiert (Build/Test/SBOM+Scan/Artefakte).
- `run-tests.sh` robuster für kubectl Versionsermittlung.
- Tooling im Image strikt gepinnt (sops, kubectl, helm, vals, age, yq, argocd-vault-plugin, helm-secrets).

### Removed
- goss-Tests aus der Pipeline entfernt (Instabilität/Permission-Probleme).

[Unreleased]: https://github.com/anwendt/gitops-init/compare/v0.4.0-beta1...HEAD
[v0.4.0-beta1]: https://github.com/anwendt/gitops-init/releases/tag/v0.4.0-beta1