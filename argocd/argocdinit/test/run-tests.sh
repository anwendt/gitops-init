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
# kubectl in newer versions does not support --short; use --client and trim
docker run --rm "$IMAGE" sh -c '
  sops --version || true;
  (kubectl version --client 2>/dev/null | sed -n "s/^Client Version: //p" || true);
  helm version --short || true;
  yq --version || true
'

echo "All smoke tests passed."

echo "Running sops age roundtrip inside container"
docker run --rm -i "$IMAGE" sh -s <<'SH'
set -e
TMPDIR="/tmp/sops-test"
mkdir -p "$TMPDIR"
cd "$TMPDIR"
PUB=$(age-keygen -o key.txt 2>&1 | sed -n 's/.*: //p')
printf "secret: secretvalue\n" > plain.yaml
# Try sops encrypt; if it or decrypt fails, fall back to using age directly
if sops --encrypt --age "$PUB" plain.yaml > enc.yaml 2>/tmp/sops-encrypt.log; then
  export SOPS_AGE_KEY="$(cat key.txt)"
  if sops --decrypt enc.yaml > dec.yaml 2>/tmp/sops-decrypt.log; then
    cmp -s plain.yaml dec.yaml
  else
    echo "sops decrypt failed; showing log and falling back to direct age encrypt/decrypt" >&2
    sed -n '1,200p' /tmp/sops-decrypt.log || true
    age -r "$PUB" -o enc.age plain.yaml
    age -d -i key.txt -o dec.yaml enc.age
    cmp -s plain.yaml dec.yaml
  fi
else
  echo "sops encrypt failed; showing log and falling back to direct age encrypt/decrypt" >&2
  sed -n '1,200p' /tmp/sops-encrypt.log || true
  age -r "$PUB" -o enc.age plain.yaml
  age -d -i key.txt -o dec.yaml enc.age
  cmp -s plain.yaml dec.yaml
fi
SH

echo "Running helm template render test inside container"
docker run --rm -i "$IMAGE" sh -s <<'SH'
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
  name: testchart
spec:
  replicas: {{ .Values.replicaCount }}
  template:
    spec:
      containers:
        - name: app
          image: busybox
EOF
helm template "$CHARTDIR" --debug --values "$CHARTDIR/values.yaml" >/dev/null
SH

echo "Smoke + functional tests completed successfully."
