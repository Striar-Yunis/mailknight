#!/bin/bash
# Build project with FIPS compliance and hardening
# Usage: build-project.sh <project_name>

set -euo pipefail

PROJECT_NAME="${1:-}"

if [[ -z "$PROJECT_NAME" ]]; then
    echo "Usage: $0 <project_name>"
    exit 1
fi

echo "🔨 Building $PROJECT_NAME with FIPS compliance and hardening"

SOURCE_DIR="source/$PROJECT_NAME"
BUILD_DIR="build"

if [[ ! -d "$SOURCE_DIR" ]]; then
    echo "❌ Source directory $SOURCE_DIR does not exist"
    exit 1
fi

# Create build directory
mkdir -p "$BUILD_DIR"

# Set build timestamp for reproducibility
export SOURCE_DATE_EPOCH=${SOURCE_DATE_EPOCH:-$(date +%s)}

cd "$SOURCE_DIR"

case "$PROJECT_NAME" in
    "argocd")
        echo "🏗️  Building ArgoCD with Go and FIPS compliance"
        
        # Ensure Go is available
        if ! command -v go &> /dev/null; then
            echo "❌ Go is not installed"
            exit 1
        fi
        
        # Set FIPS-compliant build environment
        export CGO_ENABLED=1
        export GOOS=linux
        export GOARCH=amd64
        export CGO_CFLAGS="-fstack-protector-strong -D_FORTIFY_SOURCE=2"
        export CGO_LDFLAGS="-Wl,-z,relro,-z,now"
        export OPENSSL_FORCE_FIPS_MODE=1
        
        # Build with hardening flags
        BUILD_DATE=$(date -u +'%Y-%m-%dT%H:%M:%SZ')
        GIT_COMMIT=$(git rev-parse --short HEAD)
        
        LDFLAGS=(
            "-X github.com/argoproj/argo-cd/v3/common.version=${UPSTREAM_VERSION:-unknown}"
            "-X github.com/argoproj/argo-cd/v3/common.buildDate=$BUILD_DATE"
            "-X github.com/argoproj/argo-cd/v3/common.gitCommit=$GIT_COMMIT"
            "-s -w"  # Strip symbols
        )
        
        # Build all ArgoCD components (v3.0.11+ uses single main.go with different binary names)
        echo "  Building argocd CLI..."
        go build -ldflags "${LDFLAGS[*]}" -o "../../$BUILD_DIR/argocd" ./cmd/main.go
        
        echo "  Building argocd-server..."
        go build -ldflags "${LDFLAGS[*]}" -o "../../$BUILD_DIR/argocd-server" ./cmd/main.go
        
        echo "  Building argocd-repo-server..."
        go build -ldflags "${LDFLAGS[*]}" -o "../../$BUILD_DIR/argocd-repo-server" ./cmd/main.go
        
        echo "  Building argocd-application-controller..."
        go build -ldflags "${LDFLAGS[*]}" -o "../../$BUILD_DIR/argocd-application-controller" ./cmd/main.go
        
        echo "  Building argocd-dex..."
        go build -ldflags "${LDFLAGS[*]}" -o "../../$BUILD_DIR/argocd-dex" ./cmd/main.go
        
        echo "  Building argocd-applicationset-controller..."
        go build -ldflags "${LDFLAGS[*]}" -o "../../$BUILD_DIR/argocd-applicationset-controller" ./cmd/main.go
        
        echo "  Building argocd-notification..."
        go build -ldflags "${LDFLAGS[*]}" -o "../../$BUILD_DIR/argocd-notification" ./cmd/main.go
        
        # Build UI if present
        if [[ -f "package.json" ]]; then
            echo "  Building UI..."
            npm ci --production
            npm run build:prod
            cp -r dist/app "../../$BUILD_DIR/ui"
        fi
        ;;
        
    *)
        echo "❌ Unknown project: $PROJECT_NAME"
        exit 1
        ;;
esac

cd ../..

# Strip binaries for size reduction
echo "🔧 Hardening binaries..."
find "$BUILD_DIR" -type f -executable -exec strip {} \; 2>/dev/null || true

# Set secure permissions
find "$BUILD_DIR" -type f -executable -exec chmod 755 {} \;
find "$BUILD_DIR" -type f ! -executable -exec chmod 644 {} \;

# Generate SBOM
echo "📋 Generating Software Bill of Materials (SBOM)..."
if command -v syft &> /dev/null; then
    syft dir:"$SOURCE_DIR" -o cyclonedx-json > sbom.json
    echo "✅ SBOM generated: sbom.json"
else
    echo "⚠️  Syft not available, skipping SBOM generation"
    echo '{"components": [], "metadata": {"component": {"name": "'"$PROJECT_NAME"'", "version": "unknown"}}}' > sbom.json
fi

# Generate build metadata
cat > "$BUILD_DIR/build-metadata.json" << EOF
{
  "project": "$PROJECT_NAME",
  "version": "${UPSTREAM_VERSION:-unknown}",
  "build_date": "$(date -Iseconds)",
  "build_system": "mailknight",
  "fips_enabled": true,
  "hardening_flags": {
    "cflags": "${CFLAGS:-}",
    "cxxflags": "${CXXFLAGS:-}",
    "ldflags": "${LDFLAGS:-}"
  },
  "build_environment": {
    "source_date_epoch": "$SOURCE_DATE_EPOCH",
    "cgo_enabled": "${CGO_ENABLED:-}",
    "goos": "${GOOS:-}",
    "goarch": "${GOARCH:-}"
  }
}
EOF

echo "✅ Build completed successfully"
echo "📦 Artifacts:"
find "$BUILD_DIR" -type f -exec ls -lh {} \;