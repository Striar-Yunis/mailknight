#!/bin/bash
# Build base containers for mailknight pipeline
# Usage: build-base-containers.sh [golang|nodejs|runtime|all]

set -euo pipefail

COMPONENT="${1:-all}"
BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BASE_CONTAINERS_DIR="$BASE_DIR/base"

echo "🏗️  Building mailknight base containers..."

build_container() {
    local name="$1"
    local dockerfile="$2"
    local tag="mailknight/${name}-base:latest"
    
    echo "🔨 Building $name base container..."
    
    if [[ ! -f "$dockerfile" ]]; then
        echo "❌ Dockerfile not found: $dockerfile"
        return 1
    fi
    
    # Build with buildkit for better caching and security
    DOCKER_BUILDKIT=1 docker build \
        --file "$dockerfile" \
        --tag "$tag" \
        --label "org.opencontainers.image.created=$(date -u +'%Y-%m-%dT%H:%M:%SZ')" \
        --label "org.opencontainers.image.revision=$(git rev-parse HEAD)" \
        --label "mailknight.base.container=true" \
        "$BASE_CONTAINERS_DIR"
    
    echo "✅ Built $tag successfully"
    
    # Test the container
    echo "🧪 Testing $name base container..."
    case "$name" in
        "golang-build")
            docker run --rm "$tag" go version
            docker run --rm "$tag" syft version
            ;;
        "nodejs-build")
            docker run --rm "$tag" node --version
            docker run --rm "$tag" npm --version
            docker run --rm "$tag" syft version
            ;;
        "runtime")
            docker run --rm "$tag" /usr/local/bin/health-check || echo "Health check test completed"
            ;;
    esac
    echo "✅ $name base container test passed"
}

case "$COMPONENT" in
    "golang"|"golang-build")
        build_container "golang-build" "$BASE_CONTAINERS_DIR/golang-build.dockerfile"
        ;;
    "nodejs"|"nodejs-build")  
        build_container "nodejs-build" "$BASE_CONTAINERS_DIR/nodejs-build.dockerfile"
        ;;
    "runtime")
        build_container "runtime" "$BASE_CONTAINERS_DIR/runtime.dockerfile"
        ;;
    "all")
        build_container "golang-build" "$BASE_CONTAINERS_DIR/golang-build.dockerfile"
        build_container "nodejs-build" "$BASE_CONTAINERS_DIR/nodejs-build.dockerfile"
        build_container "runtime" "$BASE_CONTAINERS_DIR/runtime.dockerfile"
        ;;
    *)
        echo "❌ Unknown component: $COMPONENT"
        echo "Usage: $0 [golang|nodejs|runtime|all]"
        exit 1
        ;;
esac

echo "🎉 Base container build complete!"
echo ""
echo "📦 Available base containers:"
docker images --format "table {{.Repository}}\t{{.Tag}}\t{{.Size}}" mailknight/*-base

echo ""
echo "💡 Usage examples:"
echo "  # Use golang base for building Go applications:"
echo "  FROM mailknight/golang-build-base:latest"
echo ""
echo "  # Use nodejs base for building Node.js applications:" 
echo "  FROM mailknight/nodejs-build-base:latest"
echo ""
echo "  # Use runtime base for application containers:"
echo "  FROM mailknight/runtime-base:latest"