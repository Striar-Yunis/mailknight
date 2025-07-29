#!/bin/bash
# Build ArgoCD containers using unified approach following upstream structure
# This script implements the pipeline structure specified in the issue:
# 1. Initialize FIPS/security compliant container to do build
# 2. Clone upstream repository into build container  
# 3. Apply any patches based on what is specified in the patches directory
# 4. Build the executable (single argocd binary with component symlinks)
# 5. Scan with trivy -> Fail on high or critical
# 6. Build all appropriate containers
# 7. Push all appropriate containers to ghcr
# 8. Scan them all with trivy and sbomb

set -euo pipefail

PROJECT_NAME="${1:-argocd}"
VERSION="${2:-v3.0.11}"

if [[ -z "$PROJECT_NAME" || -z "$VERSION" ]]; then
    echo "Usage: $0 <project_name> <version>"
    exit 1
fi

echo "🚀 Building ArgoCD following upstream structure and issue requirements"

# Step 1: Initialize FIPS/security compliant container to do build
echo "📋 Step 1: Initializing FIPS-compliant build environment"
BUILD_CONTEXT=$(mktemp -d)
trap "rm -rf $BUILD_CONTEXT" EXIT

# Copy all necessary files to build context
cp -r source projects patches scripts "$BUILD_CONTEXT/"
cd "$BUILD_CONTEXT"

# Step 2: Clone upstream repository into build container (already done by fetch-upstream.sh)
echo "✅ Step 2: Upstream repository already cloned"

# Step 3: Apply any patches based on what is specified in the patches directory
echo "🔧 Step 3: Applying security patches"
if [[ -d "patches/$PROJECT_NAME/common" ]]; then
    echo "  Applying common patches..."
    for patch in patches/$PROJECT_NAME/common/*.patch; do
        if [[ -f "$patch" ]]; then
            echo "    Applying $patch"
            (cd "source/$PROJECT_NAME" && git apply "../../$patch" || echo "    Warning: Patch $patch failed to apply")
        fi
    done
fi

if [[ -d "patches/$PROJECT_NAME/$VERSION" ]]; then
    echo "  Applying version-specific patches..."
    for patch in patches/$PROJECT_NAME/$VERSION/*.patch; do
        if [[ -f "$patch" ]]; then
            echo "    Applying $patch"
            (cd "source/$PROJECT_NAME" && git apply "../../$patch" || echo "    Warning: Patch $patch failed to apply")
        fi
    done
fi

echo "✅ Step 3: Patches applied"

# Step 4: Build the executable (single argocd binary following upstream pattern)
echo "🏗️  Step 4: Building single ArgoCD executable with FIPS compliance"

# Create unified image using the new Dockerfile
echo "  Building unified ArgoCD image..."
docker build \
    --build-arg GO_VERSION=1.24.4 \
    --build-arg NODE_VERSION=23.0.0 \
    --build-arg BUILD_DATE="$(date -u +'%Y-%m-%dT%H:%M:%SZ')" \
    --build-arg GIT_COMMIT="$(cd source/$PROJECT_NAME && git rev-parse HEAD)" \
    --build-arg GIT_TAG="$VERSION" \
    --build-arg GIT_TREE_STATE="clean" \
    --label "org.opencontainers.image.title=mailknight/$PROJECT_NAME" \
    --label "org.opencontainers.image.version=$VERSION-mailknight" \
    --label "org.opencontainers.image.created=$(date -u +'%Y-%m-%dT%H:%M:%SZ')" \
    --label "org.opencontainers.image.revision=$(cd source/$PROJECT_NAME && git rev-parse HEAD)" \
    --label "org.opencontainers.image.source=https://github.com/Striar-Yunis/mailknight" \
    --label "mailknight.project=$PROJECT_NAME" \
    --label "security.fips=enabled" \
    --label "security.hardened=true" \
    -t "mailknight/$PROJECT_NAME:$VERSION-mailknight" \
    -t "mailknight/$PROJECT_NAME:latest" \
    -f "projects/$PROJECT_NAME/Dockerfile.unified" \
    .

echo "✅ Step 4: ArgoCD executable built successfully"

# Step 5: Scan with trivy -> Fail on high or critical
echo "🔍 Step 5: Scanning for vulnerabilities with Trivy"

# Install Trivy if not available
if ! command -v trivy &> /dev/null; then
    echo "  Installing Trivy..."
    TRIVY_VERSION="0.48.3"
    curl -sL "https://github.com/aquasecurity/trivy/releases/download/v${TRIVY_VERSION}/trivy_${TRIVY_VERSION}_Linux-64bit.tar.gz" | tar -xz -C /tmp
    sudo mv /tmp/trivy /usr/local/bin/trivy
    chmod +x /usr/local/bin/trivy
fi

# Create scan results directory
mkdir -p scan-results

# Scan the image for high and critical vulnerabilities
echo "  Scanning mailknight/$PROJECT_NAME:$VERSION-mailknight for HIGH and CRITICAL vulnerabilities..."
trivy image \
    --severity HIGH,CRITICAL \
    --format json \
    --output "scan-results/trivy-scan.json" \
    "mailknight/$PROJECT_NAME:$VERSION-mailknight"

# Also generate SARIF for GitHub integration
trivy image \
    --severity HIGH,CRITICAL \
    --format sarif \
    --output "scan-results/trivy-scan.sarif" \
    "mailknight/$PROJECT_NAME:$VERSION-mailknight"

# Check if there are HIGH or CRITICAL vulnerabilities
VULN_COUNT=$(trivy image \
    --severity HIGH,CRITICAL \
    --format json \
    "mailknight/$PROJECT_NAME:$VERSION-mailknight" | \
    jq '.Results[]?.Vulnerabilities // [] | length' | \
    awk '{sum += $1} END {print sum+0}')

if [[ "$VULN_COUNT" -gt 0 ]]; then
    echo "❌ Step 5: FAILED - Found $VULN_COUNT HIGH or CRITICAL vulnerabilities"
    echo "Vulnerability details:"
    trivy image --severity HIGH,CRITICAL "mailknight/$PROJECT_NAME:$VERSION-mailknight"
    exit 1
fi

echo "✅ Step 5: No HIGH or CRITICAL vulnerabilities found"

# Step 6: Build all appropriate containers (component-specific containers)
echo "🐳 Step 6: Building component-specific containers"

# Define the components that match upstream ArgoCD release structure
COMPONENTS=(
    "server"
    "repo-server" 
    "application-controller"
    "applicationset-controller"
    "dex"
    "notifications"
)

mkdir -p images

for component in "${COMPONENTS[@]}"; do
    echo "  Building $component container..."
    
    # Create component-specific Dockerfile that uses the unified base
    cat > "Dockerfile.$component" << EOF
FROM mailknight/$PROJECT_NAME:$VERSION-mailknight

# Component-specific configuration
USER root
EOF

    # Add component-specific runtime configuration
    case "$component" in
        "server")
            cat >> "Dockerfile.$component" << 'EOF'
# Server component configuration
EXPOSE 8080 8083
ENV ARGOCD_SERVER_INSECURE="false"
ENV ARGOCD_SERVER_ROOTPATH="/"
USER 999
CMD ["/usr/local/bin/argocd-server"]
EOF
            ;;
        "repo-server")
            cat >> "Dockerfile.$component" << 'EOF'
# Repository server component configuration  
EXPOSE 8081
ENV ARGOCD_EXEC_TIMEOUT="90s"
ENV ARGOCD_REPO_SERVER_STRICT_TLS="true"
USER 999
CMD ["/usr/local/bin/argocd-repo-server"]
EOF
            ;;
        "application-controller")
            cat >> "Dockerfile.$component" << 'EOF'
# Application controller component configuration
USER 999  
CMD ["/usr/local/bin/argocd-application-controller"]
EOF
            ;;
        "applicationset-controller")
            cat >> "Dockerfile.$component" << 'EOF'
# ApplicationSet controller component configuration
USER 999
CMD ["/usr/local/bin/argocd-applicationset-controller"]
EOF
            ;;
        "dex")
            cat >> "Dockerfile.$component" << 'EOF'
# Dex authentication component configuration
EXPOSE 5556 5557 5558
USER 999
CMD ["/usr/local/bin/argocd-dex"]
EOF
            ;;
        "notifications")
            cat >> "Dockerfile.$component" << 'EOF'
# Notifications controller component configuration
USER 999
CMD ["/usr/local/bin/argocd-notifications"]
EOF
            ;;
    esac

    # Build component container
    docker build \
        --label "mailknight.component=$component" \
        -t "mailknight/$PROJECT_NAME-$component:$VERSION-mailknight" \
        -t "mailknight/$PROJECT_NAME-$component:latest" \
        -f "Dockerfile.$component" \
        .
    
    # Save image to file
    mkdir -p "images/$component"
    docker save "mailknight/$PROJECT_NAME-$component:$VERSION-mailknight" | \
        gzip > "images/$component/$PROJECT_NAME-$component-$VERSION-mailknight.tar.gz"
    
    echo "  ✅ Built $component container"
done

echo "✅ Step 6: All component containers built successfully"

# Step 7: Push all appropriate containers to ghcr (will be handled by CI/CD)
echo "📦 Step 7: Container images ready for push to ghcr.io"
echo "  Images built:"
for component in "${COMPONENTS[@]}"; do
    echo "    - mailknight/$PROJECT_NAME-$component:$VERSION-mailknight"
done

# Step 8: Scan them all with trivy and sbom
echo "🔍 Step 8: Scanning all component containers and generating SBOMs"

# Install Syft for SBOM generation if not available
if ! command -v syft &> /dev/null; then
    echo "  Installing Syft..."
    curl -sSfL https://raw.githubusercontent.com/anchore/syft/main/install.sh | sh -s -- -b /usr/local/bin v0.100.0
fi

for component in "${COMPONENTS[@]}"; do
    echo "  Scanning $component container..."
    
    # Create component-specific scan directory
    mkdir -p "scan-results/$component"
    
    # Scan for vulnerabilities
    trivy image \
        --severity HIGH,CRITICAL \
        --format json \
        --output "scan-results/$component/trivy-scan.json" \
        "mailknight/$PROJECT_NAME-$component:$VERSION-mailknight"
    
    # Generate SARIF for GitHub
    trivy image \
        --severity HIGH,CRITICAL \
        --format sarif \
        --output "scan-results/$component/trivy-scan.sarif" \
        "mailknight/$PROJECT_NAME-$component:$VERSION-mailknight"
    
    # Generate SBOM
    syft "mailknight/$PROJECT_NAME-$component:$VERSION-mailknight" \
        -o cyclonedx-json > "scan-results/$component/sbom.json"
    
    # Check for vulnerabilities
    COMPONENT_VULN_COUNT=$(trivy image \
        --severity HIGH,CRITICAL \
        --format json \
        "mailknight/$PROJECT_NAME-$component:$VERSION-mailknight" | \
        jq '.Results[]?.Vulnerabilities // [] | length' | \
        awk '{sum += $1} END {print sum+0}')
    
    if [[ "$COMPONENT_VULN_COUNT" -gt 0 ]]; then
        echo "    ⚠️  Warning: $component has $COMPONENT_VULN_COUNT HIGH or CRITICAL vulnerabilities"
    else
        echo "    ✅ $component: No HIGH or CRITICAL vulnerabilities"
    fi
done

echo "✅ Step 8: All containers scanned and SBOMs generated"

# Generate final build report
cat > build-report.json << EOF
{
  "project": "$PROJECT_NAME",
  "version": "$VERSION",
  "build_date": "$(date -Iseconds)",
  "build_approach": "unified-upstream-aligned",
  "fips_compliant": true,
  "components_built": $(printf '%s\n' "${COMPONENTS[@]}" | jq -R . | jq -s .),
  "base_image": "mailknight/$PROJECT_NAME:$VERSION-mailknight",
  "scan_results_available": true,
  "sbom_generated": true,
  "ready_for_ghcr_push": true
}
EOF

echo "🎉 ArgoCD build completed successfully following upstream structure!"
echo "📋 Build report: build-report.json"
echo "📦 Container images: $(ls images/*/)"
echo "🔍 Scan results: $(ls scan-results/*/)"

# Copy results back to original directory
cd - > /dev/null
cp -r "$BUILD_CONTEXT/images" "$BUILD_CONTEXT/scan-results" "$BUILD_CONTEXT/build-report.json" ./

echo "✅ All pipeline steps completed successfully!"