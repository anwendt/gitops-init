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
