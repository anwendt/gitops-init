#!/bin/bash

set -e  # Exit on error

# Default behaviour flags (can be overridden by CLI args or env vars)
NON_INTERACTIVE=false
AUTO_INSTALL_AGE=false
GENERATE_AGE_KEY=false
DRY_RUN=false
AGE_KEY_PATH_ENV=""
GIT_URL_ENV=""
GIT_USER_ENV=""
GIT_TOKEN_ENV=""
HTTP_PROXY_ENV=""
ARGOCD_INIT_IMAGE_ENV=""

function usage() {
    cat <<EOF
Usage: $0 [options]

Options:
  -y, --non-interactive       Run without prompts; required vars must be provided via env or options
      --auto-install-age      In non-interactive mode, install 'age' automatically if missing
      --generate-age-key      In non-interactive mode, generate a new age key (key.txt) instead of prompting
      --age-key-path PATH     Path to existing age key (uses this instead of generating)
      --git-url URL           Git repository URL (preferably without leading protocol, e.g. 'github.com/org/repo.git')
      --git-user USER         Git username
      --git-token TOKEN       Git token/password
  --http-proxy URL        HTTP_PROXY value to set for repository access
  --argocd-init-image IMG Override init container image (defaults to ghcr.io/anwendt/argocdinit:v0.4.0-beta2 or env ARGOCD_INIT_IMAGE)
  -h, --help                  Show this help and exit
    --dry-run               Do not change anything; print normalized settings and exit

Environment variables (alternate to options):
  AGE_KEY_PATH, GIT_URL, GIT_USER, GIT_TOKEN, HTTP_PROXY, ARGOCD_INIT_IMAGE
  (CLI flag --argocd-init-image has precedence over ARGOCD_INIT_IMAGE env)

Notes:
  - The script accepts Git URLs with or without the leading protocol (https:// or http://).
    If you provide a URL containing 'https://' the script will automatically strip the protocol
    and any trailing slash. However, when running in non-interactive mode you must provide
    a non-empty repository path (for example: 'github.com/org/repo.git').

Examples:
  # interactive (default)
  $0

  # non-interactive (generate key, auto-install age)
  $0 --non-interactive --auto-install-age --generate-age-key --git-url github.com/org/repo.git --git-user myuser --git-token secret

EOF
}

# Parse CLI args
while [[ "$#" -gt 0 ]]; do
  case "$1" in
    -y|--non-interactive)
      NON_INTERACTIVE=true; shift ;;
    --auto-install-age)
      AUTO_INSTALL_AGE=true; shift ;;
    --generate-age-key)
      GENERATE_AGE_KEY=true; shift ;;
    --age-key-path)
      AGE_KEY_PATH_ENV="$2"; shift 2 ;;
    --git-url)
      GIT_URL_ENV="$2"; shift 2 ;;
    --git-user)
      GIT_USER_ENV="$2"; shift 2 ;;
    --git-token)
      GIT_TOKEN_ENV="$2"; shift 2 ;;
    --http-proxy)
      HTTP_PROXY_ENV="$2"; shift 2 ;;
    --argocd-init-image)
      ARGOCD_INIT_IMAGE_ENV="$2"; shift 2 ;;
    --dry-run)
      DRY_RUN=true; shift ;;
    -h|--help)
      usage; exit 0 ;;
    *)
      echo "Unknown option: $1"; usage; exit 1 ;;
  esac
done

# Prefer CLI args, then env vars
AGE_KEY_PATH=${AGE_KEY_PATH_ENV:-${AGE_KEY_PATH:-}}
GIT_URL=${GIT_URL_ENV:-${GIT_URL:-}}
GIT_USER=${GIT_USER_ENV:-${GIT_USER:-}}
GIT_TOKEN=${GIT_TOKEN_ENV:-${GIT_TOKEN:-}}
HTTP_PROXY=${HTTP_PROXY_ENV:-${HTTP_PROXY:-}}
ARGOCD_INIT_IMAGE=${ARGOCD_INIT_IMAGE_ENV:-${ARGOCD_INIT_IMAGE:-ghcr.io/anwendt/argocdinit:v0.4.0-beta2}}

# Colors for output
GREEN="\033[0;32m"
RED="\033[0;31m"
YELLOW="\033[0;33m"
RESET="\033[0m"

# Function to check if a command is installed
function check_command() {
    command -v "$1" >/dev/null 2>&1
}

# Function to ensure 'age' is installed
function ensure_age_installed() {
    echo -e "${GREEN}Checking if 'age' is installed...${RESET}"
  if ! check_command "age"; then
    echo -e "${YELLOW}'age' is not installed.${RESET}"
    if [[ "$NON_INTERACTIVE" == "true" ]]; then
      if [[ "$AUTO_INSTALL_AGE" == "true" ]]; then
        echo -e "${GREEN}Non-interactive: installing 'age' and 'age-keygen'...${RESET}"
      else
        echo -e "${RED}Non-interactive mode and 'age' missing. Set --auto-install-age or install 'age' manually.${RESET}"
        exit 1
      fi
    else
      read -p "Would you like to install 'age' and 'age-keygen'? (y/n): " INSTALL_AGE
      if [[ "$INSTALL_AGE" != "y" && "$INSTALL_AGE" != "Y" ]]; then
        echo -e "${RED}'age' is required. Exiting.${RESET}"
        exit 1
      fi
      echo -e "${GREEN}Installing 'age' and 'age-keygen'...${RESET}"
    fi

    # Perform installation (either interactive-confirmed or auto)
    if [[ "$(uname)" == "Linux" ]]; then
      AGE_VERSION="v1.2.1"
      AGE_TARBALL="age-${AGE_VERSION}-linux-amd64.tar.gz"
      AGE_URL="https://github.com/FiloSottile/age/releases/download/${AGE_VERSION}/${AGE_TARBALL}"

      TMP_DIR=$(mktemp -d)
      pushd "$TMP_DIR" >/dev/null

      echo -e "${GREEN}Downloading ${AGE_TARBALL}...${RESET}"
      curl -fsSL -o "${AGE_TARBALL}" "${AGE_URL}"

      echo -e "${GREEN}Extracting ${AGE_TARBALL}...${RESET}"
      tar -xzf "${AGE_TARBALL}"

      echo -e "${GREEN}Installing binaries to /usr/local/bin...${RESET}"
      sudo mv age/age /usr/local/bin/age
      sudo mv age/age-keygen /usr/local/bin/age-keygen
      sudo chmod +x /usr/local/bin/age /usr/local/bin/age-keygen

      popd >/dev/null
      rm -rf "$TMP_DIR"

    elif [[ "$(uname)" == "Darwin" ]]; then
      brew install age
    else
      echo -e "${RED}Unknown operating system. Please install 'age' manually.${RESET}"
      exit 1
    fi
  else
    echo -e "${GREEN}'age' is already installed.${RESET}"
  fi
}

# Function to configure the 'age' key
function configure_age_key() {
    echo -e "${GREEN}Configuring 'age' key...${RESET}"
  # Non-interactive behaviour: prefer CLI/env-provided AGE_KEY_PATH, or GENERATE_AGE_KEY
  if [[ "$NON_INTERACTIVE" == "true" ]]; then
    if [[ -n "${AGE_KEY_PATH}" ]]; then
      if [[ ! -f "${AGE_KEY_PATH}" ]]; then
        echo -e "${RED}Provided AGE_KEY_PATH does not exist: ${AGE_KEY_PATH}${RESET}"
        exit 1
      fi
      echo -e "${GREEN}Using provided age key: ${AGE_KEY_PATH}${RESET}"
      export AGE_KEY_PATH
      return
    fi
    if [[ "$GENERATE_AGE_KEY" == "true" ]]; then
      echo -e "${GREEN}Non-interactive: generating new 'age' key...${RESET}"
      if [[ -f key.txt ]]; then
        rm key.txt
        echo -e "${GREEN}Old 'key.txt' deleted.${RESET}"
      fi
      age-keygen -o key.txt
      echo -e "${GREEN}'age' key generated: key.txt${RESET}"
      export AGE_KEY_PATH=$PWD/key.txt
      return
    fi
    echo -e "${RED}Non-interactive mode requires either --age-key-path or --generate-age-key.${RESET}"
    exit 1
  fi

  # Interactive fallback
  read -p "Do you want to generate a new 'age' key? (y/n): " NEW_AGE_KEY
  if [[ "$NEW_AGE_KEY" == "y" || "$NEW_AGE_KEY" == "Y" ]]; then
    if [[ -f key.txt ]]; then
      rm key.txt
      echo -e "${GREEN}Old 'key.txt' deleted.${RESET}"
    fi
    echo -e "${GREEN}Generating new 'age' key...${RESET}"
    age-keygen -o key.txt
    echo -e "${GREEN}'age' key generated: key.txt${RESET}"
    export AGE_KEY_PATH=$PWD/key.txt
  else
    read -p "Enter the file path to an existing 'age' key: " AGE_KEY_PATH
    if [[ ! -f "$AGE_KEY_PATH" ]]; then
      echo -e "${RED}Invalid file path. Exiting.${RESET}"
      exit 1
    fi
    echo -e "${GREEN}Using existing 'age' key: $AGE_KEY_PATH${RESET}"
    export AGE_KEY_PATH
  fi
}


# Function to validate prerequisites
function validate_prerequisites() {
    echo -e "${GREEN}Validating prerequisites...${RESET}"

    # Check if kubectl is installed
    if ! check_command "kubectl"; then
        echo -e "${RED}'kubectl' is not installed. Please install 'kubectl' and try again.${RESET}"
        exit 1
    fi

    # Check if jq is installed
    if ! check_command "jq"; then
    echo -e "${RED}'jq' is not installed. Please install 'jq' and try again.${RESET}"
    exit 1
    fi

    # Check if kubectl can connect to a cluster
    if ! kubectl cluster-info >/dev/null 2>&1; then
        echo -e "${RED}No cluster reachable. Exiting.${RESET}"
        exit 1
    fi

    # Check if 'helmcharts.helm.cattle.io' exists
    echo -e "${GREEN}Checking for 'helmcharts.helm.cattle.io' in the cluster...${RESET}"
    if ! kubectl api-resources | grep -q "^helmcharts"; then
        echo -e "${RED}'helmcharts.helm.cattle.io' is not available in the cluster. Exiting.${RESET}"
        exit 1
    fi
    echo -e "${GREEN}'helmcharts.helm.cattle.io' is available in the cluster.${RESET}"

    # Ensure 'age' is installed
  ensure_age_installed

    echo -e "${GREEN}All prerequisites are met.${RESET}"
}


# Best-effort validation for init image availability
function validate_init_image() {
  echo -e "${GREEN}Checking availability of init image: ${ARGOCD_INIT_IMAGE}${RESET}"
  if check_command docker; then
    if docker manifest inspect "${ARGOCD_INIT_IMAGE}" >/dev/null 2>&1; then
      echo -e "${GREEN}Init image is available (via docker).${RESET}"
      return 0
    else
      echo -e "${YELLOW}Warning:${RESET} Could not inspect image via 'docker manifest inspect'. The image may not exist or is not accessible. Continuing."
      return 0
    fi
  elif check_command skopeo; then
    if skopeo inspect "docker://${ARGOCD_INIT_IMAGE}" >/dev/null 2>&1; then
      echo -e "${GREEN}Init image is available (via skopeo).${RESET}"
      return 0
    else
      echo -e "${YELLOW}Warning:${RESET} Could not inspect image via 'skopeo inspect'. The image may not exist or is not accessible. Continuing."
      return 0
    fi
  else
    echo -e "${YELLOW}Warning:${RESET} Neither 'docker' nor 'skopeo' found; skipping init image availability check."
    return 0
  fi
}



# Function to validate git clone
function test_git_clone() {
    local git_url=$1
    local git_user=$2
    local git_token=$3
    echo -e "${GREEN}Testing Git repository access...${RESET}"
    if ! git ls-remote https://${git_user}:${git_token}@${git_url} >/dev/null 2>&1; then
        echo -e "${RED}Failed to access Git repository. Reconfiguring...${RESET}"
        configure_git_repository
    else
        echo -e "${GREEN}Git repository access verified successfully.${RESET}"
    fi
}

# Function to get the latest ArgoCD version
function get_helm_chart_version() {
    echo -e "${GREEN}Fetching the latest version of the ArgoCD Helm chart from Artifact Hub...${RESET}"
    LATEST_VERSION=$(curl -s "https://artifacthub.io/api/v1/packages/helm/argo/argo-cd" | jq -r '.version')
    if [[ -z "$LATEST_VERSION" ]]; then
        echo -e "${RED}Failed to fetch the latest Helm chart version. Please check your internet connection or the Artifact Hub API status.${RESET}"
        exit 1
    fi
    echo -e "${GREEN}Latest version of the ArgoCD Helm chart: $LATEST_VERSION${RESET}"
}

# Function to deploy ArgoCD using HelmChart
function deploy_argocd() {
    echo -e "${GREEN}Deploying ArgoCD HelmChart...${RESET}"
    kubectl apply -f - <<EOF
apiVersion: helm.cattle.io/v1
kind: HelmChart
metadata:
  name: argocd
  namespace: argocd
spec:
  chart: argo-cd
  repo: https://argoproj.github.io/argo-helm
  version: ${LATEST_VERSION}
  targetNamespace: argocd
  valuesContent: |-
    configs:
      cm:
        helm.valuesFileSchemes: secrets+gpg-import, secrets+gpg-import-kubernetes, secrets+age-import,
          secrets+age-import-kubernetes, secrets,secrets+literal, https
      params:
        server.insecure: true
    controller:
      metrics:
        enabled: true
      replicas: 1
      resources: {}
    dex:
      metrics:
        enabled: true
    global:
      addPrometheusAnnotations: true
    redis-ha:
      enabled: false
      haproxy:
        metrics:
          enabled: false
    repoServer:
      autoscaling:
        enabled: false
        minReplicas: 1
      env:
      - name: HELM_PLUGINS
        value: /custom-tools/helm-plugins/
      - name: HELM_SECRETS_CURL_PATH
        value: /custom-tools/curl
      - name: HELM_SECRETS_SOPS_PATH
        value: /custom-tools/sops
      - name: HELM_SECRETS_VALS_PATH
        value: /custom-tools/vals
      - name: HELM_SECRETS_KUBECTL_PATH
        value: /custom-tools/kubectl
      - name: HELM_SECRETS_BACKEND
        value: sops
      - name: HELM_SECRETS_VALUES_ALLOW_SYMLINKS
        value: "false"
      - name: HELM_SECRETS_VALUES_ALLOW_ABSOLUTE_PATH
        value: "true"
      - name: HELM_SECRETS_VALUES_ALLOW_PATH_TRAVERSAL
        value: "false"
      - name: HELM_SECRETS_WRAPPER_ENABLED
        value: "true"
      - name: HELM_SECRETS_DECRYPT_SECRETS_IN_TMP_DIR
        value: "true"
      - name: HELM_SECRETS_HELM_PATH
        value: /usr/local/bin/helm
      - name: SOPS_AGE_KEY_FILE
        value: /helm-secrets-private-keys/key.txt
      - name: HELM_SECRETS_IGNORE_MISSING_VALUES
        value: "true"
      initContainers:
        - name: download-tools
          # Updated to new multi-arch image published to GHCR
          image: ${ARGOCD_INIT_IMAGE}
          command:
            - sh
            - -c
          args:
            - |
              cp /usr/local/bin/sops /custom-tools/ && \
              cp /usr/local/bin/argocd-vault-plugin /custom-tools/ && \
              cp /usr/local/bin/kubectl /custom-tools/ && \
              cp /usr/local/bin/helm /custom-tools/ && \
              cp /usr/local/bin/vals /custom-tools/ && \
              cp /usr/local/bin/age/age /custom-tools/ && \
              cp /usr/local/bin/age/age-keygen /custom-tools/ && \
              cp /usr/local/bin/yq /custom-tools/ && \
              cp /usr/bin/curl /custom-tools/ && \
              mkdir -p /custom-tools/helm-plugins/ && \
              cp -r /opt/custom-tools/helm-plugins/helm-secrets /custom-tools/helm-plugins/ && \
              echo "Tools copied successfully"
          volumeMounts:
            - mountPath: /custom-tools
              name: custom-tools
      metrics:
        enabled: true
      volumeMounts:
      - mountPath: /custom-tools
        name: custom-tools
      - mountPath: /usr/local/sbin/helm
        name: custom-tools
        subPath: helm
      - mountPath: /helm-secrets-private-keys/
        name: helm-secrets-private-keys
      volumes:
      - emptyDir: {}
        name: custom-tools
      - name: helm-secrets-private-keys
        secret:
          secretName: helm-secrets-private-keys
    server:
      autoscaling:
        enabled: false
        minReplicas: 1
      config:
        configManagementPlugins: |-
          - name: sops
            init:
              command: ["/bin/sh", "-c"]
              args: ["if [ -f 'secrets.enc' ]; then echo '---' > secrets.yaml && sops -d --input-type yaml --output-type yaml secrets.enc >> secrets.yaml; fi"]
            generate:
              command: ["/bin/sh", "-c"]
              args: ["cat *.yaml | yq"]
          - name: argocd-vault-plugin
            generate:
              command: ["argocd-vault-plugin"]
              args: ["generate", "./"]
      metrics:
        enabled: true
EOF
    echo -e "${GREEN}ArgoCD HelmChart deployed successfully.${RESET}"
}

# Function to configure Git repository access
function configure_git_repository() {
    echo -e "${GREEN}Configuring Git repository access...${RESET}"
  # Non-interactive: use provided env/CLI values
  if [[ "$NON_INTERACTIVE" == "true" ]]; then
    if [[ -z "$GIT_URL" || -z "$GIT_USER" || -z "$GIT_TOKEN" ]]; then
      echo -e "${RED}Non-interactive mode requires GIT_URL, GIT_USER and GIT_TOKEN (via args or env).${RESET}"
      exit 1
    fi
    # Normalize: remove leading https:// or http:// if present
    GIT_URL="${GIT_URL#http://}"
    GIT_URL="${GIT_URL#https://}"
    GIT_URL="${GIT_URL%/}"
    if [[ -z "$GIT_URL" ]]; then
      echo -e "${RED}Provided GIT_URL is empty after normalization. Provide a valid repository (e.g. 'github.com/org/repo.git').${RESET}"
      exit 1
    fi
    echo -e "${GREEN}Using non-interactive Git settings.${RESET}"
    if [[ -n "$HTTP_PROXY" ]]; then
      export HTTP_PROXY="$HTTP_PROXY"
      echo -e "${GREEN}HTTP Proxy set: $HTTP_PROXY${RESET}"
    fi
  else
    read -p "Enter the Git repository URL (you may include or omit 'https://'): https://" GIT_URL

    # Normalize entered URL: strip protocol if provided and trim trailing slash
    GIT_URL="${GIT_URL#http://}"
    GIT_URL="${GIT_URL#https://}"
    GIT_URL="${GIT_URL%/}"
    if [[ -z "$GIT_URL" ]]; then
      echo -e "${RED}No Git repository provided. Exiting.${RESET}"
      exit 1
    fi

    # Check for HTTP Proxy setting
    echo -e "${GREEN}Checking HTTP Proxy configuration...${RESET}"
    if [[ -z "$HTTP_PROXY" ]]; then
      read -p "HTTP Proxy is not set. Do you want to set it now? (y/n): " SET_PROXY
      if [[ "$SET_PROXY" == "y" || "$SET_PROXY" == "Y" ]]; then
        read -p "Enter the HTTP Proxy URL: " HTTP_PROXY
        export HTTP_PROXY=$HTTP_PROXY
        echo -e "${GREEN}HTTP Proxy set: $HTTP_PROXY${RESET}"
      fi
    else
      echo -e "${GREEN}HTTP Proxy is already set: $HTTP_PROXY${RESET}"
    fi

    # Ask for Git username and token
    read -p "Enter your Git username: " GIT_USER
    read -s -p "Enter your Git token: " GIT_TOKEN
    echo
  fi

  # Test Git credentials (will prompt to reconfigure if access fails)
  test_git_clone "$GIT_URL" "$GIT_USER" "$GIT_TOKEN"

  # Export normalized URL and credentials
  export GIT_URL GIT_USER GIT_TOKEN HTTP_PROXY
}

# Function to deploy the repository secret
function deploy_repository_secret() {
    echo -e "${GREEN}Deploying repository secret...${RESET}"
    kubectl apply -f - <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: bootstrap-repo
  namespace: argocd
  labels:
    argocd.argoproj.io/secret-type: repository
stringData:
  type: git
  url: https://$GIT_URL
  proxy: $HTTP_PROXY
  username: $GIT_USER
  password: $GIT_TOKEN
EOF
    echo -e "${GREEN}Repository secret deployed successfully.${RESET}"
}

# Function to ensure the 'argocd' namespace exists
function ensure_argocd_namespace() {
    echo -e "${GREEN}Ensuring 'argocd' namespace exists...${RESET}"
    if ! kubectl get namespace argocd >/dev/null 2>&1; then
        echo -e "${YELLOW}'argocd' namespace not found. Creating it...${RESET}"
        kubectl create namespace argocd
        echo -e "${GREEN}'argocd' namespace created successfully.${RESET}"
    else
        echo -e "${GREEN}'argocd' namespace already exists.${RESET}"
    fi
}

# Function to deploy the age key secret
function deploy_age_key_secret() {
    echo -e "${GREEN}Deploying 'age' key secret...${RESET}"
    kubectl -n argocd create secret generic helm-secrets-private-keys --from-file=key.txt="$AGE_KEY_PATH" --dry-run=client -o yaml | kubectl apply -f -
    echo -e "${GREEN}'age' key secret deployed successfully.${RESET}"
}


# Function to wait for ArgoCD CRDs to be ready
function wait_for_argocd_crds() {
    echo -e "${GREEN}Waiting for ArgoCD CRDs to be registered...${RESET}"
    local timeout=300  # 5 minutes max wait
    local interval=5
    local elapsed=0

    # Wait for Application CRD
    while ! kubectl get crd applications.argoproj.io >/dev/null 2>&1; do
        if (( elapsed >= timeout )); then
            echo -e "${RED}Timed out waiting for ArgoCD CRDs after ${timeout}s.${RESET}"
            exit 1
        fi
        echo -e "${YELLOW}ArgoCD CRDs not yet ready... waiting ${interval}s.${RESET}"
        sleep $interval
        ((elapsed+=interval))
    done

    echo -e "${GREEN}ArgoCD CRDs detected successfully! (${elapsed}s)${RESET}"
}

# Wait for ArgoCD API server to become ready
function wait_for_argocd_ready() {
    echo -e "${GREEN}Waiting for ArgoCD server deployment to become ready...${RESET}"
    local timeout=300
    local interval=5
    local elapsed=0
    while true; do
        ready_replicas=$(kubectl -n argocd get deploy argocd-server -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
        if [[ "$ready_replicas" == "1" || "$ready_replicas" == "2" ]]; then
            echo -e "${GREEN}ArgoCD server is ready (${elapsed}s).${RESET}"
            break
        fi
        if (( elapsed >= timeout )); then
            echo -e "${RED}Timed out waiting for ArgoCD server to be ready after ${timeout}s.${RESET}"
            exit 1
        fi
        echo -e "${YELLOW}Waiting for ArgoCD server... (${elapsed}s)${RESET}"
        sleep $interval
        ((elapsed+=interval))
    done
}



# Function to deploy the repository secret
function deploy_bootstrap_application() {
    echo -e "${GREEN}Deploying argocd bootstrap application...${RESET}"
    kubectl apply -f - <<EOF
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: bootstrap
  namespace: argocd
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: default
  source:
    path: k8s-bootstrap
    repoURL: https://$GIT_URL
    targetRevision: HEAD
  destination:
    server: https://kubernetes.default.svc
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
      allowEmpty: false
    syncOptions:
    - Validate=false
    - CreateNamespace=true
    - PrunePropagationPolicy=foreground
    - PruneLast=true
    - ServerSideApply=true
    - ApplyOutOfSyncOnly=true
    retry:
      limit: 5
      backoff:
        duration: 5s
        factor: 2
        maxDuration: 3m
EOF
    echo -e "${GREEN}Bootstrap application deployed successfully.${RESET}"
}


# Main script execution
echo -e "${GREEN}Starting ArgoCD installation script...${RESET}"
echo -e "Using init image: ${ARGOCD_INIT_IMAGE}"

# If dry-run requested, print normalized/derived settings and exit early
if [[ "$DRY_RUN" == "true" ]]; then
  echo -e "${YELLOW}DRY RUN: reporting configuration and normalized values (no changes will be made)${RESET}"
  echo -e "NON_INTERACTIVE=${NON_INTERACTIVE}"
  echo -e "AUTO_INSTALL_AGE=${AUTO_INSTALL_AGE}"
  echo -e "GENERATE_AGE_KEY=${GENERATE_AGE_KEY}"
  echo -e "AGE_KEY_PATH (env)=${AGE_KEY_PATH:-<unset>}"
  echo -e "GIT_URL (raw)=${GIT_URL:-<unset>}"
  # show normalized git url (strip protocol and trailing slash)
  if [[ -n "${GIT_URL}" ]]; then
    normalized_url="${GIT_URL#http://}"
    normalized_url="${normalized_url#https://}"
    normalized_url="${normalized_url%/}"
  else
    normalized_url="<unset>"
  fi
  echo -e "GIT_URL (normalized)=${normalized_url}"
  echo -e "GIT_USER=${GIT_USER:-<unset>}"
  echo -e "GIT_TOKEN=${GIT_TOKEN:+<set>}"
  echo -e "HTTP_PROXY=${HTTP_PROXY:-<unset>}"
  echo -e "ARGOCD_INIT_IMAGE=${ARGOCD_INIT_IMAGE}"
  echo -e "${GREEN}DRY RUN complete.${RESET}"
  exit 0
fi

# Validate prerequisites
validate_prerequisites

# Validate init image availability (best-effort)
validate_init_image

# Validate prerequisites
ensure_argocd_namespace

# Configure the 'age' key
configure_age_key

# Configure Git repository access
configure_git_repository

# Deploy repository secret
deploy_repository_secret

# Deploy age key secret
deploy_age_key_secret

# Get the latest ArgoCD version
get_helm_chart_version

# Deploy ArgoCD
deploy_argocd
wait_for_argocd_crds
wait_for_argocd_ready


# Deploy argocd bottstrap application
deploy_bootstrap_application

echo -e "${GREEN}Script execution completed successfully.${RESET}"

argocd_password=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d)

echo -e "login to argocd using:"
echo -e "kubectl port-forward svc/argocd-server -n argocd 8080:443"
echo -e "start brower sing url: http://localhost:8080"

echo -e "${GREEN}username: admin${RESET}"
echo -e "${GREEN}password: $argocd_password${RESET}"
