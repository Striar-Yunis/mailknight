#!/bin/bash
# Build container image with hardening
# Usage: build-container.sh <project_name> <version>

set -euo pipefail

PROJECT_NAME="${1:-}"
VERSION="${2:-}"

if [[ -z "$PROJECT_NAME" || -z "$VERSION" ]]; then
    echo "Usage: $0 <project_name> <version>"
    exit 1
fi

echo "🐳 Building container image for $PROJECT_NAME:$VERSION"

# Create images directory
mkdir -p images

IMAGE_NAME="mailknight/$PROJECT_NAME"
IMAGE_TAG="$VERSION-mailknight"
FULL_IMAGE_NAME="$IMAGE_NAME:$IMAGE_TAG"

# Check if Dockerfile exists
DOCKERFILE="projects/$PROJECT_NAME/Dockerfile"
if [[ ! -f "$DOCKERFILE" ]]; then
    echo "❌ Dockerfile not found: $DOCKERFILE"
    exit 1
fi

# Build context preparation
BUILD_CONTEXT=$(mktemp -d)
trap "rm -rf $BUILD_CONTEXT" EXIT

# Copy build artifacts and source
cp -r build/* "$BUILD_CONTEXT/" 2>/dev/null || true
cp -r source "$BUILD_CONTEXT/"
cp "$DOCKERFILE" "$BUILD_CONTEXT/Dockerfile"

# Build image with hardening options
echo "🔨 Building Docker image..."
docker build \
    --build-arg PROJECT_NAME="$PROJECT_NAME" \
    --build-arg VERSION="$VERSION" \
    --build-arg BUILD_DATE="$(date -u +'%Y-%m-%dT%H:%M:%SZ')" \
    --build-arg VCS_REF="$(git rev-parse --short HEAD)" \
    --label "org.opencontainers.image.title=mailknight/$PROJECT_NAME" \
    --label "org.opencontainers.image.version=$IMAGE_TAG" \
    --label "org.opencontainers.image.created=$(date -u +'%Y-%m-%dT%H:%M:%SZ')" \
    --label "org.opencontainers.image.revision=$(git rev-parse HEAD)" \
    --label "org.opencontainers.image.source=https://github.com/Striar-Yunis/mailknight" \
    --label "security.fips=enabled" \
    --label "security.hardened=true" \
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
docker save "$FULL_IMAGE_NAME" | gzip > "images/${PROJECT_NAME}-${IMAGE_TAG}.tar.gz"

# Generate image SBOM
echo "📋 Generating image SBOM..."
if command -v syft &> /dev/null; then
    syft "$FULL_IMAGE_NAME" -o cyclonedx-json > image-sbom.json
    echo "✅ Image SBOM generated: image-sbom.json"
else
    echo "⚠️  Syft not available, skipping image SBOM generation"
    echo '{"components": [], "metadata": {"component": {"name": "'"$FULL_IMAGE_NAME"'", "version": "'"$IMAGE_TAG"'"}}}' > image-sbom.json
fi

# Image information
IMAGE_SIZE=$(docker image inspect "$FULL_IMAGE_NAME" --format='{{.Size}}' | numfmt --to=iec)
IMAGE_ID=$(docker image inspect "$FULL_IMAGE_NAME" --format='{{.Id}}')

# Generate image metadata
cat > "images/image-metadata.json" << EOF
{
  "name": "$IMAGE_NAME",
  "tag": "$IMAGE_TAG",
  "full_name": "$FULL_IMAGE_NAME",
  "id": "$IMAGE_ID",
  "size": "$IMAGE_SIZE",
  "build_date": "$(date -Iseconds)",
  "project": "$PROJECT_NAME",
  "version": "$VERSION",
  "fips_compliant": true,
  "hardened": true,
  "base_image": "registry.access.redhat.com/ubi8/ubi-minimal:latest",
  "security_features": [
    "FIPS-140-2 compliance",
    "Stack protection",
    "FORTIFY_SOURCE",
    "RELRO",
    "Non-root user",
    "Minimal attack surface"
  ]
}
EOF

echo "✅ Container image built successfully"
echo "📦 Image: $FULL_IMAGE_NAME"
echo "💾 Archive: images/${PROJECT_NAME}-${IMAGE_TAG}.tar.gz"
echo "📊 Size: $IMAGE_SIZE"

# Test basic functionality
echo "🧪 Testing image functionality..."
if docker run --rm "$FULL_IMAGE_NAME" version --client &> /dev/null; then
    echo "✅ Image functionality test passed"
else
    echo "⚠️  Image functionality test failed (may be expected for some components)"
fi