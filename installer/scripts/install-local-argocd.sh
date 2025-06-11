#!/bin/bash

set -e

# === Konfiguration ===
ARGOCD_NAMESPACE="argocd"
CONFIG_FILE="$HOME/.gitopsconfig"
REPO_SECRET_NAME="git-bootstrap-repo"
BOOTSTRAP_APP_NAME="bootstrap"

# === SOPS Key + Helm Values YAML ===
SOPS_KEY_FILE="$HOME/.sops/devargocd.key"
SOPS_SECRET_NAME="helm-secrets-private-keys"

ARGOCD_HELM_VALUES=$(cat <<'EOF'
configs:
  cm:
    helm.valuesFileSchemes: secrets+gpg-import, secrets+gpg-import-kubernetes, secrets+age-import,
      secrets+age-import-kubernetes, secrets,secrets+literal, https
  params:
    server.insecure: true
controller:
  metrics:
    enabled: true
    serviceMonitor:
      enabled: true
  replicas: 1
  resources: {}
redis:
  metrics:
    enabled: true
    serviceMonitor:
      enabled: true
applicationSet:
  metrics:
    enabled: true
    serviceMonitor:
      enabled: true
dex:
  metrics:
    enabled: true
    serviceMonitor:
      enabled: true
  image:
    repository: ghcr.io/dexidp/dex
global:
  addPrometheusAnnotations: true
  image:
    repository: quay.io/argoproj/argocd
  logging:
    format: text
    level: error
redis-ha:
  enabled: true
  image:
    repository: ecr-public.aws.com/docker/library/redis
    exporter:
      image:
        repository: ghcr.io/oliver006/redis_exporter
  haproxy:
    metrics:
      enabled: true
      serviceMonitor:
        enabled: true
    image:
      repository: ecr-public.aws.com/docker/library/haproxy
    hardAntiAffinity: false
repoServer:
  autoscaling:
    enabled: false
    minReplicas: 2
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
  - args:
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
    command:
    - sh
    - -c
    image: awendt/argocdinit:v0.3.0
    name: download-tools
    volumeMounts:
    - mountPath: /custom-tools
      name: custom-tools
  metrics:
    enabled: true
    serviceMonitor:
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
    minReplicas: 2
  config:
    configManagementPlugins: |2

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
    serviceMonitor:
      enabled: true
  extensions:
    image:
      repository: "quay.io/argoprojlabs/argocd-extension-installer"
notifications:
  metrics:
    enabled: true
    serviceMonitor:
      enabled: true
EOF
)




# === Formatierung ===
GREEN="\033[0;32m"
RED="\033[0;31m"
NC="\033[0m"

function info() { echo -e "${GREEN}[INFO]${NC} $1"; }
function error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

# === Checks ===
function check_requirements() {
  command -v helm >/dev/null || error "Helm not installed"
  command -v kubectl >/dev/null || error "kubectl not installed"
}

function check_k8s_connection() {
  kubectl version --client >/dev/null || error "kubectl not found"
  kubectl cluster-info >/dev/null || error "Kubernetes cluster not accessible"
}

# === ArgoCD Installation ===

function create_sops_key_secret() {
  info "Checking SOPS key secret..."

  if kubectl get secret "$SOPS_SECRET_NAME" -n "$ARGOCD_NAMESPACE" &>/dev/null; then
    info "SOPS key secret already exists."
    return
  fi

  if [[ ! -f "$SOPS_KEY_FILE" ]]; then
    info "No local SOPS key found at $SOPS_KEY_FILE, generating new age key..."
    mkdir -p "$(dirname "$SOPS_KEY_FILE")"
    age-keygen -o "$SOPS_KEY_FILE" || error "Failed to generate age key"
    info "New SOPS key written to $SOPS_KEY_FILE"
  fi

  info "Creating Kubernetes secret $SOPS_SECRET_NAME in namespace $ARGOCD_NAMESPACE..."

  kubectl create namespace "$ARGOCD_NAMESPACE" 2>/dev/null || true

  kubectl create secret generic "$SOPS_SECRET_NAME" \
    --from-file=key.txt="$SOPS_KEY_FILE" \
    -n "$ARGOCD_NAMESPACE" || error "Failed to create SOPS secret"
}

function is_argocd_installed() {
  helm list -n "$ARGOCD_NAMESPACE" | grep -q argocd
}

function install_argocd() {
  info "Installing ArgoCD via Helm..."

  kubectl create namespace "$ARGOCD_NAMESPACE" 2>/dev/null || true
  helm repo add argo https://argoproj.github.io/argo-helm
  helm repo update

  local tmp_values
  tmp_values=$(mktemp)
  echo "$ARGOCD_HELM_VALUES" > "$tmp_values"

  helm install argocd argo/argo-cd -n "$ARGOCD_NAMESPACE" -f "$tmp_values"

  rm -f "$tmp_values"
}


# === Git Config ===
function read_or_ask_git_config() {
  if [[ -f "$CONFIG_FILE" ]]; then
    source "$CONFIG_FILE"
  fi

  if [[ -z "$giturl" || -z "$gittoken" ]]; then
    read -rp "Enter Git Repository URL: " giturl
    read -rsp "Enter Git Token: " gittoken
    echo
    echo "giturl=\"$giturl\"" > "$CONFIG_FILE"
    echo "gittoken=\"$gittoken\"" >> "$CONFIG_FILE"
    chmod 600 "$CONFIG_FILE"
    info "Git config saved to $CONFIG_FILE"
  else
    info "Using Git config from $CONFIG_FILE"
  fi
}

function validate_git_token() {
  info "Validating Git token..."

  # Extrahiere GitHub API-URL aus giturl (z. B. https://github.com/org/repo.git)
  local api_url=$(echo "$giturl" | sed -E 's#https://github.com/([^/]+)/([^/.]+).*#https://api.github.com/repos/\1/\2#')

  local RESPONSE=$(curl -s -o /dev/null -w "%{http_code}" \
    -H "Authorization: token $gittoken" "$api_url")

  if [[ "$RESPONSE" != "200" ]]; then
    error "GitHub token check failed (HTTP $RESPONSE). API URL: $api_url"
  fi
}

# === Git-Repo Registrierung via Secret ===
function is_repo_registered() {
  kubectl get secret "$REPO_SECRET_NAME" -n "$ARGOCD_NAMESPACE" &>/dev/null
}

function register_repo_secret() {
  info "Registering Git repo via Kubernetes Secret..."

  kubectl apply -n "$ARGOCD_NAMESPACE" -f - <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: $REPO_SECRET_NAME
  namespace: $ARGOCD_NAMESPACE
  labels:
    argocd.argoproj.io/secret-type: repository
stringData:
  type: git
  url: "$giturl"
  password: "$gittoken"
  username: git
  insecure: "true"
EOF
}

# === Bootstrap-Application ===
function is_bootstrap_applied() {
  kubectl get applications.argoproj.io "$BOOTSTRAP_APP_NAME" -n "$ARGOCD_NAMESPACE" &>/dev/null
}

function apply_bootstrap_repo() {
  info "Applying ArgoCD bootstrap application..."
  cat <<EOF | kubectl apply -f -
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: $BOOTSTRAP_APP_NAME
  namespace: $ARGOCD_NAMESPACE
spec:
  project: default
  source:
    repoURL: "$giturl"
    targetRevision: HEAD
    path: bootstrap
  destination:
    server: https://kubernetes.default.svc
    namespace: $ARGOCD_NAMESPACE
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
EOF
}

function find_free_port() {
  local base_port=8080
  while lsof -iTCP:$base_port -sTCP:LISTEN >/dev/null 2>&1; do
    base_port=$((base_port + 1))
  done
  echo "$base_port"
}

function show_ui_info() {
  local ui_port
  ui_port=$(find_free_port)

  info "Starting Port-Forward to ArgoCD UI (port $ui_port)..."
  kubectl -n "$ARGOCD_NAMESPACE" port-forward svc/argocd-server "$ui_port":443 >/dev/null 2>&1 &
  sleep 3

  echo -e "\n${GREEN}You can now access the ArgoCD UI here:${NC}"
  echo -e "➡️  ${GREEN}https://localhost:$ui_port${NC}"
  echo -e "${GREEN}Default username:${NC} admin"
  echo -e "${GREEN}To get the initial password:${NC}"
  echo -e "   kubectl -n $ARGOCD_NAMESPACE get secret argocd-initial-admin-secret -o jsonpath=\"{.data.password}\" | base64 -d && echo"
  echo
}

# === Ablauf ===
check_requirements
check_k8s_connection

create_sops_key_secret

if is_argocd_installed; then
  info "ArgoCD is already installed."
else
  install_argocd
fi

read_or_ask_git_config
validate_git_token

if is_repo_registered; then
  info "Git repository already registered in ArgoCD."
else
  register_repo_secret
  info "Repository registered successfully."
fi

if is_bootstrap_applied; then
  info "Bootstrap application already exists."
else
  apply_bootstrap_repo
  info "Bootstrap application created successfully."
fi
show_ui_info
