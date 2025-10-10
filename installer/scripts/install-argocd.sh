#!/bin/bash

set -e  # Exit on error

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
        read -p "Would you like to install 'age' and 'age-keygen'? (y/n): " INSTALL_AGE
        if [[ "$INSTALL_AGE" == "y" || "$INSTALL_AGE" == "Y" ]]; then
            echo -e "${GREEN}Installing 'age' and 'age-keygen'...${RESET}"
            if [[ "$(uname)" == "Linux" ]]; then
                # Version definieren
                AGE_VERSION="v1.2.1"
                AGE_TARBALL="age-${AGE_VERSION}-linux-amd64.tar.gz"
                AGE_URL="https://github.com/FiloSottile/age/releases/download/${AGE_VERSION}/${AGE_TARBALL}"

                # Temporäres Verzeichnis anlegen
                TMP_DIR=$(mktemp -d)
                pushd "$TMP_DIR" >/dev/null

                echo -e "${GREEN}Downloading ${AGE_TARBALL}...${RESET}"
                curl -fsSL -o "${AGE_TARBALL}" "${AGE_URL}"

                echo -e "${GREEN}Extracting ${AGE_TARBALL}...${RESET}"
                tar -xzf "${AGE_TARBALL}"

                # age & age-keygen installieren
                echo -e "${GREEN}Installing binaries to /usr/local/bin...${RESET}"
                sudo mv age/age /usr/local/bin/age
                sudo mv age/age-keygen /usr/local/bin/age-keygen
                sudo chmod +x /usr/local/bin/age /usr/local/bin/age-keygen

                popd >/dev/null
                rm -rf "$TMP_DIR"

            elif [[ "$(uname)" == "Darwin" ]]; then
                # macOS via Homebrew
                brew install age
            else
                echo -e "${RED}Unknown operating system. Please install 'age' manually.${RESET}"
                exit 1
            fi
        else
            echo -e "${RED}'age' is required. Exiting.${RESET}"
            exit 1
        fi
    else
        echo -e "${GREEN}'age' is already installed.${RESET}"
    fi
}

# Function to configure the 'age' key
function configure_age_key() {
    echo -e "${GREEN}Configuring 'age' key...${RESET}"
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
        echo -e "${RED}'jg' is not installed. Please install 'kubectl' and try again.${RESET}"
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
      enabled: true
      haproxy:
        metrics:
          enabled: true
    repoServer:
      autoscaling:
        enabled: true
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
        - name: download-tools
          image: awendt/argocdinit:v0.3.0
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
        enabled: true
        minReplicas: 2
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
    read -p "Enter the Git repository URL https://" GIT_URL

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

    # Test Git credentials
    test_git_clone "$GIT_URL" "$GIT_USER" "$GIT_TOKEN"

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

# Validate prerequisites
validate_prerequisites

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

# Deploy argocd bottstrap application
deploy_bootstrap_application

echo -e "${GREEN}Script execution completed successfully.${RESET}"

argocd_password=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d)

echo -e "login to argocd using:"
echo -e "kubectl port-forward svc/argocd-server -n argocd 8080:443"
echo -e "start brower sing url: http://localhost:8080"

echo -e "${GREEN}username: admin${RESET}"
echo -e "${GREEN}password: $argocd_password${RESET}"
