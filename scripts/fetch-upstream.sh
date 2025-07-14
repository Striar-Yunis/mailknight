#!/bin/bash
# Fetch upstream source code for a project
# Usage: fetch-upstream.sh <project_name> <version>

set -euo pipefail

PROJECT_NAME="${1:-}"
VERSION="${2:-}"

if [[ -z "$PROJECT_NAME" || -z "$VERSION" ]]; then
    echo "Usage: $0 <project_name> <version>"
    exit 1
fi

echo "📥 Fetching upstream source for $PROJECT_NAME version $VERSION"

# Create source directory
mkdir -p source
cd source

case "$PROJECT_NAME" in
    "argocd")
        REPO_URL="https://github.com/argoproj/argo-cd.git"
        ;;
    "crossplane")
        REPO_URL="https://github.com/crossplane/crossplane.git"
        ;;
    "cert-manager")
        REPO_URL="https://github.com/cert-manager/cert-manager.git"
        ;;
    *)
        echo "❌ Unknown project: $PROJECT_NAME"
        exit 1
        ;;
esac

# Clone or update repository
if [[ -d "$PROJECT_NAME" ]]; then
    echo "🔄 Updating existing repository..."
    cd "$PROJECT_NAME"
    git fetch --all --tags
    git clean -fd
    git reset --hard
else
    echo "📦 Cloning repository..."
    git clone --depth 1 --branch "$VERSION" "$REPO_URL" "$PROJECT_NAME"
    cd "$PROJECT_NAME"
fi

# Checkout specific version
git checkout "$VERSION"

# Verify the checkout
CURRENT_VERSION=$(git describe --tags --exact-match 2>/dev/null || git rev-parse --short HEAD)
echo "✅ Successfully fetched $PROJECT_NAME at version: $CURRENT_VERSION"

# Generate source metadata
cat > ../source-metadata.json << EOF
{
  "project": "$PROJECT_NAME",
  "version": "$VERSION",
  "repository": "$REPO_URL",
  "commit": "$(git rev-parse HEAD)",
  "fetch_time": "$(date -Iseconds)",
  "source_verification": {
    "commit_signature": "$(git verify-commit HEAD 2>&1 || echo 'unsigned')",
    "tag_signature": "$(git verify-tag "$VERSION" 2>&1 || echo 'unsigned')"
  }
}
EOF

echo "📄 Source metadata written to source-metadata.json"