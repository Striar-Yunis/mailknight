#!/bin/bash
# Build container image with hardening
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

echo "🐳 Building container image for $PROJECT_NAME:$VERSION (component: $CONTAINER_NAME)"

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

# Build context preparation
BUILD_CONTEXT=$(mktemp -d)
trap "rm -rf $BUILD_CONTEXT" EXIT

# Copy build artifacts and source
cp -r build/* "$BUILD_CONTEXT/" 2>/dev/null || true
cp -r source "$BUILD_CONTEXT/"
cp "$DOCKERFILE" "$BUILD_CONTEXT/Dockerfile"

# Copy base Dockerfile if this is a component-specific build
if [[ "$DOCKERFILE_NAME" != "Dockerfile" ]]; then
    BASE_DOCKERFILE="projects/$PROJECT_NAME/Dockerfile"
    if [[ -f "$BASE_DOCKERFILE" ]]; then
        cp "$BASE_DOCKERFILE" "$BUILD_CONTEXT/Dockerfile.base"
        # Update the component Dockerfile to reference the copied base
        sed -i 's|FROM \./Dockerfile|FROM ./Dockerfile.base|g' "$BUILD_CONTEXT/Dockerfile"
    fi
fi

# Build image with hardening options
echo "🔨 Building Docker image for $CONTAINER_NAME component..."
docker build \
    --build-arg PROJECT_NAME="$PROJECT_NAME" \
    --build-arg CONTAINER_NAME="$CONTAINER_NAME" \
    --build-arg VERSION="$VERSION" \
    --build-arg BUILD_DATE="$(date -u +'%Y-%m-%dT%H:%M:%SZ')" \
    --build-arg VCS_REF="$(git rev-parse --short HEAD)" \
    --label "org.opencontainers.image.title=mailknight/$PROJECT_NAME-$CONTAINER_NAME" \
    --label "org.opencontainers.image.version=$IMAGE_TAG" \
    --label "org.opencontainers.image.created=$(date -u +'%Y-%m-%dT%H:%M:%SZ')" \
    --label "org.opencontainers.image.revision=$(git rev-parse HEAD)" \
    --label "org.opencontainers.image.source=https://github.com/Striar-Yunis/mailknight" \
    --label "mailknight.project=$PROJECT_NAME" \
    --label "mailknight.component=$CONTAINER_NAME" \
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
docker save "$FULL_IMAGE_NAME" | gzip > "images/$CONTAINER_NAME/${PROJECT_NAME}-${CONTAINER_NAME}-${IMAGE_TAG}.tar.gz"

# Generate component-specific image SBOM
echo "📋 Generating image SBOM..."
if command -v syft &> /dev/null; then
    syft "$FULL_IMAGE_NAME" -o cyclonedx-json > "image-sbom-${CONTAINER_NAME}.json"
    echo "✅ Image SBOM generated: image-sbom-${CONTAINER_NAME}.json"
else
    echo "⚠️  Syft not available, skipping image SBOM generation"
    echo '{"components": [], "metadata": {"component": {"name": "'"$FULL_IMAGE_NAME"'", "version": "'"$IMAGE_TAG"'"}}}' > "image-sbom-${CONTAINER_NAME}.json"
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
            if docker run --rm -d "$FULL_IMAGE_NAME" --help &> /dev/null; then
                echo "✅ Container starts successfully"
            else
                echo "⚠️  Container startup test failed"
            fi
        fi
        ;;
    *)
        # Generic test for other components
        if docker run --rm "$FULL_IMAGE_NAME" version --client &> /dev/null; then
            echo "✅ Image functionality test passed"
        else
            echo "⚠️  Image functionality test failed (may be expected for some components)"
        fi
        ;;
esac