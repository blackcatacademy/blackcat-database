#!/usr/bin/env bash
#
# Run GitHub Actions locally via the official act Docker image.
# Requires Docker daemon available (bind mounts /var/run/docker.sock).
#
# Usage:
#   ACT_IMAGE=ghcr.io/nektos/act:latest ACT_ARGS="-j phpstan" ./tools/run-actions-local.sh
#   ./tools/run-actions-local.sh -W .github/workflows/override-commands.yml
#
set -euo pipefail

WORKDIR="${WORKDIR:-$(pwd)}"
IMAGE="${ACT_IMAGE:-ghcr.io/nektos/act:latest}"

exec docker run --rm \
  -v "${WORKDIR}":/github/workspace \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -w /github/workspace \
  "${IMAGE}" "$@"
