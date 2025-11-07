#!/usr/bin/env bats

load 'test_helper'

IMAGE="${IMAGE:-awendt/argocdinit:latest-test}"

@test "sops binary exists in image" {
  run docker run --rm "$IMAGE" sh -c 'command -v sops'
  [ "$status" -eq 0 ]
}

@test "kubectl binary exists in image" {
  run docker run --rm "$IMAGE" sh -c 'command -v kubectl'
  [ "$status" -eq 0 ]
}

@test "helm binary exists in image" {
  run docker run --rm "$IMAGE" sh -c 'command -v helm'
  [ "$status" -eq 0 ]
}

@test "yq binary exists in image" {
  run docker run --rm "$IMAGE" sh -c 'command -v yq'
  [ "$status" -eq 0 ]
}

@test "vals binary exists in image" {
  run docker run --rm "$IMAGE" sh -c 'command -v vals'
  [ "$status" -eq 0 ]
}

@test "age binary exists in image" {
  run docker run --rm "$IMAGE" sh -c 'command -v age'
  [ "$status" -eq 0 ]
}

@test "helm-secrets plugin.yaml present" {
  run docker run --rm "$IMAGE" sh -c 'test -f /opt/custom-tools/helm-plugins/helm-secrets/plugin.yaml && echo ok'
  [ "$status" -eq 0 ]
}
