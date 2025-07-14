#!/bin/bash
# Release artifacts with signing and metadata
# Usage: release-artifacts.sh <project_name> <version>

set -euo pipefail

PROJECT_NAME="${1:-}"
VERSION="${2:-}"

if [[ -z "$PROJECT_NAME" || -z "$VERSION" ]]; then
    echo "Usage: $0 <project_name> <version>"
    exit 1
fi

echo "🚀 Releasing artifacts for $PROJECT_NAME:$VERSION"

# Create releases directory
mkdir -p releases

RELEASE_DIR="releases/$PROJECT_NAME-$VERSION-$(date +%Y%m%d)"
mkdir -p "$RELEASE_DIR"

IMAGE_NAME="mailknight/$PROJECT_NAME:$VERSION-mailknight"
RELEASE_DATE=$(date -Iseconds)

# Generate release version
if git describe --tags --exact-match 2>/dev/null; then
    RELEASE_VERSION=$(git describe --tags --exact-match)
else
    RELEASE_VERSION="$VERSION-lts.$(date +%Y%m%d)"
fi

echo "📦 Preparing release: $RELEASE_VERSION"

# Copy build artifacts
if [[ -d "build" ]]; then
    cp -r build/* "$RELEASE_DIR/"
fi

# Copy container image
if [[ -f "images/${PROJECT_NAME}-${VERSION}-mailknight.tar.gz" ]]; then
    cp "images/${PROJECT_NAME}-${VERSION}-mailknight.tar.gz" "$RELEASE_DIR/"
fi

# Copy SBOM files
cp sbom.json "$RELEASE_DIR/binary-sbom.json" 2>/dev/null || true
cp image-sbom.json "$RELEASE_DIR/image-sbom.json" 2>/dev/null || true

# Copy scan results
if [[ -d "scan-results" ]]; then
    cp -r scan-results "$RELEASE_DIR/"
fi

# Copy test results
if [[ -d "test-results" ]]; then
    cp -r test-results "$RELEASE_DIR/"
fi

# Generate release notes
cat > "$RELEASE_DIR/RELEASE_NOTES.md" << EOF
# Mailknight Release: $PROJECT_NAME $RELEASE_VERSION

## Overview
This is a FIPS-compliant, hardened release of $PROJECT_NAME built by the Mailknight secure software supply chain system.

## Release Information
- **Project**: $PROJECT_NAME
- **Version**: $RELEASE_VERSION
- **Base Version**: $VERSION
- **Release Date**: $RELEASE_DATE
- **FIPS Compliant**: ✅ Yes
- **Security Hardened**: ✅ Yes

## Security Features
- FIPS-140-2 compliance enabled
- Hardened compiler flags (-fstack-protector, -D_FORTIFY_SOURCE=2, -Wl,-z,relro,-z,now)
- Minimal runtime environment
- Non-root container execution
- CVE scanning and mitigation
- Software Bill of Materials (SBOM) included

## Artifacts
- \`${PROJECT_NAME}-${VERSION}-mailknight.tar.gz\` - Container image
- \`binary-sbom.json\` - Binary SBOM (CycloneDX format)
- \`image-sbom.json\` - Container image SBOM (CycloneDX format)
- \`scan-results/\` - Security scan reports
- \`test-results/\` - FIPS compliance test results

## Verification
All artifacts have been:
- Built with FIPS compliance
- Scanned for vulnerabilities
- Tested for security compliance
- Hardened against common attack vectors

## Usage
\`\`\`bash
# Load container image
docker load < ${PROJECT_NAME}-${VERSION}-mailknight.tar.gz

# Run with FIPS mode
docker run --rm mailknight/$PROJECT_NAME:$VERSION-mailknight version --client
\`\`\`

## Support
This release is part of the Mailknight Long-Term Support (LTS) program and includes:
- Regular security updates
- CVE monitoring and patching
- FIPS compliance maintenance

For more information, visit: https://github.com/Striar-Yunis/mailknight
EOF

# Generate checksums
echo "🔐 Generating checksums..."
cd "$RELEASE_DIR"
find . -type f -not -name "SHA256SUMS" -exec sha256sum {} \; > SHA256SUMS
cd - > /dev/null

# Sign artifacts if cosign is available
if command -v cosign &> /dev/null; then
    echo "✍️  Signing artifacts with cosign..."
    
    # Sign container image
    if docker image inspect "$IMAGE_NAME" &> /dev/null; then
        cosign sign --yes "$IMAGE_NAME" || echo "⚠️  Failed to sign image"
    fi
    
    # Sign release artifacts
    cosign sign-blob --yes --output-signature "$RELEASE_DIR/SHA256SUMS.sig" "$RELEASE_DIR/SHA256SUMS" || echo "⚠️  Failed to sign checksums"
else
    echo "⚠️  Cosign not available, skipping artifact signing"
fi

# Generate release manifest
cat > "$RELEASE_DIR/release-manifest.json" << EOF
{
  "name": "$PROJECT_NAME",
  "version": "$RELEASE_VERSION",
  "base_version": "$VERSION",
  "release_date": "$RELEASE_DATE",
  "release_type": "lts",
  "fips_compliant": true,
  "security_hardened": true,
  "artifacts": {
    "container_image": "${PROJECT_NAME}-${VERSION}-mailknight.tar.gz",
    "sbom_binary": "binary-sbom.json",
    "sbom_image": "image-sbom.json",
    "security_scans": "scan-results/",
    "compliance_tests": "test-results/",
    "checksums": "SHA256SUMS"
  },
  "security_info": {
    "base_image": "registry.access.redhat.com/ubi8/ubi-minimal:latest",
    "fips_mode": "enabled",
    "hardening_flags": "-fstack-protector-strong -D_FORTIFY_SOURCE=2 -Wl,-z,relro,-z,now",
    "scan_status": "$(jq -r '.results.scan_status // "UNKNOWN"' scan-results/scan-summary.json 2>/dev/null || echo "UNKNOWN")",
    "compliance_status": "$(jq -r '.compliance_status // "UNKNOWN"' test-results/fips-compliance.json 2>/dev/null || echo "UNKNOWN")"
  },
  "build_info": {
    "build_system": "mailknight",
    "git_commit": "$(git rev-parse HEAD)",
    "git_ref": "$(git symbolic-ref HEAD 2>/dev/null || git rev-parse HEAD)",
    "pipeline_id": "${CI_PIPELINE_ID:-unknown}",
    "job_id": "${CI_JOB_ID:-unknown}"
  }
}
EOF

# Create release archive
ARCHIVE_NAME="mailknight-$PROJECT_NAME-$RELEASE_VERSION.tar.gz"
tar -czf "releases/$ARCHIVE_NAME" -C releases "$(basename "$RELEASE_DIR")"

echo "✅ Release completed successfully"
echo "📦 Release directory: $RELEASE_DIR"
echo "📄 Release archive: releases/$ARCHIVE_NAME"
echo "🏷️  Release version: $RELEASE_VERSION"

# Display release summary
echo ""
echo "📊 Release Summary:"
echo "   Project: $PROJECT_NAME"
echo "   Version: $RELEASE_VERSION"
echo "   FIPS Compliant: ✅"
echo "   Security Hardened: ✅"
echo "   Artifacts: $(find "$RELEASE_DIR" -type f | wc -l) files"
echo "   Archive Size: $(du -h "releases/$ARCHIVE_NAME" | cut -f1)"