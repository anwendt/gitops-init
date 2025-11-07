#!/usr/bin/env bash
set -eu

IMAGE="$1"
echo "Running container smoke tests for image: $IMAGE"

MISSING=0
check_bin() {
  local bin="$1"
  echo -n "- Checking ${bin}... "
  if docker run --rm "$IMAGE" sh -c "command -v ${bin} >/dev/null 2>&1"; then
    echo "present"
  else
    echo "MISSING"
    MISSING=1
  fi
}

check_bin sops
check_bin kubectl
check_bin helm
check_bin yq
check_bin vals
check_bin age

echo
if [ "$MISSING" -ne 0 ]; then
  echo "One or more required binaries are missing in the image." >&2
  exit 2
fi

echo "Basic runtime checks: invoking --version where available"
docker run --rm "$IMAGE" sh -c "sops --version || true; kubectl version --client --short || true; helm version --short || true; yq --version || true"

echo "All smoke tests passed."

echo "Running sops age roundtrip inside container"
docker run --rm "$IMAGE" sh -c '
  set -e
  TMPDIR="/tmp/sops-test"
  mkdir -p "$TMPDIR"
  cd "$TMPDIR"
  age-keygen -o key.txt
  PUB=$$(age-keygen -y key.txt)
  printf "secret: secretvalue\n" > plain.yaml
  sops --encrypt --age "$$PUB" plain.yaml > enc.yaml
  sops --decrypt enc.yaml > dec.yaml
  cmp -s plain.yaml dec.yaml
'

echo "Running helm template render test inside container"
docker run --rm "$IMAGE" sh -c '
  set -e
  CHARTDIR="/tmp/chart"
  mkdir -p "$CHARTDIR/templates"
  cat > "$CHARTDIR/Chart.yaml" <<'EOF'
apiVersion: v2
name: testchart
version: 0.1.0
EOF
  cat > "$CHARTDIR/values.yaml" <<'EOF'
replicaCount: 1
EOF
  cat > "$CHARTDIR/templates/deployment.yaml" <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: {{ include "testchart.fullname" . }}
spec:
  replicas: {{ .Values.replicaCount }}
  template:
    spec:
      containers:
        - name: app
          image: busybox
EOF
  helm template "$CHARTDIR" --debug --values "$CHARTDIR/values.yaml" >/dev/null
'

echo "Smoke + functional tests completed successfully."
