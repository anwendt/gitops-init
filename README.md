# ArgoCD Installer for RKE2 Clusters

This repository provides tools to set up [ArgoCD](https://argo-cd.readthedocs.io/) in an [RKE2](https://docs.rke2.io/) Kubernetes cluster. The repository includes scripts for deploying ArgoCD with Helm, integrating `age` for encryption, and using `helm-secrets` for managing secrets.

---

## Repository Structure

```
.
├── installer/
│   └── scripts/
│       └── install-argocd.sh    # Main installation script
├── argocd/
│   └── argcdinit/
│       ├── Dockerfile           # Custom ArgoCD init container with additional tools
│       └── Makefile             # Build and push the init container image
```

---

## Features

- **ArgoCD Installation**: Deploy ArgoCD using Helm in the `argocd` namespace.
- **`age` Integration**: Secure secrets with `age` encryption.
- **Custom Init Container**: Includes additional tools like `helm-secrets`, `sops`, `vals`, `kubectl`, and `yq`.
- **Bootstrap Application**: Automatically configure ArgoCD to sync a repository with Kubernetes manifests.

---

## Licensing and Third-Party Components

This project is licensed under the **Apache License 2.0**. However, it includes third-party components that have their own licenses:

1. **SOPS** (Mozilla Public License 2.0):
   - Used for encryption of secrets in Kubernetes manifests.
   - [Repository and License](https://github.com/mozilla/sops).

2. **AGE** (BSD 3-Clause License):
   - Used for managing age-encrypted secrets.
   - [Repository and License](https://github.com/FiloSottile/age).

3. **Helm-Secrets** (MIT License):
   - A Helm plugin for managing secrets securely.
   - [Repository and License](https://github.com/jkroepke/helm-secrets).

4. **Other tools**:
   - `kubectl`, `vals`, `yq`, and `curl` are used under their respective permissive licenses.

Please refer to the `LICENSES` directory in this repository for the full license texts of third-party components.

---

## Quick Start

### 1. Clone the Repository

```bash
git clone https://github.com/<your-repo>/argocd-installer.git
cd argocd-installer
```

### 2. Run the Installer Script

Navigate to the `installer/scripts` directory and execute the `install-argocd.sh` script:

```bash
cd installer/scripts
chmod +x install-argocd.sh
./install-argocd.sh
```

### 3. Access ArgoCD

Forward the ArgoCD server port and log in:

```bash
kubectl port-forward svc/argocd-server -n argocd 8080:443
```

Open your browser and visit `https://localhost:8080`. Use the following credentials:

- **Username**: `admin`
- **Password**: The script outputs the password during execution.

---

## License

This repository is licensed under the Apache License 2.0. See the [LICENSE](LICENSE) file for details.

### Third-Party Licenses
This project includes third-party software. The licenses for these components are located in the `LICENSES` directory:
- SOPS (Mozilla Public License 2.0)
- AGE (BSD 3-Clause License)
- Helm-Secrets (MIT License)
- Other tools (e.g., kubectl, vals, yq) under their respective licenses.
