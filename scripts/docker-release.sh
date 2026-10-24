#!/usr/bin/env bash
set -euo pipefail

# Resolve paths relative to this script, so it works from any directory.
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

IMAGE_NAME="ansible-nginx-demo"
TEST_CONTAINER=""

cleanup() {
  if [[ -n "$TEST_CONTAINER" ]]; then
    docker rm -f "$TEST_CONTAINER" >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT

usage() {
  echo "Usage: bash scripts/docker-release.sh {build|test|package|publish} [image-tag]" >&2
  exit 2
}

require_version() {
  local version="${1:-}"
  if [[ ! "$version" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "Expected a version tag such as v1.0.0; got: '$version'" >&2
    exit 2
  fi
}

command="${1:-}"
tag="${2:-test}"

case "$command" in
  build)
    echo "Building ${IMAGE_NAME}:${tag}"
    docker build -t "${IMAGE_NAME}:${tag}" .
    ;;

  test)
    echo "Testing ${IMAGE_NAME}:${tag}"
    TEST_CONTAINER="nginx-test-${RANDOM}-$$"
    docker run -d --name "$TEST_CONTAINER" \
      -p 127.0.0.1:18080:80 "${IMAGE_NAME}:${tag}"

    for attempt in {1..10}; do
      if curl --fail --silent http://127.0.0.1:18080/ \
        | grep -Fq 'Deployed from GitHub Actions'; then
        echo 'Website test passed!'
        exit 0
      fi
      sleep 2
    done

    echo 'Website test failed. Container logs:' >&2
    docker logs "$TEST_CONTAINER" >&2
    exit 1
    ;;

  package)
    require_version "$tag"
    archive="${IMAGE_NAME}-${tag}.tar.gz"
    echo "Building and packaging ${IMAGE_NAME}:${tag}"
    docker build -t "${IMAGE_NAME}:${tag}" .
    docker save "${IMAGE_NAME}:${tag}" | gzip > "$archive"
    echo "Created $archive"
    ;;

  publish)
    require_version "$tag"
    archive="${IMAGE_NAME}-${tag}.tar.gz"
    [[ -f "$archive" ]] || { echo "Missing release archive: $archive" >&2; exit 1; }
    [[ -n "${GH_TOKEN:-}" ]] || { echo 'GH_TOKEN is not set' >&2; exit 1; }
    gh release create "$tag" "$archive" Dockerfile \
      --title "$tag" --generate-notes --verify-tag
    ;;

  *) usage ;;
esac
