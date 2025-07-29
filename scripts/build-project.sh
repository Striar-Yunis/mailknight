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
        echo "🏗️  Building ArgoCD with unified approach following upstream structure"
        
        # Ensure Go is available
        if ! command -v go &> /dev/null; then
            echo "❌ Go is not installed"
            exit 1
        fi
        
        # Set FIPS-compliant build environment (following upstream Makefile patterns)
        export CGO_ENABLED=1
        export GOOS=linux
        export GOARCH=amd64
        export CGO_CFLAGS="-fstack-protector-strong -D_FORTIFY_SOURCE=2 -O2"
        export CGO_LDFLAGS="-Wl,-z,relro,-z,now"
        export OPENSSL_FORCE_FIPS_MODE=1
        export GODEBUG="tarinsecurepath=0,zipinsecurepath=0"
        
        # Build with hardening flags using upstream Makefile targets
        BUILD_DATE=$(date -u +'%Y-%m-%dT%H:%M:%SZ')
        GIT_COMMIT=$(git rev-parse --short HEAD)
        GIT_TAG=${UPSTREAM_VERSION:-"unknown"}
        GIT_TREE_STATE=$(if [ -z "`git status --porcelain`" ]; then echo "clean" ; else echo "dirty"; fi)
        
        # Use upstream Makefile to build single argocd binary (this is the correct approach)
        echo "  Building single argocd binary using upstream Makefile..."
        make argocd-all \
            BUILD_DATE="$BUILD_DATE" \
            GIT_COMMIT="$GIT_COMMIT" \
            GIT_TAG="$GIT_TAG" \
            GIT_TREE_STATE="$GIT_TREE_STATE" \
            DIST_DIR="../../$BUILD_DIR" \
            BIN_NAME="argocd"
        
        # Create symlinks in build directory (following upstream pattern)
        echo "  Creating component symlinks..."
        cd "../../$BUILD_DIR"
        ln -sf argocd argocd-server
        ln -sf argocd argocd-repo-server
        ln -sf argocd argocd-cmp-server
        ln -sf argocd argocd-application-controller
        ln -sf argocd argocd-dex
        ln -sf argocd argocd-notifications
        ln -sf argocd argocd-applicationset-controller
        ln -sf argocd argocd-k8s-auth
        ln -sf argocd argocd-commit-server
        cd -
        
        # Build UI if present (following upstream pattern)
        if [[ -d "ui" && -f "ui/package.json" ]]; then
            echo "  Building UI..."
            cd ui
            # Use yarn like upstream does
            if command -v yarn &> /dev/null; then
                yarn install --network-timeout 200000
                NODE_ENV='production' NODE_ONLINE_ENV='online' NODE_OPTIONS=--max_old_space_size=8192 yarn build
            else
                npm ci --production
                npm run build:prod
            fi
            # Copy UI build output
            if [[ -d "dist/app" ]]; then
                mkdir -p "../../$BUILD_DIR/ui"
                cp -r dist/app "../../$BUILD_DIR/ui/"
            fi
            cd ..
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