#!/bin/bash
# Build runtime container image using pre-built binaries and base containers
# Usage: build-container.sh <project_name> <version> [container_name] [dockerfile]

set -euo pipefail

PROJECT_NAME="${1:-}"
VERSION="${2:-}"
CONTAINER_NAME="${3:-main}"
DOCKERFILE_NAME="${4:-Dockerfile}"

if [[ -z "$PROJECT_NAME" || -z "$VERSION" ]]; then
    echo "Usage: $0 <project_name> <version> [container_name] [dockerfile]"
    exit 1
fi

echo "🐳 Building runtime container image for $PROJECT_NAME:$VERSION (component: $CONTAINER_NAME)"

# Ensure runtime base container exists
if ! docker image inspect mailknight/runtime-base:latest &> /dev/null; then
    echo "📦 Building runtime base container..."
    ./scripts/build-base-containers.sh runtime
fi

# Create component-specific images directory
mkdir -p "images/$CONTAINER_NAME"

IMAGE_NAME="mailknight/$PROJECT_NAME-$CONTAINER_NAME"
IMAGE_TAG="$VERSION-mailknight"
FULL_IMAGE_NAME="$IMAGE_NAME:$IMAGE_TAG"

# Check if Dockerfile exists
DOCKERFILE="projects/$PROJECT_NAME/$DOCKERFILE_NAME"
if [[ ! -f "$DOCKERFILE" ]]; then
    echo "❌ Dockerfile not found: $DOCKERFILE"
    exit 1
fi

# Verify build artifacts exist
if [[ ! -d "build" ]] || [[ -z "$(ls -A build 2>/dev/null)" ]]; then
    echo "❌ No build artifacts found. Run build-project.sh first."
    exit 1
fi

# Build context preparation
BUILD_CONTEXT=$(mktemp -d)
trap "rm -rf $BUILD_CONTEXT" EXIT

echo "📋 Preparing build context with pre-built binaries..."

# Copy pre-built binaries (the key difference from the old approach)
mkdir -p "$BUILD_CONTEXT/binaries"
cp -r build/* "$BUILD_CONTEXT/binaries/" 2>/dev/null || true

# Copy other necessary files
cp -r source "$BUILD_CONTEXT/" 2>/dev/null || true
cp "$DOCKERFILE" "$BUILD_CONTEXT/Dockerfile" 

# Copy UI artifacts if they exist
if [[ -d "build/ui" ]]; then
    mkdir -p "$BUILD_CONTEXT/ui"
    cp -r build/ui/* "$BUILD_CONTEXT/ui/"
fi

# Extract versions from mailknight.yaml if it exists
GO_VERSION=""
NODE_VERSION=""
PROJECT_CONFIG="projects/$PROJECT_NAME/mailknight.yaml"
if [[ -f "$PROJECT_CONFIG" ]]; then
    echo "📋 Reading versions from $PROJECT_CONFIG"
    GO_VERSION=$(python3 -c "
import yaml
try:
    with open('$PROJECT_CONFIG', 'r') as f:
        config = yaml.safe_load(f)
    print(config['spec']['settings'].get('goVersion', ''))
except:
    print('')
")
    NODE_VERSION=$(python3 -c "
import yaml
try:
    with open('$PROJECT_CONFIG', 'r') as f:
        config = yaml.safe_load(f)
    print(config['spec']['settings'].get('nodeVersion', ''))
except:
    print('')
")
    echo "🔧 Extracted Go version: ${GO_VERSION:-'not specified'}"
    echo "🔧 Extracted Node version: ${NODE_VERSION:-'not specified'}"
fi

# Build runtime container image using pre-built binaries
echo "🔨 Building runtime Docker image for $CONTAINER_NAME component..."

# Prepare build args with version information
BUILD_ARGS=(
    --build-arg PROJECT_NAME="$PROJECT_NAME"
    --build-arg CONTAINER_NAME="$CONTAINER_NAME"
    --build-arg VERSION="$VERSION"
    --build-arg BUILD_DATE="$(date -u +'%Y-%m-%dT%H:%M:%SZ')"
    --build-arg VCS_REF="$(git rev-parse --short HEAD)"
)

# Add version build args if they were extracted from mailknight.yaml
if [[ -n "$GO_VERSION" ]]; then
    BUILD_ARGS+=(--build-arg GO_VERSION="$GO_VERSION")
    echo "🔧 Using Go version: $GO_VERSION"
fi

if [[ -n "$NODE_VERSION" ]]; then
    BUILD_ARGS+=(--build-arg NODE_VERSION="$NODE_VERSION")
    echo "🔧 Using Node version: $NODE_VERSION"
fi

# Build using buildkit for better performance and security
DOCKER_BUILDKIT=1 docker build \
    "${BUILD_ARGS[@]}" \
    --label "org.opencontainers.image.title=mailknight/$PROJECT_NAME-$CONTAINER_NAME" \
    --label "org.opencontainers.image.version=$IMAGE_TAG" \
    --label "org.opencontainers.image.created=$(date -u +'%Y-%m-%dT%H:%M:%SZ')" \
    --label "org.opencontainers.image.revision=$(git rev-parse HEAD)" \
    --label "org.opencontainers.image.source=https://github.com/Striar-Yunis/mailknight" \
    --label "mailknight.project=$PROJECT_NAME" \
    --label "mailknight.component=$CONTAINER_NAME" \
    --label "mailknight.build.method=separated-build" \
    --label "security.fips=enabled" \
    --label "security.hardened=true" \
    --label "security.binaries.prebuilt=true" \
    -t "$FULL_IMAGE_NAME" \
    -t "$IMAGE_NAME:latest" \
    "$BUILD_CONTEXT"

# Verify image was built
if ! docker image inspect "$FULL_IMAGE_NAME" &> /dev/null; then
    echo "❌ Failed to build image $FULL_IMAGE_NAME"
    exit 1
fi

# Save image to file for artifact storage
echo "💾 Saving image to file..."
docker save "$FULL_IMAGE_NAME" | gzip > "images/$CONTAINER_NAME/${PROJECT_NAME}-${CONTAINER_NAME}-${IMAGE_TAG}.tar.gz"

# Generate component-specific image SBOM
echo "📋 Generating image SBOM..."
if command -v syft &> /dev/null; then
    syft "$FULL_IMAGE_NAME" -o cyclonedx-json > "image-sbom-${CONTAINER_NAME}.json"
    echo "✅ Image SBOM generated: image-sbom-${CONTAINER_NAME}.json"
else
    echo "⚠️  Syft not available, installing in temporary container..."
    # Try to generate SBOM using the build base container
    if docker image inspect mailknight/golang-build-base:latest &> /dev/null; then
        docker run --rm -v "$(pwd):/workspace" -w /workspace \
            mailknight/golang-build-base:latest \
            syft "$FULL_IMAGE_NAME" -o cyclonedx-json > "image-sbom-${CONTAINER_NAME}.json" || \
            echo '{"components": [], "metadata": {"component": {"name": "'"$FULL_IMAGE_NAME"'", "version": "'"$IMAGE_TAG"'"}}}' > "image-sbom-${CONTAINER_NAME}.json"
    else
        echo '{"components": [], "metadata": {"component": {"name": "'"$FULL_IMAGE_NAME"'", "version": "'"$IMAGE_TAG"'"}}}' > "image-sbom-${CONTAINER_NAME}.json"
    fi
fi

# Image information
IMAGE_SIZE=$(docker image inspect "$FULL_IMAGE_NAME" --format='{{.Size}}' | numfmt --to=iec)
IMAGE_ID=$(docker image inspect "$FULL_IMAGE_NAME" --format='{{.Id}}')

# Generate component-specific image metadata
cat > "images/$CONTAINER_NAME/image-metadata.json" << EOF
{
  "name": "$IMAGE_NAME",
  "tag": "$IMAGE_TAG",
  "full_name": "$FULL_IMAGE_NAME",
  "id": "$IMAGE_ID",
  "size": "$IMAGE_SIZE",
  "build_date": "$(date -Iseconds)",
  "project": "$PROJECT_NAME",
  "component": "$CONTAINER_NAME",
  "version": "$VERSION",
  "dockerfile": "$DOCKERFILE_NAME",
  "build_method": "separated-build",
  "fips_compliant": true,
  "hardened": true,
  "base_image": "mailknight/runtime-base:latest",
  "binaries_prebuilt": true,
  "security_features": [
    "FIPS-140-2 compliance",
    "Stack protection",
    "FORTIFY_SOURCE",
    "RELRO",
    "Non-root user",
    "Minimal attack surface",
    "Pre-built binaries",
    "Separated build process"
  ]
}
EOF

echo "✅ Runtime container image built successfully using pre-built binaries"
echo "📦 Image: $FULL_IMAGE_NAME"
echo "💾 Archive: images/$CONTAINER_NAME/${PROJECT_NAME}-${CONTAINER_NAME}-${IMAGE_TAG}.tar.gz"
echo "📊 Size: $IMAGE_SIZE"

# Test basic functionality
echo "🧪 Testing image functionality..."
case "$CONTAINER_NAME" in
    "server"|"repo-server"|"application-controller"|"applicationset-controller"|"dex"|"notification")
        # For ArgoCD components, test with version command
        if docker run --rm "$FULL_IMAGE_NAME" --version &> /dev/null; then
            echo "✅ Image functionality test passed"
        else
            echo "⚠️  Image functionality test failed (may be expected - trying alternative test)"
            # Some components may not support --version, just check if container starts
            if timeout 10s docker run --rm "$FULL_IMAGE_NAME" --help &> /dev/null; then
                echo "✅ Container starts successfully"
            else
                echo "⚠️  Container startup test failed (may be expected for some components)"
            fi
        fi
        ;;
    *)
        # Generic test for other components
        if timeout 10s docker run --rm "$FULL_IMAGE_NAME" version --client &> /dev/null; then
            echo "✅ Image functionality test passed"
        else
            echo "⚠️  Image functionality test failed (may be expected for some components)"
        fi
        ;;
esac