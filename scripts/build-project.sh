#!/bin/bash
# Build project binaries using base containers with FIPS compliance and hardening
# Usage: build-project.sh <project_name>

set -euo pipefail

PROJECT_NAME="${1:-}"

if [[ -z "$PROJECT_NAME" ]]; then
    echo "Usage: $0 <project_name>"
    exit 1
fi

echo "🔨 Building $PROJECT_NAME binaries using base containers with FIPS compliance and hardening"

SOURCE_DIR="source/$PROJECT_NAME"
BUILD_DIR="build"

if [[ ! -d "$SOURCE_DIR" ]]; then
    echo "❌ Source directory $SOURCE_DIR does not exist"
    exit 1
fi

# Create build directory
mkdir -p "$BUILD_DIR"

# Ensure base containers are available
echo "🏗️  Ensuring base containers are available..."
if ! docker image inspect mailknight/golang-build-base:latest &> /dev/null; then
    echo "📦 Building golang base container..."
    ./scripts/build-base-containers.sh golang
fi

if ! docker image inspect mailknight/nodejs-build-base:latest &> /dev/null; then
    echo "📦 Building nodejs base container..."
    ./scripts/build-base-containers.sh nodejs
fi

# Set build timestamp for reproducibility
export SOURCE_DATE_EPOCH=${SOURCE_DATE_EPOCH:-$(date +%s)}

case "$PROJECT_NAME" in
    "argocd")
        echo "🏗️  Building ArgoCD using base containers with FIPS compliance"
        
        # Use the dedicated binary builder Dockerfile
        DOCKERFILE="projects/$PROJECT_NAME/Dockerfile"
        
        # Build using the multi-stage Dockerfile that uses base containers
        echo "🔨 Building ArgoCD binaries with base containers..."
        DOCKER_BUILDKIT=1 docker build \
            --file "$DOCKERFILE" \
            --target artifacts \
            --build-arg ARGO_VERSION="${UPSTREAM_VERSION:-v3.0.11}" \
            --build-arg BUILD_DATE="$(date -u +'%Y-%m-%dT%H:%M:%SZ')" \
            --build-arg GIT_COMMIT="$(git rev-parse --short HEAD)" \
            --build-arg GIT_TAG="${UPSTREAM_VERSION:-unknown}" \
            --build-arg GIT_TREE_STATE="clean" \
            --tag "mailknight/$PROJECT_NAME-builder:latest" \
            .
        
        # Extract built artifacts from the container
        echo "📦 Extracting built artifacts..."
        TEMP_CONTAINER=$(docker create "mailknight/$PROJECT_NAME-builder:latest")
        
        # Clean and recreate build directory
        rm -rf "$BUILD_DIR"
        mkdir -p "$BUILD_DIR"
        
        # Extract binaries, UI, and SBOM
        docker cp "$TEMP_CONTAINER:/binaries/" "$BUILD_DIR/" 2>/dev/null || true
        docker cp "$TEMP_CONTAINER:/ui/" "$BUILD_DIR/" 2>/dev/null || true  
        docker cp "$TEMP_CONTAINER:/sbom.json" ./sbom.json 2>/dev/null || true
        
        # Clean up temporary container
        docker rm "$TEMP_CONTAINER"
        
        # Move binaries out of subdirectory if needed
        if [[ -d "$BUILD_DIR/binaries" ]]; then
            mv "$BUILD_DIR/binaries/"* "$BUILD_DIR/"
            rmdir "$BUILD_DIR/binaries"
        fi
        
        echo "✅ ArgoCD binaries built successfully using base containers"
        ;;
        
    *)
        echo "❌ Unknown project: $PROJECT_NAME"
        exit 1
        ;;
esac

# Verify binaries were created
echo "🔍 Verifying built binaries..."
if [[ ! -d "$BUILD_DIR" ]] || [[ -z "$(ls -A "$BUILD_DIR" 2>/dev/null)" ]]; then
    echo "❌ No binaries found in build directory"
    exit 1
fi

# Generate build metadata
cat > "$BUILD_DIR/build-metadata.json" << EOF
{
  "project": "$PROJECT_NAME",
  "version": "${UPSTREAM_VERSION:-unknown}",
  "build_date": "$(date -Iseconds)",
  "build_system": "mailknight-base-containers",
  "fips_enabled": true,
  "build_method": "base-containers",
  "base_containers": {
    "golang": "mailknight/golang-build-base:latest",
    "nodejs": "mailknight/nodejs-build-base:latest"
  },
  "hardening_flags": {
    "cflags": "${CFLAGS:-}",
    "cxxflags": "${CXXFLAGS:-}",
    "ldflags": "${LDFLAGS:-}"
  },
  "build_environment": {
    "source_date_epoch": "$SOURCE_DATE_EPOCH",
    "cgo_enabled": "1",
    "goos": "linux",
    "goarch": "amd64"
  }
}
EOF

echo "✅ Build completed successfully using base containers"
echo "📦 Artifacts:"
find "$BUILD_DIR" -type f -exec ls -lh {} \;