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
# driver.
set -euo pipefail

IMAGE_OS="${ImageOS:-unknown}"
IMAGE_VERSION="${ImageVersion:-unknown}"
SERVER_VERSION="$(docker version --format '{{.Server.Version}}')"
DRIVER="$(docker info --format '{{.Driver}}')"
# Read by the containerd image store check of a later slice.
# shellcheck disable=SC2034
DRIVER_STATUS="$(docker info --format '{{range .DriverStatus}}{{index . 0}}={{index . 1}};{{end}}')"

echo "::notice::e2e runner image ${IMAGE_OS}/${IMAGE_VERSION}, Docker ${SERVER_VERSION}, storage driver ${DRIVER}"
