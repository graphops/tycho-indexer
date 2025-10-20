#!/usr/bin/env bash
# Builds the tycho-indexer images while stripping the default TARGETPLATFORM
# assignment from the upstream Dockerfile on the fly.
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: build-tycho-graphops.sh [options]

Builds the base tycho-indexer image from the upstream Dockerfile using a sed
patch to drop the default TARGETPLATFORM assignment, then builds the
GraphOps-specific image on top.

Environment variables (can also be overridden via matching flags):
  BUILD_DOCKER_BIN           Container CLI to invoke (default: docker)
  BUILD_PLATFORM             Optional value passed to --platform (default: empty)
  BUILD_BASE_DOCKERFILE      Upstream Dockerfile path (default: Dockerfile)
  BUILD_BASE_CONTEXT         Build context directory for upstream Dockerfile (default: .)
  BUILD_UPSTREAM_STAGE_IMAGE Tag for the patched base image (default: localhost/tycho-indexer:upstream-stage)
  BUILD_GRAPHOPS_DOCKERFILE  GraphOps Dockerfile path (default: Dockerfile.graphops.yaml)
  BUILD_GRAPHOPS_CONTEXT     Build context directory for GraphOps Dockerfile (default: .)
  BUILD_RELEASE_IMAGE        Tag for the final release image (default: localhost/tycho-indexer:release)
  BUILD_PUSH                 Set to "true" to push the release image (default: false)

Options:
  --docker-bin PATH           Override container CLI (same as BUILD_DOCKER_BIN)
  --platform VALUE            Set --platform for both builds (same as BUILD_PLATFORM)
  --base-dockerfile PATH      Set upstream Dockerfile path
  --base-context PATH         Set upstream build context directory
  --upstream-stage-image TAG  Set tag for patched base image
  --graphops-dockerfile PATH  Set GraphOps Dockerfile path
  --graphops-context PATH     Set GraphOps build context directory
  --release-image TAG         Set tag for final release image
  --push                      Push the release image after building (same as BUILD_PUSH=true)
  -h, --help                  Show this message and exit
EOF
}

: "${BUILD_DOCKER_BIN:=docker}"
: "${BUILD_PLATFORM:=}"
: "${BUILD_BASE_DOCKERFILE:=Dockerfile}"
: "${BUILD_BASE_CONTEXT:=.}"
: "${BUILD_UPSTREAM_STAGE_IMAGE:=localhost/tycho-indexer:upstream-latest}"
: "${BUILD_GRAPHOPS_DOCKERFILE:=Dockerfile.graphops}"
: "${BUILD_GRAPHOPS_CONTEXT:=.}"
: "${BUILD_RELEASE_IMAGE:=harbor.mgmt.infra.graphops.xyz/infra/tycho-indexer:latest}"
: "${BUILD_PUSH:=false}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --docker-bin)
      [[ $# -lt 2 ]] && { echo "Missing value for $1" >&2; exit 1; }
      BUILD_DOCKER_BIN="$2"
      shift 2
      ;;
    --platform)
      [[ $# -lt 2 ]] && { echo "Missing value for $1" >&2; exit 1; }
      BUILD_PLATFORM="$2"
      shift 2
      ;;
    --base-dockerfile)
      [[ $# -lt 2 ]] && { echo "Missing value for $1" >&2; exit 1; }
      BUILD_BASE_DOCKERFILE="$2"
      shift 2
      ;;
    --base-context)
      [[ $# -lt 2 ]] && { echo "Missing value for $1" >&2; exit 1; }
      BUILD_BASE_CONTEXT="$2"
      shift 2
      ;;
    --upstream-stage-image)
      [[ $# -lt 2 ]] && { echo "Missing value for $1" >&2; exit 1; }
      BUILD_UPSTREAM_STAGE_IMAGE="$2"
      shift 2
      ;;
    --graphops-dockerfile)
      [[ $# -lt 2 ]] && { echo "Missing value for $1" >&2; exit 1; }
      BUILD_GRAPHOPS_DOCKERFILE="$2"
      shift 2
      ;;
    --graphops-context)
      [[ $# -lt 2 ]] && { echo "Missing value for $1" >&2; exit 1; }
      BUILD_GRAPHOPS_CONTEXT="$2"
      shift 2
      ;;
    --release-image)
      [[ $# -lt 2 ]] && { echo "Missing value for $1" >&2; exit 1; }
      BUILD_RELEASE_IMAGE="$2"
      shift 2
      ;;
    --push)
      BUILD_PUSH=true
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    --)
      shift
      break
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

log() {
  printf '[graphops-build] %s\n' "$*"
}

[[ -f "$BUILD_BASE_DOCKERFILE" ]] || { echo "Base Dockerfile not found: $BUILD_BASE_DOCKERFILE" >&2; exit 1; }
[[ -f "$BUILD_GRAPHOPS_DOCKERFILE" ]] || { echo "GraphOps Dockerfile not found: $BUILD_GRAPHOPS_DOCKERFILE" >&2; exit 1; }

platform_args=()
if [[ -n "$BUILD_PLATFORM" ]]; then
  platform_args+=(--platform "$BUILD_PLATFORM")
fi

log "Building base image ${BUILD_UPSTREAM_STAGE_IMAGE} from ${BUILD_BASE_DOCKERFILE}"
"$BUILD_DOCKER_BIN" build "${platform_args[@]}" \
  -t "$BUILD_UPSTREAM_STAGE_IMAGE" \
  -f <(sed 's/^ARG TARGETPLATFORM=.*/ARG TARGETPLATFORM/' "$BUILD_BASE_DOCKERFILE") \
  "$BUILD_BASE_CONTEXT"

log "Building release image ${BUILD_RELEASE_IMAGE} from ${BUILD_GRAPHOPS_DOCKERFILE} (base ${BUILD_UPSTREAM_STAGE_IMAGE})"
"$BUILD_DOCKER_BIN" build "${platform_args[@]}" \
  --build-arg "BASE_IMAGE=${BUILD_UPSTREAM_STAGE_IMAGE}" \
  -t "$BUILD_RELEASE_IMAGE" \
  -f "$BUILD_GRAPHOPS_DOCKERFILE" \
  "$BUILD_GRAPHOPS_CONTEXT"

normalize_bool() {
  local value="${1:-}"
  value="${value,,}"
  case "$value" in
    1|true|yes|on) return 0 ;;
    *) return 1 ;;
  esac
}

if normalize_bool "$BUILD_PUSH"; then
  log "Pushing release image ${BUILD_RELEASE_IMAGE}"
  "$BUILD_DOCKER_BIN" push "$BUILD_RELEASE_IMAGE"
fi

log "Build complete: ${BUILD_RELEASE_IMAGE}"
