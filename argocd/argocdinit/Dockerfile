# Use specific, pinned Alpine version for consistency and security
FROM alpine:3.22.2

LABEL org.opencontainers.image.title="argocd init container"
LABEL org.opencontainers.image.description="A container image that includes helm-secrets and addtional tools sops, argocd-vault-plugin, kubectl, helm, vals, age, yq, and curl."
LABEL org.opencontainers.image.version="v0.2.0-dirty"
LABEL org.opencontainers.image.licenses="Apache-2.0"
LABEL org.opencontainers.image.authors="Andres Martin Wendt"
LABEL org.opencontainers.image.source="https://github.com/anwendt/gitops-init"

USER 0

ARG VERSION_HELM=3.19.0
ARG VERSION_SOPS=3.10.2
ARG VERSION_VALS=0.41.2
ARG VERSION_KUBECTL=1.34.1
ARG VERSION_AGE=1.2.1
ARG VERSION_VAULT=1.18.1
ARG VERSION_HELMSECRETS=4.6.11
ARG VERSION_CURL=8.17.0
ARG VERSION_YQ=4.48.1

ENV HOME=/home/user/

RUN if [ "$(uname -m)" == "x86_64" ]; then CURL_ARCH=amd64; GO_ARCH=amd64; else CURL_ARCH="aarch64" GO_ARCH="arm64"; fi \
    && apk update \
    && apk upgrade \
    && apk add --no-cache gnupg git curl jq bash \
    && rm -rf /var/cache/apk/* \
    # Download and install sops
    && wget -qO /usr/local/bin/sops https://github.com/mozilla/sops/releases/download/v${VERSION_SOPS}/sops-v${VERSION_SOPS}.linux.${GO_ARCH} \
    # Download argocd-vault-plugin
    && wget -qO /usr/local/bin/argocd-vault-plugin https://github.com/argoproj-labs/argocd-vault-plugin/releases/download/v${VERSION_VAULT}/argocd-vault-plugin_${VERSION_VAULT}_linux_${GO_ARCH} \
    # Download kubectl
    && wget -qO /usr/local/bin/kubectl https://dl.k8s.io/release/v${VERSION_KUBECTL}/bin/linux/${GO_ARCH}/kubectl \
    # Download helm
    && wget -qO - https://get.helm.sh/helm-v${VERSION_HELM}-linux-${GO_ARCH}.tar.gz | tar xzvf - -C /usr/local/bin/ --strip-components 1 "linux-${GO_ARCH}/helm" \
    # Download vals
    && wget -qO - https://github.com/variantdev/vals/releases/download/v${VERSION_VALS}/vals_${VERSION_VALS}_linux_${GO_ARCH}.tar.gz | tar xzf - -C /usr/local/bin/ vals \
    # Download age
    && wget -qO - https://github.com/FiloSottile/age/releases/download/v${VERSION_AGE}/age-v${VERSION_AGE}-linux-${GO_ARCH}.tar.gz | tar xzf - -C /usr/local/bin/ age \
    # Download and install yq
    && wget -qO /usr/local/bin/yq https://github.com/mikefarah/yq/releases/download/${VERSION_YQ}/yq_linux_${GO_ARCH} \
    # Download helm-secrets
    && mkdir -p /opt/custom-tools/helm-plugins/ \
    && wget -qO - https://github.com/jkroepke/helm-secrets/releases/download/v${VERSION_HELMSECRETS}/helm-secrets.tar.gz | tar xzf - -C /opt/custom-tools/helm-plugins/ helm-secrets/scripts helm-secrets/plugin.yaml \
    && chmod +x /usr/local/bin/* \
    # Create user 1001
    && adduser -D -u 1001 -g 1001 user

USER 1001:1001
CMD ["/bin/sh"]
