#!/usr/bin/env bash
# check-runner-image-store.sh
#
# The e2e workflow's guard, run before `kind load docker-image`. kind's load
# imports what `docker save` writes with `--all-platforms`, and Docker's
# containerd image store writes an index naming every platform with only the
# host's manifest present (kind issue 3795), so the guard names the runner
# image (<ImageOS>/<ImageVersion>, the variables GitHub-hosted runners set)
# and the store before the load: one ::notice:: line with the image, the
# Docker server version and the storage driver. Exit 0 on the classic graph
# driver; exit 1 on the containerd image store (DriverStatus carries
# io.containerd.snapshotter), with one ::error:: line naming it.
set -euo pipefail

IMAGE_OS="${ImageOS:-unknown}"
IMAGE_VERSION="${ImageVersion:-unknown}"
SERVER_VERSION="$(docker version --format '{{.Server.Version}}')"
DRIVER="$(docker info --format '{{.Driver}}')"
DRIVER_STATUS="$(docker info --format '{{range .DriverStatus}}{{index . 0}}={{index . 1}};{{end}}')"

echo "::notice::e2e runner image ${IMAGE_OS}/${IMAGE_VERSION}, Docker ${SERVER_VERSION}, storage driver ${DRIVER}"

if [[ "$DRIVER_STATUS" == *io.containerd.snapshotter* ]]; then
  echo "::error::e2e runner image ${IMAGE_OS}/${IMAGE_VERSION}, Docker ${SERVER_VERSION}, runs the containerd image store; kind's load docker-image cannot import its docker save output (kind issue 3795). Pin the runner to an image with the graph driver, or move the probe step to docker save --platform linux/amd64 and kind load image-archive."
  exit 1
fi
